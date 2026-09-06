LoadoutLocker = LoadoutLocker or {}

local DB = {}
LoadoutLocker.DB = DB

LoadoutLockerDB = LoadoutLockerDB or {}
LoadoutLockerAccountDB = LoadoutLockerAccountDB or {}

local C = LoadoutLocker.Constants
local cachedTertiaryPriority

local function GetPromptFlag(key)
    return LoadoutLockerDB[key] ~= false
end

local function SetPromptFlag(key, enabled)
    LoadoutLockerDB[key] = enabled and true or false
end

local function GetAccountFlag(key)
    return LoadoutLockerAccountDB[key] == true
end

local function SetAccountFlag(key, enabled)
    LoadoutLockerAccountDB[key] = enabled and true or false
end

local function NormalizeInvSlot(invSlot)
    return LoadoutLocker.Gear.NormalizeInvSlot(invSlot)
end

local function IsLoadoutRef(value)
    return type(value) == "table" and value.specID and value.configID
end

local function NormalizeLoadoutRef(value, fallbackSpecID)
    if IsLoadoutRef(value) then
        return {
            specID = value.specID,
            configID = value.configID,
        }
    end

    if type(value) == "number" and fallbackSpecID then
        return {
            specID = fallbackSpecID,
            configID = value,
        }
    end

    if type(value) == "string" then
        local specID, configID = LoadoutLocker.Loadout.DecodeLoadoutKey(value)
        if specID and configID then
            return { specID = specID, configID = configID }
        end
    end
end

local function CopyLoadoutRef(ref)
    if not ref then
        return nil
    end
    return {
        specID = ref.specID,
        configID = ref.configID,
    }
end

local function ResolveStoredLoadoutRef(override, defaultRef)
    return LoadoutLocker.Loadout.ResolveAssignableRef(override, defaultRef)
end

local function EnsureGlobalAssignmentStore(storeKey, collectionKey)
    LoadoutLockerDB[storeKey] = LoadoutLockerDB[storeKey] or {}
    local store = LoadoutLockerDB[storeKey]
    if type(store.defaultLoadout) == "number" then
        store.defaultLoadout = nil
    end
    if not store[collectionKey] then
        store[collectionKey] = {}
    end
    return store
end

local function MigrateLegacyAssignmentStore(storeKey, collectionKey, raidBosses)
    if LoadoutLockerDB[storeKey .. "Migrated"] then
        return
    end

    local legacy = LoadoutLockerDB[storeKey]
    if type(legacy) ~= "table" then
        LoadoutLockerDB[storeKey .. "Migrated"] = true
        return
    end

    local store = EnsureGlobalAssignmentStore(storeKey, collectionKey)

    for specID, assignments in pairs(legacy) do
        if type(specID) == "number" and type(assignments) == "table" then
            if assignments.defaultConfigID and not store.defaultLoadout then
                store.defaultLoadout = NormalizeLoadoutRef(assignments.defaultConfigID, specID)
            end
            if assignments.defaultLoadout and not store.defaultLoadout then
                store.defaultLoadout = CopyLoadoutRef(NormalizeLoadoutRef(assignments.defaultLoadout, specID))
            end

            local collection = assignments[collectionKey]
            if type(collection) == "table" then
                for key, value in pairs(collection) do
                    if not store[collectionKey][key] then
                        store[collectionKey][key] = CopyLoadoutRef(NormalizeLoadoutRef(value, specID))
                    end
                end
            end

            if raidBosses and type(assignments.raids) == "table" then
                store.raids = store.raids or {}
                for raidKey, raidAssignment in pairs(assignments.raids) do
                    store.raids[raidKey] = store.raids[raidKey] or { bosses = {} }
                    local bosses = raidAssignment and raidAssignment.bosses
                    if type(bosses) == "table" then
                        for bossKey, value in pairs(bosses) do
                            if not store.raids[raidKey].bosses[bossKey] then
                                store.raids[raidKey].bosses[bossKey] = CopyLoadoutRef(NormalizeLoadoutRef(value, specID))
                            end
                        end
                    end
                end
            end
        end
    end

    LoadoutLockerDB[storeKey .. "Migrated"] = true
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

local function InvalidateLoadoutListCache()
    local Loadout = LoadoutLocker.Loadout
    if Loadout and Loadout.InvalidateListCache then
        Loadout.InvalidateListCache()
    end
end

local CURRENT_GEAR_SCHEMA = 4

local function EnsureGearSetStore()
    LoadoutLockerDB.gearSets = LoadoutLockerDB.gearSets or {}
    LoadoutLockerDB.nextGearSetID = LoadoutLockerDB.nextGearSetID or 1
