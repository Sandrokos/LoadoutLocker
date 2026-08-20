LoadoutLocker = LoadoutLocker or {}

local RaidUI = {}
LoadoutLocker.RaidUI = RaidUI

local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Raids = LoadoutLocker.Raids
local Instance = LoadoutLocker.Instance
local Loadout = LoadoutLocker.Loadout
local PromptUtils = LoadoutLocker.PromptUtils
local Print = LoadoutLocker.Print
local Widgets = LoadoutLocker.MenuWidgets
local Catalog = LoadoutLocker.RaidCatalog

local promptFrame
local simFrame
local choiceButtons = {}
local choiceLabels = {}
local simRaidButtons = {}
local simBossRows = {}
local dismissedRaidKey
local lastRaidKey
local simulatedRaidKey
local simulatedKills = {}
local stoppingSim
local MAX_CHOICES = 8
local MAX_SIM_BOSSES = 8
local ENTER_EVALUATE_DELAY = 2.0
local PROMPT_MIN_WIDTH = 360
local PROMPT_MAX_WIDTH = 520
local PROMPT_PADDING = 40
local CHOICE_BUTTON_WIDTH = 220
local CHOICE_BUTTON_HEIGHT = 22
local LOADOUT_BUTTON_TEXT_MAX = 35
local CHOICE_TOP_OFFSET = -72
local CHOICE_ROW_GAP = 14
local FRAME_BOTTOM_PAD = 50

local DEFAULT_RAID_SIM_KEY = "venomous_abyss"

local RAID_SIM_ALIASES = {
    abyss = DEFAULT_RAID_SIM_KEY,
    venomous = DEFAULT_RAID_SIM_KEY,
    venom = DEFAULT_RAID_SIM_KEY,
    ulatek = DEFAULT_RAID_SIM_KEY,
    ["ula'tek"] = DEFAULT_RAID_SIM_KEY,
    grotto = "tidebound_grotto",
    tidebound = "tidebound_grotto",
    nymrissa = "tidebound_grotto",
    march = "march_on_quel_danas",
    quel = "march_on_quel_danas",
    ["quel'danas"] = "march_on_quel_danas",
    ["quel danas"] = "march_on_quel_danas",
    rotmire = "sporefall",
    voidspire = "voidspire",
    void = "voidspire",
    dreamrift = "dreamrift",
    dream = "dreamrift",
    sporefall = "sporefall",
}

local ScheduleEvaluate = PromptUtils.CreateScheduleEvaluate(function()
    RaidUI.Evaluate()
end)

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

