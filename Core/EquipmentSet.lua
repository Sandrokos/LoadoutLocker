LoadoutLocker = LoadoutLocker or {}

local EquipmentSet = {}
LoadoutLocker.EquipmentSet = EquipmentSet

local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Loadout = LoadoutLocker.Loadout
local Print = LoadoutLocker.Print

local pendingSync
local syncFallbackTimer
local syncFrame = CreateFrame("Frame")

local function ClearPendingSync()
    pendingSync = nil
    if syncFallbackTimer then
        syncFallbackTimer:Cancel()
        syncFallbackTimer = nil
    end
    syncFrame:UnregisterEvent("EQUIPMENT_SWAP_FINISHED")
end

local function FlushPendingSync()
    if not pendingSync then
        return
    end

    local data = pendingSync
    ClearPendingSync()
    EquipmentSet.SyncForLoadout(data.specID, data.configID, data.loadoutName)
end

syncFrame:SetScript("OnEvent", function(_, event)
    if event == "EQUIPMENT_SWAP_FINISHED" and pendingSync then
        FlushPendingSync()
    end
end)

local function GetAPI()
    return C_EquipmentSet
end

local function GetSpecIcon(specID)
    if not specID then
        return nil
    end

    local id, _, _, icon
    if GetSpecializationInfoForSpecID then
        id, _, _, icon = GetSpecializationInfoForSpecID(specID)
    elseif GetSpecializationInfoByID then
        id, _, _, icon = GetSpecializationInfoByID(specID)
    end

    if id == specID and icon and icon > 0 then
        return icon
    end

    return nil
end

local function ApplySetIcon(api, setID, setName, icon)
    if not icon or not setID or not api.ModifyEquipmentSet or not api.GetEquipmentSetInfo then
        return
    end

    local currentName, currentIcon = api.GetEquipmentSetInfo(setID)
    if currentIcon == icon then
        return
    end

    api.ModifyEquipmentSet(setID, setName or currentName, icon)
end

function EquipmentSet.IsAvailable()
    local api = GetAPI()
    return api and api.CanUseEquipmentSets and api.CanUseEquipmentSets()
end

function EquipmentSet.GetSetID(setName)
    if not setName then
        return nil
    end

    local api = GetAPI()
    if not api or not api.GetEquipmentSetID then
        return nil
    end

    return api.GetEquipmentSetID(setName)
end

function EquipmentSet.BuildSetName(loadoutName, configID)
    local label = loadoutName
    if not label or label == "" then
        label = "Loadout " .. tostring(configID or "?")
    end

    local name = C.EQUIPMENT_SET_PREFIX .. label
    if #name > C.EQUIPMENT_SET_MAX_NAME then
        name = string.sub(name, 1, C.EQUIPMENT_SET_MAX_NAME)
    end

    return name
end

function EquipmentSet.GetLoadoutsUsingSetName(specID, setName, excludeConfigID)
    local matches = {}
    if not setName then
        return matches
    end

    local specData = DB:GetSpecEntries(specID)
    if not specData then
        return matches
    end

    for configID, entry in pairs(specData) do
        if entry.gear and entry.equipmentSetName == setName and configID ~= excludeConfigID then
            matches[#matches + 1] = {
                configID = configID,
                entry = entry,
                name = Loadout.ResolveLoadoutName(configID, entry.loadoutName),
            }
        end
    end

    Loadout.SortByName(matches)
    return matches
end

function EquipmentSet.AssignSetNameToLoadouts(setName, loadouts)
    for _, loadout in ipairs(loadouts) do
        loadout.entry.equipmentSetName = setName
    end
end

function EquipmentSet.DeleteByName(setName)
    if not setName or not EquipmentSet.IsAvailable() then
        return false
    end

    local api = GetAPI()
    local setID = EquipmentSet.GetSetID(setName)
    if not setID or not api.DeleteEquipmentSet then
        return false
    end

    api.DeleteEquipmentSet(setID)
    return true
end

function EquipmentSet.RenameSet(oldName, newName, icon)
    if not oldName or not newName or oldName == newName then
        return oldName == newName
    end

    if not EquipmentSet.IsAvailable() then
        return false
    end

    local api = GetAPI()
    if not api.ModifyEquipmentSet then
        return false
    end

    local setID = EquipmentSet.GetSetID(oldName)
    if not setID then
        return false
    end

    if EquipmentSet.GetSetID(newName) then
        return false
    end

    if icon then
        api.ModifyEquipmentSet(setID, newName, icon)
    else
        api.ModifyEquipmentSet(setID, newName)
    end
    return EquipmentSet.GetSetID(newName) ~= nil
