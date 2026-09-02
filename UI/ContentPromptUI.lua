LoadoutLocker = LoadoutLocker or {}

local ContentPromptUI = {}
LoadoutLocker.ContentPromptUI = ContentPromptUI

function ContentPromptUI.SelectLayout(choices, force)
    if not choices or #choices == 0 then
        return "hide"
    end

    local anyInactive = false
    for _, choice in ipairs(choices) do
        if not choice.isActive then
            anyInactive = true
            break
        end
    end

    if not anyInactive and not force then
        return "hide"
    end

    if #choices == 1 then
        return "compact"
    end

    return "list"
end

function ContentPromptUI.BuildChoice(specID, configID, extraLabel)
    local Loadout = LoadoutLocker.Loadout
    return {
        specID = specID,
        configID = configID,
        extraLabel = extraLabel,
        loadoutLabel = Loadout.GetAssignedLoadoutLabel(specID, configID),
        isActive = Loadout.IsAssignedLoadoutActive(specID, configID),
    }
end

function ContentPromptUI.Create(config)
    local Instance = LoadoutLocker.Instance
    local PromptUtils = LoadoutLocker.PromptUtils
    local Print = LoadoutLocker.Print

    local UI = {}
    local promptFrame
    local dismissedKey
    local lastContentKey
    local choiceButtons = {}
    local choiceLabels = {}
    local EVALUATE_DELAY = 0.5
    local COMPACT_HEIGHT = 142
    local COMPACT_WIDTH = 360
    local BUTTON_BOTTOM = 18
    local COMPACT_BUTTON_GAP = 16
    local SWAP_BUTTON_WIDTH = 140
    local DISMISS_BUTTON_WIDTH = 100
    local MAX_CHOICES = 8
    local PROMPT_MIN_WIDTH = 360
    local PROMPT_MAX_WIDTH = 520
    local PROMPT_PADDING = 40
    local CHOICE_BUTTON_WIDTH = 220
    local CHOICE_BUTTON_HEIGHT = 22
    local LOADOUT_BUTTON_TEXT_MAX = 35
    local CHOICE_TOP_OFFSET = -90
    local CHOICE_ROW_GAP = 14
    local FRAME_BOTTOM_PAD = 54
    local listHelpText = config.listHelpText or "Assigned loadouts:"

    local function HideChoiceContent()
        for index = 1, MAX_CHOICES do
            if choiceLabels[index] then
                choiceLabels[index]:Hide()
            end
            if choiceButtons[index] then
                choiceButtons[index]:Hide()
            end
        end
    end

    local function HidePrompt()
        if not promptFrame then
            return
        end

        HideChoiceContent()
        PromptUtils.ResetPromptLoadingState(promptFrame)
        promptFrame:Hide()
    end

    local function FormatLoadoutButtonText(loadoutLabel)
        local text = loadoutLabel or "Switch"
        if #text <= LOADOUT_BUTTON_TEXT_MAX then
            return text
        end
        return text:sub(1, LOADOUT_BUTTON_TEXT_MAX - 3) .. "..."
    end

    local function BuildChoicesMeasureKey(choices)
        local parts = {}
        for index, choice in ipairs(choices) do
            parts[index] = choice.loadoutLabel or ""
        end
        return table.concat(parts, "\1")
    end

    local function MeasurePromptWidth(frame, choices)
        local measureKey = BuildChoicesMeasureKey(choices)
        if frame.promptMeasureKey == measureKey and frame.promptMeasuredWidth then
            return frame.promptMeasuredWidth
        end

        local maxWidth = PROMPT_MIN_WIDTH
        local measurer = frame.measureFont
        if not measurer then
            measurer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            measurer:SetWordWrap(false)
            frame.measureFont = measurer
        end

        for _, choice in ipairs(choices) do
            measurer:SetText(FormatLoadoutButtonText(choice.loadoutLabel))
            maxWidth = math.max(maxWidth, measurer:GetStringWidth() + PROMPT_PADDING)
        end

        local width = math.min(maxWidth, PROMPT_MAX_WIDTH)
        frame.promptMeasureKey = measureKey
        frame.promptMeasuredWidth = width
        return width
    end

    local function CreateChoiceButton(parent, index)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(CHOICE_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
        choiceButtons[index] = button
        return button
    end

    local function CreateChoiceLabel(parent, index)
        local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetWordWrap(true)
        label:SetJustifyH("CENTER")
        choiceLabels[index] = label
        return label
    end

    local function HideCompactWidgets(frame)
        if frame.loadout then
            frame.loadout:Hide()
        end
        if frame.swapButton then
            frame.swapButton:Hide()
            frame.swapButton:Disable()
        end
    end

    local function LayoutCompactButtons(frame)
        local totalWidth = SWAP_BUTTON_WIDTH + COMPACT_BUTTON_GAP + DISMISS_BUTTON_WIDTH
        local swapOffset = -totalWidth / 2 + SWAP_BUTTON_WIDTH / 2
        local dismissOffset = totalWidth / 2 - DISMISS_BUTTON_WIDTH / 2
        frame.swapButton:ClearAllPoints()
        frame.swapButton:SetSize(SWAP_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
        frame.swapButton:SetPoint("BOTTOM", frame, "BOTTOM", swapOffset, BUTTON_BOTTOM)
        frame.dismissButton:ClearAllPoints()
        frame.dismissButton:SetSize(DISMISS_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
        frame.dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", dismissOffset, BUTTON_BOTTOM)
    end

    local function ShowCompactLayout(frame, choice, contentKey)
        HideChoiceContent()
        if frame.help then
            frame.help:Hide()
        end
        frame:SetSize(COMPACT_WIDTH, COMPACT_HEIGHT)
        frame.content:SetWidth(320)
        frame.loadout:SetText("Switch to: " .. (choice.loadoutLabel or "Loadout"))
        frame.loadout:Show()
        frame.swapButton:SetText("Switch Loadout")
        frame.swapButton:Show()
        LayoutCompactButtons(frame)

        local configured = PromptUtils.ConfigureLoadoutSwitchButton(
            frame.swapButton,
            choice.specID,
            choice.configID,
            function()
                dismissedKey = contentKey
            end
        )
        if configured then
            frame.swapButton:Enable()
        else
            frame.loadout:SetText(
                frame.loadout:GetText() .. "\n|cffff2020Cannot switch to that specialization.|r"
            )
            frame.swapButton:Disable()
        end
    end

    local function ShowListLayout(frame, choices, contentKey)
        HideCompactWidgets(frame)
        HideChoiceContent()
        frame.help:SetText(listHelpText)
        frame.help:Show()

        local frameWidth = MeasurePromptWidth(frame, choices)
        frame:SetWidth(frameWidth)
        local labelWidth = frameWidth - PROMPT_PADDING
        frame.content:SetWidth(labelWidth)
        frame.help:SetWidth(labelWidth)

        local y = CHOICE_TOP_OFFSET
        for index, choice in ipairs(choices) do
            local label = choiceLabels[index] or CreateChoiceLabel(frame, index)
            label:ClearAllPoints()
            label:SetWidth(CHOICE_BUTTON_WIDTH)
            local extraLabel = choice.extraLabel or ""
            label:SetText(extraLabel)
            if extraLabel ~= "" then
                label:Show()
                label:SetPoint("TOP", frame, "TOP", 0, y)
                y = y - (label:GetStringHeight() or 14) - 10
            else
                label:Hide()
            end

            local button = choiceButtons[index] or CreateChoiceButton(frame, index)
            button:ClearAllPoints()
            button:SetSize(CHOICE_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
            button:SetPoint("TOP", frame, "TOP", 0, y)
            button.configID = choice.configID
            button.specID = choice.specID

            if choice.isActive then
                button:SetText("Active")
                button:Disable()
                button:SetScript("OnClick", nil)
            else
                button:SetText(FormatLoadoutButtonText(choice.loadoutLabel))
                if PromptUtils.ConfigureLoadoutSwitchButton(button, choice.specID, choice.configID, function()
                    dismissedKey = contentKey
                    HidePrompt()
                end) then
                    button:Enable()
                else
                    button:Disable()
                end
            end
            button:Show()

            y = y - CHOICE_BUTTON_HEIGHT - CHOICE_ROW_GAP
        end

        frame:SetHeight(math.abs(y) + FRAME_BOTTOM_PAD)
        frame.dismissButton:ClearAllPoints()
        frame.dismissButton:SetSize(DISMISS_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
        frame.dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, BUTTON_BOTTOM)
    end

    local function EnsurePromptFrame()
        if promptFrame then
            return promptFrame
        end

        local frame = PromptUtils.CreatePromptFrame({
            globalName = config.globalName,
            title = config.title,
            height = COMPACT_HEIGHT,
        })
        frame.content = PromptUtils.CreatePromptLabel(frame, frame.title)
        frame.help = PromptUtils.CreatePromptLabel(frame, frame.content, -8, "GameFontDisableSmall")
        frame.help:Hide()
        frame.loadout = PromptUtils.CreatePromptLabel(frame, frame.content, -10, "GameFontGreenSmall")
        frame.swapButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.swapButton:SetText("Switch Loadout")
        LayoutCompactButtons(frame)
        PromptUtils.ConfigurePromptDismiss(frame, function()
            dismissedKey = frame.contentKey
        end)
        frame.HideChoiceContent = HideChoiceContent
        promptFrame = frame
        return frame
    end

    local function ChoicesFromRef(ref)
        if not ref or not ref.specID or not ref.configID then
            return {}
        end
        return { ContentPromptUI.BuildChoice(ref.specID, ref.configID) }
    end

    function UI.ShowPrompt(contentKey, content, choices, options)
        options = options or {}
        if not options.force and (not config.arePromptsEnabled() or dismissedKey == contentKey) then
            return
        end

        local layout = ContentPromptUI.SelectLayout(choices, options.force)
        if layout == "hide" then
            HidePrompt()
            return
        end

        local frame = EnsurePromptFrame()
        frame.contentKey = contentKey
        frame.content:SetText(content and content.name or contentKey)
        frame.content:Show()
        PromptUtils.ResetPromptLoadingState(frame)

        if layout == "compact" then
            ShowCompactLayout(frame, choices[1], contentKey)
        else
            ShowListLayout(frame, choices, contentKey)
        end

        PromptUtils.EnsureDismissButtonVisible(frame)
        frame:Show()
    end

    function UI.HidePrompt()
        HidePrompt()
    end

    function UI.ClearDismiss()
        dismissedKey = nil
    end

    function UI.IsLoading()
        return promptFrame and promptFrame.isLoading
    end

    function UI.Evaluate()
        if UI.IsLoading() then
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
        UI.ShowPrompt(contentKey, content, ChoicesFromRef(config.getLoadoutRef(contentKey)))
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

        local choices = ChoicesFromRef(config.getLoadoutRef(contentKey))
        if #choices == 0 then
            Print("Assign a " .. config.label .. " loadout in /locker before simulating.")
            return
        end

        dismissedKey = nil
        UI.ShowPrompt(contentKey, content, choices, { force = true })
        Print("Showing simulated " .. config.label .. " prompt for " .. content.name .. ".")
    end

    if not config.skipZoneEvaluate then
        PromptUtils.RegisterZoneEvaluate(function()
            UI.Evaluate()
        end, {
            delay = EVALUATE_DELAY,
            extraEvents = config.extraEvents,
        })
    end

    return UI
end
