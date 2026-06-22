LoadoutLocker = LoadoutLocker or {}

function LoadoutLocker.Print(msg)
    print("|cff00ccffLoadoutLocker:|r " .. msg)
end

function LoadoutLocker.RefreshUI()
    if LoadoutLocker.RefreshTalentUI then
        LoadoutLocker.RefreshTalentUI()
    end
end

local STARTER_BUILD_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID) or -2
local EQUIP_SLOT_DELAY = 0.15
local LOADOUT_APPLY_DELAY = 0.25
local SAVE_RETRY_DELAY = 0.15
local MAX_SAVE_RETRIES = 8

local EQUIP_SLOTS = {
    INVSLOT_HEAD,
    INVSLOT_NECK,
    INVSLOT_SHOULDER,
    INVSLOT_BODY,
    INVSLOT_CHEST,
    INVSLOT_WAIST,
    INVSLOT_LEGS,
    INVSLOT_FEET,
    INVSLOT_WRIST,
    INVSLOT_HAND,
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
    INVSLOT_BACK,
    INVSLOT_MAINHAND,
    INVSLOT_OFFHAND,
}

local BAGS = {
    Enum.BagIndex.Backpack,
    Enum.BagIndex.Bag_1,
    Enum.BagIndex.Bag_2,
    Enum.BagIndex.Bag_3,
    Enum.BagIndex.Bag_4,
}

LoadoutLocker.TALENT_UI_ADDON = "Blizzard_PlayerSpells"

local DB = LoadoutLocker.DB
local Print = LoadoutLocker.Print
local RefreshUI = LoadoutLocker.RefreshUI

local Talents = {}
LoadoutLocker.Talents = Talents

local Gear = {}
LoadoutLocker.Gear = Gear

local activeLoadoutBySpec = {}
local pendingLoadoutSwitch
local deferredGearSwap
local equipQueueRunning
local loadoutSelectionHooked
local loadoutApplyTimer

function Talents.GetSpecID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        return select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    end
end

function Talents.GetLoadoutConfigID(specID)
    specID = specID or Talents.GetSpecID()
    if specID then
        return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end
end

function Talents.GetLoadoutName(configID)
    if not configID then
        return nil
    end

    if configID == STARTER_BUILD_CONFIG_ID then
        return "Starter Build"
    end

    local configInfo = C_Traits.GetConfigInfo(configID)
    return configInfo and configInfo.name or ("Loadout " .. tostring(configID))
end

function Talents.IsStarterBuild(configID)
    return configID == STARTER_BUILD_CONFIG_ID
end

local function RememberActiveLoadout(specID, configID)
    if specID and configID then
        activeLoadoutBySpec[specID] = configID
    end
end

local function HookLoadoutSelection()
    if loadoutSelectionHooked or not C_ClassTalents or not C_ClassTalents.UpdateLastSelectedSavedConfigID then
        return
    end

    loadoutSelectionHooked = true

    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function(specID, configID)
        if not specID or not configID or Talents.IsStarterBuild(configID) then
            return
        end

        pendingLoadoutSwitch = { specID = specID, configID = configID }
    end)
end

