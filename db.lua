LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}

function DB:Initialize()
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

function DB:CopyGearSet(gear)
    local copy = {}
    for slot, entry in pairs(gear) do
        local invSlot = tonumber(slot) or slot
        if type(entry) == "table" then
            local slotCopy = {
                itemID = entry.itemID,
                itemLink = entry.itemLink,
            }
            if entry.enchantID then
                slotCopy.enchantID = entry.enchantID
            end
            if entry.gems then
                slotCopy.gems = {
                    entry.gems[1] or 0,
                    entry.gems[2] or 0,
                    entry.gems[3] or 0,
                    entry.gems[4] or 0,
                }
            end
            if entry.itemLevel then
                slotCopy.itemLevel = entry.itemLevel
            end
            copy[invSlot] = slotCopy
        else
            copy[invSlot] = entry
        end
    end
    return copy
end

function DB:CreateOrUpdateGearSet(specID, configID, gear, loadoutName)
    local specData = self:EnsureSpecTable(specID)
    specData[configID] = {
        gear = self:CopyGearSet(gear),
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
