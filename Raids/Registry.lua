LoadoutLocker = LoadoutLocker or {}

local Raids = {}
LoadoutLocker.Raids = Raids

local Catalog = LoadoutLocker.RaidCatalog
local RaidConstants = LoadoutLocker.RaidConstants
local Instance = LoadoutLocker.Instance
local Text = LoadoutLocker.Text

local byKey = {}
local byInstanceID = {}

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

for _, raid in ipairs(Catalog.CURRENT_TIER) do
    RegisterRaid(raid)
end

function Raids.GetByKey(key)
    return byKey[key]
end

function Raids.GetMenuSections()
    return {
        {
            header = RaidConstants.SEASON_ONE_HEADER,
            raids = Catalog.CURRENT_TIER,
        },
    }
end

local function ResolveFromZoneNames(instanceInfo, raidsByKey)
    for _, zoneName in ipairs(Instance.CollectZoneNames(instanceInfo)) do
        local key, entity = Instance.MatchEntityName(zoneName, raidsByKey)
        if key then
            return key, entity, zoneName
        end
    end
end

local function ResolveFromPlayerMap(raidsByKey, raidsByInstanceID)
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

    local savedIndex, savedEncounters = FindSavedInstance(instanceInfo.instanceID, instanceInfo.difficultyID)
    local encounterCount = savedEncounters or instanceInfo.numEncounters or #raid.bosses

    if not savedIndex then
        return states
    end

    for encounterIndex = 1, encounterCount do
        local bossName, _, isKilled = GetSavedInstanceEncounterInfo(savedIndex, encounterIndex)
        if bossName and isKilled then
            local boss = Raids.FindBossByName(raid, bossName)
            if boss then
                states[boss.key] = true
            end
        end
    end

    return states
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

function Raids.RequestLockoutRefresh()
    if RequestRaidInfo then
        RequestRaidInfo()
    end
end
