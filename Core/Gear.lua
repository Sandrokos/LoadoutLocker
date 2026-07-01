LoadoutLocker = LoadoutLocker or {}

function LoadoutLocker.RefreshUI()
    if LoadoutLocker.RefreshTalentUI then
        LoadoutLocker.RefreshTalentUI()
    end
end

local C = LoadoutLocker.Constants
local Items = LoadoutLocker.Items
local Loadout = LoadoutLocker.Loadout
local PromptUtils = LoadoutLocker.PromptUtils

local DB = LoadoutLocker.DB
local EquipmentSet = LoadoutLocker.EquipmentSet
local Print = LoadoutLocker.Print
local RefreshUI = LoadoutLocker.RefreshUI

local Gear = {}
LoadoutLocker.Gear = Gear

local equipQueueRunning
local loadoutApplyTimer
local specChangeInProgress
local equipmentSetSwapPending
local gearApplyLocked
local swapIdleCallbacks = {}
local equipmentSetSwapCallbacks = {}

local swapEventFrame = CreateFrame("Frame")

local function IsGearSwapActive()
    return equipQueueRunning or equipmentSetSwapPending or gearApplyLocked
end

local function NotifySwapIdle()
    if IsGearSwapActive() then
        return
    end

    local callbacks = swapIdleCallbacks
    swapIdleCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

