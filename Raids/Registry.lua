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

function Raids.IsInRaidInstance(instanceInfo)
    instanceInfo = instanceInfo or Instance.GetCurrent()
    return instanceInfo.instanceType == "raid"
end

function Raids.ResolveCurrent(instanceInfo)
    return Instance.Resolve(instanceInfo or Instance.GetCurrent(), "raid", byKey, byInstanceID)
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
