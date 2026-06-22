LoadoutLocker = LoadoutLocker or {}

function LoadoutLocker.Print(msg)
    print("|cff00ccffLoadoutLocker:|r " .. msg)
end

function LoadoutLocker.RefreshUI()
    if LoadoutLocker.RefreshTalentUI then
        LoadoutLocker.RefreshTalentUI()
    end
end

local C = LoadoutLocker.Constants
local Items = LoadoutLocker.Items
local Loadout = LoadoutLocker.Loadout

local DB = LoadoutLocker.DB
local Print = LoadoutLocker.Print
local RefreshUI = LoadoutLocker.RefreshUI

local Gear = {}
LoadoutLocker.Gear = Gear

local equipQueueRunning
local loadoutApplyTimer

local function ModifiersMatch(modsA, modsB)
    if not modsA or not modsB then
        return false
    end

    if modsA.itemID ~= modsB.itemID then
        return false
    end

    if (modsA.enchantID or 0) ~= (modsB.enchantID or 0) then
        return false
    end

    return Items.GemsMatch(modsA.gems, modsB.gems)
end

local function GetEntryModifiers(entry)
    if type(entry) ~= "table" then
        return {
            itemID = entry,
            enchantID = 0,
            gems = {},
        }
    end

    if entry.enchantID or entry.gems then
        return {
            itemID = entry.itemID,
            enchantID = entry.enchantID or 0,
            gems = Items.CopyGemsTable(entry.gems) or {},
        }
    end

    local mods = Items.ParseItemLinkModifiers(entry.itemLink)
    if mods then
        return mods
    end

    return {
        itemID = entry.itemID,
        enchantID = 0,
        gems = {},
    }
end

local function EntryRequiresModifierMatch(entry)
    if type(entry) ~= "table" then
        return false
    end

    if entry.enchantID or entry.gems then
        return true
    end

    return entry.itemLink ~= nil
end

local function ItemLinkEquals(linkA, linkB)
    return linkA and linkB and linkA == linkB
end

local function ItemLinkMatchesEntry(itemLink, entry, entryMods)
    if not itemLink or not entry then
        return false
    end

    if type(entry) == "table" and ItemLinkEquals(itemLink, entry.itemLink) then
        return true
    end

    local linkMods = Items.ParseItemLinkModifiers(itemLink)
    if not linkMods then
        return false
    end

    entryMods = entryMods or GetEntryModifiers(entry)
    if linkMods.itemID ~= entryMods.itemID then
        return false
    end

    if not ModifiersMatch(linkMods, entryMods) then
        return false
    end

    local savedLevel = Items.GetSavedItemLevel(entry)
    if savedLevel > 0 then
        local candidateLevel = Items.GetItemLevel(itemLink)
        if candidateLevel > 0 and candidateLevel ~= savedLevel then
            return false
        end
    end

    return true
end

local function SnapshotEquippedGear()
    local gear = {}

    Items.ForEachEquipped(function(location)
        gear[location.invSlot] = Items.ToGearEntry(location)
    end)

    return gear
end