end

local function AllocateGearSetID()
    EnsureGearSetStore()
    local id = LoadoutLockerDB.nextGearSetID
    LoadoutLockerDB.nextGearSetID = id + 1
    return id
end

local function IterLoadoutEntries(callback)
    for specID, specData in pairs(LoadoutLockerDB) do
        if type(specID) == "number" and type(specData) == "table" then
            for configID, entry in pairs(specData) do
                if type(configID) == "number" and type(entry) == "table" then
                    callback(specID, configID, entry)
                end
            end
        end
    end
end

local function SetDefaultLoadoutRef(storeKey, collectionKey, specID, configID)
    local store = EnsureGlobalAssignmentStore(storeKey, collectionKey)
    if specID and configID then
        store.defaultLoadout = { specID = specID, configID = configID }
    else
        store.defaultLoadout = nil
    end
    return true
end

local function SetDefaultFromDropdownValue(storeKey, collectionKey, value, fallbackSpecID)
    if value == "" or value == nil then
        return SetDefaultLoadoutRef(storeKey, collectionKey, nil, nil)
    end

    local specID, configID = LoadoutLocker.Loadout.ParseAssignmentValue(value, fallbackSpecID)
    return SetDefaultLoadoutRef(storeKey, collectionKey, specID, configID)
end

local function GetContentLoadoutRef(storeKey, collectionKey, itemKey)
    local store = LoadoutLockerDB[storeKey]
    if not store or not itemKey then
        return nil
    end

    return ResolveStoredLoadoutRef(
        NormalizeLoadoutRef(store[collectionKey] and store[collectionKey][itemKey]),
        NormalizeLoadoutRef(store.defaultLoadout)
    )
end

local function SetContentLoadoutRef(storeKey, collectionKey, itemKey, specID, configID, expandKeys)
    local store = EnsureGlobalAssignmentStore(storeKey, collectionKey)
    if not store or not itemKey then
        return false
    end

    local keys = expandKeys and expandKeys(itemKey) or { itemKey }
    for _, key in ipairs(keys) do
        if specID and configID then
            store[collectionKey][key] = { specID = specID, configID = configID }
        else
            store[collectionKey][key] = nil
        end
    end

    return true
end

local function SetContentFromDropdownValue(storeKey, collectionKey, itemKey, value, fallbackSpecID, expandKeys)
    if value == "default" then
        return SetContentLoadoutRef(storeKey, collectionKey, itemKey, nil, nil, expandKeys)
    end

    local specID, configID = LoadoutLocker.Loadout.ParseAssignmentValue(value, fallbackSpecID)
    return SetContentLoadoutRef(storeKey, collectionKey, itemKey, specID, configID, expandKeys)
end

local function DefineContentAssignments(def)
    local storeKey = def.storeKey
    local collectionKey = def.collectionKey
    local promptFlag = def.promptFlag
    local prefix = def.prefix
    local expandKeys = def.expandKeys

    DB["Are" .. prefix .. "PromptsEnabled"] = function()
        return GetPromptFlag(promptFlag)
    end

    DB["Set" .. prefix .. "PromptsEnabled"] = function(_, enabled)
        SetPromptFlag(promptFlag, enabled)
    end

    DB["Get" .. prefix .. "Assignments"] = function()
        return EnsureGlobalAssignmentStore(storeKey, collectionKey)
    end

    DB["Get" .. prefix .. "AssignmentsIfExists"] = function()
        return LoadoutLockerDB[storeKey]
    end

    DB["Get" .. prefix .. "DefaultLoadoutRef"] = function()
        local store = LoadoutLockerDB[storeKey]
        return store and NormalizeLoadoutRef(store.defaultLoadout)
    end

    DB["Set" .. prefix .. "DefaultLoadoutRef"] = function(_, specID, configID)
        return SetDefaultLoadoutRef(storeKey, collectionKey, specID, configID)
    end

    DB["Set" .. prefix .. "DefaultConfigID"] = function(_, _specID, value)
        return SetDefaultFromDropdownValue(storeKey, collectionKey, value, _specID)
    end

    DB["Get" .. prefix .. "LoadoutRef"] = function(_, itemKey)
        return GetContentLoadoutRef(storeKey, collectionKey, itemKey)
    end

    DB["Set" .. prefix .. "LoadoutRef"] = function(_, itemKey, specID, configID)
        return SetContentLoadoutRef(storeKey, collectionKey, itemKey, specID, configID, expandKeys)
    end

    DB["Set" .. prefix .. "ConfigID"] = function(_, _specID, itemKey, value)
        return SetContentFromDropdownValue(storeKey, collectionKey, itemKey, value, _specID, expandKeys)
    end

    DB["Clear" .. prefix .. "ConfigID"] = function(_, _specID, itemKey)
        return SetContentLoadoutRef(storeKey, collectionKey, itemKey, nil, nil, expandKeys)
    end
