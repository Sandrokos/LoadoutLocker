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

local deferredGearSwap
local equipQueueRunning
local loadoutApplyTimer

local function GemsMatch(gemsA, gemsB)
    return Items.GemsMatch(gemsA, gemsB)
end

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

    return GemsMatch(modsA.gems, modsB.gems)
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

local function GetLinkItemLevel(itemLink)
    return Items.GetItemLevel(itemLink)
end

local function GetSavedItemLevel(entry)
    return Items.GetSavedItemLevel(entry)
end

local function ItemLinkMatchesEntry(itemLink, entry)
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

    local entryMods = GetEntryModifiers(entry)
    if linkMods.itemID ~= entryMods.itemID then
        return false
    end

    if not ModifiersMatch(linkMods, entryMods) then
        return false
    end

    local savedLevel = GetSavedItemLevel(entry)
    if savedLevel > 0 then
        local candidateLevel = GetLinkItemLevel(itemLink)
        if candidateLevel > 0 and candidateLevel ~= savedLevel then
            return false
        end
    end

    return true
end

local function CreateGearEntry(itemID, itemLink)
    return Items.ToGearEntry({ itemID = itemID, itemLink = itemLink })
end

function Gear.ParseItemLinkModifiers(itemLink)
    return Items.ParseItemLinkModifiers(itemLink)
end

function Gear.CreateGearEntryFromLink(itemID, itemLink, bag, slot)
    return Items.ToGearEntryFromLink(itemID, itemLink, bag, slot)
end

local function SnapshotEquippedGear()
    local gear = {}

    Items.ForEachEquipped(function(location)
        gear[location.invSlot] = CreateGearEntry(location.itemID, location.itemLink)
    end)

    return gear
end

local function FindEmptyBagSlot(reservedBagSlots)
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
    return gearSet[invSlot] or gearSet[tostring(invSlot)]
end

local function SetGearSetEntry(gearSet, invSlot, entry)
    invSlot = Gear.NormalizeInvSlot(invSlot)
    gearSet[invSlot] = entry
    gearSet[tostring(invSlot)] = nil
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

function Gear.SetGearSetEntry(gearSet, invSlot, entry)
    SetGearSetEntry(gearSet, invSlot, entry)
end

local function ResolveGearEntry(entry)
    if type(entry) == "table" then
        return entry.itemID, entry.bag, entry.slot, entry.itemLink, entry.enchantID, Items.CopyGemsTable(entry.gems)
    end

    return entry, nil, nil, nil, nil, nil
end

local swapDeclinedUpgradeSlots

local function IsUpgradeDeclinedForSlot(invSlot, declinedUpgradeSlots)
    local slots = declinedUpgradeSlots or swapDeclinedUpgradeSlots
    if not slots then
        return false
    end

    local normalizedSlot = tonumber(invSlot) or invSlot
    return slots[normalizedSlot]
        or slots[tostring(normalizedSlot)]
        or false
end

local function ShouldKeepEquippedUpgrade(invSlot, itemLink, gearEntry, declinedUpgradeSlots)
    if not itemLink or not gearEntry then
        return false
    end

    if IsUpgradeDeclinedForSlot(invSlot, declinedUpgradeSlots) then
        return false
    end

    return LoadoutLocker.Upgrades.IsLinkBetterThanSavedEntry(itemLink, gearEntry)
end

local function SlotSatisfiesTarget(invSlot, targetEntry, declinedUpgradeSlots)
    if not targetEntry then
        return not GetInventoryItemID("player", invSlot)
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ShouldKeepEquippedUpgrade(invSlot, equippedLink, targetEntry, declinedUpgradeSlots) then
        return true
    end

    return ItemLinkMatchesEntry(equippedLink, targetEntry)
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
            snapshot[invSlot] = CreateGearEntry(equippedID, equippedLink)
        elseif equippedLink and entry and ShouldKeepEquippedUpgrade(invSlot, equippedLink, entry, swapDeclinedUpgradeSlots) then
            snapshot[invSlot] = CreateGearEntry(equippedID, equippedLink)
        elseif type(entry) == "table" and entry.itemLink then
            snapshot[invSlot] = CreateGearEntry(entry.itemID, entry.itemLink)
        elseif entry then
            snapshot[invSlot] = entry
        end
    end

    return snapshot
end

local function ExpectedGearReady(expectedGearSet)
    Gear.NormalizeGearSetKeys(expectedGearSet)

    for _, invSlot in ipairs(C.EQUIP_SLOTS) do
        local entry = Gear.GetGearSetEntry(expectedGearSet, invSlot)
        if entry then
            local equippedLink = GetInventoryItemLink("player", invSlot)
            if not ItemLinkMatchesEntry(equippedLink, entry)
                and not ShouldKeepEquippedUpgrade(invSlot, equippedLink, entry, swapDeclinedUpgradeSlots) then
                return false
            end
        end
    end

    return true