local function BuildSwapBagState(reservedBagSlots)
    local state = {
        emptySlots = {},
        locationsByItemID = {},
        locationsByLink = {},
        reservedBagSlots = reservedBagSlots,
    }

    Items.ForEachBagSlot(function(bag, slot)
        local locationKey = Items.GetLocationKey({ bag = bag, slot = slot })
        local itemID = C_Container.GetContainerItemID(bag, slot)
        if itemID then
            local location = Items.FromBagSlot(bag, slot)
            local list = state.locationsByItemID[itemID]
            if not list then
                list = {}
                state.locationsByItemID[itemID] = list
            end
            list[#list + 1] = location
            if location.itemLink then
                state.locationsByLink[location.itemLink] = location
            end
        elseif not reservedBagSlots[locationKey] then
            state.emptySlots[#state.emptySlots + 1] = { bag = bag, slot = slot, key = locationKey }
        end
    end)

    return state
end

local function TakeEmptyBagSlot(bagState)
    while #bagState.emptySlots > 0 do
        local slotInfo = table.remove(bagState.emptySlots, 1)
        if not C_Container.GetContainerItemID(slotInfo.bag, slotInfo.slot) then
            bagState.reservedBagSlots[slotInfo.key] = true
            return slotInfo.bag, slotInfo.slot, slotInfo.key
        end
    end
end

local function FindEmptyBagSlot(reservedBagSlots, bagState)
    if bagState then
        return TakeEmptyBagSlot(bagState)
    end

    local emptyBag, emptySlot

    Items.ForEachBagSlot(function(bag, slot)
        if emptyBag then
            return
        end

        local locationKey = Items.GetLocationKey({ bag = bag, slot = slot })
        if not reservedBagSlots[locationKey] and not C_Container.GetContainerItemID(bag, slot) then
            emptyBag = bag
            emptySlot = slot
        end
    end)

    if emptyBag then
        return emptyBag, emptySlot, Items.GetLocationKey({ bag = emptyBag, slot = emptySlot })
    end
end

function Gear.NormalizeInvSlot(invSlot)
    return tonumber(invSlot) or invSlot
end

function Gear.GetGearSetEntry(gearSet, invSlot)
    if not gearSet then
        return nil
    end

    invSlot = Gear.NormalizeInvSlot(invSlot)
    return gearSet[invSlot]
end

function Gear.SetGearSetEntry(gearSet, invSlot, entry)
    gearSet[Gear.NormalizeInvSlot(invSlot)] = entry
end

function Gear.NormalizeGearSetKeys(gearSet)
    if not gearSet then
        return gearSet
    end

    local merged = {}
    for slot, entry in pairs(gearSet) do
        local invSlot = Gear.NormalizeInvSlot(slot)
        merged[invSlot] = entry
    end

    for slot in pairs(gearSet) do
        gearSet[slot] = nil
    end

    for invSlot, entry in pairs(merged) do
        gearSet[invSlot] = entry
    end

    return gearSet
end
local function ResolveGearEntry(entry)
    if type(entry) == "table" then
        return entry.itemID, entry.bag, entry.slot, entry.itemLink, entry.enchantID, Items.CopyGemsTable(entry.gems)
    end

    return entry, nil, nil, nil, nil, nil
end

local function SlotSatisfiesTarget(invSlot, targetEntry)
    if not targetEntry then
        return not GetInventoryItemID("player", invSlot)
    end

    return ItemLinkMatchesEntry(GetInventoryItemLink("player", invSlot), targetEntry)
end

local function MergeGearSnapshot(snapshot, expectedGearSet)
    if not expectedGearSet then
        return snapshot
    end

    for invSlot, entry in pairs(expectedGearSet) do
        invSlot = Gear.NormalizeInvSlot(invSlot)
        local equippedID = GetInventoryItemID("player", invSlot)
        local equippedLink = GetInventoryItemLink("player", invSlot)

        if equippedID and entry and ItemLinkMatchesEntry(equippedLink, entry) then
            snapshot[invSlot] = Items.ToGearEntry({ itemID = equippedID, itemLink = equippedLink })
        elseif type(entry) == "table" and entry.itemLink then
            snapshot[invSlot] = Items.ToGearEntry({ itemID = entry.itemID, itemLink = entry.itemLink })
        elseif entry then
            snapshot[invSlot] = entry
        end
    end

    return snapshot
end

local function SaveEquippedGearSet(specID, configID, expectedGearSet)
    local snapshot = MergeGearSnapshot(SnapshotEquippedGear(), expectedGearSet)
    DB:CreateOrUpdateGearSet(specID, configID, snapshot, Loadout.GetLoadoutName(configID))
    RefreshUI()
end

local function ReportSwapIssue(reported, key, message)
    if reported[key] then
        return
    end

    reported[key] = true
    Print(message)
end

local function BuildNeededItems(gearSet)
    local neededItems = {}
    for _, entry in pairs(gearSet) do
        local itemID = ResolveGearEntry(entry)
        if itemID then
            neededItems[itemID] = true
        end
    end
    return neededItems
end

local function ShouldUnequipSlot(invSlot, gearSet, neededItems)
    local currentItem = GetInventoryItemID("player", invSlot)
    if not currentItem then
        return false
    end

    local gearEntry = Gear.GetGearSetEntry(gearSet, invSlot)
    local currentLink = GetInventoryItemLink("player", invSlot)

    local targetItem, targetBag, targetSlot, targetLink = ResolveGearEntry(gearEntry)
    if targetItem then
        if ItemLinkMatchesEntry(currentLink, gearEntry) then
            return false
        end

        if not EntryRequiresModifierMatch(gearEntry) and not targetLink and currentItem == targetItem then
            if targetBag and targetSlot then
                local preferredLink = C_Container.GetContainerItemLink(targetBag, targetSlot)
                if currentLink and preferredLink and currentLink ~= preferredLink then
                    return true
                end
            end
            return false
        end
    end

    if not targetItem and neededItems[currentItem] then
        return false
    end

    return true
end

function Gear.BuildGearDiff(targetGearSet)
    local diff = {
        unequip = {},
        equip = {},
        empty = true,
    }

    if not targetGearSet then
        return diff
    end

    Gear.NormalizeGearSetKeys(targetGearSet)
    local neededItems = BuildNeededItems(targetGearSet)

    for _, invSlot in ipairs(C.EQUIP_SLOTS) do
        if ShouldUnequipSlot(invSlot, targetGearSet, neededItems) then
            diff.unequip[#diff.unequip + 1] = invSlot
        end
    end

    for _, invSlot in ipairs(C.EQUIP_SLOTS) do
        local targetEntry = Gear.GetGearSetEntry(targetGearSet, invSlot)
        if targetEntry and not SlotSatisfiesTarget(invSlot, targetEntry) then
            diff.equip[#diff.equip + 1] = {
                invSlot = invSlot,
                entry = targetEntry,
            }
        end
    end

    diff.empty = #diff.unequip == 0 and #diff.equip == 0
    return diff
end

local function IsEmbellishedGearEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    return Items.IsEmbellished(entry.itemLink, entry.itemID)
end

local function OrderSwapDiff(diff)
    local equipSlots = {}

    for _, change in ipairs(diff.equip) do
        equipSlots[Gear.NormalizeInvSlot(change.invSlot)] = true
    end

    local filteredUnequip = {}
    for _, invSlot in ipairs(diff.unequip) do
        if not equipSlots[Gear.NormalizeInvSlot(invSlot)] then
            filteredUnequip[#filteredUnequip + 1] = invSlot
        end
    end
    diff.unequip = filteredUnequip

    table.sort(diff.equip, function(a, b)
        local aEmbellished = IsEmbellishedGearEntry(a.entry) and 1 or 0
        local bEmbellished = IsEmbellishedGearEntry(b.entry) and 1 or 0
        if aEmbellished ~= bEmbellished then
            return aEmbellished < bEmbellished
        end
        return a.invSlot < b.invSlot
    end)

    table.sort(diff.unequip, function(a, b)
        local aEmbellished = Items.IsEmbellished(GetInventoryItemLink("player", a)) and 1 or 0
        local bEmbellished = Items.IsEmbellished(GetInventoryItemLink("player", b)) and 1 or 0
        if aEmbellished ~= bEmbellished then
            return aEmbellished < bEmbellished
        end
        return a < b
    end)

    return diff
end

local function UnequipToBag(invSlot, reservedBagSlots, bagState)
    if not GetInventoryItemID("player", invSlot) then
        return true
    end

    local bag, slot, locationKey = FindEmptyBagSlot(reservedBagSlots, bagState)
    if not bag then
        return false
    end

    ClearCursor()
    PickupInventoryItem(invSlot)
    C_Container.PickupContainerItem(bag, slot)
    ClearCursor()

    reservedBagSlots[locationKey] = true
    return true
end

local function FindItemInBags(itemID, itemLink, usedLocations, gearEntry, bagState)
    local linkMatch
    local exactModifierMatch
    local bestModifierBag, bestModifierSlot, bestModifierKey, bestModifierDistance
    local itemIDMatchBag, itemIDMatchSlot, itemIDMatchKey
    local savedLevel = gearEntry and Items.GetSavedItemLevel(gearEntry) or 0
    local requireModifier = gearEntry and EntryRequiresModifierMatch(gearEntry)
    local entryMods = gearEntry and GetEntryModifiers(gearEntry)
    local canSearchByModifiers = entryMods and entryMods.itemID

    local function considerLocation(location)
        if linkMatch or exactModifierMatch then
            return
        end

        local locationKey = Items.GetLocationKey(location)
        if usedLocations[locationKey] then
            return
        end

        local link = location.itemLink
        if link then
            if gearEntry and ItemLinkMatchesEntry(link, gearEntry, entryMods) then
                linkMatch = { "bag", location.bag, location.slot, locationKey }
                return
            end

            if itemLink and ItemLinkEquals(link, itemLink) then
                linkMatch = { "bag", location.bag, location.slot, locationKey }
                return
            end

            if canSearchByModifiers then
                if type(gearEntry) == "table" and ItemLinkEquals(link, gearEntry.itemLink) then
                    exactModifierMatch = { "bag", location.bag, location.slot, locationKey }
                    return
                end

                if ItemLinkMatchesEntry(link, gearEntry, entryMods) then
                    local distance = 0
                    if savedLevel > 0 then
                        local level = Items.GetItemLevel(link)
                        distance = level > 0 and math.abs(level - savedLevel) or math.huge
                    end

                    if not bestModifierBag or distance < bestModifierDistance then
                        bestModifierBag = location.bag
                        bestModifierSlot = location.slot
                        bestModifierKey = locationKey
                        bestModifierDistance = distance
                    end
                end
            end
        end

        if not requireModifier and not itemIDMatchBag and location.itemID == itemID then
            itemIDMatchBag = location.bag
            itemIDMatchSlot = location.slot
            itemIDMatchKey = locationKey
        end
    end

    if type(gearEntry) == "table" and gearEntry.itemLink and bagState.locationsByLink[gearEntry.itemLink] then
        considerLocation(bagState.locationsByLink[gearEntry.itemLink])
    end

    if itemLink and bagState.locationsByLink[itemLink] then
        considerLocation(bagState.locationsByLink[itemLink])
    end

    for _, location in ipairs(bagState.locationsByItemID[itemID] or {}) do
        considerLocation(location)
    end

    if linkMatch then
        return linkMatch[1], linkMatch[2], linkMatch[3], linkMatch[4]
    end

    if exactModifierMatch then
        return exactModifierMatch[1], exactModifierMatch[2], exactModifierMatch[3], exactModifierMatch[4]
    end

    if bestModifierBag then
        return "bag", bestModifierBag, bestModifierSlot, bestModifierKey
    end

    if itemIDMatchBag then
        return "bag", itemIDMatchBag, itemIDMatchSlot, itemIDMatchKey
    end
end

local function FindItemOnPlayer(itemID, itemLink, targetSlot, usedLocations, gearEntry, bagState)
    local sourceType, bag, slot, locationKey = FindItemInBags(itemID, itemLink, usedLocations, gearEntry, bagState)
    if sourceType then
        return sourceType, bag, slot, locationKey
    end

    Items.ForEachEquipped(function(location)
        if sourceType or location.invSlot == targetSlot then
            return
        end

        local equippedKey = Items.GetLocationKey(location)
        if usedLocations[equippedKey] then
            return
        end

        if gearEntry and ItemLinkMatchesEntry(location.itemLink, gearEntry) then
            sourceType = "equipped"
            bag = location.invSlot
            locationKey = equippedKey
        elseif itemLink and ItemLinkEquals(location.itemLink, itemLink) then
            sourceType = "equipped"
            bag = location.invSlot
            locationKey = equippedKey
        elseif (not gearEntry or not EntryRequiresModifierMatch(gearEntry))
            and not itemLink and location.itemID == itemID then
            sourceType = "equipped"
            bag = location.invSlot
            locationKey = equippedKey
        end
    end)

    return sourceType, bag, slot, locationKey
end

local function TryEquipFromBag(invSlot, bag, slot, usedLocations)
    local locationKey = Items.GetLocationKey({ bag = bag, slot = slot })
    if usedLocations[locationKey] or not C_Container.GetContainerItemID(bag, slot) then
        return false
    end

    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    PickupInventoryItem(invSlot)
    ClearCursor()
    usedLocations[locationKey] = true
    return true
end

local function NeedsEquipForEntry(invSlot, gearEntry)
    local itemID = ResolveGearEntry(gearEntry)
    if not itemID then
        return false
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ItemLinkMatchesEntry(equippedLink, gearEntry) then
        return false
    end

    if not EntryRequiresModifierMatch(gearEntry) then
        local _, preferredBag, preferredSlot, itemLink = ResolveGearEntry(gearEntry)
        if GetInventoryItemID("player", invSlot) ~= itemID then
            return true
        end

        if preferredBag and preferredSlot then
            local preferredLink = C_Container.GetContainerItemLink(preferredBag, preferredSlot)
            if equippedLink and preferredLink and equippedLink ~= preferredLink then
                return true
            end
        end

        if itemLink and equippedLink and equippedLink ~= itemLink then
            return true
        end

        return false
    end

    return true
end

local function EquipSlot(invSlot, gearEntry, usedLocations, bagState)
    local itemID, preferredBag, preferredSlot, itemLink = ResolveGearEntry(gearEntry)
    if not itemID then
        return true
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ItemLinkMatchesEntry(equippedLink, gearEntry) then
        return true
    end

    if preferredBag and preferredSlot then
        local preferredItemID = C_Container.GetContainerItemID(preferredBag, preferredSlot)
        if preferredItemID then
            local preferredLink = C_Container.GetContainerItemLink(preferredBag, preferredSlot)
            if ItemLinkMatchesEntry(preferredLink, gearEntry)
                and TryEquipFromBag(invSlot, preferredBag, preferredSlot, usedLocations) then
                return true
            end
        end
    end

    local sourceType, arg1, arg2, locationKey = FindItemOnPlayer(itemID, itemLink, invSlot, usedLocations, gearEntry, bagState)
    if not sourceType then
        return false
    end

    ClearCursor()

    if sourceType == "bag" then
        C_Container.PickupContainerItem(arg1, arg2)
    else
        PickupInventoryItem(arg1)
    end

    PickupInventoryItem(invSlot)
    ClearCursor()

    usedLocations[locationKey] = true
    return true
end

local function PrintGearDiffFailures(diff, reported)
    reported = reported or {}

    for _, change in ipairs(diff.equip) do
        local itemID = ResolveGearEntry(change.entry)
        ReportSwapIssue(
            reported,
            "missing:" .. tostring(itemID),
            "Missing item: " .. Items.GetDisplayName(itemID)
        )
    end

    for _, invSlot in ipairs(diff.unequip) do
        ReportSwapIssue(
            reported,
            "unequip:" .. tostring(invSlot),
            string.format("%s still has the wrong item equipped.", C.GetSlotLabel(invSlot))
        )
    end
end

local function RunGearSwap(gearSet, onComplete, gearDiff)
    if equipQueueRunning then
        return
    end

    if not gearSet or not next(gearSet) then
        return
    end

    Gear.NormalizeGearSetKeys(gearSet)

    local diff = gearDiff or Gear.BuildGearDiff(gearSet)
    OrderSwapDiff(diff)
    if diff.empty then
        if onComplete then
            onComplete(true)
        end
        return
    end

    equipQueueRunning = true
    local reported = {}
    local neededItems = BuildNeededItems(gearSet)
    local usedLocations = {}
    local reservedBagSlots = {}
    local bagState = BuildSwapBagState(reservedBagSlots)
    local phase = C.SWAP_PHASE.UNEQUIP
    local unequipIndex = 1
    local equipIndex = 1

    local function FinishSwap(ready)
        equipQueueRunning = false
        if onComplete then
            onComplete(ready ~= false)
        end
    end

    local function VerifyAndComplete()
        C_Timer.After(C.SAVE_RETRY_DELAY, function()
            local remaining = Gear.BuildGearDiff(gearSet)
            if remaining.empty then
                FinishSwap(true)
                return
            end

            PrintGearDiffFailures(remaining, reported)
            FinishSwap(false)
        end)
    end

    local function Step()
        if InCombatLockdown() then
            equipQueueRunning = false
            Print("Combat started. Gear swap cancelled.")
            return
        end

        if phase == C.SWAP_PHASE.UNEQUIP then
            while unequipIndex <= #diff.unequip do
                local invSlot = diff.unequip[unequipIndex]
                unequipIndex = unequipIndex + 1

                if ShouldUnequipSlot(invSlot, gearSet, neededItems) then
                    if not UnequipToBag(invSlot, reservedBagSlots, bagState) then
                        ReportSwapIssue(
                            reported,
                            "bagspace",
                            "Not enough bag space to swap gear."
                        )
                    end
                    C_Timer.After(C.EQUIP_SLOT_DELAY, Step)
                    return
                end
            end

            phase = C.SWAP_PHASE.EQUIP
            C_Timer.After(C.EQUIP_SLOT_DELAY, Step)
            return
        end

        while equipIndex <= #diff.equip do
            local change = diff.equip[equipIndex]
            equipIndex = equipIndex + 1

            if NeedsEquipForEntry(change.invSlot, change.entry) then
                if not EquipSlot(change.invSlot, change.entry, usedLocations, bagState) then
                    local itemID = ResolveGearEntry(change.entry)
                    ReportSwapIssue(
                        reported,
                        "missing:" .. tostring(itemID),
                        "Missing item: " .. Items.GetDisplayName(itemID)
                    )
                end
                C_Timer.After(C.EQUIP_SLOT_DELAY, Step)
                return
            end
        end

        VerifyAndComplete()
    end

    Step()
end

local function ApplyGearSwap(gearSet, onComplete, gearDiff)
    if not gearSet or not next(gearSet) then
        return
    end

    if InCombatLockdown() then
        Print("Cannot swap gear in combat.")
        return
    end

    RunGearSwap(gearSet, onComplete, gearDiff)
end

local function RequireSpecID(specID)
    specID = specID or Loadout.GetSpecID()
    if not specID then
        Print("No specialization selected.")
    end
    return specID
end

function Gear.Save(specID, configID)
    local context = Loadout.GetActive(specID)
    if not context then
        Print("No specialization selected.")
        return false
    end

    if configID then
        context.configID = configID
        context.name = Loadout.GetLoadoutName(configID)
        context.isStarter = Loadout.IsStarterBuild(configID)
    end

    if context.isStarter then
        Print("Cannot save gear for the Starter Build.")
        return false
    end

    DB:CreateOrUpdateGearSet(context.specID, context.configID, SnapshotEquippedGear(), context.name)
    Print(string.format("Saved gear for %s.", context.name))
    RefreshUI()
    return true
end

function Gear.DeleteSavedGear(configID, specID, notFoundMessage)
    specID = RequireSpecID(specID)
    if not specID then
        return false
    end

    if not configID then
        Print("No loadout selected.")
        return false
    end

    local entry = DB:DeleteGearSet(specID, configID)
    if not entry then
        Print(notFoundMessage or "No saved gear set for that loadout.")
        return false
    end

    local loadoutName = entry.loadoutName or Loadout.GetLoadoutName(configID)
    Print(string.format("Removed saved gear for %s.", loadoutName))
    RefreshUI()
    return true
end

function Gear.CopyGearSetToLoadout(sourceConfigID, targetConfigID, specID)
    specID = RequireSpecID(specID)
    if not specID then
        return false
    end

    if not sourceConfigID or not targetConfigID then
        Print("Select source and target loadouts.")
        return false
    end

    if sourceConfigID == targetConfigID then
        Print("Source and target loadouts must be different.")
        return false
    end

    if Loadout.IsStarterBuild(targetConfigID) then
        Print("Cannot copy gear to the Starter Build.")
        return false
    end

    if not DB:HasGearSet(specID, sourceConfigID) then
        Print("No saved gear set to copy from that loadout.")
        return false
    end

    local sourceName = Loadout.GetLoadoutName(sourceConfigID)
    local targetName = Loadout.GetLoadoutName(targetConfigID)
    DB:CopyGearSetToLoadout(specID, sourceConfigID, targetConfigID, targetName)
    Print(string.format("Copied gear set from %s to %s.", sourceName, targetName))
    RefreshUI()
    return true
end

function Gear.Delete(specID, configID)
    local context = Loadout.GetActive(specID)
    if not context then
        Print("No specialization selected.")
        return false
    end

    return Gear.DeleteSavedGear(
        configID or context.configID,
        context.specID,
        "No saved gear set for the current talent loadout."
    )
end

function Gear.List(specID)
    specID = RequireSpecID(specID)
    if not specID then
        return
    end

    local specData = DB:GetSpecEntries(specID)
    if not specData or not next(specData) then
        Print("No saved gear sets for this specialization.")
        return
    end

    local currentConfigID = Loadout.GetLoadoutConfigID(specID)
    Print("Saved gear sets for this spec:")

    for configID, entry in pairs(specData) do
        local marker = (configID == currentConfigID) and " (current)" or ""
        local name = entry.loadoutName or Loadout.GetLoadoutName(configID)
        Print(string.format("- %s%s", name, marker))
    end
end

function Gear.ScheduleLoadoutGearApply()
    if loadoutApplyTimer then
        loadoutApplyTimer:Cancel()
    end

    loadoutApplyTimer = C_Timer.NewTimer(C.LOADOUT_APPLY_DELAY, function()
        loadoutApplyTimer = nil
        Gear.ApplyGearForLoadoutChange()
    end)
end

local function PromptAndApplyGear(specID, configID, gearSet, options)
    options = options or {}
    Gear.NormalizeGearSetKeys(gearSet)

    local diff = Gear.BuildGearDiff(gearSet)
    local alreadyAppliedMessage = options.alreadyAppliedMessage or "Already wearing saved gear for this loadout."

    if not (options.forceUpgradeCheck or DB:AreUpgradeChecksEnabled()) then
        if diff.empty then
            Print(alreadyAppliedMessage)
            return
        end

        ApplyGearSwap(gearSet, function(ready)
            if not ready then
                return
            end

            if options.appliedMessage then
                Print(options.appliedMessage)
            end
        end, diff)
        return
    end

    local findOptions = {
        specID = specID,
        configID = configID,
    }
    if not options.offers then
        options.offers = LoadoutLocker.Upgrades.FindOffers(gearSet, findOptions)
    end

    if options.requireOffers and #options.offers == 0 then
        Print(options.noOffersMessage or "No better items found in your bags.")
        return
    end

    if diff.empty and #options.offers == 0 then
        Print(alreadyAppliedMessage)
        return
    end

    LoadoutLocker.Upgrades.PromptForBetterItems(gearSet, {
        specID = specID,
        configID = configID,
        offers = options.offers,
        onComplete = function(updatedGearSet, changed)
            if options.requireChange and not changed then
                Print(options.noChangeMessage or "No upgrades selected.")
                return
            end

            local swapDiff = changed and Gear.BuildGearDiff(updatedGearSet) or diff
            if swapDiff.empty then
                if changed then
                    SaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
                elseif options.appliedMessage then
                    Print(options.appliedMessage)
                else
                    Print(alreadyAppliedMessage)
                end
                return
            end

            ApplyGearSwap(updatedGearSet, function(ready)
                if not ready then
                    return
                end

                if changed then
                    SaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
                elseif options.appliedMessage then
                    Print(options.appliedMessage)
                end
            end, swapDiff)
        end,
    })
end

function Gear.ApplyGearForLoadoutChange()
    if LoadoutLocker.Upgrades.IsPromptActive() or equipQueueRunning then
        return
    end

    local switch = Loadout.ConsumePendingSwitch()
    if not switch then
        return
    end

    local specID = switch.specID
    local configID = switch.configID
    local previousConfigID = Loadout.GetPreviousConfigID(specID)
    Loadout.RememberActive(specID, configID)

    if previousConfigID == nil or previousConfigID == configID then
        return
    end

    local gearSet = DB:GetGearSet(specID, configID)
    if not gearSet then
        return
    end

    gearSet = DB:CopyGearSet(gearSet)
    Print(string.format("Talent loadout changed to %s. Applying saved gear...", Loadout.GetLoadoutName(configID)))

    PromptAndApplyGear(specID, configID, gearSet, {
        appliedMessage = "Applied saved gear set.",
        upgradedMessage = "Applied and saved upgraded gear set.",
    })
end

function Gear.ScanForUpgrades()
    local gearSet, context = Loadout.GetActiveGearSetCopy()
    if not context then
        Print("No talent loadout selected.")
        return
    end

    if not gearSet then
        Print("No saved gear set for the current talent loadout.")
        return
    end

    PromptAndApplyGear(context.specID, context.configID, gearSet, {
        forceUpgradeCheck = true,
        requireOffers = true,
        requireChange = true,
        noOffersMessage = "No better items found in your bags.",
        noChangeMessage = "No upgrades selected.",
    })
end

function Gear.OnSpecChanged()
    local specID = Loadout.GetSpecID()
    if not specID then
        return
    end

    C_Timer.After(0, function()
        Loadout.RememberActive(specID, Loadout.GetLoadoutConfigID(specID))
    end)
end