end

function DB:Initialize()
    LoadoutLockerDB = LoadoutLockerDB or {}
    LoadoutLockerAccountDB = LoadoutLockerAccountDB or {}
    LoadoutLockerDB.dungeonAssignments = LoadoutLockerDB.dungeonAssignments or {}
    LoadoutLockerDB.raidAssignments = LoadoutLockerDB.raidAssignments or {}
    LoadoutLockerDB.delveAssignments = LoadoutLockerDB.delveAssignments or {}
    LoadoutLockerDB.pvpAssignments = LoadoutLockerDB.pvpAssignments or {}
    MigrateLegacyAssignmentStore("dungeonAssignments", "dungeons", false)
    MigrateLegacyAssignmentStore("raidAssignments", "raids", true)
    MigrateLegacyAssignmentStore("delveAssignments", "delves", false)
    MigrateLegacyAssignmentStore("pvpAssignments", "modes", false)
    if LoadoutLockerAccountDB.onboardingComplete ~= true then
        LoadoutLockerAccountDB.onboardingComplete = nil
    end
    self:GetTertiaryPriority()
    self:MigrateGearSets()
end

DefineContentAssignments({
    prefix = "Dungeon",
    storeKey = "dungeonAssignments",
    collectionKey = "dungeons",
    promptFlag = "dungeonPromptsEnabled",
    expandKeys = function(dungeonKey)
        return LoadoutLocker.Dungeons.GetLinkedAssignmentKeys(dungeonKey)
    end,
})

DefineContentAssignments({
    prefix = "Delve",
    storeKey = "delveAssignments",
    collectionKey = "delves",
    promptFlag = "delvePromptsEnabled",
})

DefineContentAssignments({
    prefix = "PvP",
    storeKey = "pvpAssignments",
    collectionKey = "modes",
    promptFlag = "pvpPromptsEnabled",
})

function DB:AreRaidPromptsEnabled()
    return GetPromptFlag("raidPromptsEnabled")
end

function DB:SetRaidPromptsEnabled(enabled)
    SetPromptFlag("raidPromptsEnabled", enabled)
end

function DB:GetRaidAssignments(_specID)
    return EnsureGlobalAssignmentStore("raidAssignments", "raids")
end

function DB:GetRaidAssignmentIfExists(_specID, raidKey)
    local store = LoadoutLockerDB.raidAssignments
    return store and store.raids and store.raids[raidKey]
end

function DB:GetRaidAssignment(_specID, raidKey)
    local store = self:GetRaidAssignments()
    if not store or not raidKey then
        return nil
    end

    store.raids = store.raids or {}
    local raidAssignment = store.raids[raidKey]
    if not raidAssignment then
        raidAssignment = { bosses = {} }
        store.raids[raidKey] = raidAssignment
    elseif not raidAssignment.bosses then
        raidAssignment.bosses = {}
    end

    return raidAssignment
end

function DB:GetRaidDefaultLoadoutRef()
    local store = LoadoutLockerDB.raidAssignments
    return store and NormalizeLoadoutRef(store.defaultLoadout)
end

function DB:SetRaidDefaultLoadoutRef(specID, configID)
    return SetDefaultLoadoutRef("raidAssignments", "raids", specID, configID)
end

function DB:SetRaidDefaultConfigID(_specID, value)
    return SetDefaultFromDropdownValue("raidAssignments", "raids", value, _specID)
end

function DB:GetRaidBossLoadoutRef(raidKey, bossKey)
    local store = LoadoutLockerDB.raidAssignments
    if not store or not raidKey or not bossKey then
        return nil
    end

    local raidAssignment = store.raids and store.raids[raidKey]
    local override = raidAssignment and raidAssignment.bosses and raidAssignment.bosses[bossKey]
    return ResolveStoredLoadoutRef(
        NormalizeLoadoutRef(override),
        self:GetRaidDefaultLoadoutRef()
    )
end

function DB:SetRaidBossLoadoutRef(raidKey, bossKey, specID, configID)
    if not bossKey then
        return false
    end

    local raidAssignment = self:GetRaidAssignment(nil, raidKey)
    if not raidAssignment then
        return false
    end

    if specID and configID then
        raidAssignment.bosses[bossKey] = { specID = specID, configID = configID }
    else
        raidAssignment.bosses[bossKey] = nil
    end
    return true