end

local function SaveEquippedGearSet(specID, configID, expectedGearSet)
    local snapshot = MergeGearSnapshot(SnapshotEquippedGear(), expectedGearSet)
    DB:CreateOrUpdateGearSet(specID, configID, snapshot, Loadout.GetLoadoutName(configID))
    RefreshUI()
end

local function ScheduleSaveEquippedGearSet(specID, configID, expectedGearSet, attemptsLeft)
    attemptsLeft = attemptsLeft or C.MAX_SAVE_RETRIES

    C_Timer.After(C.SAVE_RETRY_DELAY, function()
        if expectedGearSet and not ExpectedGearReady(expectedGearSet) and attemptsLeft > 1 then
            ScheduleSaveEquippedGearSet(specID, configID, expectedGearSet, attemptsLeft - 1)
            return
        end

        SaveEquippedGearSet(specID, configID, expectedGearSet)
    end)
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

    if gearEntry and ShouldKeepEquippedUpgrade(invSlot, currentLink, gearEntry, swapDeclinedUpgradeSlots) then
        return false
    end

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

local function DiffSlotFilter(diff)
    local slots = {}

    for _, invSlot in ipairs(diff.unequip) do
        slots[Gear.NormalizeInvSlot(invSlot)] = true
    end

    for _, change in ipairs(diff.equip) do
        slots[Gear.NormalizeInvSlot(change.invSlot)] = true
    end

    return slots
end

function Gear.BuildGearDiff(targetGearSet, declinedUpgradeSlots)
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
        if targetEntry and not SlotSatisfiesTarget(invSlot, targetEntry, declinedUpgradeSlots) then
            diff.equip[#diff.equip + 1] = {
                invSlot = invSlot,
                entry = targetEntry,
            }
        end
    end

    diff.empty = #diff.unequip == 0 and #diff.equip == 0
    return diff
end

function Gear.ValidateGearDiff(targetGearSet, declinedUpgradeSlots)
    local diff = Gear.BuildGearDiff(targetGearSet, declinedUpgradeSlots)
    return diff.empty, diff
end

local function IsEmbellishedGearEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local itemLink = entry.itemLink
    local itemID = entry.itemID
    if not itemLink and itemID then
        itemLink = select(2, C_Item.GetItemInfo(itemID))
    end

    return Items.IsEmbellished(itemLink, itemID)
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

local function UnequipToBag(invSlot, reservedBagSlots)
    if not GetInventoryItemID("player", invSlot) then
        return true
    end

    local bag, slot, locationKey = FindEmptyBagSlot(reservedBagSlots)
    if not bag then
        Print("Not enough bag space to swap gear.")
        return false
    end

    ClearCursor()
    PickupInventoryItem(invSlot)
    C_Container.PickupContainerItem(bag, slot)
    ClearCursor()

    reservedBagSlots[locationKey] = true
    return true
end

local function FindItemInBagsByLink(itemLink, usedLocations, gearEntry)
    if not itemLink and not gearEntry then
        return
    end

    local found

    Items.ForEachBagItem(function(location)
        if found then
            return
        end

        local locationKey = Items.GetLocationKey(location)
        if not usedLocations[locationKey] and location.itemLink then
            if gearEntry and ItemLinkMatchesEntry(location.itemLink, gearEntry) then
                found = { "bag", location.bag, location.slot, locationKey }
            elseif itemLink and ItemLinkEquals(location.itemLink, itemLink) then
                found = { "bag", location.bag, location.slot, locationKey }
            end
        end
    end)

    if found then
        return found[1], found[2], found[3], found[4]
    end
end

local function FindItemInBagsByModifiers(entry, usedLocations)
    local modifiers = GetEntryModifiers(entry)
    if not modifiers.itemID then
        return
    end

    local savedLevel = GetSavedItemLevel(entry)
    local bestSource, bestBag, bestSlot, bestKey, bestDistance

    local exactMatch

    Items.ForEachBagItem(function(location)
        if exactMatch then
            return
        end

        local locationKey = Items.GetLocationKey(location)
        if usedLocations[locationKey] then
            return
        end

        local link = location.itemLink
        if type(entry) == "table" and ItemLinkEquals(link, entry.itemLink) then
            exactMatch = { "bag", location.bag, location.slot, locationKey }
            return
        end

        if ItemLinkMatchesEntry(link, entry) then
            local distance = 0
            if savedLevel > 0 then
                local level = GetLinkItemLevel(link)
                distance = level > 0 and math.abs(level - savedLevel) or math.huge
            end
            if not bestSource or distance < bestDistance then
                bestSource = "bag"
                bestBag = location.bag
                bestSlot = location.slot
                bestKey = locationKey
                bestDistance = distance
            end
        end
    end)

    if exactMatch then
        return exactMatch[1], exactMatch[2], exactMatch[3], exactMatch[4]
    end

    if bestSource then
        return bestSource, bestBag, bestSlot, bestKey
    end
