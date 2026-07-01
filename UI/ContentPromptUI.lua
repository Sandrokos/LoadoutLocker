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
    local EVALUATE_DELAY = 0.5

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
        if not options.force and (not config.arePromptsEnabled() or dismissedKey == contentKey) then
            return
        end
        if not configID or not specID then
            return
        end
        if not options.force and Loadout.IsAssignedLoadoutActive(specID, configID) then
            return
        end

        local frame = EnsurePromptFrame()
        frame.contentKey = contentKey
        frame.configID = configID
        frame.specID = specID
        frame.content:SetText(content and content.name or contentKey)
        frame.content:Show()
        frame.loadout:SetText("Switch to: " .. Loadout.FormatLoadoutLabel(specID, Loadout.GetLoadoutName(configID)))
        frame.loadout:Show()
        frame.isLoading = nil
        PromptUtils.HidePromptLoadingIndicator(frame)
        local configured = PromptUtils.ConfigureLoadoutSwitchButton(
            frame.swapButton,
            specID,
            configID,
            function()
                dismissedKey = contentKey
            end
        )
        if configured then
            frame.swapButton:Enable()
            frame.dismissButton:Enable()
        else
            frame.loadout:SetText(
                frame.loadout:GetText() .. "\n|cffff2020Cannot switch to that specialization.|r"
            )
            frame.swapButton:Disable()
            frame.dismissButton:Enable()
        end
        frame:Show()
    end

    function UI.HidePrompt()
        HidePrompt()
    end

    function UI.Evaluate()
        if promptFrame and promptFrame.isLoading then
            return
        end

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
        local ref = config.getLoadoutRef(contentKey)
        if not ref then
            HidePrompt()
            return
        end

        UI.ShowPrompt(contentKey, content, ref.configID, ref.specID)
    end

    function UI.Simulate(simKey)
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

        local ref = config.getLoadoutRef(contentKey)
        if not ref then
            Print("Assign a " .. config.label .. " loadout in /locker before simulating.")
            return
        end

        dismissedKey = nil
        UI.ShowPrompt(contentKey, content, ref.configID, ref.specID, { force = true })
        Print("Showing simulated " .. config.label .. " prompt for " .. content.name .. ".")
    end

    PromptUtils.RegisterZoneEvaluate(function()
        UI.Evaluate()
    end, {
        delay = EVALUATE_DELAY,
        extraEvents = config.extraEvents,
    })

    return UI
end
