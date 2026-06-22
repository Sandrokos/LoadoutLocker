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
        for _, itemInfo in ipairs(Items.GetItemInfoCandidates(itemLink, itemID)) do
            local ok, socketCount = pcall(C_Item.GetItemNumSockets, itemInfo)
            if ok and type(socketCount) == "number" and socketCount >= 0 then
                return socketCount
            end
        end
    end

    return 4
end

local linkModsCache = {}
local scanTooltips = {}
local TOOLTIP_LINE_KEYS = { "TextLeft", "TextRight" }

function Items.GetItemInfoCandidates(itemLink, itemID)
    local candidates = {}

    if type(itemLink) == "string" and itemLink ~= "" then
        candidates[#candidates + 1] = itemLink

        local itemString = string.match(itemLink, "item[%-?%d:]+")
        if itemString and itemString ~= itemLink then
            candidates[#candidates + 1] = itemString
        end
    end

    if type(itemID) == "number" and itemID > 0 then
        candidates[#candidates + 1] = itemID
    end

    return candidates
end

function Items.ResolveItemLink(itemID, itemLink)
    if itemLink then
        return itemLink
    end

    if itemID then
        return select(2, C_Item.GetItemInfo(itemID))
    end
end

function Items.EnsureScanTooltip(frameName)
    frameName = frameName or "LoadoutLockerScanTooltip"
    if scanTooltips[frameName] then
        return scanTooltips[frameName]
    end

    local tooltip = CreateFrame("GameTooltip", frameName, UIParent, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltips[frameName] = tooltip
    return tooltip
end

function Items.ForEachHyperlinkTooltipLine(itemLink, frameName, callback)
    if not itemLink or not callback then
        return
    end

    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, info = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and info and info.lines then
            for _, line in ipairs(info.lines) do
                local result = callback(line.leftText, line.rightText, line.type)
                if result ~= nil then
                    return result
                end
            end
        end
    end

    local tooltip = Items.EnsureScanTooltip(frameName)
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for i = 1, tooltip:NumLines() do
        for _, lineKey in ipairs(TOOLTIP_LINE_KEYS) do
            local line = _G[frameName .. lineKey .. i]
            local text = line and line:GetText()
            if text then
                local result = callback(text)
                if result ~= nil then
                    return result
                end
            end
        end
    end
end

function Items.ScanHyperlinkText(itemLink, frameName, textCallback)
    return Items.ForEachHyperlinkTooltipLine(itemLink, frameName, function(leftText, rightText)
        for _, text in ipairs({ leftText, rightText }) do
            if text then
                local result = textCallback(text)
                if result ~= nil then
                    return result
                end
            end
        end
    end)
end

local function TooltipLineMentionsEmbellishment(text)
    return text and text ~= "" and text:find("Embellish", 1, true) ~= nil
end

local function ScanHyperlinkEmbellishment(itemLink)
    return Items.ForEachHyperlinkTooltipLine(itemLink, "LoadoutLockerItemsScanTooltip", function(leftText, rightText)
        if TooltipLineMentionsEmbellishment(leftText) or TooltipLineMentionsEmbellishment(rightText) then
            return true
        end
    end) or false
end

local embellishCache = {}

function Items.IsEmbellished(itemLink, itemID)
    itemLink = Items.ResolveItemLink(itemID, itemLink)
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

    if linkModsCache[itemLink] then
        return linkModsCache[itemLink]
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

    local mods = {
        itemID = itemID,
        enchantID = enchantID,
        gems = gems,
    }
    linkModsCache[itemLink] = mods
    return mods
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

function Items.ToComparisonProfile(location)
    return LoadoutLocker.Upgrades.BuildComparisonProfile(location)
end

function Items.CollectPlayerProfiles(gearSet)
    local savedItemIDs

    if gearSet then
        savedItemIDs = {}
        for _, entry in pairs(gearSet) do
            local itemID = type(entry) == "table" and entry.itemID or entry
            if itemID then
                savedItemIDs[itemID] = true
            end
        end
    end

    local profiles = {}

    Items.ForEachPlayerItem(function(location)
        if savedItemIDs then
            local matches = false
            for savedItemID in pairs(savedItemIDs) do
                if Items.MatchesFamily(savedItemID, location.itemID) then
                    matches = true
                    break
                end
            end
            if not matches then
                return
            end
        end

        profiles[#profiles + 1] = Items.ToComparisonProfile(location)
    end)

    return profiles
end