end

function DB:SetRaidBossConfigID(_specID, raidKey, bossKey, value)
    if value == "default" then
        return self:ClearRaidBossConfigID(nil, raidKey, bossKey)
    end

    local specID, configID = LoadoutLocker.Loadout.ParseAssignmentValue(value, _specID)
    return self:SetRaidBossLoadoutRef(raidKey, bossKey, specID, configID)
end

function DB:ClearRaidBossConfigID(_specID, raidKey, bossKey)
    return self:SetRaidBossLoadoutRef(raidKey, bossKey, nil, nil)
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
    local rec = self:GetGearSetRecord(specID, configID)
    return rec and rec.ignoredUpgradeSlots
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
    local rec = self:GetGearSetRecord(specID, configID)
    if not rec then
        return false
    end

    rec.ignoredUpgradeSlots = rec.ignoredUpgradeSlots or {}
    rec.ignoredUpgradeSlots[NormalizeInvSlot(invSlot)] = true
    return true
end

function DB:ClearIgnoredUpgradeSlot(specID, configID, invSlot)
    local rec = self:GetGearSetRecord(specID, configID)
    if not rec or not rec.ignoredUpgradeSlots then
        return false
    end

    rec.ignoredUpgradeSlots[NormalizeInvSlot(invSlot)] = nil

    if not next(rec.ignoredUpgradeSlots) then
        rec.ignoredUpgradeSlots = nil
    end

    return true
end

function DB:ClearAllIgnoredUpgradeSlots(specID, configID)
    local rec = self:GetGearSetRecord(specID, configID)
    if not rec or not rec.ignoredUpgradeSlots then
        return false
    end

    rec.ignoredUpgradeSlots = nil
    return true
end

function DB:GetAllSavedGearEntries()
    local list = {}

    for specID, specData in pairs(LoadoutLockerDB) do
        if type(specID) == "number" and type(specData) == "table" then
            for configID, entry in pairs(specData) do
                if type(configID) == "number" and type(entry) == "table" and self:HasGearSet(specID, configID) then
                    list[#list + 1] = {
                        specID = specID,
                        configID = configID,
                        name = LoadoutLocker.Loadout.ResolveLoadoutName(configID, entry.loadoutName),
                        equipmentSetName = self:GetEquipmentSetName(specID, configID),
                    }
                end
            end
        end
    end

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

function DB:CountLoadoutsUsingGearSet(gearSetID)
    if not gearSetID then
        return 0
    end

    local n = 0
    IterLoadoutEntries(function(_, _, entry)
        if entry.gearSetID == gearSetID then
            n = n + 1
        end
    end)
    return n
end

function DB:NeedsSharedSavePrompt(specID, configID)
    local entry = self:GetEntry(specID, configID)
    local id = entry and entry.gearSetID
    return self:CountLoadoutsUsingGearSet(id) > 1
end

function DB:GetGearSetRecord(specID, configID)
    local entry = self:GetEntry(specID, configID)
    local id = entry and entry.gearSetID
    local rec = id and LoadoutLockerDB.gearSets and LoadoutLockerDB.gearSets[id]
    if not rec then
        return nil
    end
    rec.id = rec.id or id
    return rec
end

function DB:GetGearSet(specID, configID)
    local rec = self:GetGearSetRecord(specID, configID)
    return rec and rec.gear
end

function DB:HasGearSet(specID, configID)
    return self:GetGearSet(specID, configID) ~= nil
end

function DB:GetEquipmentSetName(specID, configID)
    local rec = self:GetGearSetRecord(specID, configID)
    return rec and rec.equipmentSetName
end

function DB:SetEquipmentSetName(specID, configID, name)
    local rec = self:GetGearSetRecord(specID, configID)
    if not rec then
        return false
    end
    rec.equipmentSetName = name
    return true
end

function DB:CopyGearSet(gear)
    local copy = {}
    if not gear then
        return copy
    end

    for slot, entry in pairs(gear) do
        copy[NormalizeInvSlot(slot)] = NormalizeGearEntry(entry)
    end

    return copy
end

