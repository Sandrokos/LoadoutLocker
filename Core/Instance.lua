LoadoutLocker = LoadoutLocker or {}

local Instance = {}
LoadoutLocker.Instance = Instance

local Text = LoadoutLocker.Text

function Instance.GetCurrent()
    local name, instanceType, difficultyID, _, _, _, _, instanceID, _, lfgDungeonID, numEncounters =
        GetInstanceInfo()

    return {
        name = name,
        instanceType = instanceType,
        difficultyID = difficultyID,
        instanceID = instanceID,
        lfgDungeonID = lfgDungeonID,
        numEncounters = numEncounters,
        inInstance = IsInInstance(),
    }
end

function Instance.CollectZoneNames(instanceInfo)
    local seen = {}
    local names = {}

    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    if instanceInfo then
        add(instanceInfo.name)
    end
    add(GetZoneText())
    add(GetSubZoneText())
    add(GetRealZoneText())

    return names
end

function Instance.MatchEntityName(instanceName, byKey)
    if not instanceName then
        return nil
    end

    for _, entity in pairs(byKey) do
        if Text.NameMatches(instanceName, entity) then
            return entity.key, entity
        end
    end
end

local function ResolveByInstanceID(instanceInfo, byKey, byInstanceID)
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

function Instance.Resolve(instanceInfo, expectedType, byKey, byInstanceID, byLfgDungeonID)
    if not instanceInfo then
        return nil
    end

    local instanceName = instanceInfo.name
    local key, entity, name = ResolveByInstanceID(instanceInfo, byKey, byInstanceID)
    if key then
        return key, entity, name
    end

    if instanceInfo.instanceType ~= expectedType then
        return nil
    end

    local lfgDungeonID = instanceInfo.lfgDungeonID
    if lfgDungeonID and byLfgDungeonID then
        key = byLfgDungeonID[lfgDungeonID]
        if key then
            return key, byKey[key], instanceName
        end
    end

    key, entity = Instance.MatchEntityName(instanceName, byKey)
    if key then
        return key, entity, instanceName
    end
end
