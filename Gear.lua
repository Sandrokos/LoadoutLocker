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
    INVSLOT_TABARD,
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

local function NormalizeGearSet(gearSet)
    if not gearSet then
        return nil
    end

    local normalized = {}
    for slot, data in pairs(gearSet) do
        local invSlot = tonumber(slot)
        local itemID = type(data) == "table" and data.itemID or tonumber(data)
        if invSlot and itemID then
            normalized[invSlot] = itemID
        end
    end

    return normalized
end

local function SnapshotEquippedGear()
    local gear = {}

    for _, slot in ipairs(EQUIP_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            gear[slot] = itemID
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

local function BuildNeededItems(gearSet)
    local neededItems = {}
    for _, itemID in pairs(gearSet) do
        neededItems[itemID] = true
    end
    return neededItems
end

local function ShouldUnequipSlot(invSlot, gearSet, neededItems)
    local currentItem = GetInventoryItemID("player", invSlot)
    if not currentItem then
        return false
    end

    local targetItem = gearSet[invSlot]
    if targetItem and currentItem == targetItem then
        return false
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

local function FindItemInBags(itemID, usedLocations)
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

local function FindItemOnPlayer(itemID, targetSlot, usedLocations)
    local sourceType, bag, slot, locationKey = FindItemInBags(itemID, usedLocations)
    if sourceType then
        return sourceType, bag, slot, locationKey
    end

    for _, equippedSlot in ipairs(EQUIP_SLOTS) do
        if equippedSlot ~= targetSlot then
            local locationKey = "equipped:" .. equippedSlot
            if not usedLocations[locationKey] and GetInventoryItemID("player", equippedSlot) == itemID then
                return "equipped", equippedSlot, nil, locationKey
            end
        end
    end
end

local function EquipSlot(invSlot, itemID, usedLocations)
    if not itemID then
        return true
    end

    if GetInventoryItemID("player", invSlot) == itemID then
        return true
    end

    local sourceType, arg1, arg2, locationKey = FindItemOnPlayer(itemID, invSlot, usedLocations)
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

local function RunGearSwap(gearSet, onComplete)
    if equipQueueRunning then
        return
    end

    gearSet = NormalizeGearSet(gearSet)
    if not gearSet or not next(gearSet) then
        return
    end

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
                        equipQueueRunning = false
                        return
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

            local itemID = gearSet[invSlot]
            if itemID and GetInventoryItemID("player", invSlot) ~= itemID then
                EquipSlot(invSlot, itemID, usedLocations)
                C_Timer.After(EQUIP_SLOT_DELAY, Step)
                return
            end
        end

        equipQueueRunning = false
        if onComplete then
            onComplete()
        end
    end

    Step()
end

local function ApplyGearSwap(gearSet, onComplete)
    gearSet = NormalizeGearSet(gearSet)
    if not gearSet or not next(gearSet) then
        return
    end

    if InCombatLockdown() then
        deferredGearSwap = gearSet
        Print("Cannot swap gear in combat. Queued until combat ends.")
        return
    end

    RunGearSwap(gearSet, onComplete)
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
    DB:SetGearSet(specID, configID, SnapshotEquippedGear(), loadoutName)
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

    local gearSet = NormalizeGearSet(DB:GetGearSet(specID, configID))
    if not gearSet then
        return
    end

    local loadoutName = Talents.GetLoadoutName(configID)
    Print(string.format("Talent loadout changed to %s. Applying saved gear...", loadoutName))
    ApplyGearSwap(gearSet, function()
        Print("Applied saved gear set.")
    end)
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

function Gear.OnRegenEnabled()
    if not deferredGearSwap or InCombatLockdown() then
        return
    end

    local gearSet = deferredGearSwap
    deferredGearSwap = nil
    ApplyGearSwap(gearSet, function()
        Print("Applied saved gear set.")
    end)
end

HookLoadoutSelection()
