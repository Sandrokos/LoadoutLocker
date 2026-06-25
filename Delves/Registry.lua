LoadoutLocker = LoadoutLocker or {}

local Delves = {}
LoadoutLocker.Delves = Delves

local Catalog = LoadoutLocker.DelveCatalog
local DelveConstants = LoadoutLocker.DelveConstants
local Instance = LoadoutLocker.Instance
local Text = LoadoutLocker.Text

local byKey = {}
local byInstanceID = {}

local function RegisterDelve(delve)
    if byKey[delve.key] then
        return
    end

    Text.PrepareEntity(delve)
    byKey[delve.key] = delve

    for _, instanceID in ipairs(delve.instanceIDs) do
        local keys = byInstanceID[instanceID]
        if not keys then
            keys = {}
            byInstanceID[instanceID] = keys
        end
        keys[#keys + 1] = delve.key
    end
end

for _, delve in ipairs(Catalog.GetAllDelves()) do
    RegisterDelve(delve)
end

function Delves.GetByKey(key)
    return byKey[key]
end

local cachedSections

function Delves.GetMenuSections()
    if not cachedSections then
        cachedSections = {
            {
                key = "midnight",
                tabText = "Midnight",
                header = DelveConstants.MIDNIGHT_HEADER,
                delves = Catalog.MIDNIGHT_DELVES,
            },
            {
                key = "tww",
                tabText = "The War Within",
                shortTabText = "TWW",
                header = DelveConstants.KHAZ_ALGAR_HEADER,
                delves = Catalog.KHAZ_ALGAR_DELVES,
            },
        }
    end

    return cachedSections
end

local function ResolveByInstanceID(instanceInfo)
    local keys = instanceInfo.instanceID and byInstanceID[instanceInfo.instanceID]
    if not keys then
        return nil
    end

    local instanceName = instanceInfo.name
    if #keys == 1 then
        local key = keys[1]
        return key, byKey[key], instanceName
    end

    for _, key in ipairs(keys) do
        local entity = byKey[key]
        if Text.NameMatches(instanceName, entity) then
            return key, entity, instanceName
        end
    end

    local key = keys[1]
    return key, byKey[key], instanceName
end

function Delves.IsInDelveInstance(instanceInfo)
    if C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress() then
        return true
    end

    instanceInfo = instanceInfo or Instance.GetCurrent()
    if instanceInfo.instanceType == "scenario" and Delves.ResolveCurrent(instanceInfo) then
        return true
    end

    return false
end

function Delves.ResolveCurrent(instanceInfo)
    instanceInfo = instanceInfo or Instance.GetCurrent()

    local key, entity, name = ResolveByInstanceID(instanceInfo)
    if key then
        return key, entity, name
    end

    for _, zoneName in ipairs(Instance.CollectZoneNames(instanceInfo)) do
        key, entity = Instance.MatchEntityName(zoneName, byKey)
        if key then
            return key, entity, zoneName
        end
    end
end