end

local function FindItemInBags(itemID, itemLink, usedLocations, gearEntry)
    local sourceType, bag, slot, locationKey = FindItemInBagsByLink(itemLink, usedLocations, gearEntry)
    if sourceType then
        return sourceType, bag, slot, locationKey
    end

    if gearEntry then
        sourceType, bag, slot, locationKey = FindItemInBagsByModifiers(gearEntry, usedLocations)
        if sourceType then
            return sourceType, bag, slot, locationKey
        end
    end

    if gearEntry and EntryRequiresModifierMatch(gearEntry) then
        return
    end

    Items.ForEachBagItem(function(location)
        if sourceType then
            return
        end

        local locationKey = Items.GetLocationKey(location)
        if not usedLocations[locationKey] and location.itemID == itemID then
            sourceType = "bag"
            bag = location.bag
            slot = location.slot
            locationKey = locationKey
        end
    end)

    return sourceType, bag, slot, locationKey
end

local function FindItemOnPlayer(itemID, itemLink, targetSlot, usedLocations, gearEntry)
    local sourceType, bag, slot, locationKey = FindItemInBags(itemID, itemLink, usedLocations, gearEntry)
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
    local locationKey = "bag:" .. bag .. ":" .. slot
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

local function NeedsEquipForEntry(invSlot, gearEntry, declinedUpgradeSlots)
    local itemID = ResolveGearEntry(gearEntry)
    if not itemID then
        return false
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ShouldKeepEquippedUpgrade(invSlot, equippedLink, gearEntry, declinedUpgradeSlots) then
        return false
    end

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

local function EquipSlot(invSlot, gearEntry, usedLocations)
    local itemID, preferredBag, preferredSlot, itemLink = ResolveGearEntry(gearEntry)
    if not itemID then
        return true
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ItemLinkMatchesEntry(equippedLink, gearEntry) then
        return true
    end

    if ShouldKeepEquippedUpgrade(invSlot, equippedLink, gearEntry, swapDeclinedUpgradeSlots) then
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

    local sourceType, arg1, arg2, locationKey = FindItemOnPlayer(itemID, itemLink, invSlot, usedLocations, gearEntry)
    if not sourceType then
        Print("Missing item: " .. Items.GetDisplayName(itemID))
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

local function PrintGearDiffFailures(diff)
    for _, change in ipairs(diff.equip) do
        local itemID = ResolveGearEntry(change.entry)
        Print(string.format(
            "Slot %d still needs: %s",
            change.invSlot,
            Items.GetDisplayName(itemID)
        ))
    end

    for _, invSlot in ipairs(diff.unequip) do
        Print(string.format("Slot %d still has the wrong item equipped.", invSlot))
    end
end

