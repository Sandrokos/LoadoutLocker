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
local ContentPromptUI = LoadoutLocker.ContentPromptUI

local simFrame
local simRaidButtons = {}
local simBossRows = {}
local lastRaidKey
local simulatedRaidKey
local simulatedKills = {}
local stoppingSim
local MAX_SIM_BOSSES = 8
local ENTER_EVALUATE_DELAY = 2.0

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

local RaidPrompt = ContentPromptUI.Create({
    globalName = "LoadoutLockerRaidPrompt",
    title = "Raid Loadout",
    label = "raid",
    listHelpText = "Assigned loadouts for this raid:",
    skipZoneEvaluate = true,
    arePromptsEnabled = function()
        return DB:AreRaidPromptsEnabled()
    end,
    isInInstance = function()
        return false
    end,
    resolveCurrent = function()
        return nil
    end,
    getLoadoutRef = function()
        return nil
    end,
    getByKey = function(key)
        return Raids.GetByKey(key)
    end,
    getFallbackContent = function()
        return nil
    end,
})

local function BuildGroupedPromptChoices(raidKey, bosses)
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

    if #order == 0 then
        return nil
    end

    local choices = {}
    for _, key in ipairs(order) do
        local group = groups[key]
        choices[#choices + 1] = ContentPromptUI.BuildChoice(
            group.specID,
            group.configID,
            table.concat(group.bossNames, "\n")
        )
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
    return BuildGroupedPromptChoices(raidKey, raid.bosses) ~= nil
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

    local choices = BuildGroupedPromptChoices(simulatedRaidKey, aliveBosses)
    if ContentPromptUI.SelectLayout(choices, false) == "hide" then
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
    RaidPrompt.ClearDismiss()
    lastRaidKey = nil
    RaidPrompt.HidePrompt()
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
    RaidPrompt.ClearDismiss()
    RefreshSimPanel()
    RaidUI.Evaluate({ force = true })
end

function RaidUI.MarkSimulatedBossKilled(bossKey)
    if not simulatedRaidKey or not bossKey or simulatedKills[bossKey] then
        return
    end

    simulatedKills[bossKey] = true
    RaidPrompt.ClearDismiss()
    RefreshSimPanel()
    RaidUI.Evaluate({ force = true })
end

function RaidUI.ShowSimPanel(preferredRaidKey)
    EnsureSimPanel()

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
            RaidPrompt.HidePrompt()
            return
        end
        instanceInfo = GetSimulatedInstanceInfo(raid)
    elseif not Raids.IsInRaidInstance(instanceInfo) then
        if lastRaidKey then
            RaidPrompt.ClearDismiss()
            lastRaidKey = nil
        end
        RaidPrompt.HidePrompt()
        return
    else
        raidKey, raid = Raids.ResolveCurrent(instanceInfo)
    end

    if not raidKey or not raid then
        RaidPrompt.HidePrompt()
        return
    end

    local bosses = GetPromptBosses(raid, instanceInfo)
    if #bosses == 0 then
        RaidPrompt.HidePrompt()
        return
    end

    if RaidPrompt.IsLoading() then
        return
    end

    if lastRaidKey and lastRaidKey ~= raidKey then
        RaidPrompt.ClearDismiss()
    end

    lastRaidKey = raidKey

    local choices = BuildGroupedPromptChoices(raidKey, bosses)

    if not choices or #choices == 0 then
        RaidPrompt.HidePrompt()
        return
    end

    RaidPrompt.ShowPrompt(raidKey, raid, choices, { force = usingSimulation or options.force })
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
        .. tostring(defaultRef and Loadout.GetAssignedLoadoutLabel(defaultRef.specID, defaultRef.configID))
    lines[#lines + 1] = "dismissed: shared prompt"

    if not raidKey or not raid then
        return
    end

    local killStates = simulating and GetSimulatedKillStates(raid) or Raids.GetInstanceBossKillStates(raid, instanceInfo)
    local bosses = GetPromptBosses(raid, instanceInfo)
    local choices = BuildGroupedPromptChoices(raidKey, bosses)

    lines[#lines + 1] = "promptBosses: " .. tostring(#bosses)
    lines[#lines + 1] = "instanceKills:"
    for _, boss in ipairs(raid.bosses) do
        lines[#lines + 1] = "  " .. boss.key .. ": " .. tostring(killStates[boss.key] and "dead" or "alive")
    end
    lines[#lines + 1] = "choices: " .. tostring(choices and #choices or 0)

    if choices then
        for index, choice in ipairs(choices) do
            lines[#lines + 1] = "  choice " .. index .. ": " .. tostring(choice.loadoutLabel)
        end
    end

    lines[#lines + 1] = "boss assignments:"
    for _, boss in ipairs(bosses) do
        local ref = DB:GetRaidBossLoadoutRef(raidKey, boss.key)
        lines[#lines + 1] = "  " .. boss.key .. " -> "
            .. tostring(ref and Loadout.GetAssignedLoadoutLabel(ref.specID, ref.configID))
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

        RaidPrompt.ClearDismiss()
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
