LoadoutLocker = LoadoutLocker or {}

local Loadout = {}
LoadoutLocker.Loadout = Loadout
local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB

local activeLoadoutBySpec = {}
local pendingLoadoutSwitch
local loadoutSelectionHooked
local lastAppliedSpecID
local lastUpgradeCheckBySpec = {}

function Loadout.GetSpecID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        return (C_SpecializationInfo.GetSpecializationInfo(specIndex))
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

function Loadout.ResolveLoadoutName(configID, cachedName)
    if cachedName and cachedName ~= "" then
        return cachedName
    end

    return Loadout.GetLoadoutName(configID)
end

function Loadout.SortByName(list)
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
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

    local gear = DB:GetGearSet(specID, configID)

    return {
        specID = specID,
        configID = configID,
        name = Loadout.GetLoadoutName(configID),
        isStarter = Loadout.IsStarterBuild(configID),
        hasSavedGear = gear ~= nil,
        gear = gear,
    }
end

function Loadout.GetActiveGearSetCopy(specID)
    local context = Loadout.GetActive(specID)
    if not context or not context.gear then
        return nil, context
    end

    return DB:CopyGearSet(context.gear), context
end

function Loadout.QueueSwitch(specID, configID)
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return
    end

    if Loadout.GetSpecID() ~= specID then
        return
    end

    pendingLoadoutSwitch = { specID = specID, configID = configID }
end

function Loadout.ClearPendingSwitch()
    pendingLoadoutSwitch = nil
end

function Loadout.GetLastAppliedSpecID()
    return lastAppliedSpecID
end

function Loadout.RememberAppliedSpec(specID)
    lastAppliedSpecID = specID
end

function Loadout.ShouldApplyGearForSwitch(specID, configID)
    if not specID or not configID then
        return false
    end

    local previousConfigID = Loadout.GetPreviousConfigID(specID)
    if lastAppliedSpecID ~= specID then
        return true
    end

    if previousConfigID == nil then
        return true
    end

    return previousConfigID ~= configID
end

function Loadout.ConsumePendingSwitch()
    local switch = pendingLoadoutSwitch
    pendingLoadoutSwitch = nil
    return switch
end

function Loadout.PeekPendingSwitch()
    return pendingLoadoutSwitch
end

function Loadout.ShouldRunUpgradeCheck(specID, configID)
    if not specID or not configID then
        return false
    end

    return lastUpgradeCheckBySpec[specID] ~= configID
end

function Loadout.RememberUpgradeCheck(specID, configID)
    if specID and configID then
        lastUpgradeCheckBySpec[specID] = configID
    end
end

function Loadout.ClearUpgradeCheck(specID)
    if specID then
        lastUpgradeCheckBySpec[specID] = nil
    end
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

        if Loadout.GetSpecID() ~= specID then
            return
        end

        pendingLoadoutSwitch = { specID = specID, configID = configID }

        local gear = LoadoutLocker.Gear
        if gear and gear.ScheduleLoadoutGearApply then
            gear.ScheduleLoadoutGearApply()
        end
    end)
end

function Loadout.RecordCurrent()
    local specID = Loadout.GetSpecID()
    local configID = specID and Loadout.GetLoadoutConfigID(specID)
    if specID and configID then
        Loadout.RememberActive(specID, configID)
        Loadout.RememberAppliedSpec(specID)
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

    Loadout.SortByName(list)

    return list
end

function Loadout.SwitchTo(configID, specID)
    specID = specID or Loadout.GetSpecID()
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return false, "invalid"
    end

    if Loadout.GetLoadoutConfigID(specID) == configID then
        return true, "unchanged"
    end

    if not C_ClassTalents or not C_ClassTalents.LoadConfig then
        return false, "api"
    end

    local result = C_ClassTalents.LoadConfig(configID, true)
    if result == 0 then
        return false, "error"
    end

    if C_ClassTalents.UpdateLastSelectedSavedConfigID then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    else
        pendingLoadoutSwitch = { specID = specID, configID = configID }
    end

    return true, result
end

Loadout.HookSelection()
