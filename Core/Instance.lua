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
    }
end

function Instance.Resolve(instanceInfo, expectedType, byKey, byInstanceID, byLfgDungeonID)
    if not instanceInfo or instanceInfo.instanceType ~= expectedType then
        return nil
    end

    local instanceName = instanceInfo.name
    local instanceID = instanceInfo.instanceID
    local lfgDungeonID = instanceInfo.lfgDungeonID

    if lfgDungeonID and byLfgDungeonID then
        local key = byLfgDungeonID[lfgDungeonID]
        if key then
            return key, byKey[key], instanceName
        end
    end
    local keys = instanceID and byInstanceID[instanceID]

    if keys then
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

    for _, entity in pairs(byKey) do
        if Text.NameMatches(instanceName, entity) then
            return entity.key, entity, instanceName
        end
    end
end