local function WaitForSwapIdle(callback)
    if not IsGearSwapActive() then
        C_Timer.After(C.EQUIP_SLOT_DELAY, callback)
        return
    end

    swapIdleCallbacks[#swapIdleCallbacks + 1] = callback
end

local function ReleaseGearApplyLock()
    gearApplyLocked = false
    NotifySwapIdle()
end

local function NotifyEquipmentSetSwapFinished()
    equipmentSetSwapPending = false
    swapEventFrame:UnregisterEvent("EQUIPMENT_SWAP_FINISHED")

    local callbacks = equipmentSetSwapCallbacks
    equipmentSetSwapCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end

    NotifySwapIdle()
end

local function WaitForEquipmentSetSwap(callback)
    if not equipmentSetSwapPending then
        C_Timer.After(C.EQUIP_SLOT_DELAY, callback)
        return
    end

    equipmentSetSwapCallbacks[#equipmentSetSwapCallbacks + 1] = callback
    swapEventFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
end

swapEventFrame:SetScript("OnEvent", function(_, event)
    if event == "EQUIPMENT_SWAP_FINISHED" then
        NotifyEquipmentSetSwapFinished()
    end
end)

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

    if entry.itemLink then
        local mods = Items.ParseItemLinkModifiers(entry.itemLink)
        if mods then
            return {
                itemID = entry.itemID or mods.itemID,
                enchantID = mods.enchantID,
                gems = Items.CopyGemsTable(mods.gems) or {},
            }
        end
    end

    if entry.enchantID or entry.gems then
        return {
            itemID = entry.itemID,
            enchantID = entry.enchantID or 0,
            gems = Items.CopyGemsTable(entry.gems) or {},
        }
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

local function ItemLinkMatchesEntry(itemLink, entry, entryMods, options)
    if not itemLink or not entry then
        return false
    end

    options = options or {}

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

    if options.matchSavedLevel then
        local savedLevel = Items.GetSavedItemLevel(entry)
        if savedLevel > 0 then
            local candidateLevel = Items.GetItemLevel(itemLink)
            if candidateLevel > 0 and candidateLevel ~= savedLevel then
                return false
            end
        end
    end

    return true
end

local function SlotEntryMatchesEquipped(invSlot, entry, equippedLink, equippedItemID)
    equippedLink = equippedLink or GetInventoryItemLink("player", invSlot)
    if not equippedLink or not entry then
        return false
    end

    if ItemLinkMatchesEntry(equippedLink, entry, nil, { matchSavedLevel = true }) then
        return true
    end

    if type(entry) == "table" and entry.itemLink then
        return false
    end

    local itemID = equippedItemID or GetInventoryItemID("player", invSlot)
    local entryItemID = Gear.GetEntryItemID(entry)
    if not itemID or itemID ~= entryItemID then
        return false
    end

    local linkMods = Items.ParseItemLinkModifiers(equippedLink)
    local entryMods = GetEntryModifiers(entry)
    if not linkMods or linkMods.itemID ~= entryMods.itemID then
        return false
    end

    return (linkMods.enchantID or 0) == (entryMods.enchantID or 0)
        and Items.GemsMatch(linkMods.gems, entryMods.gems)
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
    bagState.emptyIndex = bagState.emptyIndex or 1

    while bagState.emptyIndex <= #bagState.emptySlots do
        local slotInfo = bagState.emptySlots[bagState.emptyIndex]
        bagState.emptyIndex = bagState.emptyIndex + 1

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

function Gear.GetEntryItemID(entry)
    if type(entry) == "table" then
        if entry.itemID then
            return entry.itemID
        end

        if entry.itemLink then
            local mods = Items.ParseItemLinkModifiers(entry.itemLink)
            if mods and mods.itemID then
                return mods.itemID
            end
        end

        return nil
    end

    return tonumber(entry) or entry
end

function Gear.GetEntryItemLink(entry)
    if type(entry) == "table" then
        return entry.itemLink
    end
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

    local equippedLink = GetInventoryItemLink("player", invSlot)
    local equippedID = GetInventoryItemID("player", invSlot)
    return SlotEntryMatchesEquipped(invSlot, targetEntry, equippedLink, equippedID)
end

local function MergeGearSnapshot(snapshot, expectedGearSet)
    if not expectedGearSet then
        return snapshot
    end

    for invSlot, entry in pairs(expectedGearSet) do
        invSlot = Gear.NormalizeInvSlot(invSlot)
        local equippedID = GetInventoryItemID("player", invSlot)
        local equippedLink = GetInventoryItemLink("player", invSlot)

        if equippedID and entry and SlotEntryMatchesEquipped(invSlot, entry, equippedLink, equippedID) then
            snapshot[invSlot] = Items.ToGearEntry({ itemID = equippedID, itemLink = equippedLink })
        elseif type(entry) == "table" and entry.itemLink then
            snapshot[invSlot] = Items.ToGearEntry({
                itemID = Gear.GetEntryItemID(entry),
                itemLink = entry.itemLink,
            })
        elseif entry then
            snapshot[invSlot] = entry
        end
    end

    return snapshot
end

local function BuildWorkingGearSet(gearSet)
    if not gearSet then
        return gearSet
    end

    Gear.NormalizeGearSetKeys(gearSet)
    return MergeGearSnapshot(SnapshotEquippedGear(), gearSet)
end

local function SaveEquippedGearSet(specID, configID, expectedGearSet)
    local loadoutName = Loadout.GetLoadoutName(configID)
    local snapshot = MergeGearSnapshot(SnapshotEquippedGear(), expectedGearSet)
    DB:CreateOrUpdateGearSet(specID, configID, snapshot, loadoutName)
    EquipmentSet.ScheduleSyncForLoadout(specID, configID, loadoutName)
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
        if SlotEntryMatchesEquipped(invSlot, gearEntry, currentLink) then
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

    local unequipEmbellished = {}
    for _, invSlot in ipairs(diff.unequip) do
        unequipEmbellished[invSlot] = Items.IsEmbellished(GetInventoryItemLink("player", invSlot)) and 1 or 0
    end

    table.sort(diff.equip, function(a, b)
        local aEmbellished = IsEmbellishedGearEntry(a.entry) and 1 or 0
        local bEmbellished = IsEmbellishedGearEntry(b.entry) and 1 or 0
        if aEmbellished ~= bEmbellished then
            return aEmbellished < bEmbellished
        end
        return a.invSlot < b.invSlot
    end)

    table.sort(diff.unequip, function(a, b)
        local aEmbellished = unequipEmbellished[a]
        local bEmbellished = unequipEmbellished[b]
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
    local levelMatchOptions = savedLevel > 0 and { matchSavedLevel = true } or nil

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
            if gearEntry and ItemLinkMatchesEntry(link, gearEntry, entryMods, levelMatchOptions) then
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

                if ItemLinkMatchesEntry(link, gearEntry, entryMods, levelMatchOptions) then
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
    if SlotEntryMatchesEquipped(invSlot, gearEntry, equippedLink) then
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
    if SlotEntryMatchesEquipped(invSlot, gearEntry, equippedLink) then
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
        if itemID and GetInventoryItemID("player", change.invSlot) == itemID then
            -- Correct item is equipped; link/modifier checks can lag after swaps.
        else
            ReportSwapIssue(
                reported,
                "missing:" .. tostring(itemID),
                "Missing item: " .. Items.GetDisplayName(itemID)
            )
        end
    end

    for _, invSlot in ipairs(diff.unequip) do
        ReportSwapIssue(
            reported,
            "unequip:" .. tostring(invSlot),
            string.format("%s still has the wrong item equipped.", C.GetSlotLabel(invSlot))
        )
    end
end

local function IsAcceptableRemainingDiff(remaining, gearSet)
    for _, change in ipairs(remaining.equip) do
        local targetItemID = Gear.GetEntryItemID(change.entry)
        if targetItemID and GetInventoryItemID("player", change.invSlot) ~= targetItemID then
            return false
        end
    end

    for _, invSlot in ipairs(remaining.unequip) do
        local targetEntry = Gear.GetGearSetEntry(gearSet, invSlot)
        local targetItemID = Gear.GetEntryItemID(targetEntry)
        local equippedID = GetInventoryItemID("player", invSlot)

        if equippedID and targetItemID and equippedID ~= targetItemID then
            return false
        end

        if equippedID and not targetItemID then
            return false
        end
    end

    return true
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
        C_Timer.After(C.EQUIP_SLOT_DELAY, NotifySwapIdle)
    end

    local function VerifyAndComplete(attempt)
        attempt = attempt or 1
        local delay = (attempt == 1) and (C.EQUIP_SLOT_DELAY * 2) or C.EQUIP_SLOT_DELAY

        C_Timer.After(delay, function()
            local remaining = Gear.BuildGearDiff(gearSet)
            if remaining.empty then
                FinishSwap(true)
                return
            end

            if IsAcceptableRemainingDiff(remaining, gearSet) then
                FinishSwap(true)
                return
            end

            if attempt < 6 then
                VerifyAndComplete(attempt + 1)
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
            C_Timer.After(0, NotifySwapIdle)
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
                if not EquipSlot(change.invSlot, change.entry, usedLocations, bagState)
                    and NeedsEquipForEntry(change.invSlot, change.entry) then
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
    EquipmentSet.SyncForLoadout(context.specID, context.configID, context.name)
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

    local loadoutName = Loadout.ResolveLoadoutName(configID, entry.loadoutName)
    EquipmentSet.OnGearSetDeleted(specID, configID, entry)
    Print(string.format("Removed saved gear for %s.", loadoutName))
    RefreshUI()
    return true
end

function Gear.CopyGearSetToLoadout(sourceConfigID, targetConfigID, sourceSpecID, targetSpecID)
    sourceSpecID = sourceSpecID or Loadout.GetSpecID()
    targetSpecID = targetSpecID or sourceSpecID
    if not sourceSpecID or not targetSpecID then
        Print("No specialization available.")
        return false
    end

    if not sourceConfigID or not targetConfigID then
        Print("Select source and target loadouts.")
        return false
    end

    if sourceSpecID == targetSpecID and sourceConfigID == targetConfigID then
        Print("Source and target loadouts must be different.")
        return false
    end

    if Loadout.IsStarterBuild(targetConfigID) then
        Print("Cannot copy gear to the Starter Build.")
        return false
    end

    if not DB:HasGearSet(sourceSpecID, sourceConfigID) then
        Print("No saved gear set to copy from that loadout.")
        return false
    end

    local sourceName = Loadout.FormatLoadoutLabel(sourceSpecID, Loadout.GetLoadoutName(sourceConfigID))
    local targetName = Loadout.FormatLoadoutLabel(targetSpecID, Loadout.GetLoadoutName(targetConfigID))
    DB:CopyGearSetToLoadout(targetSpecID, sourceConfigID, targetConfigID, Loadout.GetLoadoutName(targetConfigID), sourceSpecID)
    if sourceSpecID == targetSpecID then
        EquipmentSet.LinkCopiedLoadouts(targetSpecID, sourceConfigID, targetConfigID)
    end
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
        local name = Loadout.ResolveLoadoutName(configID, entry.loadoutName)
        Print(string.format("- %s%s", name, marker))
    end
end

function Gear.IsSwapActive()
    return IsGearSwapActive()
end

function Gear.ScheduleLoadoutGearApply()
    if specChangeInProgress or Loadout.IsAwaitingTalentSwitchAfterSpec() then
        return
    end

    if loadoutApplyTimer then
        loadoutApplyTimer:Cancel()
    end

    loadoutApplyTimer = C_Timer.NewTimer(C.LOADOUT_APPLY_DELAY, function()
        loadoutApplyTimer = nil
        if IsGearSwapActive() then
            Gear.ScheduleLoadoutGearApply()
            return
        end
        Gear.ApplyGearForLoadoutChange()
    end)
end

local function ValidateEquippedGear(gearSet, onComplete)
    local function check(attempt)
        attempt = attempt or 1
        local delay = (attempt == 1) and (C.EQUIP_SLOT_DELAY * 2) or C.EQUIP_SLOT_DELAY

        C_Timer.After(delay, function()
            local remaining = Gear.BuildGearDiff(gearSet)
            if remaining.empty or IsAcceptableRemainingDiff(remaining, gearSet) then
                onComplete(true)
                return
            end

            if attempt < 6 then
                check(attempt + 1)
                return
            end

            PrintGearDiffFailures(remaining, {})
            onComplete(false)
        end)
    end

    check(1)
end

local function RunUpgradeStep(specID, configID, gearSet, options, onComplete)
    if not (options.forceUpgradeCheck or DB:AreUpgradeChecksEnabled()) then
        onComplete(gearSet, false)
        return
    end

    local workingGearSet = BuildWorkingGearSet(gearSet)

    local offers = options.offers
    if not offers then
        offers = LoadoutLocker.Upgrades.FindOffers(workingGearSet, {
            specID = specID,
            configID = configID,
        })
    end

    if options.requireOffers and #offers == 0 then
        Print(options.noOffersMessage or "No better items found in your bags.")
        onComplete(gearSet, false)
        return
    end

    if #offers == 0 then
        onComplete(gearSet, false)
        return
    end

    LoadoutLocker.Upgrades.PromptForBetterItems(workingGearSet, {
        specID = specID,
        configID = configID,
        offers = offers,
        onComplete = function(updatedGearSet, changed)
            if options.requireChange and not changed then
                Print(options.noChangeMessage or "No upgrades selected.")
                onComplete(gearSet, false)
                return
            end

            if not changed then
                onComplete(gearSet, false)
                return
            end

            local swapDiff = Gear.BuildGearDiff(updatedGearSet)
            if swapDiff.empty then
                onComplete(updatedGearSet, true)
                return
            end

            ApplyGearSwap(updatedGearSet, function(ready)
                onComplete(updatedGearSet, ready ~= false)
            end, swapDiff)
        end,
    })
end

local function RunUpgradeOnlyPipeline(specID, configID, gearSet, options)
    gearApplyLocked = true

    local function finish(success, changed)
        if success then
            if changed then
                Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
            end
            if options.onApplied then
                options.onApplied()
            end
        elseif options.onApplyFailed then
            options.onApplyFailed()
        end
    end

    local function afterUpgrades(workingGearSet, changed)
        if changed then
            SaveEquippedGearSet(specID, configID, workingGearSet)
        end

        ValidateEquippedGear(workingGearSet, function(valid)
            finish(valid, changed)
        end)
    end

    Gear.NormalizeGearSetKeys(gearSet)
    local workingGearSet = BuildWorkingGearSet(gearSet)
    RunUpgradeStep(specID, configID, gearSet, options, afterUpgrades)
end

local function RunLoadoutGearPipeline(specID, configID, gearSet, options)
    local function finish(success, changed)
        if success then
            if changed then
                Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
            elseif options.appliedMessage then
                Print(options.appliedMessage)
            end
            if options.onApplied then
                options.onApplied()
            end
        elseif options.onApplyFailed then
            options.onApplyFailed()
        end
    end

    local function afterValidation(success, workingGearSet, changed)
        finish(success, changed)
    end

    local function afterUpgrades(workingGearSet, changed)
        if changed then
            SaveEquippedGearSet(specID, configID, workingGearSet)
        end

        ValidateEquippedGear(workingGearSet, function(valid)
            afterValidation(valid, workingGearSet, changed)
        end)
    end

    Gear.NormalizeGearSetKeys(gearSet)
    local workingGearSet = BuildWorkingGearSet(gearSet)

    local function afterEquipmentSet()
        RunUpgradeStep(specID, configID, gearSet, options, afterUpgrades)
    end

    local function fallbackManualSwap()
        local diff = Gear.BuildGearDiff(gearSet)
        if diff.empty then
            afterEquipmentSet()
            return
        end

        ApplyGearSwap(gearSet, function(ready)
            if not ready then
                if options.onApplyFailed then
                    options.onApplyFailed()
                end
                return
            end

            afterEquipmentSet()
        end, diff)
    end

    if EquipmentSet.TryUse(specID, configID) then
        Gear.NormalizeGearSetKeys(gearSet)
        if Gear.BuildGearDiff(gearSet).empty then
            C_Timer.After(C.EQUIP_SLOT_DELAY, afterEquipmentSet)
            return
        end

        equipmentSetSwapPending = true
        swapEventFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
        C_Timer.After(3, function()
            if equipmentSetSwapPending then
                NotifyEquipmentSetSwapFinished()
            end
        end)

        WaitForEquipmentSetSwap(function()
            afterEquipmentSet()
        end)
        return
    end

    fallbackManualSwap()
end

local function PromptAndApplyGear(specID, configID, gearSet, options)
    options = options or {}
    Gear.NormalizeGearSetKeys(gearSet)
    local workingGearSet = BuildWorkingGearSet(gearSet)

    local function FinishApplied(ready)
        if ready == false then
            if options.onApplyFailed then
                options.onApplyFailed()
            end
            return
        end

        if options.onApplied then
            options.onApplied()
        end
    end

    local diff = Gear.BuildGearDiff(workingGearSet)
    local alreadyAppliedMessage = options.alreadyAppliedMessage or "Already wearing saved gear for this loadout."

    if not (options.forceUpgradeCheck or DB:AreUpgradeChecksEnabled()) then
        if diff.empty then
            Print(alreadyAppliedMessage)
            FinishApplied(true)
            return
        end

        ApplyGearSwap(gearSet, function(ready)
            if not ready then
                FinishApplied(false)
                return
            end

            if options.appliedMessage then
                Print(options.appliedMessage)
            end
            FinishApplied(ready)
        end, diff)
        return
    end

    local findOptions = {
        specID = specID,
        configID = configID,
    }
    if not options.offers then
        options.offers = LoadoutLocker.Upgrades.FindOffers(workingGearSet, findOptions)
    end

    if options.requireOffers and #options.offers == 0 then
        Print(options.noOffersMessage or "No better items found in your bags.")
        FinishApplied(false)
        return
    end

    if diff.empty and #options.offers == 0 then
        Print(alreadyAppliedMessage)
        FinishApplied(true)
        return
    end

    LoadoutLocker.Upgrades.PromptForBetterItems(workingGearSet, {
        specID = specID,
        configID = configID,
        offers = options.offers,
        onComplete = function(updatedGearSet, changed)
            if options.requireChange and not changed then
                Print(options.noChangeMessage or "No upgrades selected.")
                FinishApplied(false)
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
                FinishApplied(true)
                return
            end

            ApplyGearSwap(updatedGearSet, function(ready)
                if not ready then
                    FinishApplied(false)
                    return
                end

                if changed then
                    SaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
                elseif options.appliedMessage then
                    Print(options.appliedMessage)
                end
                FinishApplied(ready)
            end, swapDiff)
        end,
    })
end

function Gear.ApplyGearForLoadoutChange()
    if Loadout.IsAwaitingTalentSwitchAfterSpec() then
        return
    end

    if LoadoutLocker.Upgrades.IsPromptActive() or IsGearSwapActive() then
        Gear.ScheduleLoadoutGearApply()
        return
    end

    local specID = Loadout.GetSpecID()
    if not specID then
        return
    end

    local pending = Loadout.PeekPendingSwitch()
    local configID = Loadout.GetLoadoutConfigID(specID)
    if pending and pending.specID == specID and pending.configID then
        configID = pending.configID
    end

    if not configID or Loadout.IsStarterBuild(configID) then
        return
    end

    local shouldApplyGear = Loadout.ShouldApplyGearForSwitch(specID, configID)
    local shouldRunUpgrades = Loadout.ShouldRunUpgradeCheck(specID, configID)

    if not shouldApplyGear and not shouldRunUpgrades then
        PromptUtils.NotifyPromptGearStepFinished(specID, configID)
        return
    end

    Loadout.ConsumePendingSwitch()

    local gearSet = DB:GetGearSet(specID, configID)
    if not gearSet then
        Loadout.RememberAppliedSpec(specID)
        Loadout.RememberUpgradeCheck(specID, configID)
        PromptUtils.NotifyPromptGearStepFinished(specID, configID)
        return
    end

    gearSet = DB:CopyGearSet(gearSet)

    local applyOptions = {
        appliedMessage = "Applied saved gear set.",
        upgradedMessage = "Applied and saved upgraded gear set.",
        onApplied = function()
            Loadout.RememberActive(specID, configID)
            Loadout.RememberAppliedSpec(specID)
            Loadout.RememberUpgradeCheck(specID, configID)
            ReleaseGearApplyLock()
            PromptUtils.NotifyPromptGearStepFinished(specID, configID)
        end,
        onApplyFailed = function()
            ReleaseGearApplyLock()
            PromptUtils.NotifyPromptGearStepFinished(specID, configID)
        end,
    }
    if shouldRunUpgrades or DB:AreUpgradeChecksEnabled() then
        applyOptions.forceUpgradeCheck = true
    end

    if not shouldApplyGear then
        RunUpgradeOnlyPipeline(specID, configID, gearSet, applyOptions)
        return
    end

    local loadoutName = Loadout.GetLoadoutName(configID)
    if Loadout.GetLastAppliedSpecID() ~= specID then
        Print(string.format("Specialization changed. Applying saved gear for %s...", loadoutName))
    else
        Print(string.format("Talent loadout changed to %s. Applying saved gear...", loadoutName))
    end

    gearApplyLocked = true
    RunLoadoutGearPipeline(specID, configID, gearSet, applyOptions)
end

local function ScheduleSpecGearApply(attempt)
    attempt = attempt or 1

    C_Timer.After(C.LOADOUT_APPLY_DELAY, function()
        if IsGearSwapActive() then
            WaitForSwapIdle(function()
                ScheduleSpecGearApply(attempt)
            end)
            return
        end

        local specID = Loadout.GetSpecID()
        if specID then
            local configID = Loadout.GetLoadoutConfigID(specID)
            if configID and not Loadout.IsStarterBuild(configID) then
                Loadout.QueueSwitch(specID, configID)
            end
        end

        Gear.ApplyGearForLoadoutChange()

        if Loadout.GetLastAppliedSpecID() == Loadout.GetSpecID() then
            specChangeInProgress = false
            return
        end

        if IsGearSwapActive() then
            WaitForSwapIdle(function()
                if Loadout.GetLastAppliedSpecID() == Loadout.GetSpecID() then
                    specChangeInProgress = false
                elseif attempt < 5 then
                    ScheduleSpecGearApply(attempt + 1)
                else
                    specChangeInProgress = false
                end
            end)
            return
        end

        if attempt >= 5 then
            specChangeInProgress = false
            return
        end

        ScheduleSpecGearApply(attempt + 1)
    end)
end

function Gear.OnTalentSwitchAfterSpecComplete()
    specChangeInProgress = false
    Gear.ScheduleLoadoutGearApply()
end

function Gear.OnSpecChanged()
    specChangeInProgress = true

    local pending = Loadout.PeekPendingSwitch()
    local currentSpecID = Loadout.GetSpecID()
    if pending and pending.specID == currentSpecID and Loadout.IsAwaitingTalentSwitchAfterSpec() then
        PromptUtils.MarkSpecSwitchComplete()
        PromptUtils.SetPromptLoadingStep(PromptUtils.STEP_CHANGING_TALENTS)
        Loadout.ConsumePendingSwitch()
        local targetSpecID = pending.specID
        local targetConfigID = pending.configID

        C_Timer.After(C.SPEC_TALENT_SWITCH_DELAY, function()
            if Loadout.GetSpecID() ~= targetSpecID then
                Loadout.ClearAwaitingTalentSwitchAfterSpec()
                specChangeInProgress = false
                PromptUtils.FailPendingPromptSwitch("spec")
                return
            end

            local ok, reason = Loadout.SwitchTo(targetConfigID, targetSpecID)
            if not ok and reason ~= "unchanged" then
                Loadout.ClearAwaitingTalentSwitchAfterSpec()
                specChangeInProgress = false
                PromptUtils.FailPendingPromptSwitch(reason or "talent")
            elseif reason == "unchanged" then
                Loadout.ClearAwaitingTalentSwitchAfterSpec()
                Gear.OnTalentSwitchAfterSpecComplete()
                PromptUtils.OnPromptLoadoutTalentsApplied(targetSpecID, targetConfigID)
            end

            RefreshUI()
        end)
        return
    end

    if Loadout.IsAwaitingTalentSwitchAfterSpec() then
        local awaiting = Loadout.GetAwaitingTalentSwitchAfterSpec()
        Loadout.ClearAwaitingTalentSwitchAfterSpec()
        if awaiting and awaiting.specID ~= currentSpecID then
            PromptUtils.FailPendingPromptSwitch("spec")
        end
    end

    if pending then
        Loadout.ClearPendingSwitch()
    end

    ScheduleSpecGearApply(1)

    C_Timer.After(0, function()
        RefreshUI()
    end)
end

function Gear.ScanForUpgrades()
    LoadoutLocker.Upgrades.DismissPrompt()

    local gearSet, context = Loadout.GetActiveGearSetCopy()
    if not context then
        Print("No talent loadout selected.")
        return
    end

    if not gearSet then
        Print("No saved gear set for the current talent loadout.")
        return
    end

    Loadout.ClearUpgradeCheck(context.specID)

    PromptAndApplyGear(context.specID, context.configID, gearSet, {
        forceUpgradeCheck = true,
        requireOffers = true,
        requireChange = true,
        noOffersMessage = "No better items found in your bags.",
        noChangeMessage = "No upgrades selected.",
    })
end

