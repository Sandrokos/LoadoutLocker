LoadoutLocker = LoadoutLocker or {}

local ContentPromptUI = {}
LoadoutLocker.ContentPromptUI = ContentPromptUI

function ContentPromptUI.Create(config)
    local Instance = LoadoutLocker.Instance
    local Loadout = LoadoutLocker.Loadout
    local PromptUtils = LoadoutLocker.PromptUtils
    local Print = LoadoutLocker.Print

    local UI = {}
    local promptFrame
    local dismissedKey
    local lastContentKey
    local ScheduleEvaluate = PromptUtils.CreateScheduleEvaluate(function()
        UI.Evaluate()
    end)

    local function HidePrompt()
        if promptFrame then
            promptFrame:Hide()
        end
    end

    local function EnsurePromptFrame()
        if promptFrame then
            return promptFrame
        end

        local frame = PromptUtils.CreatePromptFrame({
            globalName = config.globalName,
            title = config.title,
            height = 118,
        })
        frame.content = PromptUtils.CreatePromptLabel(frame, frame.title)
        frame.loadout = PromptUtils.CreatePromptLabel(frame, frame.content, -4, "GameFontGreenSmall")
        frame.swapButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.swapButton:SetSize(140, 22)
        frame.swapButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 14)
        frame.swapButton:SetText("Switch Loadout")
        frame.swapButton:SetScript("OnClick", function()
            if not frame.configID then
                return
            end
            frame.swapButton:Disable()
            frame.dismissButton:Disable()
            if not PromptUtils.SwitchToLoadout(frame.configID, frame.specID) then
                frame.swapButton:Enable()
                frame.dismissButton:Enable()
                return
            end
            dismissedKey = frame.contentKey
            HidePrompt()
        end)
        frame.dismissButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 14)
        frame.dismissButton:SetScript("OnClick", function()
            dismissedKey = frame.contentKey
            HidePrompt()
        end)
        promptFrame = frame
        return frame
    end

    function UI.ShowPrompt(contentKey, content, configID, specID, options)
        options = options or {}
        if not options.force and not config.arePromptsEnabled() then
            return
        end
        if not options.force and dismissedKey == contentKey then
            return
        end
        local currentConfigID = Loadout.GetLoadoutConfigID(specID)
        if not configID or (not options.force and currentConfigID == configID) then
            return
        end

        local frame = EnsurePromptFrame()
        frame.contentKey = contentKey
        frame.configID = configID
        frame.specID = specID
        frame.content:SetText(content and content.name or contentKey)
        frame.loadout:SetText("Switch to: " .. Loadout.GetLoadoutName(configID))
        frame.swapButton:Enable()
        frame.dismissButton:Enable()
        frame:Show()
    end

    function UI.HidePrompt()
        HidePrompt()
    end

    function UI.Evaluate()
        local instanceInfo = Instance.GetCurrent()
        if not config.isInInstance(instanceInfo) then
            if lastContentKey then
                dismissedKey = nil
                lastContentKey = nil
            end
            HidePrompt()
            return
        end

        local contentKey, content = config.resolveCurrent(instanceInfo)
        if not contentKey then
            HidePrompt()
            return
        end

        lastContentKey = contentKey
        local specID = Loadout.GetSpecID()
        if not specID then
            return
        end

        local configID = config.getConfigID(specID, contentKey)
        if not configID then
            HidePrompt()
            return
        end

        UI.ShowPrompt(contentKey, content, configID, specID)
    end

    function UI.Simulate(simKey)
        local specID = Loadout.GetSpecID()
        if not specID then
            Print("Select a specialization first.")
            return
        end

        local contentKey, content = config.resolveCurrent(Instance.GetCurrent())
        if not content and simKey then
            content = config.getByKey(simKey)
            contentKey = content and content.key
        end
        if not content then
            content = config.getFallbackContent()
            contentKey = content and content.key
        end
        if not content then
            Print("No " .. config.label .. " data available to simulate.")
            return
        end

        local configID = config.getConfigID(specID, contentKey)
        if not configID then
            Print("Assign a " .. config.label .. " loadout in /locker before simulating.")
            return
        end

        dismissedKey = nil
        UI.ShowPrompt(contentKey, content, configID, specID, { force = true })
        Print("Showing simulated " .. config.label .. " prompt for " .. content.name .. ".")
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    if config.extraEvents then
        for _, event in ipairs(config.extraEvents) do
            eventFrame:RegisterEvent(event)
        end
    end
    eventFrame:SetScript("OnEvent", function()
        ScheduleEvaluate(0.5)
    end)

    return UI
end
