LoadoutLocker = LoadoutLocker or {}

local Loadout = {}
LoadoutLocker.Loadout = Loadout
LoadoutLocker.Talents = Loadout

local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB

local activeLoadoutBySpec = {}
local pendingLoadoutSwitch
local loadoutSelectionHooked

function Loadout.GetSpecID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        return select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    end
end

function Loadout.GetLoadoutConfigID(specID)
    specID = specID or Loadout.GetSpecID()
    if specID then
        return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end
end

function Loadout.GetLoadoutName(configID)
    if not configID then
        return nil
    end

    if configID == C.STARTER_BUILD_CONFIG_ID then
        return "Starter Build"
    end

    local configInfo = C_Traits.GetConfigInfo(configID)
    return configInfo and configInfo.name or ("Loadout " .. tostring(configID))
end

function Loadout.IsStarterBuild(configID)
    return configID == C.STARTER_BUILD_CONFIG_ID
end

function Loadout.RememberActive(specID, configID)
    if specID and configID then
        activeLoadoutBySpec[specID] = configID
    end
end

function Loadout.GetActive(specID)
    specID = specID or Loadout.GetSpecID()
    if not specID then
        return nil
    end

    local configID = Loadout.GetLoadoutConfigID(specID)
    if not configID then
        return nil
    end

    return {
        specID = specID,
        configID = configID,
        name = Loadout.GetLoadoutName(configID),
        isStarter = Loadout.IsStarterBuild(configID),
        hasSavedGear = DB:HasGearSet(specID, configID),
        gear = DB:GetGearSet(specID, configID),
    }
end

function Loadout.GetActiveGearSetCopy(specID)
    local context = Loadout.GetActive(specID)
    if not context or not context.gear then
        return nil, context
    end

    return DB:CopyGearSet(context.gear), context
end

function Loadout.ConsumePendingSwitch()
    local switch = pendingLoadoutSwitch
    pendingLoadoutSwitch = nil
    return switch
end

function Loadout.GetPreviousConfigID(specID)
    return activeLoadoutBySpec[specID]
end

function Loadout.HookSelection()
    if loadoutSelectionHooked or not C_ClassTalents or not C_ClassTalents.UpdateLastSelectedSavedConfigID then
        return
    end

    loadoutSelectionHooked = true

    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function(specID, configID)
        if not specID or not configID or Loadout.IsStarterBuild(configID) then
            return
        end

        pendingLoadoutSwitch = { specID = specID, configID = configID }
    end)
end

function Loadout.RecordCurrent()
    local specID = Loadout.GetSpecID()
    local configID = specID and Loadout.GetLoadoutConfigID(specID)
    if specID and configID then
        Loadout.RememberActive(specID, configID)
        return true
    end
end

function Loadout.GetConfigList(specID)
    specID = specID or Loadout.GetSpecID()
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then
        return {}
    end

    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID) or {}
    local list = {}

    for _, configID in ipairs(configIDs) do
        if not Loadout.IsStarterBuild(configID) then
            list[#list + 1] = {
                configID = configID,
                name = Loadout.GetLoadoutName(configID),
                hasSavedGear = DB:HasGearSet(specID, configID),
            }
        end
    end

    table.sort(list, function(a, b)
        return a.name < b.name
    end)

    return list
end

Loadout.HookSelection()
