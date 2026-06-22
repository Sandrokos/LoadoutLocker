LoadoutLocker = LoadoutLocker or {}

local Items = {}
LoadoutLocker.Items = Items

local C = LoadoutLocker.Constants

function Items.GetGemsMaxIndex(gems)
    if not gems then
        return 0
    end

    local maxIndex = 0
    for index in pairs(gems) do
        if type(index) == "number" and index > maxIndex then
            maxIndex = index
        end
    end

    return maxIndex
end

function Items.CopyGemsTable(gems)
    local maxIndex = Items.GetGemsMaxIndex(gems)
    if maxIndex == 0 then
        return nil
    end

    local copy = {}
    for i = 1, maxIndex do
        copy[i] = gems[i] or 0
    end

    return copy
end

function Items.GemsMatch(gemsA, gemsB)
    local maxIndex = math.max(Items.GetGemsMaxIndex(gemsA), Items.GetGemsMaxIndex(gemsB))
    for i = 1, maxIndex do
        if (gemsA and gemsA[i] or 0) ~= (gemsB and gemsB[i] or 0) then
            return false
        end
    end

    return true
end

function Items.GetGemSlotCount(itemLink, itemID)
    if C_Item and C_Item.GetItemNumSockets then
        local candidates = {}
        if itemLink then
            candidates[#candidates + 1] = itemLink
        end
        if itemID then
            candidates[#candidates + 1] = itemID
        end

        for _, itemInfo in ipairs(candidates) do
            local ok, socketCount = pcall(C_Item.GetItemNumSockets, itemInfo)
            if ok and type(socketCount) == "number" and socketCount >= 0 then
                return socketCount
            end
        end
    end

    return 4
end

local embellishCache = {}
local scanTooltip

local EMBELLISH_TEXT_MARKERS = {
    "Embellish",
}

local function EnsureScanTooltip()
    if scanTooltip then
        return scanTooltip
    end

    scanTooltip = CreateFrame("GameTooltip", "LoadoutLockerItemsScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

local function TooltipLineMentionsEmbellishment(text)
    if not text or text == "" then
        return false
    end

    for _, marker in ipairs(EMBELLISH_TEXT_MARKERS) do
        if text:find(marker, 1, true) then
            return true
        end
    end

    return false
end

local function ScanHyperlinkEmbellishment(itemLink)
    if C_TooltipInfo and itemLink and C_TooltipInfo.GetHyperlink then
        local ok, info = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and info and info.lines then
            for _, line in ipairs(info.lines) do
                if TooltipLineMentionsEmbellishment(line.leftText)
                    or TooltipLineMentionsEmbellishment(line.rightText) then
                    return true
                end
            end
        end
    end

    local tooltip = EnsureScanTooltip()
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for i = 2, tooltip:NumLines() do
        local left = _G["LoadoutLockerItemsScanTooltipTextLeft" .. i]
        local right = _G["LoadoutLockerItemsScanTooltipTextRight" .. i]
        local leftText = left and left:GetText() or ""
        local rightText = right and right:GetText() or ""
        if TooltipLineMentionsEmbellishment(leftText) or TooltipLineMentionsEmbellishment(rightText) then
            return true
        end
    end

    return false
end

function Items.IsEmbellished(itemLink, itemID)
    if not itemLink and itemID then
        itemLink = select(2, C_Item.GetItemInfo(itemID))
    end

    if not itemLink then
        return false
    end

    if embellishCache[itemLink] ~= nil then
        return embellishCache[itemLink]
    end

    local isEmbellished = ScanHyperlinkEmbellishment(itemLink)
    embellishCache[itemLink] = isEmbellished
    return isEmbellished
end

function Items.FromEquippedSlot(invSlot)
    local itemID = GetInventoryItemID("player", invSlot)
    if not itemID then
        return nil
    end

    return {
        itemID = itemID,
        itemLink = GetInventoryItemLink("player", invSlot),
        invSlot = invSlot,
    }
end

function Items.FromBagSlot(bag, slot)
    local itemID = C_Container.GetContainerItemID(bag, slot)
    if not itemID then
        return nil
    end

    return {
        itemID = itemID,
        itemLink = C_Container.GetContainerItemLink(bag, slot),
        bag = bag,
        slot = slot,
    }
end

function Items.FromLink(itemID, itemLink)
    if not itemID then
        return nil
    end

    return {
        itemID = itemID,
        itemLink = itemLink,
    }
end

function Items.ForEachEquipped(callback)
    for _, invSlot in ipairs(C.EQUIP_SLOTS) do
        local location = Items.FromEquippedSlot(invSlot)
        if location then
            callback(location)
        end
    end
end

function Items.ForEachBagItem(callback)
    for _, bag in ipairs(C.BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local location = Items.FromBagSlot(bag, slot)
            if location then
                callback(location)
            end
        end
    end
end

function Items.ForEachPlayerItem(callback)
    Items.ForEachEquipped(callback)
    Items.ForEachBagItem(callback)
end

function Items.ForEachBagSlot(callback)
    for _, bag in ipairs(C.BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            callback(bag, slot)
        end
    end
end

function Items.GetLocationKey(location)
    if location and location.bag and location.slot then
        return "bag:" .. location.bag .. ":" .. location.slot
    end

    if location and location.invSlot then
        return "equipped:" .. location.invSlot
    end
end

function Items.GetDisplayName(itemID)
    local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not itemName then
        itemName = GetItemInfo(itemID)
    end
    return itemName or ("item:" .. tostring(itemID))
end

function Items.MatchesFamily(itemIDA, itemIDB)
    if not itemIDA or not itemIDB then
        return false
    end

    if itemIDA == itemIDB then
        return true
    end

    local nameA = Items.GetDisplayName(itemIDA)
    local nameB = Items.GetDisplayName(itemIDB)
    return nameA and nameB and nameA == nameB
end

function Items.ParseItemLinkModifiers(itemLink)
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

    local itemID = num(2)
    local enchantID = num(3)
    local gemCount = Items.GetGemSlotCount(itemLink, itemID)
    local gems = {}

    for i = 1, gemCount do
        gems[i] = num(3 + i)
    end

    return {
        itemID = itemID,
        enchantID = enchantID,
        gems = gems,
    }
end

function Items.GetItemLevel(itemLink, itemLocation)
    if itemLocation and C_Item.GetCurrentItemLevel then
        local level = C_Item.GetCurrentItemLevel(itemLocation)
        if level and level > 0 then
            return level
        end
    end

    if itemLink and C_Item.GetDetailedItemLevelInfo then
        local level = C_Item.GetDetailedItemLevelInfo(itemLink)
        if level and level > 0 then
            return level
        end
    end

    if itemLink then
        return select(4, C_Item.GetItemInfo(itemLink)) or 0
    end

    return 0
end

function Items.GetSavedItemLevel(entry)
    if type(entry) ~= "table" then
        return 0
    end

    if entry.itemLevel and entry.itemLevel > 0 then
        return entry.itemLevel
    end

    if entry.itemLink then
        return Items.GetItemLevel(entry.itemLink)
    end

    return 0
end

function Items.ToGearEntry(location)
    if not location or not location.itemID then
        return nil
    end

    local itemLink = location.itemLink
    if itemLink then
        local entry = {
            itemID = location.itemID,
            itemLink = itemLink,
        }
        local mods = Items.ParseItemLinkModifiers(itemLink)
        if mods then
            entry.enchantID = mods.enchantID
            entry.gems = Items.CopyGemsTable(mods.gems)
        end
        entry.itemLevel = Items.GetItemLevel(itemLink)
        if location.bag and location.slot then
            entry.bag = location.bag
            entry.slot = location.slot
        end
        return entry
    end

    return location.itemID
end

function Items.ToGearEntryFromLink(itemID, itemLink, bag, slot)
    return Items.ToGearEntry({
        itemID = itemID,
        itemLink = itemLink,
        bag = bag,
        slot = slot,
    })
end

function Items.ToComparisonProfile(location)
    return LoadoutLocker.Upgrades.BuildComparisonProfile(location)
end

function Items.CollectPlayerProfiles()
    local profiles = {}

    Items.ForEachPlayerItem(function(location)
        profiles[#profiles + 1] = Items.ToComparisonProfile(location)
    end)

    return profiles
end

function Items.CollectPlayerLocations()
    local locations = {}

    Items.ForEachPlayerItem(function(location)
        locations[#locations + 1] = location
    end)

    return locations
end
