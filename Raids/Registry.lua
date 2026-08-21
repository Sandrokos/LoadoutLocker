LoadoutLocker = LoadoutLocker or {}

local Raids = {}
LoadoutLocker.Raids = Raids

local Catalog = LoadoutLocker.RaidCatalog
local RaidConstants = LoadoutLocker.RaidConstants
local Constants = LoadoutLocker.Constants
local Instance = LoadoutLocker.Instance
local Text = LoadoutLocker.Text

local byKey = {}
local byInstanceID = {}
local sessionKills = {}

local function RegisterRaid(raid)
    if byKey[raid.key] then
        return
    end

    Text.PrepareEntity(raid)

    for _, boss in ipairs(raid.bosses) do
        Text.PrepareEntity(boss)
    end

    byKey[raid.key] = raid

    for _, instanceID in ipairs(raid.instanceIDs) do
        local keys = byInstanceID[instanceID]
        if not keys then
            keys = {}
            byInstanceID[instanceID] = keys
        end
        keys[#keys + 1] = raid.key
    end
end

for _, raid in ipairs(Catalog.SEASON_ONE) do
    RegisterRaid(raid)
end

for _, raid in ipairs(Catalog.SEASON_TWO) do
    RegisterRaid(raid)
end

function Raids.GetByKey(key)
    return byKey[key]
end

function Raids.GetMenuSections()
    return {
        {
            key = "season2",
            tabText = "Season 2",
            header = RaidConstants.SEASON_TWO_HEADER,
            raids = Catalog.SEASON_TWO,
        },
        {
            key = "season1",
            tabText = "Season 1",
            header = RaidConstants.SEASON_ONE_HEADER,
            raids = Catalog.SEASON_ONE,
        },
    }
end

local function ResolveFromZoneNames(instanceInfo, byKey)
    for _, zoneName in ipairs(Instance.CollectZoneNames(instanceInfo)) do
        local key, entity = Instance.MatchEntityName(zoneName, byKey)
        if key then
            return key, entity, zoneName
        end
    end
end

local function ResolveFromPlayerMap(byKey, byInstanceID)
    if not C_Map or not C_Map.GetBestMapForUnit or not EJ_GetInstanceForMap or not EJ_GetInstanceInfo then
        return nil
    end

    local uiMapID = C_Map.GetBestMapForUnit("player")
    if not uiMapID then
        return nil
    end

    local journalInstanceID = EJ_GetInstanceForMap(uiMapID)
    if not journalInstanceID or journalInstanceID <= 0 then
        return nil
    end

    local name, _, _, _, _, _, _, _, _, mapInstanceID, _, isRaid = EJ_GetInstanceInfo(journalInstanceID)
    if not isRaid or not mapInstanceID then
        return nil
    end

    return Instance.Resolve({
        name = name,
        instanceType = "raid",
        instanceID = mapInstanceID,
    }, "raid", byKey, byInstanceID)
end

function Raids.IsInRaidInstance(instanceInfo)
    instanceInfo = instanceInfo or Instance.GetCurrent()
    -- 5-man dungeons are never raids. Subzones like "The Galvanized Grotto"
    -- in Temple of Sethraliss must not trigger Tidebound Grotto prompts.
    if instanceInfo.instanceType == "party" then
        return false
    end

    if instanceInfo.instanceType == "raid" then
        return true
    end

    if instanceInfo.inInstance and Raids.ResolveCurrent(instanceInfo) then
        return true
    end

    return false
end

function Raids.ResolveCurrent(instanceInfo)
    instanceInfo = instanceInfo or Instance.GetCurrent()
    if instanceInfo.instanceType == "party" then
        return
    end

    local key, entity, name = Instance.Resolve(instanceInfo, "raid", byKey, byInstanceID)
    if key then
        return key, entity, name
    end

    if instanceInfo.inInstance or IsInInstance() then
        key, entity, name = ResolveFromZoneNames(instanceInfo, byKey)
        if key then
            return key, entity, name
        end

        key, entity, name = ResolveFromPlayerMap(byKey, byInstanceID)
        if key then
            return key, entity, name
        end
    end

    if instanceInfo.instanceType ~= "none" and instanceInfo.instanceType ~= "raid" then
        return ResolveFromZoneNames(instanceInfo, byKey)
    end
end

function Raids.FindBossByName(raid, encounterName)
    if not raid or not encounterName then
        return nil
    end

    for _, boss in ipairs(raid.bosses) do
        if Text.NameMatches(encounterName, boss) then
            return boss
        end
    end
end

local function FindSavedInstance(instanceID, difficultyID)
    for index = 1, GetNumSavedInstances() do
        local _, _, _, savedDifficultyID, _, _, _, _, _, _, numEncounters, _, _, savedInstanceID =
            GetSavedInstanceInfo(index)

        if savedInstanceID == instanceID and savedDifficultyID == difficultyID then
            return index, numEncounters
        end
    end
end

function Raids.GetBossKillStates(raid, instanceInfo)
    local states = {}

    for _, boss in ipairs(raid.bosses) do
        states[boss.key] = false
    end

    if not instanceInfo or not instanceInfo.instanceID or not instanceInfo.difficultyID then
        return states
    end

    local savedIndex = FindSavedInstance(instanceInfo.instanceID, instanceInfo.difficultyID)
    if not savedIndex then
        return states
    end

    for _, boss in ipairs(raid.bosses) do
        local encounterIndex = boss.encounterIndex
        if encounterIndex then
            local _, _, isKilled = GetSavedInstanceEncounterInfo(savedIndex, encounterIndex)
            if isKilled then
                states[boss.key] = true
            end
        end
    end

    return states
end

function Raids.HasSavedLockout(instanceInfo)
    if not instanceInfo or not instanceInfo.instanceID or not instanceInfo.difficultyID then
        return false
    end
    return FindSavedInstance(instanceInfo.instanceID, instanceInfo.difficultyID) ~= nil
end

function Raids.GetAliveBosses(raid, killStates)
    killStates = killStates or Raids.GetBossKillStates(raid)
    local alive = {}

    for _, boss in ipairs(raid.bosses) do
        if not killStates[boss.key] then
            alive[#alive + 1] = boss
        end
    end

    return alive
end

function Raids.GetAvailableBosses(raid, killStates)
    killStates = killStates or Raids.GetBossKillStates(raid)
    local available = {}

    for _, boss in ipairs(raid.bosses) do
        if not killStates[boss.key] then
            local unlocked = true
            for _, requiredKey in ipairs(boss.requires or {}) do
                if not killStates[requiredKey] then
                    unlocked = false
                    break
                end
            end

            if unlocked then
                available[#available + 1] = boss
            end
        end
    end

    return available
end

function Raids.RecordInstanceBossKill(instanceInfo, bossKey)
    local instanceID = instanceInfo and instanceInfo.instanceID
    if not instanceID or not bossKey then
        return
    end

    local kills = sessionKills[instanceID]
    if not kills then
        kills = {}
        sessionKills[instanceID] = kills
    end
    kills[bossKey] = true
end

local journalInstanceByMapID = {}
local journalEncounterByBoss = {}

local function FindJournalInstanceID(mapInstanceID)
    if not mapInstanceID then
        return nil
    end

    if journalInstanceByMapID[mapInstanceID] then
        return journalInstanceByMapID[mapInstanceID]
    end

    if not EJ_GetInstanceByIndex or not EJ_GetInstanceInfo then
        return nil
    end

    local index = 1
    while true do
        local journalInstanceID = EJ_GetInstanceByIndex(index, true)
        if not journalInstanceID then
            break
        end

        local _, _, _, _, _, _, _, _, _, ejMapInstanceID = EJ_GetInstanceInfo(journalInstanceID)
        if ejMapInstanceID == mapInstanceID then
            journalInstanceByMapID[mapInstanceID] = journalInstanceID
            return journalInstanceID
        end

        index = index + 1
    end
end

local function GetJournalEncounterID(raid, boss, mapInstanceID)
    local cacheKey = raid.key .. ":" .. boss.key
    if journalEncounterByBoss[cacheKey] then
        return journalEncounterByBoss[cacheKey]
    end

    if boss.encounterID then
        journalEncounterByBoss[cacheKey] = boss.encounterID
        return boss.encounterID
    end

    if not boss.encounterIndex or not EJ_GetEncounterInfoByIndex then
        return nil
    end

    local journalInstanceID = FindJournalInstanceID(mapInstanceID)
    if not journalInstanceID then
        return nil
    end

    if EJ_SelectInstance then
        EJ_SelectInstance(journalInstanceID)
    end

    local _, _, encounterID = EJ_GetEncounterInfoByIndex(boss.encounterIndex)
    if encounterID then
        journalEncounterByBoss[cacheKey] = encounterID
    end

    return encounterID
end

local function ResolveRaidDifficultyID(instanceInfo)
    local mapID = instanceInfo and instanceInfo.instanceID
    local difficultyID = instanceInfo and instanceInfo.difficultyID
    if not mapID or not difficultyID then
        return nil
    end

    if C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID then
        return C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID) or difficultyID
    end

    return difficultyID
end

local function MergeKillStates(target, source)
    if not source then
        return
    end

    for key, killed in pairs(source) do
        if killed and target[key] ~= nil then
            target[key] = true
        end
    end
end

local function GetKillStatesFromLockTimeRemaining(raid)
    local states = {}

    if not GetInstanceLockTimeRemaining or not GetInstanceLockTimeRemainingEncounter then
        return states
    end

    local _, _, encountersTotal = GetInstanceLockTimeRemaining()
    if not encountersTotal or encountersTotal <= 0 then
        return states
    end

    for index = 1, encountersTotal do
        local bossName, _, isKilled = GetInstanceLockTimeRemainingEncounter(index)
        if bossName and isKilled then
            local boss = Raids.FindBossByName(raid, bossName)
            if boss then
                states[boss.key] = true
            end
        end
    end

    for _, boss in ipairs(raid.bosses) do
        local encounterIndex = boss.encounterIndex
        if encounterIndex and encounterIndex <= encountersTotal then
            local _, _, isKilled = GetInstanceLockTimeRemainingEncounter(encounterIndex)
            if isKilled then
                states[boss.key] = true
            end
        end
    end

    return states
end

local function GetKillStatesFromRaidLocks(raid, instanceInfo)
    local states = {}

    if not C_RaidLocks or not C_RaidLocks.IsEncounterComplete then
        return states
    end

    local mapID = instanceInfo.instanceID
    local difficultyID = ResolveRaidDifficultyID(instanceInfo)
    if not mapID or not difficultyID then
        return states
    end

    for _, boss in ipairs(raid.bosses) do
        local encounterID = GetJournalEncounterID(raid, boss, mapID)
        if encounterID and C_RaidLocks.IsEncounterComplete(mapID, encounterID, difficultyID) then
            states[boss.key] = true
        end
    end

    return states
end

function Raids.GetInstanceBossKillStates(raid, instanceInfo)
    local states = {}

    for _, boss in ipairs(raid.bosses) do
        states[boss.key] = false
    end

    if not instanceInfo then
        return states
    end

    if instanceInfo.inInstance then
        local lockTimeStates = GetKillStatesFromLockTimeRemaining(raid)
        MergeKillStates(states, lockTimeStates)

        local _, _, encountersTotal = GetInstanceLockTimeRemaining and GetInstanceLockTimeRemaining() or nil
        local hasInstanceLockData = encountersTotal and encountersTotal > 0
        local isMythic = instanceInfo.difficultyID == Constants.MYTHIC_RAID_DIFFICULTY_ID

        if hasInstanceLockData or isMythic then
            MergeKillStates(states, GetKillStatesFromRaidLocks(raid, instanceInfo))
        end

        if isMythic then
            MergeKillStates(states, Raids.GetBossKillStates(raid, instanceInfo))
        end
    end

    if instanceInfo.instanceID then
        local kills = sessionKills[instanceInfo.instanceID]
        if kills then
            MergeKillStates(states, kills)
        end
    end

    return states
end

function Raids.GetAliveBossesInInstance(raid, instanceInfo)
    return Raids.GetAliveBosses(raid, Raids.GetInstanceBossKillStates(raid, instanceInfo))
end

function Raids.RequestLockoutRefresh()
    if RequestRaidInfo then
        RequestRaidInfo()
    end
end