function DB:MigrateGearSets()
    if (LoadoutLockerDB.schemaVersion or 0) >= CURRENT_GEAR_SCHEMA then
        EnsureGearSetStore()
        return
    end

    EnsureGearSetStore()
    local groups = {}
    IterLoadoutEntries(function(specID, configID, entry)
        if not entry.gear then
            return
        end

        local name = entry.equipmentSetName
        local key
        if type(name) == "string" and name ~= "" then
            key = "n:" .. name
        else
            key = "u:" .. tostring(specID) .. ":" .. tostring(configID)
        end
        groups[key] = groups[key] or {}
        groups[key][#groups[key] + 1] = {
            specID = specID,
            configID = configID,
            entry = entry,
        }
    end)

    for _, rows in pairs(groups) do
        table.sort(rows, function(a, b)
            local sa, sb = a.entry.savedAt or 0, b.entry.savedAt or 0
            if sa ~= sb then
                return sa > sb
            end
            return a.configID > b.configID
        end)

        local winner = rows[1].entry
        local id = AllocateGearSetID()
        LoadoutLockerDB.gearSets[id] = {
            id = id,
            gear = self:CopyGearSet(winner.gear),
            equipmentSetName = winner.equipmentSetName,
            savedAt = winner.savedAt,
            ignoredUpgradeSlots = self:CopyIgnoredUpgradeSlots(winner.ignoredUpgradeSlots),
        }

        for _, row in ipairs(rows) do
            row.entry.gearSetID = id
            row.entry.gear = nil
            row.entry.equipmentSetName = nil
            row.entry.ignoredUpgradeSlots = nil
        end
    end

    LoadoutLockerDB.schemaVersion = CURRENT_GEAR_SCHEMA
end

function DB:CreateOrUpdateGearSet(specID, configID, gear, loadoutName)
    local specData = self:EnsureSpecTable(specID)
    local existing = specData[configID]
    local copied = self:CopyGearSet(gear)
    EnsureGearSetStore()

    local id = existing and existing.gearSetID
    if not id or not LoadoutLockerDB.gearSets[id] then
        id = AllocateGearSetID()
    end

    local rec = LoadoutLockerDB.gearSets[id] or {}
    rec.id = id
    rec.gear = copied
    rec.savedAt = time()
    LoadoutLockerDB.gearSets[id] = rec

    specData[configID] = {
        gearSetID = id,
        loadoutName = loadoutName,
        savedAt = time(),
    }
    InvalidateLoadoutListCache()
end

function DB:ForkGearSet(specID, configID, gear)
    local existing = self:GetEntry(specID, configID)
    local rec = self:GetGearSetRecord(specID, configID)
    local sourceGear = gear or (rec and rec.gear)
    if not sourceGear then
        return false
    end

    EnsureGearSetStore()
    local id = AllocateGearSetID()
    LoadoutLockerDB.gearSets[id] = {
        id = id,
        gear = self:CopyGearSet(sourceGear),
        savedAt = time(),
        ignoredUpgradeSlots = rec and self:CopyIgnoredUpgradeSlots(rec.ignoredUpgradeSlots),
    }

    local specData = self:EnsureSpecTable(specID)
    specData[configID] = {
        gearSetID = id,
        loadoutName = existing and existing.loadoutName,
        savedAt = time(),
    }
    InvalidateLoadoutListCache()
    return true
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

function DB:CopyGearSetToLoadout(specID, sourceConfigID, targetConfigID, targetLoadoutName, sourceSpecID)
    local sourceEntry = self:GetEntry(sourceSpecID or specID, sourceConfigID)
    if not sourceEntry or not sourceEntry.gearSetID then
        return false
    end

    if not self:HasGearSet(sourceSpecID or specID, sourceConfigID) then
        return false
    end

    local specData = self:EnsureSpecTable(specID)
    specData[targetConfigID] = {
        gearSetID = sourceEntry.gearSetID,
        loadoutName = targetLoadoutName,
        savedAt = time(),
    }
    InvalidateLoadoutListCache()
    return true
end

function DB:DeleteGearSet(specID, configID)
    local specData = LoadoutLockerDB[specID]
    local entry = specData and specData[configID]
    if not entry then
        return nil
    end

    local rec = self:GetGearSetRecord(specID, configID)
    local payload = {
        loadoutName = entry.loadoutName,
        equipmentSetName = rec and rec.equipmentSetName,
        gearSetID = entry.gearSetID,
    }
    local id = entry.gearSetID
    specData[configID] = nil
    if id and self:CountLoadoutsUsingGearSet(id) == 0 and LoadoutLockerDB.gearSets then
        LoadoutLockerDB.gearSets[id] = nil
    end
    InvalidateLoadoutListCache()
    return payload
end

function DB:GetSpecEntries(specID)
    return LoadoutLockerDB[specID]
end

function DB:IsOnboardingComplete()
    return GetAccountFlag("onboardingComplete")
end

function DB:SetOnboardingComplete()
    SetAccountFlag("onboardingComplete", true)
end
