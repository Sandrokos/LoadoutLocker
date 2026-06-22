LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}
GearSpecChangerDB = GearSpecChangerDB or {}

local function MigrateSavedData()
    if not next(LoadoutLockerDB) and next(GearSpecChangerDB) then
        LoadoutLockerDB = GearSpecChangerDB
        GearSpecChangerDB = nil
    end
end

function DB:Initialize()
    MigrateSavedData()
    LoadoutLockerDB = LoadoutLockerDB or {}
end

function DB:EnsureSpecTable(specID)
    LoadoutLockerDB[specID] = LoadoutLockerDB[specID] or {}
    return LoadoutLockerDB[specID]
end

function DB:GetEntry(specID, configID)
    local specData = LoadoutLockerDB[specID]
    return specData and specData[configID]
end

function DB:GetGearSet(specID, configID)
    local entry = self:GetEntry(specID, configID)
    return entry and entry.gear
end

function DB:HasGearSet(specID, configID)
    return self:GetGearSet(specID, configID) ~= nil
end

function DB:SetGearSet(specID, configID, gear, loadoutName)
    local specData = self:EnsureSpecTable(specID)
    specData[configID] = {
        gear = gear,
        loadoutName = loadoutName,
        savedAt = time(),
    }
end

function DB:DeleteGearSet(specID, configID)
    local specData = LoadoutLockerDB[specID]
    local entry = specData and specData[configID]
    if not entry then
        return nil
    end

    specData[configID] = nil
    return entry
end

function DB:GetSpecEntries(specID)
    return LoadoutLockerDB[specID]
end