end

function EquipmentSet.EnsureSet(setName, specID)
    if not setName or not EquipmentSet.IsAvailable() then
        return nil
    end

    local api = GetAPI()
    local setID = EquipmentSet.GetSetID(setName)
    local icon = GetSpecIcon(specID)
    if setID then
        ApplySetIcon(api, setID, setName, icon)
        return setID
    end

    if not api.CreateEquipmentSet then
        return nil
    end

    if icon then
        api.CreateEquipmentSet(setName, icon)
    else
        api.CreateEquipmentSet(setName)
    end
    return EquipmentSet.GetSetID(setName)
end

function EquipmentSet.LinkCopiedLoadouts(specID, sourceConfigID, targetConfigID)
    local sourceEntry = DB:GetEntry(specID, sourceConfigID)
    local targetEntry = DB:GetEntry(specID, targetConfigID)
    if not sourceEntry or not targetEntry then
        return
    end

    local setName = sourceEntry.equipmentSetName
    if not setName then
        setName = EquipmentSet.BuildSetName(
            Loadout.ResolveLoadoutName(sourceConfigID, sourceEntry.loadoutName),
            sourceConfigID
        )
        sourceEntry.equipmentSetName = setName
    end

    targetEntry.equipmentSetName = setName
end

function EquipmentSet.OnGearSetDeleted(specID, configID, entry)
    if not entry or not entry.equipmentSetName then
        return
    end

    local setName = entry.equipmentSetName
    local remaining = EquipmentSet.GetLoadoutsUsingSetName(specID, setName, configID)

    if #remaining == 0 then
        EquipmentSet.DeleteByName(setName)
        return
    end

    local renameTarget = remaining[1]
    local newName = EquipmentSet.BuildSetName(renameTarget.name, renameTarget.configID)
    if newName == setName then
        return
    end

    if not EquipmentSet.RenameSet(setName, newName, GetSpecIcon(specID)) then
        return
    end

    EquipmentSet.AssignSetNameToLoadouts(newName, remaining)
end

function EquipmentSet.SyncForLoadout(specID, configID, loadoutName)
    if not EquipmentSet.IsAvailable() then
        return false
    end

    local entry = DB:GetEntry(specID, configID)
    if not entry then
        return false
    end

    local api = GetAPI()
    if not api.SaveEquipmentSet then
        return false
    end

    local setName = entry.equipmentSetName
    if not setName then
        setName = EquipmentSet.BuildSetName(loadoutName, configID)
        entry.equipmentSetName = setName
    else
        local desiredName = EquipmentSet.BuildSetName(loadoutName, configID)
        local sharedWith = EquipmentSet.GetLoadoutsUsingSetName(specID, setName, configID)
        if #sharedWith == 0 and setName ~= desiredName then
            if EquipmentSet.RenameSet(setName, desiredName, GetSpecIcon(specID)) then
                setName = desiredName
                entry.equipmentSetName = desiredName
            end
        end
    end

    local setID = EquipmentSet.EnsureSet(setName, specID)
    if not setID then
        Print("Could not create an Equipment Manager set. You may be at the set limit.")
        return false
    end

    local icon = GetSpecIcon(specID)
    if icon then
        api.SaveEquipmentSet(setID, icon)
        ApplySetIcon(api, setID, setName, icon)
    else
        api.SaveEquipmentSet(setID)
    end
    entry.equipmentSetName = setName
    return true
end

function EquipmentSet.ScheduleSyncForLoadout(specID, configID, loadoutName)
    if not EquipmentSet.IsAvailable() then
        return
    end

    pendingSync = {
        specID = specID,
        configID = configID,
        loadoutName = loadoutName,
    }

    syncFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")

    if syncFallbackTimer then
        syncFallbackTimer:Cancel()
    end

    syncFallbackTimer = C_Timer.NewTimer(C.SAVE_RETRY_DELAY + C.EQUIP_SLOT_DELAY, function()
        syncFallbackTimer = nil
        FlushPendingSync()
    end)
end

function EquipmentSet.TryUse(specID, configID)
    if not EquipmentSet.IsAvailable() or InCombatLockdown() then
        return false
    end

    local entry = DB:GetEntry(specID, configID)
    if not entry or not entry.equipmentSetName then
        return false
    end

    local api = GetAPI()
    if not api.UseEquipmentSet then
        return false
    end

    local setID = EquipmentSet.GetSetID(entry.equipmentSetName)
    if not setID then
        return false
    end

    return api.UseEquipmentSet(setID) == true
end