local function RunGearSwap(gearSet, onComplete, declinedUpgradeSlots, verifyAttempt)
    if equipQueueRunning then
        return
    end

    if not gearSet or not next(gearSet) then
        return
    end

    verifyAttempt = verifyAttempt or 1
    Gear.NormalizeGearSetKeys(gearSet)
    swapDeclinedUpgradeSlots = declinedUpgradeSlots

    local diff = Gear.BuildGearDiff(gearSet, declinedUpgradeSlots)
    OrderSwapDiff(diff)
    if diff.empty then
        swapDeclinedUpgradeSlots = nil
        if onComplete then
            onComplete(true)
        end
        return
    end

    equipQueueRunning = true
    local neededItems = BuildNeededItems(gearSet)
    local usedLocations = {}
    local reservedBagSlots = {}
    local phase = C.SWAP_PHASE.UNEQUIP
    local unequipIndex = 1
    local equipIndex = 1

    local function FinishSwap(ready)
        equipQueueRunning = false
        swapDeclinedUpgradeSlots = nil
        if onComplete then
            onComplete(ready ~= false)
        end
    end

    local function VerifyAndComplete()
        C_Timer.After(C.SAVE_RETRY_DELAY, function()
            local ready, remaining = Gear.ValidateGearDiff(gearSet, declinedUpgradeSlots)
            if ready then
                FinishSwap(true)
                return
            end

            if verifyAttempt < C.MAX_SWAP_VERIFY_RETRIES then
                equipQueueRunning = false
                RunGearSwap(gearSet, onComplete, declinedUpgradeSlots, verifyAttempt + 1)
                return
            end

            PrintGearDiffFailures(remaining)
            FinishSwap(false)
        end)
    end

    local function Step()
        if InCombatLockdown() then
            deferredGearSwap = gearSet
            equipQueueRunning = false
            Print("Combat started. Gear swap will continue when combat ends.")
            return
        end

        if phase == C.SWAP_PHASE.UNEQUIP then
            while unequipIndex <= #diff.unequip do
                local invSlot = diff.unequip[unequipIndex]
                unequipIndex = unequipIndex + 1

                if ShouldUnequipSlot(invSlot, gearSet, neededItems) then
                    if not UnequipToBag(invSlot, reservedBagSlots) then
                        Print("Could not unequip slot " .. tostring(invSlot) .. "; continuing.")
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

            if NeedsEquipForEntry(change.invSlot, change.entry, declinedUpgradeSlots) then
                if not EquipSlot(change.invSlot, change.entry, usedLocations) then
                    Print("Could not equip slot " .. tostring(change.invSlot) .. "; continuing.")
                end
                C_Timer.After(C.EQUIP_SLOT_DELAY, Step)
                return
            end
        end

        VerifyAndComplete()
    end

    Step()
end

local function ApplyGearSwap(gearSet, onComplete, declinedUpgradeSlots)
    if not gearSet or not next(gearSet) then
        return
    end

    if InCombatLockdown() then
        deferredGearSwap = gearSet
        Print("Cannot swap gear in combat. Queued until combat ends.")
        return
    end

    RunGearSwap(gearSet, onComplete, declinedUpgradeSlots)
end

function Gear.EquipGearSetAndSave(specID, configID, gearSet, onComplete)
    ApplyGearSwap(gearSet, function()
        ScheduleSaveEquippedGearSet(specID, configID, gearSet)
        if onComplete then
            onComplete()
        end
    end)
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

function Gear.Delete(specID, configID)
    local context = Loadout.GetActive(specID)
    if not context then
        Print("No specialization selected.")
        return false
    end

    if configID then
        context.configID = configID
    end

    local entry = DB:DeleteGearSet(context.specID, context.configID)
    if not entry then
        Print("No saved gear set for the current talent loadout.")
        return false
    end

    local loadoutName = entry.loadoutName or context.name
    Print(string.format("Removed saved gear for %s.", loadoutName))
    RefreshUI()
    return true
end

function Gear.List(specID)
    specID = specID or Loadout.GetSpecID()
    if not specID then
        Print("No specialization selected.")
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

    if options.requireOffers then
        local offers = LoadoutLocker.Upgrades.FindOffers(gearSet)
        if #offers == 0 then
            Print(options.noOffersMessage or "No better items found in your bags.")
            return
        end
        options.offers = offers
    end

    if diff.empty then
        local offers = options.offers or LoadoutLocker.Upgrades.FindOffers(gearSet)
        if #offers == 0 then
            Print(options.alreadyAppliedMessage or "Already wearing saved gear for this loadout.")
            return
        end
    end

    LoadoutLocker.Upgrades.PromptForBetterItems(gearSet, {
        specID = specID,
        configID = configID,
        offers = options.offers,
        onComplete = function(updatedGearSet, changed, declinedSlots)
            if options.requireChange and not changed then
                Print(options.noChangeMessage or "No upgrades selected.")
                return
            end

            local swapDiff = Gear.BuildGearDiff(updatedGearSet, declinedSlots)
            if swapDiff.empty then
                if changed then
                    ScheduleSaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
                elseif options.appliedMessage then
                    Print(options.appliedMessage)
                else
                    Print(options.alreadyAppliedMessage or "Already wearing saved gear for this loadout.")
                end
                return
            end

            ApplyGearSwap(updatedGearSet, function(ready)
                if not ready then
                    Print("Some gear slots could not be verified after swapping.")
                    return
                end

                if changed then
                    ScheduleSaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print(options.upgradedMessage or "Applied and saved upgraded gear set.")
                elseif options.appliedMessage then
                    Print(options.appliedMessage)
                end
            end, declinedSlots)
        end,
    })
end

function Gear.ApplyGearForLoadoutChange()
    if LoadoutLocker.Upgrades.IsPromptActive() then
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

function Gear.RecordCurrentLoadout()
    return Loadout.RecordCurrent()
end