local function ParseItemLinkModifiers(itemLink)
    if not itemLink then
        return nil
    end

    local itemString = string.match(itemLink, "item[%-?%d:]+")
    if not itemString then
        return nil
    end

    local parts = {}
    for part in string.gmatch(itemString .. ":", "([^:]*):") do
        parts[#parts + 1] = part
    end

    local function num(index)
        return tonumber(parts[index]) or 0
    end

    return {
        itemID = num(2),
        enchantID = num(3),
        gems = { num(4), num(5), num(6), num(7) },
    }
end

local function CopyGemsTable(gems)
    if not gems then
        return { 0, 0, 0, 0 }
    end

    return { gems[1] or 0, gems[2] or 0, gems[3] or 0, gems[4] or 0 }
end

local function GemsMatch(gemsA, gemsB)
    gemsA = gemsA or { 0, 0, 0, 0 }
    gemsB = gemsB or { 0, 0, 0, 0 }

    for i = 1, 4 do
        if (gemsA[i] or 0) ~= (gemsB[i] or 0) then
            return false
        end
    end

    return true
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
            gems = { 0, 0, 0, 0 },
        }
    end

    if entry.enchantID or entry.gems then
        return {
            itemID = entry.itemID,
            enchantID = entry.enchantID or 0,
            gems = CopyGemsTable(entry.gems),
        }
    end

    local mods = ParseItemLinkModifiers(entry.itemLink)
    if mods then
        return mods
    end

    return {
        itemID = entry.itemID,
        enchantID = 0,
        gems = { 0, 0, 0, 0 },
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

local function ItemLinksMatch(linkA, linkB)
    return linkA and linkB and linkA == linkB
end

local function GetLinkItemLevel(itemLink)
    if not itemLink then
        return 0
    end

    if C_Item.GetDetailedItemLevelInfo then
        local level = C_Item.GetDetailedItemLevelInfo(itemLink)
        if level and level > 0 then
            return level
        end
    end

    local _, _, _, level = C_Item.GetItemInfo(itemLink)
    return level or 0
end

local function GetSavedItemLevel(entry)
    if type(entry) ~= "table" then
        return 0
    end

    if entry.itemLevel and entry.itemLevel > 0 then
        return entry.itemLevel
    end

    return GetLinkItemLevel(entry.itemLink)
end

local function ItemLinkMatchesEntry(itemLink, entry)
    if not itemLink or not entry then
        return false
    end

    if type(entry) == "table" and ItemLinksMatch(itemLink, entry.itemLink) then
        return true
    end

    local linkMods = ParseItemLinkModifiers(itemLink)
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
    if itemLink then
        local entry = {
            itemID = itemID,
            itemLink = itemLink,
        }
        local mods = ParseItemLinkModifiers(itemLink)
        if mods then
            entry.enchantID = mods.enchantID
            entry.gems = CopyGemsTable(mods.gems)
        end
        entry.itemLevel = GetLinkItemLevel(itemLink)
        return entry
    end

    return itemID
end

function Gear.ParseItemLinkModifiers(itemLink)
    return ParseItemLinkModifiers(itemLink)
end

function Gear.CreateGearEntryFromLink(itemID, itemLink, bag, slot)
    local entry = CreateGearEntry(itemID, itemLink)
    if type(entry) == "table" then
        if bag and slot then
            entry.bag = bag
            entry.slot = slot
        end
    end
    return entry
end

local function SnapshotEquippedGear()
    local gear = {}

    for _, slot in ipairs(EQUIP_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            gear[slot] = CreateGearEntry(itemID, GetInventoryItemLink("player", slot))
        end
    end

    return gear
end

local function GetItemDisplayName(itemID)
    local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not itemName then
        itemName = GetItemInfo(itemID)
    end
    return itemName or ("item:" .. itemID)
end

local function FindEmptyBagSlot(reservedBagSlots)
    for _, bag in ipairs(BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local locationKey = "bag:" .. bag .. ":" .. slot
            if not reservedBagSlots[locationKey] and not C_Container.GetContainerItemID(bag, slot) then
                return bag, slot, locationKey
            end
        end
    end
end

local function NormalizeInvSlot(invSlot)
    return tonumber(invSlot) or invSlot
end

local function GetGearSetEntry(gearSet, invSlot)
    if not gearSet then
        return nil
    end

    invSlot = NormalizeInvSlot(invSlot)
    return gearSet[invSlot] or gearSet[tostring(invSlot)]
end

local function SetGearSetEntry(gearSet, invSlot, entry)
    invSlot = NormalizeInvSlot(invSlot)
    gearSet[invSlot] = entry
    gearSet[tostring(invSlot)] = nil
end

function Gear.NormalizeGearSetKeys(gearSet)
    if not gearSet then
        return gearSet
    end

    local merged = {}
    for slot, entry in pairs(gearSet) do
        local invSlot = NormalizeInvSlot(slot)
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
        return entry.itemID, entry.bag, entry.slot, entry.itemLink, entry.enchantID, CopyGemsTable(entry.gems)
    end

    return entry, nil, nil, nil, nil, nil
end

local swapDeclinedUpgradeSlots

local function IsUpgradeDeclinedForSlot(invSlot)
    if not swapDeclinedUpgradeSlots then
        return false
    end

    local normalizedSlot = tonumber(invSlot) or invSlot
    return swapDeclinedUpgradeSlots[normalizedSlot]
        or swapDeclinedUpgradeSlots[tostring(normalizedSlot)]
        or false
end

local function ShouldKeepEquippedUpgrade(invSlot, itemLink, gearEntry)
    if not itemLink or not gearEntry then
        return false
    end

    if IsUpgradeDeclinedForSlot(invSlot) then
        return false
    end

    return LoadoutLocker.Upgrades.IsLinkBetterThanSavedEntry(itemLink, gearEntry)
end

local function MergeGearSnapshot(snapshot, expectedGearSet)
    if not expectedGearSet then
        return snapshot
    end

    for invSlot, entry in pairs(expectedGearSet) do
        invSlot = NormalizeInvSlot(invSlot)
        local equippedID = GetInventoryItemID("player", invSlot)
        local equippedLink = GetInventoryItemLink("player", invSlot)

        if equippedID and entry and ItemLinkMatchesEntry(equippedLink, entry) then
            snapshot[invSlot] = CreateGearEntry(equippedID, equippedLink)
        elseif equippedLink and entry and ShouldKeepEquippedUpgrade(invSlot, equippedLink, entry) then
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

    for _, invSlot in ipairs(EQUIP_SLOTS) do
        local entry = GetGearSetEntry(expectedGearSet, invSlot)
        if entry then
            local equippedLink = GetInventoryItemLink("player", invSlot)
            if not ItemLinkMatchesEntry(equippedLink, entry)
                and not ShouldKeepEquippedUpgrade(invSlot, equippedLink, entry) then
                return false
            end
        end
    end

    return true
end

local function SaveEquippedGearSet(specID, configID, expectedGearSet)
    local snapshot = MergeGearSnapshot(SnapshotEquippedGear(), expectedGearSet)
    DB:CreateOrUpdateGearSet(specID, configID, snapshot, Talents.GetLoadoutName(configID))
    RefreshUI()
end

local function ScheduleSaveEquippedGearSet(specID, configID, expectedGearSet, attemptsLeft)
    attemptsLeft = attemptsLeft or MAX_SAVE_RETRIES

    C_Timer.After(SAVE_RETRY_DELAY, function()
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

    local gearEntry = GetGearSetEntry(gearSet, invSlot)
    local currentLink = GetInventoryItemLink("player", invSlot)

    if gearEntry and ShouldKeepEquippedUpgrade(invSlot, currentLink, gearEntry) then
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

    for _, bag in ipairs(BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local locationKey = "bag:" .. bag .. ":" .. slot
            if not usedLocations[locationKey] then
                local link = C_Container.GetContainerItemLink(bag, slot)
                if link then
                    if gearEntry and ItemLinkMatchesEntry(link, gearEntry) then
                        return "bag", bag, slot, locationKey
                    end
                    if itemLink and ItemLinksMatch(link, itemLink) then
                        return "bag", bag, slot, locationKey
                    end
                end
            end
        end
    end
end

local function FindItemInBagsByModifiers(entry, usedLocations)
    local modifiers = GetEntryModifiers(entry)
    if not modifiers.itemID then
        return
    end

    local savedLevel = GetSavedItemLevel(entry)
    local bestSource, bestBag, bestSlot, bestKey, bestDistance

    for _, bag in ipairs(BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local locationKey = "bag:" .. bag .. ":" .. slot
            if not usedLocations[locationKey] then
                local link = C_Container.GetContainerItemLink(bag, slot)
                if type(entry) == "table" and ItemLinksMatch(link, entry.itemLink) then
                    return "bag", bag, slot, locationKey
                end
                if ItemLinkMatchesEntry(link, entry) then
                    local distance = 0
                    if savedLevel > 0 then
                        local level = GetLinkItemLevel(link)
                        distance = level > 0 and math.abs(level - savedLevel) or math.huge
                    end
                    if not bestSource or distance < bestDistance then
                        bestSource = "bag"
                        bestBag = bag
                        bestSlot = slot
                        bestKey = locationKey
                        bestDistance = distance
                    end
                end
            end
        end
    end

    return bestSource, bestBag, bestSlot, bestKey
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

    for _, bag in ipairs(BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local locationKey = "bag:" .. bag .. ":" .. slot
            if not usedLocations[locationKey] and C_Container.GetContainerItemID(bag, slot) == itemID then
                return "bag", bag, slot, locationKey
            end
        end
    end
end

local function FindItemOnPlayer(itemID, itemLink, targetSlot, usedLocations, gearEntry)
    local sourceType, bag, slot, locationKey = FindItemInBags(itemID, itemLink, usedLocations, gearEntry)
    if sourceType then
        return sourceType, bag, slot, locationKey
    end

    for _, equippedSlot in ipairs(EQUIP_SLOTS) do
        if equippedSlot ~= targetSlot then
            local locationKey = "equipped:" .. equippedSlot
            if not usedLocations[locationKey] then
                local equippedLink = GetInventoryItemLink("player", equippedSlot)
                if gearEntry and ItemLinkMatchesEntry(equippedLink, gearEntry) then
                    return "equipped", equippedSlot, nil, locationKey
                end
                if itemLink and ItemLinksMatch(equippedLink, itemLink) then
                    return "equipped", equippedSlot, nil, locationKey
                end
                if not gearEntry or not EntryRequiresModifierMatch(gearEntry) then
                    if not itemLink and GetInventoryItemID("player", equippedSlot) == itemID then
                        return "equipped", equippedSlot, nil, locationKey
                    end
                end
            end
        end
    end
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

local function NeedsEquipForEntry(invSlot, gearEntry)
    local itemID = ResolveGearEntry(gearEntry)
    if not itemID then
        return false
    end

    local equippedLink = GetInventoryItemLink("player", invSlot)
    if ShouldKeepEquippedUpgrade(invSlot, equippedLink, gearEntry) then
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

    if ShouldKeepEquippedUpgrade(invSlot, equippedLink, gearEntry) then
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
        Print("Missing item: " .. GetItemDisplayName(itemID))
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

local function RunGearSwap(gearSet, onComplete, declinedUpgradeSlots)
    if equipQueueRunning then
        return
    end

    if not gearSet or not next(gearSet) then
        return
    end

    Gear.NormalizeGearSetKeys(gearSet)

    swapDeclinedUpgradeSlots = declinedUpgradeSlots

    equipQueueRunning = true
    local neededItems = BuildNeededItems(gearSet)
    local usedLocations = {}
    local reservedBagSlots = {}
    local phase = "unequip"
    local index = 1

    local function Step()
        if InCombatLockdown() then
            deferredGearSwap = gearSet
            equipQueueRunning = false
            Print("Combat started. Gear swap will continue when combat ends.")
            return
        end

        if phase == "unequip" then
            while index <= #EQUIP_SLOTS do
                local invSlot = EQUIP_SLOTS[index]
                index = index + 1

                if ShouldUnequipSlot(invSlot, gearSet, neededItems) then
                    if not UnequipToBag(invSlot, reservedBagSlots) then
                        Print("Could not unequip slot " .. tostring(invSlot) .. "; continuing.")
                    end
                    C_Timer.After(EQUIP_SLOT_DELAY, Step)
                    return
                end
            end

            phase = "equip"
            index = 1
            C_Timer.After(EQUIP_SLOT_DELAY, Step)
            return
        end

        while index <= #EQUIP_SLOTS do
            local invSlot = EQUIP_SLOTS[index]
            index = index + 1

            local gearEntry = GetGearSetEntry(gearSet, invSlot)
            if gearEntry and NeedsEquipForEntry(invSlot, gearEntry) then
                if not EquipSlot(invSlot, gearEntry, usedLocations) then
                    Print("Could not equip slot " .. tostring(invSlot) .. "; continuing.")
                end
                C_Timer.After(EQUIP_SLOT_DELAY, Step)
                return
            end
        end

        equipQueueRunning = false
        swapDeclinedUpgradeSlots = nil
        if onComplete then
            C_Timer.After(EQUIP_SLOT_DELAY, onComplete)
        end
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
    specID = specID or Talents.GetSpecID()
    if not specID then
        Print("No specialization selected.")
        return false
    end

    configID = configID or Talents.GetLoadoutConfigID(specID)
    if not configID then
        Print("No talent loadout selected.")
        return false
    end

    if Talents.IsStarterBuild(configID) then
        Print("Cannot save gear for the Starter Build.")
        return false
    end

    local loadoutName = Talents.GetLoadoutName(configID)
    DB:CreateOrUpdateGearSet(specID, configID, SnapshotEquippedGear(), loadoutName)
    Print(string.format("Saved gear for %s.", loadoutName))
    RefreshUI()
    return true
end

function Gear.Delete(specID, configID)
    specID = specID or Talents.GetSpecID()
    if not specID then
        Print("No specialization selected.")
        return false
    end

    configID = configID or Talents.GetLoadoutConfigID(specID)
    if not configID then
        Print("No active talent loadout found.")
        return false
    end

    local entry = DB:DeleteGearSet(specID, configID)
    if not entry then
        Print("No saved gear set for the current talent loadout.")
        return false
    end

    local loadoutName = entry.loadoutName or Talents.GetLoadoutName(configID)
    Print(string.format("Removed saved gear for %s.", loadoutName))
    RefreshUI()
    return true
end

function Gear.List(specID)
    specID = specID or Talents.GetSpecID()
    if not specID then
        Print("No specialization selected.")
        return
    end

    local specData = DB:GetSpecEntries(specID)
    if not specData or not next(specData) then
        Print("No saved gear sets for this specialization.")
        return
    end

    local currentConfigID = Talents.GetLoadoutConfigID(specID)
    Print("Saved gear sets for this spec:")

    for configID, entry in pairs(specData) do
        local marker = (configID == currentConfigID) and " (current)" or ""
        local name = entry.loadoutName or Talents.GetLoadoutName(configID)
        Print(string.format("- %s%s", name, marker))
    end
end

function Gear.ScheduleLoadoutGearApply()
    if loadoutApplyTimer then
        loadoutApplyTimer:Cancel()
    end

    loadoutApplyTimer = C_Timer.NewTimer(LOADOUT_APPLY_DELAY, function()
        loadoutApplyTimer = nil
        Gear.ApplyGearForLoadoutChange()
    end)
end

function Gear.ApplyGearForLoadoutChange()
    if LoadoutLocker.Upgrades.IsPromptActive() then
        return
    end

    if not pendingLoadoutSwitch then
        return
    end

    local specID = pendingLoadoutSwitch.specID
    local configID = pendingLoadoutSwitch.configID
    pendingLoadoutSwitch = nil

    local previousConfigID = activeLoadoutBySpec[specID]
    RememberActiveLoadout(specID, configID)

    if previousConfigID == nil or previousConfigID == configID then
        return
    end

    local storedGear = DB:GetGearSet(specID, configID)
    if not storedGear then
        return
    end

    local gearSet = DB:CopyGearSet(storedGear)

    local loadoutName = Talents.GetLoadoutName(configID)
    Print(string.format("Talent loadout changed to %s. Applying saved gear...", loadoutName))

    LoadoutLocker.Upgrades.PromptForBetterItems(gearSet, {
        specID = specID,
        configID = configID,
        onComplete = function(updatedGearSet, changed, declinedSlots)
            ApplyGearSwap(updatedGearSet, function()
                if changed then
                    ScheduleSaveEquippedGearSet(specID, configID, updatedGearSet)
                    Print("Applied and saved upgraded gear set.")
                else
                    Print("Applied saved gear set.")
                end
            end, declinedSlots)
        end,
    })
end

function Gear.ScanForUpgrades()
    local specID = Talents.GetSpecID()
    local configID = specID and Talents.GetLoadoutConfigID(specID)
    if not specID or not configID then
        Print("No talent loadout selected.")
        return
    end

    local storedGear = DB:GetGearSet(specID, configID)
    if not storedGear then
        Print("No saved gear set for the current talent loadout.")
        return
    end

    local gearSet = DB:CopyGearSet(storedGear)

    if #LoadoutLocker.Upgrades.FindOffers(gearSet) == 0 then
        Print("No better items found in your bags.")
        return
    end

    LoadoutLocker.Upgrades.PromptForBetterItems(gearSet, {
        specID = specID,
        configID = configID,
        onComplete = function(updatedGearSet, changed, declinedSlots)
            if not changed then
                Print("No upgrades selected.")
                return
            end

            ApplyGearSwap(updatedGearSet, function()
                ScheduleSaveEquippedGearSet(specID, configID, updatedGearSet)
                Print("Applied and saved upgraded gear set.")
            end, declinedSlots)
        end,
    })
end

function Gear.OnSpecChanged()
    local specID = Talents.GetSpecID()
    if not specID then
        return
    end

    C_Timer.After(0, function()
        RememberActiveLoadout(specID, Talents.GetLoadoutConfigID(specID))
    end)
end

function Gear.RecordCurrentLoadout()
    local specID = Talents.GetSpecID()
    local configID = specID and Talents.GetLoadoutConfigID(specID)
    if specID and configID then
        RememberActiveLoadout(specID, configID)
        return true
    end
end

HookLoadoutSelection()