local function CreateChoiceButton(parent, index)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(CHOICE_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
    choiceButtons[index] = button
    return button
end

local function EnsurePromptFrame()
    if promptFrame then
        return promptFrame
    end

    local frame = PromptUtils.CreatePromptFrame({
        globalName = "LoadoutLockerRaidPrompt",
        title = "Raid Loadout",
        height = 160,
    })

    frame.raidName = PromptUtils.CreatePromptLabel(frame, frame.title)
    frame.help = PromptUtils.CreatePromptLabel(frame, frame.raidName, -4, "GameFontDisableSmall")
    frame.help:SetText("Assigned loadouts for this raid:")

    PromptUtils.ConfigurePromptDismiss(frame, function()
        dismissedRaidKey = frame.raidKey
    end)

    frame.HideChoiceContent = HideChoiceContent

    promptFrame = frame
    return frame
end

local function CreateChoiceLabel(parent, index)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetWordWrap(true)
    label:SetJustifyH("CENTER")
    choiceLabels[index] = label
    return label
end

local function TruncateButtonText(text, maxLength)
    if not text or #text <= maxLength then
        return text
    end

    return text:sub(1, maxLength - 3) .. "..."
end

local function FormatLoadoutButtonText(loadoutLabel)
    return TruncateButtonText(loadoutLabel or "Switch", LOADOUT_BUTTON_TEXT_MAX)
end

local function FormatBossLabel(bossNames)
    return table.concat(bossNames, "\n")
end

local function MeasureMultilineTextWidth(measurer, text)
    text = text or ""
    measurer.measureCache = measurer.measureCache or {}
    local cached = measurer.measureCache[text]
    if cached then
        return cached
    end

    local maxWidth = 0

    for line in string.gmatch(text, "[^\n]+") do
        measurer:SetText(line)
        maxWidth = math.max(maxWidth, measurer:GetStringWidth())
    end

    measurer.measureCache[text] = maxWidth
    return maxWidth
end

local function NeedsPromptForChoices(choices)
    for _, choice in ipairs(choices) do
        if not choice.isActive then
            return true
        end
    end

    return false
end

local function CollectBossNames(bossList)
    local names = {}

    for _, boss in ipairs(bossList) do
        names[#names + 1] = boss.name
    end

    return names
end

local function BuildChoicesMeasureKey(choices)
    local parts = {}
    for index, choice in ipairs(choices) do
        parts[index] = string.format("%s\0%s", choice.bossLabel or "", choice.loadoutLabel or "")
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
        maxWidth = math.max(
            maxWidth,
            math.min(MeasureMultilineTextWidth(measurer, choice.bossLabel), CHOICE_BUTTON_WIDTH) + PROMPT_PADDING,
            CHOICE_BUTTON_WIDTH + PROMPT_PADDING
        )
        measurer:SetText(FormatLoadoutButtonText(choice.loadoutLabel) or "Active")
        maxWidth = math.max(maxWidth, measurer:GetStringWidth() + PROMPT_PADDING, CHOICE_BUTTON_WIDTH + PROMPT_PADDING)
    end

    local width = math.min(math.max(maxWidth, PROMPT_MIN_WIDTH), PROMPT_MAX_WIDTH)
    frame.promptMeasureKey = measureKey
    frame.promptMeasuredWidth = width
    return width
end

local function LayoutChoiceButtons(frame, choices)
    for index = 1, MAX_CHOICES do
        if choiceLabels[index] then
            choiceLabels[index]:Hide()
        end
        if choiceButtons[index] then
            choiceButtons[index]:Hide()
        end
    end

    local frameWidth = MeasurePromptWidth(frame, choices)
    frame:SetWidth(frameWidth)
    local labelWidth = frameWidth - PROMPT_PADDING

    if frame.raidName then
        frame.raidName:SetWidth(labelWidth)
    end
    if frame.help then
        frame.help:SetWidth(labelWidth)
    end

    local y = CHOICE_TOP_OFFSET
    for index, choice in ipairs(choices) do
        local label = choiceLabels[index] or CreateChoiceLabel(frame, index)
        label:ClearAllPoints()
        label:SetWidth(CHOICE_BUTTON_WIDTH)
        local bossLabel = choice.bossLabel or ""
        label:SetText(bossLabel)
        local labelHeight = 0
        if bossLabel ~= "" then
            label:Show()
            label:SetPoint("TOP", frame, "TOP", 0, y)
            labelHeight = label:GetStringHeight() or 14
            y = y - labelHeight - 6
        else
            label:Hide()
        end

        local button = choiceButtons[index] or CreateChoiceButton(frame, index)
        button:ClearAllPoints()
        button:SetSize(CHOICE_BUTTON_WIDTH, CHOICE_BUTTON_HEIGHT)
        button:SetPoint("TOP", frame, "TOP", 0, y)
        button.configID = choice.configID
        button.specID = choice.specID
        button.raidKey = choice.raidKey

        if choice.isActive then
            button:SetText("Active")
            button:Disable()
            button:SetScript("OnClick", nil)
            button:Show()
        else
            button:SetText(FormatLoadoutButtonText(choice.loadoutLabel))
            if PromptUtils.ConfigureLoadoutSwitchButton(button, choice.specID, choice.configID, function()
                dismissedRaidKey = choice.raidKey
                HidePrompt()
            end) then
                button:Enable()
                button:Show()
            else
                button:Disable()
                button:Show()
            end
        end

        y = y - CHOICE_BUTTON_HEIGHT - CHOICE_ROW_GAP
    end

    frame:SetHeight(math.abs(y) + FRAME_BOTTOM_PAD)
    frame.dismissButton:ClearAllPoints()
    frame.dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    PromptUtils.EnsureDismissButtonVisible(frame)
end

function RaidUI.ShowPrompt(raidKey, raid, choices, options)
    options = options or {}

    if not options.force and not DB:AreRaidPromptsEnabled() then
        return
    end

    if not choices or #choices == 0 then
        HidePrompt()
        return
    end

    if not options.force and dismissedRaidKey == raidKey then
        return
    end

    local frame = EnsurePromptFrame()
    frame.raidKey = raidKey
    frame.raidName:SetText(raid and raid.name or raidKey)
    frame.raidName:Show()
    if #choices == 1 then
        frame.help:SetText("Switch to your assigned loadout:")
    else
        frame.help:SetText("Assigned loadouts for this raid:")
    end
    frame.help:Show()
    PromptUtils.ResetPromptLoadingState(frame)
    LayoutChoiceButtons(frame, choices)
    frame:Show()
end

local function BuildLoadoutChoice(raidKey, specID, configID, bossNames)
    return {
        configID = configID,
        specID = specID,
        raidKey = raidKey,
        bossLabel = FormatBossLabel(bossNames),
        loadoutLabel = Loadout.FormatLoadoutLabel(specID, Loadout.GetLoadoutName(configID)),
        isActive = Loadout.IsAssignedLoadoutActive(specID, configID),
    }
end

local function BuildGroupedPromptChoices(raidKey, raid, bosses)
    if not bosses or #bosses == 0 then
        return nil
    end

    local groups = {}
    local order = {}

    for _, boss in ipairs(bosses) do
        local ref = DB:GetRaidBossLoadoutRef(raidKey, boss.key)
        if ref then
            local key = Loadout.EncodeLoadoutKey(ref.specID, ref.configID)
            local group = groups[key]
            if not group then
                group = {
                    specID = ref.specID,
                    configID = ref.configID,
                    bossNames = {},
                }
                groups[key] = group
                order[#order + 1] = key
            end
            group.bossNames[#group.bossNames + 1] = boss.name
        end
    end

    local defaultRef = DB:GetRaidDefaultLoadoutRef()
    local defaultBossNames = {}
    for _, boss in ipairs(bosses) do
        if not DB:GetRaidBossLoadoutRef(raidKey, boss.key) then
            defaultBossNames[#defaultBossNames + 1] = boss.name
        end
    end

    if defaultRef and #defaultBossNames > 0 then
        local defaultKey = Loadout.EncodeLoadoutKey(defaultRef.specID, defaultRef.configID)
        local group = groups[defaultKey]
        if not group then
            group = {
                specID = defaultRef.specID,
                configID = defaultRef.configID,
                bossNames = {},
            }
            groups[defaultKey] = group
            order[#order + 1] = defaultKey
        end
        for _, bossName in ipairs(defaultBossNames) do
            group.bossNames[#group.bossNames + 1] = bossName
        end
    end

    local choices = {}

    if #order == 0 then
        if not defaultRef then
            return nil
        end

        choices[#choices + 1] = BuildLoadoutChoice(
            raidKey,
            defaultRef.specID,
            defaultRef.configID,
            CollectBossNames(bosses)
        )
    else
        for _, key in ipairs(order) do
            local group = groups[key]
            choices[#choices + 1] = BuildLoadoutChoice(
                raidKey,
                group.specID,
                group.configID,
                group.bossNames
            )
        end
    end

    if not NeedsPromptForChoices(choices) then
        return nil
    end

    return choices
end

local function NormalizeSimRaidKey(key)
    if not key or key == "" then
        return nil
    end

    key = string.lower(key)
    key = RAID_SIM_ALIASES[key] or key
    if Raids.GetByKey(key) then
        return key
    end

    return nil
end

local function GetSimulatedKillStates(raid)
    local states = {}

    for _, boss in ipairs(raid.bosses) do
        states[boss.key] = simulatedKills[boss.key] or false
    end

    return states
end

local function GetPromptBosses(raid, instanceInfo)
    if instanceInfo and instanceInfo.isSimulation then
        return Raids.GetAliveBosses(raid, GetSimulatedKillStates(raid))
    end

    return Raids.GetAliveBossesInInstance(raid, instanceInfo)
end

local function HasAnyRaidAssignments(raidKey)
    if DB:GetRaidDefaultLoadoutRef() then
        return true
    end

    local assignment = DB:GetRaidAssignmentIfExists(nil, raidKey)
    if assignment and assignment.bosses then
        for _ in pairs(assignment.bosses) do
            return true
        end
    end

    return false
end

local function HasPromptableRaidAssignments(raidKey, raid)
    return BuildGroupedPromptChoices(raidKey, raid, raid.bosses) ~= nil
end

local function FindRaidKeyForSimulation(preferredKey)
    preferredKey = NormalizeSimRaidKey(preferredKey)
    if preferredKey then
        return preferredKey
    end

    local marchRaid = Raids.GetByKey(DEFAULT_RAID_SIM_KEY)
    if marchRaid and HasPromptableRaidAssignments(DEFAULT_RAID_SIM_KEY, marchRaid) then
        return DEFAULT_RAID_SIM_KEY
    end

    for _, raid in ipairs(Catalog.SEASON_TWO) do
        if HasPromptableRaidAssignments(raid.key, raid) then
            return raid.key
        end
    end

    return DEFAULT_RAID_SIM_KEY
end

local function GetSimulatedInstanceInfo(raid)
    return {
        name = raid.name,
        instanceType = "raid",
        difficultyID = C.NORMAL_RAID_DIFFICULTY_ID,
        instanceID = raid.instanceIDs and raid.instanceIDs[1],
        numEncounters = #raid.bosses,
        inInstance = true,
        isSimulation = true,
    }
end

local function CreateSimBossRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(380, 26)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(260)
    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetSize(100, 22)
    row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    simBossRows[index] = row
    return row
end

local function RefreshSimPanel()
    if not simFrame then
        return
    end

    for _, raid in ipairs(Catalog.SEASON_TWO) do
        local button = simRaidButtons[raid.key]
        if button then
            local label = raid.name
            if raid.key == simulatedRaidKey then
                label = label .. " (active)"
            end
            button:SetText(label)
        end
    end

    local raid = simulatedRaidKey and Raids.GetByKey(simulatedRaidKey)
    for index = 1, MAX_SIM_BOSSES do
        local row = simBossRows[index] or CreateSimBossRow(simFrame.bossContainer, index)
        local boss = raid and raid.bosses[index]
        if boss then
            row:ClearAllPoints()
            row:SetPoint("TOP", simFrame.bossContainer, "TOP", 0, -((index - 1) * 28))
            row:Show()
            row.name:SetText(boss.name)
            if simulatedKills[boss.key] then
                row.button:SetText("Killed")
                row.button:Disable()
                row.button:SetScript("OnClick", nil)
            else
                row.button:SetText("Mark killed")
                row.button:Enable()
                local bossKey = boss.key
                row.button:SetScript("OnClick", function()
                    RaidUI.MarkSimulatedBossKilled(bossKey)
                end)
            end
        else
            row:Hide()
        end
    end

    if not raid then
        simFrame.status:SetText("Select a raid to simulate.")
        return
    end

    if not HasAnyRaidAssignments(simulatedRaidKey) then
        simFrame.status:SetText("Assign raid loadouts in /locker to test prompts.")
        return
    end

    local instanceInfo = GetSimulatedInstanceInfo(raid)
    local aliveBosses = GetPromptBosses(raid, instanceInfo)
    if #aliveBosses == 0 then
        simFrame.status:SetText("All bosses marked killed. No prompt will appear.")
        return
    end

    if not BuildGroupedPromptChoices(simulatedRaidKey, raid, aliveBosses) then
        simFrame.status:SetText("No prompt needed - your active loadout matches all alive bosses.")
        return
    end

    simFrame.status:SetText(#aliveBosses .. " boss(es) alive in this simulation.")
end

local function EnsureSimPanel()
    if simFrame then
        return simFrame
    end

    local raidCount = #Catalog.SEASON_TWO
    local frame = Widgets.CreateDialogFrame({
        name = "LoadoutLockerRaidSim",
        title = "Raid Simulation",
        width = 440,
        height = 148 + (raidCount * 28) + (MAX_SIM_BOSSES * 28),
        onClose = function()
            RaidUI.StopSimulation()
            Print("Raid simulation stopped.")
        end,
    })

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.help:SetPoint("TOP", frame.title, "BOTTOM", 0, -10)
    frame.help:SetWidth(380)
    frame.help:SetWordWrap(true)
    frame.help:SetJustifyH("CENTER")
    frame.help:SetText("Pick a raid, mark bosses killed, and watch the loadout prompt update.")

    local raidTop = -72
    for index, raid in ipairs(Catalog.SEASON_TWO) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(380, 24)
        button:SetPoint("TOP", frame, "TOP", 0, raidTop - ((index - 1) * 28))
        button:SetText(raid.name)
        button:SetScript("OnClick", function()
            RaidUI.SelectSimulatedRaid(raid.key)
        end)
        simRaidButtons[raid.key] = button
    end

    local bossHeaderY = raidTop - (raidCount * 28) - 20
    frame.bossHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bossHeader:SetPoint("TOP", frame, "TOP", 0, bossHeaderY)
    frame.bossHeader:SetText("Bosses")

    frame.bossContainer = CreateFrame("Frame", nil, frame)
    frame.bossContainer:SetSize(380, MAX_SIM_BOSSES * 28)
    frame.bossContainer:SetPoint("TOP", frame.bossHeader, "BOTTOM", 0, -8)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    frame.status:SetWidth(380)
    frame.status:SetWordWrap(true)
    frame.status:SetJustifyH("CENTER")

    frame:SetScript("OnHide", function()
        if stoppingSim or not RaidUI.IsSimulatingRaid() then
            return
        end
        RaidUI.StopSimulation()
    end)

    simFrame = frame
    return frame
end

function RaidUI.StopSimulation()
    if stoppingSim then
        return
    end

    stoppingSim = true
    simulatedRaidKey = nil
    simulatedKills = {}
    dismissedRaidKey = nil
    lastRaidKey = nil
    HidePrompt()
    if simFrame and simFrame:IsShown() then
        simFrame:Hide()
    end
    stoppingSim = false
end

function RaidUI.SelectSimulatedRaid(raidKey)
    if not Raids.GetByKey(raidKey) then
        return
    end

    simulatedRaidKey = raidKey
    simulatedKills = {}
    dismissedRaidKey = nil
    RefreshSimPanel()
    RaidUI.Evaluate({ force = true })
end

function RaidUI.MarkSimulatedBossKilled(bossKey)
    if not simulatedRaidKey or not bossKey or simulatedKills[bossKey] then
        return
    end

    simulatedKills[bossKey] = true
    dismissedRaidKey = nil
    RefreshSimPanel()
    RaidUI.Evaluate({ force = true })
end

function RaidUI.ShowSimPanel(preferredRaidKey)
    EnsureSimPanel()
    RefreshSimPanel()

    if preferredRaidKey then
        RaidUI.SelectSimulatedRaid(preferredRaidKey)
    elseif not simulatedRaidKey then
        RaidUI.SelectSimulatedRaid(FindRaidKeyForSimulation(nil))
    else
        RefreshSimPanel()
        RaidUI.Evaluate({ force = true })
    end

    simFrame:Show()
end

function RaidUI.SetSimulatedRaid(raidKey)
    if raidKey then
        RaidUI.SelectSimulatedRaid(raidKey)
    else
        RaidUI.StopSimulation()
    end
end

function RaidUI.IsSimulatingRaid()
    return simulatedRaidKey ~= nil
end

function RaidUI.Evaluate(options)
    options = options or {}

    local usingSimulation = RaidUI.IsSimulatingRaid()
    local instanceInfo = Instance.GetCurrent()
    local raidKey, raid

    if usingSimulation then
        raidKey = simulatedRaidKey
        raid = Raids.GetByKey(raidKey)
        if not raid then
            simulatedRaidKey = nil
            HidePrompt()
            return
        end
        instanceInfo = GetSimulatedInstanceInfo(raid)
    elseif not Raids.IsInRaidInstance(instanceInfo) then
        if lastRaidKey then
            dismissedRaidKey = nil
            lastRaidKey = nil
        end
        HidePrompt()
        return
    else
        raidKey, raid = Raids.ResolveCurrent(instanceInfo)
    end

    if not raidKey or not raid then
        HidePrompt()
        return
    end

    local bosses = GetPromptBosses(raid, instanceInfo)
    if #bosses == 0 then
        HidePrompt()
        return
    end

    if promptFrame and promptFrame.isLoading then
        return
    end

    if lastRaidKey and lastRaidKey ~= raidKey then
        dismissedRaidKey = nil
    end

    lastRaidKey = raidKey

    local choices = BuildGroupedPromptChoices(raidKey, raid, bosses)

    if not choices or #choices == 0 then
        HidePrompt()
        return
    end

    RaidUI.ShowPrompt(raidKey, raid, choices, { force = usingSimulation or options.force })
end

function RaidUI.Simulate(requestedRaidKey)
    if requestedRaidKey == "stop" or requestedRaidKey == "off" then
        RaidUI.StopSimulation()
        Print("Raid simulation stopped.")
        return
    end

    local raidKey = NormalizeSimRaidKey(requestedRaidKey)
    if requestedRaidKey and not raidKey then
        Print("Unknown raid. Use abyss, grotto, venomous, or tidebound.")
        return
    end

    RaidUI.ShowSimPanel(raidKey)
end

function RaidUI.AppendDebugLines(lines, instanceInfo, specID)
    local simulating = RaidUI.IsSimulatingRaid()
    local inRaid = simulating or Raids.IsInRaidInstance(instanceInfo)
    local raidKey, raid

    if simulating then
        raidKey = simulatedRaidKey
        raid = Raids.GetByKey(raidKey)
        instanceInfo = raid and GetSimulatedInstanceInfo(raid) or instanceInfo
    else
        raidKey, raid = Raids.ResolveCurrent(instanceInfo)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "--- Raids ---"
    lines[#lines + 1] = "simulating: " .. tostring(simulating)
    lines[#lines + 1] = "active: " .. tostring(inRaid)
    lines[#lines + 1] = "resolvedKey: " .. tostring(raidKey)
    lines[#lines + 1] = "resolvedName: " .. tostring(raid and raid.name)
    lines[#lines + 1] = "promptsEnabled: " .. tostring(DB:AreRaidPromptsEnabled())
    local defaultRef = DB:GetRaidDefaultLoadoutRef()
    lines[#lines + 1] = "defaultLoadout: "
        .. tostring(defaultRef and Loadout.FormatLoadoutLabel(defaultRef.specID, Loadout.GetLoadoutName(defaultRef.configID)))
    lines[#lines + 1] = "dismissedRaidKey: " .. tostring(dismissedRaidKey)

    if not raidKey or not raid then
        return
    end

    local killStates = simulating and GetSimulatedKillStates(raid) or Raids.GetInstanceBossKillStates(raid, instanceInfo)
    local bosses = GetPromptBosses(raid, instanceInfo)
    local choices = BuildGroupedPromptChoices(raidKey, raid, bosses)

    lines[#lines + 1] = "promptBosses: " .. tostring(#bosses)
    lines[#lines + 1] = "instanceKills:"
    for _, boss in ipairs(raid.bosses) do
        lines[#lines + 1] = "  " .. boss.key .. ": " .. tostring(killStates[boss.key] and "dead" or "alive")
    end
    lines[#lines + 1] = "choices: " .. tostring(choices and #choices or 0)

    if choices then
        for index, choice in ipairs(choices) do
            lines[#lines + 1] = "  choice " .. index .. ": "
                .. tostring(Loadout.FormatLoadoutLabel(choice.specID, Loadout.GetLoadoutName(choice.configID)))
        end
    end

    lines[#lines + 1] = "boss assignments:"
    for _, boss in ipairs(bosses) do
        local ref = DB:GetRaidBossLoadoutRef(raidKey, boss.key)
        lines[#lines + 1] = "  " .. boss.key .. " -> "
            .. tostring(ref and Loadout.FormatLoadoutLabel(ref.specID, Loadout.GetLoadoutName(ref.configID)))
    end
end

local function RequestRaidLockoutRefreshIfNeeded()
    local instanceInfo = Instance.GetCurrent()
    if not Raids.IsInRaidInstance(instanceInfo) then
        return
    end
    Raids.RequestLockoutRefresh()
end

local eventFrame = PromptUtils.RegisterPromptEvents(function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local _, encounterName, _, _, endStatus = ...
        if endStatus ~= 1 then
            return
        end

        local instanceInfo = Instance.GetCurrent()
        local _, raid = Raids.ResolveCurrent(instanceInfo)
        if raid then
            local boss = Raids.FindBossByName(raid, encounterName)
            if boss then
                Raids.RecordInstanceBossKill(instanceInfo, boss.key)
            end
        end

        dismissedRaidKey = nil
        ScheduleEvaluate(1.0)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        if IsInInstance() then
            RequestRaidLockoutRefreshIfNeeded()
            ScheduleEvaluate(ENTER_EVALUATE_DELAY)
        else
            ScheduleEvaluate(0.5)
        end
        return
    end

    if event == "UPDATE_INSTANCE_INFO" or event == "LFG_LOCK_INFO_RECEIVED" then
        if Raids.IsInRaidInstance(Instance.GetCurrent()) then
            ScheduleEvaluate(0.5)
        end
        return
    end
end, {
    events = {
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "ZONE_CHANGED",
        "ENCOUNTER_END",
        "UPDATE_INSTANCE_INFO",
        "LFG_LOCK_INFO_RECEIVED",
    },
})
