LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}

local C = LoadoutLocker.Constants
local cachedTertiaryPriority

local function GetPromptFlag(key)
    return LoadoutLockerDB[key] ~= false
end

local function SetPromptFlag(key, enabled)
    LoadoutLockerDB[key] = enabled and true or false
end

local function EnsureAssignmentStore(storeKey, collectionKey, specID)
    LoadoutLockerDB[storeKey] = LoadoutLockerDB[storeKey] or {}
    if not specID then
        return nil
    end

    local assignments = LoadoutLockerDB[storeKey][specID]
    if not assignments then
        assignments = { [collectionKey] = {} }
        LoadoutLockerDB[storeKey][specID] = assignments
    elseif not assignments[collectionKey] then
        assignments[collectionKey] = {}
    end

    return assignments
end

local function GetAssignmentStoreIfExists(storeKey, specID)
    return LoadoutLockerDB[storeKey] and LoadoutLockerDB[storeKey][specID]
end

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
    LoadoutLockerDB.dungeonAssignments = LoadoutLockerDB.dungeonAssignments or {}
    LoadoutLockerDB.raidAssignments = LoadoutLockerDB.raidAssignments or {}
    self:GetTertiaryPriority()
end

function DB:AreDungeonPromptsEnabled()
    return GetPromptFlag("dungeonPromptsEnabled")
end

function DB:SetDungeonPromptsEnabled(enabled)
    SetPromptFlag("dungeonPromptsEnabled", enabled)
end

function DB:GetDungeonAssignments(specID)
    return EnsureAssignmentStore("dungeonAssignments", "dungeons", specID)
end

function DB:GetDungeonDefaultConfigID(specID)
    local assignments = GetAssignmentStoreIfExists("dungeonAssignments", specID)
    return assignments and assignments.defaultConfigID
end

function DB:SetDungeonDefaultConfigID(specID, configID)
    local assignments = self:GetDungeonAssignments(specID)
    if not assignments then
        return false
    end

    assignments.defaultConfigID = configID
    return true
end

function DB:GetDungeonConfigID(specID, dungeonKey)
    local assignments = self:GetDungeonAssignments(specID)
    if not assignments then
        return nil
    end

    local override = assignments.dungeons[dungeonKey]
    if override then
        return override
    end

    return assignments.defaultConfigID
end

function DB:SetDungeonConfigID(specID, dungeonKey, configID)
    local assignments = self:GetDungeonAssignments(specID)
    if not assignments or not dungeonKey then
        return false
    end

    if configID then
        assignments.dungeons[dungeonKey] = configID
    else
        assignments.dungeons[dungeonKey] = nil
    end

    return true
end

function DB:ClearDungeonConfigID(specID, dungeonKey)
    return self:SetDungeonConfigID(specID, dungeonKey, nil)
end

function DB:AreRaidPromptsEnabled()
    return GetPromptFlag("raidPromptsEnabled")
end

function DB:SetRaidPromptsEnabled(enabled)
    SetPromptFlag("raidPromptsEnabled", enabled)
end

function DB:GetRaidAssignments(specID)
    return EnsureAssignmentStore("raidAssignments", "raids", specID)
end

function DB:GetRaidAssignmentIfExists(specID, raidKey)
    local assignments = GetAssignmentStoreIfExists("raidAssignments", specID)
    return assignments and assignments.raids[raidKey]
end

function DB:GetRaidAssignment(specID, raidKey)
    local assignments = self:GetRaidAssignments(specID)
    if not assignments then
        return nil
    end

    local raidAssignment = assignments.raids[raidKey]
    if not raidAssignment then
        raidAssignment = { bosses = {} }
        assignments.raids[raidKey] = raidAssignment
    elseif not raidAssignment.bosses then
        raidAssignment.bosses = {}
    end

    return raidAssignment
end

function DB:GetRaidDefaultConfigID(specID)
    local assignments = GetAssignmentStoreIfExists("raidAssignments", specID)
    return assignments and assignments.defaultConfigID
end

function DB:SetRaidDefaultConfigID(specID, configID)
    local assignments = self:GetRaidAssignments(specID)
    if not assignments then
        return false
    end

    assignments.defaultConfigID = configID
    return true
end

function DB:GetRaidBossConfigID(specID, raidKey, bossKey)
    local assignments = GetAssignmentStoreIfExists("raidAssignments", specID)
    if not assignments then
        return nil
    end

    local raidAssignment = assignments.raids and assignments.raids[raidKey]
    if raidAssignment and raidAssignment.bosses and raidAssignment.bosses[bossKey] then
        return raidAssignment.bosses[bossKey]
    end

    return assignments.defaultConfigID
end

function DB:SetRaidBossConfigID(specID, raidKey, bossKey, configID)
    if not bossKey then
        return false
    end

    local raidAssignment = self:GetRaidAssignment(specID, raidKey)
    if not raidAssignment then
        return false
    end

    raidAssignment.bosses[bossKey] = configID
    return true
end

function DB:ClearRaidBossConfigID(specID, raidKey, bossKey)
    return self:SetRaidBossConfigID(specID, raidKey, bossKey, nil)
end

function DB:AreUpgradeChecksEnabled()
    return GetPromptFlag("upgradeChecksEnabled")
end

function DB:SetUpgradeChecksEnabled(enabled)
    SetPromptFlag("upgradeChecksEnabled", enabled)
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
        equipmentSetName = existing and existing.equipmentSetName,
    }
end

function DB:CopyIgnoredUpgradeSlots(ignored)
    if not ignored then
        return nil
    end

    local copy = {}
    for slot, value in pairs(ignored) do
        copy[NormalizeInvSlot(slot)] = value
    end

    return copy
end

function DB:CopyGearSetToLoadout(specID, sourceConfigID, targetConfigID, targetLoadoutName)
    local gear = self:GetGearSet(specID, sourceConfigID)
    if not gear then
        return false
    end

    local specData = self:EnsureSpecTable(specID)
    local sourceEntry = self:GetEntry(specID, sourceConfigID)
    specData[targetConfigID] = {
        gear = self:CopyGearSet(gear),
        loadoutName = targetLoadoutName,
        savedAt = time(),
        ignoredUpgradeSlots = sourceEntry and self:CopyIgnoredUpgradeSlots(sourceEntry.ignoredUpgradeSlots),
        equipmentSetName = sourceEntry and sourceEntry.equipmentSetName,
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
