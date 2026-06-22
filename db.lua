LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}

local C = LoadoutLocker.Constants
local cachedTertiaryPriority

local function NormalizeInvSlot(invSlot)
    return LoadoutLocker.Gear.NormalizeInvSlot(invSlot)
end

local function InvalidateTertiaryPriorityCache()
    cachedTertiaryPriority = nil
end

local function NormalizeGearEntry(entry)
    local Items = LoadoutLocker.Items
    if type(entry) == "table" then
        local slotCopy = {
            itemID = entry.itemID,
            itemLink = entry.itemLink,
        }
        if entry.itemLevel then
            slotCopy.itemLevel = entry.itemLevel
        end
        if entry.bag and entry.slot then
            slotCopy.bag = entry.bag
            slotCopy.slot = entry.slot
        end
        if slotCopy.itemLink and Items then
            local mods = Items.ParseItemLinkModifiers(slotCopy.itemLink)
            if mods then
                slotCopy.enchantID = mods.enchantID
                local gems = Items.CopyGemsTable(mods.gems)
                if gems then
                    slotCopy.gems = gems
                end
            end
        end
        return slotCopy
    end

    local itemID = tonumber(entry) or entry

    local itemLink = Items and Items.ResolveItemLink(itemID)
    if itemLink and Items then
        return Items.ToGearEntry({ itemID = itemID, itemLink = itemLink }) or { itemID = itemID }
    end

    return { itemID = itemID }
end

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

function DB:NormalizeTertiaryPriority(priority)
    local valid = {}
    local seen = {}
    local fields = C.TERTIARY_FIELDS

    if type(priority) == "table" then
        for _, field in ipairs(priority) do
            if fields[field] and not seen[field] then
                seen[field] = true
                valid[#valid + 1] = field
            end
        end
    end

    for _, field in ipairs(C.DEFAULT_TERTIARY_PRIORITY) do
        if not seen[field] then
            valid[#valid + 1] = field
        end
    end

    return valid
end

function DB:GetTertiaryPriority()
    if cachedTertiaryPriority then
        return cachedTertiaryPriority
    end

    local priority = self:NormalizeTertiaryPriority(LoadoutLockerDB.tertiaryPriority)
    LoadoutLockerDB.tertiaryPriority = priority
    cachedTertiaryPriority = priority
    return priority
end

function DB:GetTertiaryPriorityCopy()
    local priority = self:GetTertiaryPriority()
    local copy = {}
    for index, field in ipairs(priority) do
        copy[index] = field
    end
    return copy
end

function DB:SetTertiaryPriority(priority)
    LoadoutLockerDB.tertiaryPriority = self:NormalizeTertiaryPriority(priority)
    InvalidateTertiaryPriorityCache()
end

function DB:ResetTertiaryPriority()
    LoadoutLockerDB.tertiaryPriority = nil
    InvalidateTertiaryPriorityCache()
    return self:GetTertiaryPriority()
end

function DB:MoveTertiaryPriority(field, direction)
    local priority = self:GetTertiaryPriorityCopy()
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

function DB:GetIgnoredUpgradeSlots(specID, configID)
    local entry = self:GetEntry(specID, configID)
    return entry and entry.ignoredUpgradeSlots
end

function DB:IsUpgradeSlotIgnored(specID, configID, invSlot)
    local ignored = self:GetIgnoredUpgradeSlots(specID, configID)
    if not ignored then
        return false
    end

    return ignored[NormalizeInvSlot(invSlot)] or false
end

function DB:GetIgnoredUpgradeSlotList(specID, configID)
    local ignored = self:GetIgnoredUpgradeSlots(specID, configID)
    if not ignored then
        return {}
    end

    local slots = {}
    for slot in pairs(ignored) do
        slots[#slots + 1] = NormalizeInvSlot(slot)
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
    entry.ignoredUpgradeSlots[NormalizeInvSlot(invSlot)] = true
    return true
end

function DB:ClearIgnoredUpgradeSlot(specID, configID, invSlot)
    local entry = self:GetEntry(specID, configID)
    if not entry or not entry.ignoredUpgradeSlots then
        return false
    end

    entry.ignoredUpgradeSlots[NormalizeInvSlot(invSlot)] = nil

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
                name = LoadoutLocker.Loadout.ResolveLoadoutName(configID, entry.loadoutName),
            }
        end
    end

    LoadoutLocker.Loadout.SortByName(list)

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

    for slot, entry in pairs(gear) do
        copy[NormalizeInvSlot(slot)] = NormalizeGearEntry(entry)
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
