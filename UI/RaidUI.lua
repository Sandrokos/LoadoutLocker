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

local promptFrame
local choiceButtons = {}
local dismissedRaidKey
local lastRaidKey
local simulatedRaidKey
local MAX_CHOICES = 8
local ENTER_EVALUATE_DELAY = 2.0

local DEFAULT_RAID_SIM_KEY = "march_on_quel_danas"

local RAID_SIM_ALIASES = {
    march = DEFAULT_RAID_SIM_KEY,
    quel = DEFAULT_RAID_SIM_KEY,
    ["quel'danas"] = DEFAULT_RAID_SIM_KEY,
    ["quel danas"] = DEFAULT_RAID_SIM_KEY,
    rotmire = "sporefall",
}

local ScheduleEvaluate = PromptUtils.CreateScheduleEvaluate(function()
    RaidUI.Evaluate()
end)

local function HidePrompt()
    if promptFrame then
        promptFrame:Hide()
    end
end

local function CreateChoiceButton(parent, index)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(300, 24)
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
    frame.help:SetText("Remaining bosses need different loadouts:")

    frame.dismissButton:SetScript("OnClick", function()
        dismissedRaidKey = frame.raidKey
        HidePrompt()
    end)

    promptFrame = frame
    return frame
end

local function LayoutChoiceButtons(frame, choices)
    for index = 1, MAX_CHOICES do
        local button = choiceButtons[index]
        if button then
            button:Hide()
        end
    end

    local topOffset = -72
    local spacing = 28

    for index, choice in ipairs(choices) do
        local button = choiceButtons[index] or CreateChoiceButton(frame, index)
        button:ClearAllPoints()
        button:SetPoint("TOP", frame, "TOP", 0, topOffset - ((index - 1) * spacing))
        button:SetText(choice.label)
        button.configID = choice.configID
        button.specID = choice.specID
        button.raidKey = choice.raidKey
        if PromptUtils.ConfigureLoadoutSwitchButton(button, choice.specID, choice.configID, function()
            dismissedRaidKey = choice.raidKey
            HidePrompt()
        end) then
            button:Show()
            button:Enable()
        else
            button:Hide()
        end
    end

    frame:SetHeight(108 + math.max(#choices, 1) * spacing)
    frame.dismissButton:ClearAllPoints()
    frame.dismissButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
end

function RaidUI.ShowPrompt(raidKey, raid, choices, options)
    options = options or {}

    if not options.force and not DB:AreRaidPromptsEnabled() then
        return
    end

    if not choices or #choices == 0 then
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
        frame.help:SetText("Remaining bosses need different loadouts:")
    end
    frame.help:Show()
    frame.isLoading = nil
    PromptUtils.HidePromptLoadingIndicator(frame)
    LayoutChoiceButtons(frame, choices)
    frame:Show()
end

local function BuildChoiceLabel(bossNames, specID, configID)
    local loadoutLabel = Loadout.FormatLoadoutLabel(specID, Loadout.GetLoadoutName(configID))
    return table.concat(bossNames, ", ") .. "  \194\187  " .. loadoutLabel
end

local function BuildGroupedPromptChoices(raidKey, raid, bosses)
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

    if #order == 0 then
        local defaultRef = DB:GetRaidDefaultLoadoutRef()
        if defaultRef and not Loadout.IsAssignedLoadoutActive(defaultRef.specID, defaultRef.configID) then
            return {
                {
                    configID = defaultRef.configID,
                    specID = defaultRef.specID,
                    raidKey = raidKey,
                    label = BuildChoiceLabel({ raid.name }, defaultRef.specID, defaultRef.configID),
                },
            }
        end
        return nil
    end

    local choices = {}
    for _, key in ipairs(order) do
        local group = groups[key]
        if not Loadout.IsAssignedLoadoutActive(group.specID, group.configID) then
            choices[#choices + 1] = {
                configID = group.configID,
                specID = group.specID,
                raidKey = raidKey,
                label = BuildChoiceLabel(group.bossNames, group.specID, group.configID),
            }
        end
    end

    if #choices == 0 then
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

local function GetPromptBosses(raid, killStates)
    local alive = Raids.GetAliveBosses(raid, killStates)
    if #alive > 0 then
        return alive
    end
    return raid.bosses
end

local function HasPromptableRaidAssignments(raidKey, raid)
    for _, boss in ipairs(raid.bosses) do
        local ref = DB:GetRaidBossLoadoutRef(raidKey, boss.key)
        if ref and not Loadout.IsAssignedLoadoutActive(ref.specID, ref.configID) then
            return true
        end
    end

    local defaultRef = DB:GetRaidDefaultLoadoutRef()
    return defaultRef and not Loadout.IsAssignedLoadoutActive(defaultRef.specID, defaultRef.configID)
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

    local Catalog = LoadoutLocker.RaidCatalog
    for _, raid in ipairs(Catalog.CURRENT_TIER) do
        if HasPromptableRaidAssignments(raid.key, raid) then
            return raid.key
        end
    end

    return DEFAULT_RAID_SIM_KEY
end

local function BuildSimulatedKillStates(raid)
    local killStates = {}
    for _, boss in ipairs(raid.bosses) do
        killStates[boss.key] = false
    end
    return killStates
end

local function GetSimulatedInstanceInfo(raid)
    return {
        name = raid.name,
        instanceType = "raid",
        difficultyID = C.NORMAL_RAID_DIFFICULTY_ID,
        instanceID = raid.instanceIDs and raid.instanceIDs[1],
        numEncounters = #raid.bosses,
    }
end

function RaidUI.SetSimulatedRaid(raidKey)
    simulatedRaidKey = raidKey
    dismissedRaidKey = nil
    if not raidKey then
        HidePrompt()
    end
end

function RaidUI.IsSimulatingRaid()
    return simulatedRaidKey ~= nil
end

function RaidUI.Evaluate(options)
    options = options or {}
    if promptFrame and promptFrame.isLoading then
        return
    end

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

    if not raidKey then
        HidePrompt()
        return
    end

    if lastRaidKey and lastRaidKey ~= raidKey then
        dismissedRaidKey = nil
    end

    lastRaidKey = raidKey

    local killStates = usingSimulation
        and BuildSimulatedKillStates(raid)
        or Raids.GetBossKillStates(raid, instanceInfo)
    local choices = BuildGroupedPromptChoices(
        raidKey,
        raid,
        GetPromptBosses(raid, killStates)
    )

    if not choices or #choices == 0 then
        HidePrompt()
        return
    end

    RaidUI.ShowPrompt(raidKey, raid, choices, { force = usingSimulation or options.force })
end

function RaidUI.Simulate(requestedRaidKey)
    if requestedRaidKey == "stop" or requestedRaidKey == "off" then
        RaidUI.SetSimulatedRaid(nil)
        Print("Raid simulation stopped.")
        return
    end

    local raidKey = FindRaidKeyForSimulation(requestedRaidKey)
    local raid = Raids.GetByKey(raidKey)
    if not raid then
        Print("No raid data available to simulate.")
        return
    end

    if not HasPromptableRaidAssignments(raidKey, raid) then
        Print("Assign a raid loadout in /locker that differs from your current build first.")
        return
    end

    RaidUI.SetSimulatedRaid(raidKey)
    RaidUI.Evaluate({ force = true })

    if not promptFrame or not promptFrame:IsShown() then
        RaidUI.SetSimulatedRaid(nil)
        Print("Raid simulation could not build a prompt for " .. raid.name .. ".")
        return
    end

    Print("Simulating raid: " .. raid.name .. " (/locker sim raid stop to end).")
end

function RaidUI.AppendDebugLines(lines, instanceInfo, specID)
    local inRaid = Raids.IsInRaidInstance(instanceInfo)
    local raidKey, raid = Raids.ResolveCurrent(instanceInfo)

    lines[#lines + 1] = ""
    lines[#lines + 1] = "--- Raids ---"
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

    local killStates = Raids.GetBossKillStates(raid, instanceInfo)
    local bosses = GetPromptBosses(raid, killStates)
    local choices = BuildGroupedPromptChoices(raidKey, raid, bosses)

    lines[#lines + 1] = "promptBosses: " .. tostring(#bosses)
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("ENCOUNTER_END")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local _, _, _, _, endStatus = ...
        if endStatus ~= 1 then
            return
        end

        dismissedRaidKey = nil
        Raids.RequestLockoutRefresh()
        ScheduleEvaluate(1.0)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        if IsInInstance() then
            Raids.RequestLockoutRefresh()
            ScheduleEvaluate(ENTER_EVALUATE_DELAY)
        else
            ScheduleEvaluate(0.5)
        end
        return
    end

    if event == "UPDATE_INSTANCE_INFO" then
        ScheduleEvaluate(0.1)
    end
end)
