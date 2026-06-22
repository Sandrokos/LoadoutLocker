LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}

function DB:Initialize()
    LoadoutLockerDB = LoadoutLockerDB or {}
    self:GetTertiaryPriority()
end

function DB:AreUpgradeChecksEnabled()
    return LoadoutLockerDB.upgradeChecksEnabled ~= false
end

function DB:SetUpgradeChecksEnabled(enabled)
    LoadoutLockerDB.upgradeChecksEnabled = enabled and true or false
end

local function GetDefaultTertiaryPriority()
    local C = LoadoutLocker.Constants
    return C and C.DEFAULT_TERTIARY_PRIORITY or { "sockets", "avoidance", "leech", "speed" }
end

local function GetTertiaryFields()
    local C = LoadoutLocker.Constants
    return C and C.TERTIARY_FIELDS or {
        sockets = true,
        avoidance = true,
        leech = true,
        speed = true,
    }
end

function DB:NormalizeTertiaryPriority(priority)
    local valid = {}
    local seen = {}
    local fields = GetTertiaryFields()

    if type(priority) == "table" then
        for _, field in ipairs(priority) do
            if fields[field] and not seen[field] then
                seen[field] = true
                valid[#valid + 1] = field
            end
        end
    end

    for _, field in ipairs(GetDefaultTertiaryPriority()) do
        if not seen[field] then
            valid[#valid + 1] = field
        end
    end

    return valid
end

function DB:GetTertiaryPriority()
    local priority = self:NormalizeTertiaryPriority(LoadoutLockerDB.tertiaryPriority)
    LoadoutLockerDB.tertiaryPriority = priority

    local copy = {}
    for index, field in ipairs(priority) do
        copy[index] = field
    end

    return copy
end

function DB:SetTertiaryPriority(priority)
    LoadoutLockerDB.tertiaryPriority = self:NormalizeTertiaryPriority(priority)
end

function DB:ResetTertiaryPriority()
    LoadoutLockerDB.tertiaryPriority = nil
    return self:GetTertiaryPriority()
end

function DB:MoveTertiaryPriority(field, direction)
    local priority = self:GetTertiaryPriority()
    local index

    for i, entry in ipairs(priority) do
        if entry == field then
            index = i
            break
        end
    end

    if not index then
        return false
    end

    local swapIndex = direction == "up" and (index - 1) or (index + 1)
    if swapIndex < 1 or swapIndex > #priority then
        return false
    end

    priority[index], priority[swapIndex] = priority[swapIndex], priority[index]
    self:SetTertiaryPriority(priority)
    return true
end

function DB:NormalizeInvSlot(invSlot)
    return tonumber(invSlot) or invSlot
end

function DB:GetIgnoredUpgradeSlots(specID, configID)
    local entry = self:GetEntry(specID, configID)
    return entry and entry.ignoredUpgradeSlots
end

function DB:IsUpgradeSlotIgnored(specID, configID, invSlot)
    local ignored = self:GetIgnoredUpgradeSlots(specID, configID)
    if not ignored then
        return false
    end

    local slot = self:NormalizeInvSlot(invSlot)
    return ignored[slot] or ignored[tostring(slot)] or false
end

function DB:GetIgnoredUpgradeSlotList(specID, configID)
    local ignored = self:GetIgnoredUpgradeSlots(specID, configID)
    if not ignored then
        return {}
    end

    local slots = {}
    for slot in pairs(ignored) do
        slots[#slots + 1] = self:NormalizeInvSlot(slot)
    end

    table.sort(slots)
    return slots
end

function DB:SetIgnoredUpgradeSlot(specID, configID, invSlot)
    local entry = self:GetEntry(specID, configID)
    if not entry then
        return false
    end

    entry.ignoredUpgradeSlots = entry.ignoredUpgradeSlots or {}
    entry.ignoredUpgradeSlots[self:NormalizeInvSlot(invSlot)] = true
    return true
end

function DB:ClearIgnoredUpgradeSlot(specID, configID, invSlot)
    local entry = self:GetEntry(specID, configID)
    if not entry or not entry.ignoredUpgradeSlots then
        return false
    end

    local slot = self:NormalizeInvSlot(invSlot)
    entry.ignoredUpgradeSlots[slot] = nil
    entry.ignoredUpgradeSlots[tostring(slot)] = nil

    if not next(entry.ignoredUpgradeSlots) then
        entry.ignoredUpgradeSlots = nil
    end

    return true
end

function DB:ClearAllIgnoredUpgradeSlots(specID, configID)
    local entry = self:GetEntry(specID, configID)
    if not entry or not entry.ignoredUpgradeSlots then
        return false
    end

    entry.ignoredUpgradeSlots = nil
    return true
end

function DB:GetSavedGearSetList(specID)
    local specData = self:GetSpecEntries(specID)
    if not specData then
        return {}
    end

    local list = {}
    for configID, entry in pairs(specData) do
        if entry.gear then
            list[#list + 1] = {
                configID = configID,
                name = entry.loadoutName or ("Loadout " .. tostring(configID)),
            }
        end
    end

    table.sort(list, function(a, b)
        return a.name < b.name
    end)

    return list
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
    local Items = LoadoutLocker.Items

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
            if entry.gems and Items then
                local gems = Items.CopyGemsTable(entry.gems)
                if gems then
                    slotCopy.gems = gems
                end
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
    local existing = specData[configID]
    specData[configID] = {
        gear = self:CopyGearSet(gear),
        loadoutName = loadoutName,
        savedAt = time(),
        ignoredUpgradeSlots = existing and existing.ignoredUpgradeSlots,
    }
end

function DB:CopyGearSetToLoadout(specID, sourceConfigID, targetConfigID, targetLoadoutName)
    local gear = self:GetGearSet(specID, sourceConfigID)
    if not gear then
        return false
    end

    local specData = self:EnsureSpecTable(specID)
    specData[targetConfigID] = {
        gear = self:CopyGearSet(gear),
        loadoutName = targetLoadoutName,
        savedAt = time(),
    }
    return true
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
