LoadoutLocker = LoadoutLocker or {}

local Upgrades = {}
LoadoutLocker.Upgrades = Upgrades

local TERTIARY_PRIORITY = { "sockets", "avoidance", "leech", "speed" }

local TERTIARY_LABELS = {
    sockets = "socket",
    avoidance = "Avoidance",
    leech = "Leech",
    speed = "Speed",
}

local TERTIARY_STAT_KEYS = {
    avoidance = {
        "ITEM_MOD_CR_AVOIDANCE_SHORT",
        "ITEM_MOD_CR_AVOIDANCE",
    },
    leech = {
        "ITEM_MOD_CR_LEECH_SHORT",
        "ITEM_MOD_CR_LIFESTEAL",
        "ITEM_MOD_CR_LEECH",
    },
    speed = {
        "ITEM_MOD_CR_SPEED_SHORT",
        "ITEM_MOD_CR_SPEED",
    },
}

local TERTIARY_TOOLTIP_MARKERS = {
    avoidance = "Avoidance",
    leech = "Leech",
    speed = "Speed",
}

local TRACK_RANK = {
    { "ascendant voidforged", 10, "Ascendant Voidforged" },
    { "sporefused", 10, "Sporefused" },
    { "sporeinfused", 10, "Sporeinfused" },
    { "mythic", 5 },
    { "myth", 5 },
    { "heroic", 4 },
    { "hero", 4 },
    { "champion", 3 },
    { "veteran", 2 },
    { "adventurer", 1 },
}

local TRACK_SCAN_MARKERS = {
    { "ascendant voidforged", "Ascendant Voidforged" },
    { "sporefused", "Sporefused" },
    { "sporeinfused", "Sporeinfused" },
}

local scanTooltip

local BAGS = {
    Enum.BagIndex.Backpack,
    Enum.BagIndex.Bag_1,
    Enum.BagIndex.Bag_2,
    Enum.BagIndex.Bag_3,
    Enum.BagIndex.Bag_4,
}

local SEARCH_SLOTS = {
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

local offerState = {
    callback = nil,
    gearSet = nil,
    changed = false,
    saveTarget = nil,
    declinedSlots = nil,
    offerQueue = nil,
    offerIndex = 1,
}
local currentOffer
local upgradeFrame
local ShowNextOffer
local AcceptCurrentOffer
local RespondToOffer

local function NormalizeInvSlot(invSlot)
    return tonumber(invSlot) or invSlot
end

local function IterGearSetSlots(gearSet)
    local slots = {}
    local seen = {}

    for invSlot in pairs(gearSet) do
        local normalized = NormalizeInvSlot(invSlot)
        if type(normalized) == "number" and not seen[normalized] then
            seen[normalized] = true
            slots[#slots + 1] = normalized
        end
    end

    table.sort(slots)
    return slots
end

local function GetGearEntry(gearSet, invSlot)
    return gearSet[invSlot] or gearSet[tostring(invSlot)]
end

local function GetInstanceLocationKey(profile)
    if profile and profile.bag and profile.slot then
        return "bag:" .. profile.bag .. ":" .. profile.slot
    end

    if profile and profile.invSlot then
        return "equipped:" .. profile.invSlot
    end
end

local function IsReservedInstance(profile, reservedInstances)
    local key = GetInstanceLocationKey(profile)
    return key and reservedInstances[key]
end

AcceptCurrentOffer = function()
    if not currentOffer or not offerState.gearSet then
        return
    end

    local candidate = currentOffer.candidate
    LoadoutLocker.Gear.SetGearSetEntry(
        offerState.gearSet,
        currentOffer.invSlot,
        LoadoutLocker.Gear.CreateGearEntryFromLink(
            candidate.itemID,
            candidate.itemLink,
            candidate.bag,
            candidate.slot
        )
    )

    offerState.changed = true
end

RespondToOffer = function(accepted)
    if not currentOffer then
        return
    end

    if accepted then
        AcceptCurrentOffer()
    else
        offerState.declinedSlots[NormalizeInvSlot(currentOffer.invSlot)] = true
    end

    currentOffer = nil

    if upgradeFrame then
        upgradeFrame:Hide()
    end

    offerState.offerIndex = offerState.offerIndex + 1
    C_Timer.After(0.05, ShowNextOffer)
end

local function GetItemName(itemID)
    return C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or GetItemInfo(itemID)
end

local function ItemsShareName(itemIDA, itemIDB)
    if not itemIDA or not itemIDB then
        return false
    end

    if itemIDA == itemIDB then
        return true
    end

    local nameA = GetItemName(itemIDA)
    local nameB = GetItemName(itemIDB)
    return nameA and nameB and nameA == nameB
end

local function MatchTrackEntry(trackString)
    if not trackString or trackString == "" then
        return nil
    end

    local lower = string.lower(trackString)
    for _, entry in ipairs(TRACK_RANK) do
        if string.find(lower, entry[1], 1, true) then
            return entry
        end
    end
end

local function GetExplicitTierEntry(trackString)
    if not trackString or trackString == "" then
        return nil
    end

    local lower = string.lower(trackString)
    for _, entry in ipairs(TRACK_RANK) do
        if entry[2] < 10 and string.find(lower, entry[1], 1, true) then
            return entry
        end
    end
end

local function GetExplicitTierRank(trackString)
    local entry = GetExplicitTierEntry(trackString)
    return entry and entry[2] or nil
end

local function GetTrackRank(trackString)
    local entry = MatchTrackEntry(trackString)
    return entry and entry[2] or 0
end

local function GetTrackLabel(trackString)
    if not trackString or trackString == "" then
        return "Unknown"
    end

    local familyEntry = MatchTrackEntry(trackString)
    if familyEntry and familyEntry[2] >= 10 then
        local tierEntry = GetExplicitTierEntry(trackString)
        if tierEntry then
            return (familyEntry[3] or familyEntry[1]) .. ": " .. (tierEntry[3] or tierEntry[1])
        end
        return familyEntry[3] or familyEntry[1]
    end

    if familyEntry and familyEntry[3] then
        return familyEntry[3]
    end

    return trackString
end

-- Sporefused and Ascendant Voidforged use fixed ilvls per tier; prefer explicit tier labels.
local function GetComparableTrackRank(profile)
    local namedRank = GetTrackRank(profile.trackString)
    if namedRank < 10 then
        return namedRank
    end

    local explicitTier = GetExplicitTierRank(profile.trackString)
    if explicitTier then
        return explicitTier
    end

    local itemLevel = profile.itemLevel or 0
    if itemLevel >= 295 then
        return 6
    end
    if itemLevel >= 289 then
        return 5
    end
    if itemLevel >= 285 then
        return 4
    end
    if itemLevel >= 272 then
        return 3
    end
    if itemLevel >= 259 then
        return 2
    end

    return 1
end

local function TracksAreSameFamily(trackA, trackB)
    if not trackA or not trackB then
        return false
    end

    return GetTrackRank(trackA) >= 10 and GetTrackRank(trackB) >= 10
        and GetTrackLabel(trackA) == GetTrackLabel(trackB)
end

local function GetItemIcon(itemID, itemLink)
    if itemLink and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return select(5, C_Item.GetItemInfo(itemID))
end

local function FormatSocketLine(socketCount)
    if socketCount <= 0 then
        return nil
    end
    if socketCount == 1 then
        return "1 socket"
    end
    return socketCount .. " sockets"
end

local function FormatProfileDetails(profile)
    local parts = {
        string.format("%s | ilvl %d", GetTrackLabel(profile.trackString), profile.itemLevel),
    }

    local socketLine = FormatSocketLine(profile.sockets)
    if socketLine then
        parts[#parts + 1] = socketLine
    end

    for _, field in ipairs(TERTIARY_PRIORITY) do
        if field ~= "sockets" and profile[field] > 0 then
            parts[#parts + 1] = TERTIARY_LABELS[field]
        end
    end

    if #parts == 1 then
        parts[#parts + 1] = "No bonus stats"
    end

    return table.concat(parts, ", ")
end

local function AttachItemTooltip(widget, itemLink)
    if not itemLink then
        widget:SetScript("OnEnter", nil)
        widget:SetScript("OnLeave", nil)
        return
    end

    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CreateItemPanel(parent, name, xOffset)
    local panel = CreateFrame("Frame", parent:GetName() .. name, parent)
    panel:SetSize(185, 1)

    panel.header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.header:SetPoint("TOP", panel, "TOP", 0, 0)

    panel.icon = CreateFrame("Button", nil, panel)
    panel.icon:SetSize(40, 40)
    panel.icon:SetPoint("TOP", panel.header, "BOTTOM", 0, -8)
    panel.icon:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    panel.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.name:SetPoint("TOP", panel.icon, "BOTTOM", 0, -6)
    panel.name:SetWidth(175)
    panel.name:SetWordWrap(true)
    panel.name:SetJustifyH("CENTER")
    panel.name:SetNonSpaceWrap(false)

    panel.details = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.details:SetPoint("TOP", panel.name, "BOTTOM", 0, -6)
    panel.details:SetWidth(175)
    panel.details:SetWordWrap(true)
    panel.details:SetJustifyH("CENTER")
    panel.details:SetNonSpaceWrap(false)

    return panel
end

local function MeasureItemPanel(panel)
    local headerHeight = panel.header:GetStringHeight() or 12
    local nameHeight = panel.name:GetStringHeight() or 14
    local detailsHeight = panel.details:GetStringHeight() or 14
    return headerHeight + 8 + 40 + 6 + nameHeight + 6 + detailsHeight
end

local function LayoutUpgradeFrame(frame)
    local reasonHeight = frame.reason:GetStringHeight() or 14
    local panelTop = -36 - reasonHeight - 14

    frame.currentPanel:ClearAllPoints()
    frame.currentPanel:SetPoint("TOP", frame, "TOP", -108, panelTop)
    frame.upgradePanel:ClearAllPoints()
    frame.upgradePanel:SetPoint("TOP", frame, "TOP", 108, panelTop)

    local panelHeight = math.max(
        MeasureItemPanel(frame.currentPanel),
        MeasureItemPanel(frame.upgradePanel)
    )

    local arrowOffset = panelTop - (panelHeight / 2) + 12
    frame.arrow:ClearAllPoints()
    frame.arrow:SetPoint("TOP", frame, "TOP", 0, arrowOffset)

    local frameHeight = math.abs(panelTop) + panelHeight + 58
    frame:SetHeight(math.max(320, math.min(frameHeight, 520)))
end

local function SetItemPanel(panel, headerText, profile)
    panel.header:SetText(headerText)

    local itemName = GetItemName(profile.itemID) or "Unknown Item"
    panel.name:SetText(itemName)

    local icon = GetItemIcon(profile.itemID, profile.itemLink)
    if icon then
        panel.icon:GetNormalTexture():SetTexture(icon)
    end

    panel.details:SetText(FormatProfileDetails(profile))
    AttachItemTooltip(panel.icon, profile.itemLink)
end

local function CreateUpgradeFrame()
    if upgradeFrame then
        return upgradeFrame
    end

    local frame = CreateFrame("Frame", "LoadoutLockerUpgradeFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -18)
    frame.title:SetText("LoadoutLocker Upgrade")

    frame.reason = frame:CreateFontString(nil, "ARTWORK", "GameFontGreenSmall")
    frame.reason:SetPoint("TOP", frame, "TOP", 0, -36)
    frame.reason:SetWidth(430)
    frame.reason:SetWordWrap(true)
    frame.reason:SetJustifyH("CENTER")
    frame.reason:SetSpacing(2)

    frame.currentPanel = CreateItemPanel(frame, "Current", -108)
    frame.upgradePanel = CreateItemPanel(frame, "Upgrade", 108)

    frame.arrow = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    frame.arrow:SetText("=>")

    frame.acceptButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.acceptButton:SetSize(120, 22)
    frame.acceptButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 16)
    frame.acceptButton:SetText("Use Upgrade")
    frame.acceptButton:SetScript("OnClick", function(self)
        if not currentOffer then
            return
        end
        self:Disable()
        frame.declineButton:Disable()
        RespondToOffer(true)
    end)

    frame.declineButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.declineButton:SetSize(120, 22)
    frame.declineButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 16)
    frame.declineButton:SetText("Keep Saved")
    frame.declineButton:SetScript("OnClick", function(self)
        if not currentOffer then
            return
        end
        self:Disable()
        frame.acceptButton:Disable()
        RespondToOffer(false)
    end)

    tinsert(UISpecialFrames, frame:GetName())
    upgradeFrame = frame
    return frame
end

local function ShowUpgradeFrame(offer)
    local frame = CreateUpgradeFrame()

    frame.acceptButton:Enable()
    frame.declineButton:Enable()
    frame.title:SetText(GetItemName(offer.candidate.itemID) or "Upgrade Found")
    frame.reason:SetText(offer.reason)
    SetItemPanel(frame.currentPanel, "Saved Item", offer.reference)
    SetItemPanel(frame.upgradePanel, "Upgrade", offer.candidate)
    LayoutUpgradeFrame(frame)

    frame:Show()
end

local function GetItemLevel(itemLink, itemLocation)
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

local function GetSavedItemLevel(gearEntry)
    if type(gearEntry) ~= "table" then
        return 0
    end

    if gearEntry.itemLevel and gearEntry.itemLevel > 0 then
        return gearEntry.itemLevel
    end

    if gearEntry.itemLink then
        return GetItemLevel(gearEntry.itemLink)
    end

    return 0
end

local function GetItemInfoCandidates(itemLink, itemID)
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

local function EnsureScanTooltip()
    if scanTooltip then
        return scanTooltip
    end

    scanTooltip = CreateFrame("GameTooltip", "LoadoutLockerUpgradeScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

local function MatchSpecialTrackFromText(text)
    if not text then
        return nil
    end

    local lower = string.lower(text)
    for _, marker in ipairs(TRACK_SCAN_MARKERS) do
        if string.find(lower, marker[1], 1, true) then
            return marker[2]
        end
    end
end

local function MatchStandardTrackFromText(text)
    if not text then
        return nil
    end

    local lower = string.lower(text)
    for _, entry in ipairs(TRACK_RANK) do
        if entry[2] < 10 and string.find(lower, entry[1], 1, true) then
            return entry[3] or entry[1]
        end
    end
end

local function ScanTooltipForUpgradeTrack(itemLink)
    if not itemLink then
        return nil
    end

    local tooltip = EnsureScanTooltip()
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for i = 1, tooltip:NumLines() do
        for _, lineKey in ipairs({ "TextLeft", "TextRight" }) do
            local line = _G["LoadoutLockerUpgradeScanTooltip" .. lineKey .. i]
            if line then
                local text = line:GetText()
                if text then
                    for _, marker in ipairs(TRACK_SCAN_MARKERS) do
                        local familyLabel = marker[2]
                        local tier = string.match(text, familyLabel .. "%s*:%s*(%S+)")
                        if tier then
                            return familyLabel .. ": " .. tier
                        end
                    end

                    local standardTrack = MatchStandardTrackFromText(text)
                    if standardTrack then
                        return standardTrack
                    end
                end
            end
        end
    end

    for i = 1, tooltip:NumLines() do
        for _, lineKey in ipairs({ "TextLeft", "TextRight" }) do
            local line = _G["LoadoutLockerUpgradeScanTooltip" .. lineKey .. i]
            if line then
                local track = MatchSpecialTrackFromText(line:GetText())
                if track then
                    return track
                end
            end
        end
    end
end

local function GetUpgradeTrackFromInfo(info)
    if not info then
        return nil
    end

    if info.trackString and info.trackString ~= "" then
        return info.trackString
    end

    return nil
end

local function GetUpgradeTrack(itemLink, itemID, itemLocation)
    local upgradeInfo
    local linkCandidates = {}

    if type(itemLink) == "string" and itemLink ~= "" then
        linkCandidates[#linkCandidates + 1] = itemLink

        local itemString = string.match(itemLink, "item[%-?%d:]+")
        if itemString and itemString ~= itemLink then
            linkCandidates[#linkCandidates + 1] = itemString
        end
    end

    if itemLocation and C_Item.GetItemUpgradeInfo then
        local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemLocation)
        if ok and info then
            upgradeInfo = info
            local track = GetUpgradeTrackFromInfo(info)
            if track then
                return track
            end
        end
    end

    if C_Item.GetItemUpgradeInfo then
        for _, itemInfo in ipairs(linkCandidates) do
            local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemInfo)
            if ok and info then
                upgradeInfo = info
                local track = GetUpgradeTrackFromInfo(info)
                if track then
                    return track
                end
                break
            end
        end

        if #linkCandidates == 0 and type(itemID) == "number" and itemID > 0 then
            local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemID)
            if ok and info then
                upgradeInfo = info
                local track = GetUpgradeTrackFromInfo(info)
                if track then
                    return track
                end
            end
        end
    end

    local tooltipTrack = ScanTooltipForUpgradeTrack(itemLink)
    if tooltipTrack then
        return tooltipTrack
    end

    if C_Item.GetItemCreationContext then
        for _, itemInfo in ipairs(linkCandidates) do
            local ok, _, creationContext = pcall(C_Item.GetItemCreationContext, itemInfo)
            if ok and creationContext and creationContext ~= "" then
                local entry = MatchTrackEntry(creationContext)
                if entry then
                    return creationContext
                end
            end
        end
    end

    if upgradeInfo and upgradeInfo.trackString and upgradeInfo.trackString ~= "" then
        return upgradeInfo.trackString
    end
end

local function ApplySavedEntryStats(profile, gearEntry)
    if not profile or type(gearEntry) ~= "table" then
        return profile
    end

    local savedLevel = GetSavedItemLevel(gearEntry)
    if savedLevel > 0 then
        profile.itemLevel = savedLevel
    end

    if gearEntry.itemLink then
        local savedTrack = GetUpgradeTrack(gearEntry.itemLink, gearEntry.itemID)
        if savedTrack and savedTrack ~= "" then
            profile.trackString = savedTrack
        end
    end

    return profile
end

local function CountSockets(itemLink, itemID)
    if not C_Item.GetItemNumSockets then
        return 0
    end

    for _, itemInfo in ipairs(GetItemInfoCandidates(itemLink, itemID)) do
        local ok, socketCount = pcall(C_Item.GetItemNumSockets, itemInfo)
        if ok and type(socketCount) == "number" then
            return socketCount
        end
    end

    return 0
end

local function GetStatValue(stats, keys)
    for _, key in ipairs(keys) do
        local value = stats[key]
        if value and value > 0 then
            return value
        end
    end

    return 0
end

local function GetItemStatsTable(itemLink, itemID)
    if not C_Item or not C_Item.GetItemStats then
        return nil
    end

    for _, itemInfo in ipairs(GetItemInfoCandidates(itemLink, itemID)) do
        local ok, stats = pcall(C_Item.GetItemStats, itemInfo)
        if ok and stats and next(stats) then
            return stats
        end
    end
end

local function ScanTooltipForTertiaries(itemLink)
    local stats = {
        avoidance = 0,
        leech = 0,
        speed = 0,
    }

    if not itemLink then
        return stats
    end

    local tooltip = EnsureScanTooltip()
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for i = 1, tooltip:NumLines() do
        for _, lineKey in ipairs({ "TextLeft", "TextRight" }) do
            local line = _G["LoadoutLockerUpgradeScanTooltip" .. lineKey .. i]
            if line then
                local text = line:GetText()
                if text then
                    for field, marker in pairs(TERTIARY_TOOLTIP_MARKERS) do
                        if string.find(text, marker, 1, true) then
                            stats[field] = 1
                        end
                    end
                end
            end
        end
    end

    return stats
end

local function GetTertiaryStats(itemLink, itemID, itemLocation)
    local stats = {
        avoidance = 0,
        leech = 0,
        speed = 0,
    }

    if itemLocation and C_Item.GetItemLink then
        local locationLink = C_Item.GetItemLink(itemLocation)
        if locationLink then
            itemLink = locationLink
        end
    end

    if not itemLink and itemID then
        itemLink = select(2, C_Item.GetItemInfo(itemID))
    end

    if not itemLink then
        return stats
    end

    local itemStats = GetItemStatsTable(itemLink, itemID)
    if itemStats then
        for field, keys in pairs(TERTIARY_STAT_KEYS) do
            stats[field] = GetStatValue(itemStats, keys)
        end
    end

    if stats.avoidance == 0 and stats.leech == 0 and stats.speed == 0 then
        local tooltipStats = ScanTooltipForTertiaries(itemLink)
        for field, value in pairs(tooltipStats) do
            if value > stats[field] then
                stats[field] = value
            end
        end
    end

    return stats
end

local function BuildItemProfile(itemID, itemLink, bag, slot, invSlot)
    local itemLocation
    if bag and slot and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if itemLocation and not itemLocation:IsValid() then
            itemLocation = nil
        end
    elseif invSlot and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        itemLocation = ItemLocation:CreateFromEquipmentSlot(invSlot)
        if itemLocation and not itemLocation:IsValid() then
            itemLocation = nil
        end
    end

    if not itemLink and itemLocation and C_Item.GetItemLink then
        itemLink = C_Item.GetItemLink(itemLocation)
    end

    if not itemLink and itemID then
        itemLink = select(2, C_Item.GetItemInfo(itemID))
    end

    local tertiary = GetTertiaryStats(itemLink, itemID, itemLocation)
    local trackString = GetUpgradeTrack(itemLink, itemID, itemLocation)

    return {
        itemID = itemID,
        itemLink = itemLink,
        bag = bag,
        slot = slot,
        invSlot = invSlot,
        itemLevel = GetItemLevel(itemLink, itemLocation),
        trackString = trackString,
        sockets = CountSockets(itemLink, itemID),
        avoidance = tertiary.avoidance,
        leech = tertiary.leech,
        speed = tertiary.speed,
    }
end

local function FormatItemBonuses(profile)
    local parts = {}

    if profile.sockets > 0 then
        if profile.sockets > 1 then
            parts[#parts + 1] = profile.sockets .. " sockets"
        else
            parts[#parts + 1] = "socket"
        end
    end

    for _, field in ipairs(TERTIARY_PRIORITY) do
        if field ~= "sockets" and profile[field] > 0 then
            parts[#parts + 1] = TERTIARY_LABELS[field]
        end
    end

    if #parts == 0 then
        return "no bonus"
    end

    return table.concat(parts, ", ")
end

-- Items can have a socket and a tertiary at the same time; compare the full profile.
local function IsBetterBonusProfile(candidate, reference)
    for _, field in ipairs(TERTIARY_PRIORITY) do
        local candidateValue = candidate[field]
        local referenceValue = reference[field]
        if candidateValue ~= referenceValue then
            return candidateValue > referenceValue
        end
    end

    return false
end

local function IsBetterTertiary(candidate, reference)
    return IsBetterBonusProfile(candidate, reference)
end

local function IsSameItemInstance(candidate, reference)
    if not candidate or not reference then
        return false
    end

    if candidate.itemLink and reference.itemLink and candidate.itemLink == reference.itemLink then
        return true
    end

    if candidate.bag and candidate.slot and reference.bag and reference.slot then
        return candidate.bag == reference.bag and candidate.slot == reference.slot
    end

    return false
end

local function IsBetterItem(candidate, reference)
    if not candidate or not reference or IsSameItemInstance(candidate, reference) then
        return false
    end

    local candidateTrack = GetComparableTrackRank(candidate)
    local referenceTrack = GetComparableTrackRank(reference)
    if candidateTrack ~= referenceTrack then
        return candidateTrack > referenceTrack
    end

    if candidate.itemLevel ~= reference.itemLevel then
        return candidate.itemLevel > reference.itemLevel
    end

    if TracksAreSameFamily(candidate.trackString, reference.trackString) then
        local candidateTier = GetExplicitTierRank(candidate.trackString)
        local referenceTier = GetExplicitTierRank(reference.trackString)
        if candidateTier and referenceTier and candidateTier ~= referenceTier then
            return candidateTier > referenceTier
        end
        return false
    end

    local candidateNamedRank = GetTrackRank(candidate.trackString)
    local referenceNamedRank = GetTrackRank(reference.trackString)
    if candidateNamedRank ~= referenceNamedRank then
        return candidateNamedRank > referenceNamedRank
    end

    return IsBetterTertiary(candidate, reference)
end

local function GetSavedItemID(gearEntry)
    if type(gearEntry) == "table" then
        return gearEntry.itemID
    end

    return gearEntry
end

local function GetSavedItemLink(gearEntry)
    if type(gearEntry) == "table" then
        return gearEntry.itemLink
    end
end

local function ProfileMatchesSavedEntry(itemLink, gearEntry)
    local savedLink = GetSavedItemLink(gearEntry)
    if savedLink and itemLink then
        return itemLink == savedLink
    end

    local savedLevel = GetSavedItemLevel(gearEntry)
    if savedLevel > 0 and itemLink then
        local level = GetItemLevel(itemLink)
        return level > 0 and level == savedLevel
    end

    return false
end

local function FindReferenceProfile(savedItemID, invSlot, savedItemLink, gearEntry)
    local savedLink = savedItemLink or GetSavedItemLink(gearEntry)

    if savedLink then
        return ApplySavedEntryStats(BuildItemProfile(savedItemID, savedLink), gearEntry)
    end

    local profile

    if invSlot then
        local equippedID = GetInventoryItemID("player", invSlot)
        local equippedLink = GetInventoryItemLink("player", invSlot)
        if equippedID and equippedLink and ProfileMatchesSavedEntry(equippedLink, gearEntry)
            and (equippedID == savedItemID or ItemsShareName(savedItemID, equippedID)) then
            profile = BuildItemProfile(equippedID, equippedLink, nil, nil, invSlot)
        end
    end

    if not profile then
        local savedLevel = GetSavedItemLevel(gearEntry)
        for _, bag in ipairs(BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local bagItemID = C_Container.GetContainerItemID(bag, slot)
                if bagItemID == savedItemID or ItemsShareName(savedItemID, bagItemID) then
                    local itemLink = C_Container.GetContainerItemLink(bag, slot)
                    if ProfileMatchesSavedEntry(itemLink, gearEntry) then
                        profile = BuildItemProfile(bagItemID, itemLink, bag, slot)
                        break
                    end
                    if not savedLink and savedLevel > 0 then
                        local bagProfile = BuildItemProfile(bagItemID, itemLink, bag, slot)
                        if bagProfile.itemLevel == 0 or bagProfile.itemLevel == savedLevel then
                            profile = bagProfile
                            break
                        end
                    end
                end
            end
            if profile then
                break
            end
        end
    end

    if not profile then
        profile = BuildItemProfile(savedItemID, select(2, C_Item.GetItemInfo(savedItemID)))
    end

    return ApplySavedEntryStats(profile, gearEntry)
end

local function ConsiderUpgradeCandidate(profile, referenceProfile, reservedInstances, bestCandidate)
    if not profile then
        return bestCandidate
    end

    if IsReservedInstance(profile, reservedInstances)
        or IsSameItemInstance(profile, referenceProfile)
        or not IsBetterItem(profile, referenceProfile) then
        return bestCandidate
    end

    if not bestCandidate or IsBetterItem(profile, bestCandidate) then
        return profile
    end

    return bestCandidate
end

local function ItemMatchesSavedFamily(savedItemID, itemID)
    if not itemID or not savedItemID then
        return false
    end

    if itemID == savedItemID then
        return true
    end

    return ItemsShareName(savedItemID, itemID)
end

local function FindBestUpgrade(savedItemID, referenceProfile, reservedInstances, targetInvSlot)
    if not GetItemName(savedItemID) then
        return nil
    end

    reservedInstances = reservedInstances or {}
    local bestCandidate

    if targetInvSlot then
        local itemID = GetInventoryItemID("player", targetInvSlot)
        if ItemMatchesSavedFamily(savedItemID, itemID) then
            local itemLink = GetInventoryItemLink("player", targetInvSlot)
            bestCandidate = ConsiderUpgradeCandidate(
                BuildItemProfile(itemID, itemLink, nil, nil, targetInvSlot),
                referenceProfile,
                reservedInstances,
                bestCandidate
            )
        end
    end

    for _, bag in ipairs(BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if ItemMatchesSavedFamily(savedItemID, itemID) then
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                bestCandidate = ConsiderUpgradeCandidate(
                    BuildItemProfile(itemID, itemLink, bag, slot),
                    referenceProfile,
                    reservedInstances,
                    bestCandidate
                )
            end
        end
    end

    for _, invSlot in ipairs(SEARCH_SLOTS) do
        if invSlot ~= targetInvSlot then
            local itemID = GetInventoryItemID("player", invSlot)
            if ItemMatchesSavedFamily(savedItemID, itemID) then
                local itemLink = GetInventoryItemLink("player", invSlot)
                bestCandidate = ConsiderUpgradeCandidate(
                    BuildItemProfile(itemID, itemLink, nil, nil, invSlot),
                    referenceProfile,
                    reservedInstances,
                    bestCandidate
                )
            end
        end
    end

    return bestCandidate
end

function Upgrades.IsLinkBetterThanSavedEntry(itemLink, gearEntry)
    if not itemLink or not gearEntry then
        return false
    end

    local savedID = GetSavedItemID(gearEntry)
    if not savedID then
        return false
    end

    local linkMods = LoadoutLocker.Gear.ParseItemLinkModifiers(itemLink)
    if not linkMods or not ItemsShareName(savedID, linkMods.itemID) then
        return false
    end

    if type(gearEntry) == "table" and gearEntry.itemLink and itemLink == gearEntry.itemLink then
        return false
    end

    local referenceProfile = FindReferenceProfile(savedID, nil, GetSavedItemLink(gearEntry), gearEntry)
    local candidateProfile = BuildItemProfile(linkMods.itemID, itemLink)
    return IsBetterItem(candidateProfile, referenceProfile)
end

function Upgrades.MergeBetterEquippedIntoGearSet(gearSet)
    if not gearSet then
        return false
    end

    local changed = false

    for _, invSlot in ipairs(SEARCH_SLOTS) do
        local gearEntry = GetGearEntry(gearSet, invSlot)
        if gearEntry then
            local equippedLink = GetInventoryItemLink("player", invSlot)
            if equippedLink and Upgrades.IsLinkBetterThanSavedEntry(equippedLink, gearEntry) then
                local itemID = GetInventoryItemID("player", invSlot)
                LoadoutLocker.Gear.SetGearSetEntry(
                    gearSet,
                    invSlot,
                    LoadoutLocker.Gear.CreateGearEntryFromLink(itemID, equippedLink)
                )
                changed = true
            end
        end
    end

    return changed
end

local function DescribeUpgradeReason(candidate, reference)
    local reasons = {}
    local candidateComparable = GetComparableTrackRank(candidate)
    local referenceComparable = GetComparableTrackRank(reference)

    if candidateComparable > referenceComparable then
        reasons[#reasons + 1] = string.format(
            "higher track (%s > %s)",
            GetTrackLabel(candidate.trackString),
            GetTrackLabel(reference.trackString)
        )
    elseif candidateComparable == referenceComparable
        and GetTrackLabel(candidate.trackString) ~= GetTrackLabel(reference.trackString) then
        reasons[#reasons + 1] = string.format(
            "higher track (%s > %s)",
            GetTrackLabel(candidate.trackString),
            GetTrackLabel(reference.trackString)
        )
    end

    if candidate.itemLevel > reference.itemLevel then
        reasons[#reasons + 1] = string.format("higher item level (%d > %d)", candidate.itemLevel, reference.itemLevel)
    end

    if candidateComparable == referenceComparable
        and candidate.itemLevel == reference.itemLevel then
        for _, field in ipairs(TERTIARY_PRIORITY) do
            if candidate[field] > reference[field] then
                if field == "sockets" then
                    reasons[#reasons + 1] = candidate.sockets > 1 and "extra sockets" or "extra socket"
                elseif reference[field] > 0 then
                    reasons[#reasons + 1] = "more " .. TERTIARY_LABELS[field]
                else
                    reasons[#reasons + 1] = TERTIARY_LABELS[field]
                end
            end
        end
    end

    if #reasons == 0 then
        return "better upgrade"
    end

    return table.concat(reasons, ", ")
end

function Upgrades.FindOffers(gearSet)
    local offers = {}
    local reservedInstances = {}
    local offeredSlots = {}

    for _, invSlot in ipairs(IterGearSetSlots(gearSet)) do
        local normalizedSlot = NormalizeInvSlot(invSlot)
        if not offeredSlots[normalizedSlot] then
            local gearEntry = GetGearEntry(gearSet, invSlot)
            local savedItemID = GetSavedItemID(gearEntry)
            if savedItemID then
                local referenceProfile = FindReferenceProfile(
                    savedItemID,
                    normalizedSlot,
                    GetSavedItemLink(gearEntry),
                    gearEntry
                )
                local candidate = FindBestUpgrade(savedItemID, referenceProfile, reservedInstances, normalizedSlot)
                if candidate then
                    offers[#offers + 1] = {
                        invSlot = normalizedSlot,
                        savedItemID = savedItemID,
                        candidate = candidate,
                        reference = referenceProfile,
                        reason = DescribeUpgradeReason(candidate, referenceProfile),
                    }
                    offeredSlots[normalizedSlot] = true

                    local key = GetInstanceLocationKey(candidate)
                    if key then
                        reservedInstances[key] = true
                    end
                end
            end
        end
    end

    table.sort(offers, function(a, b)
        return a.invSlot < b.invSlot
    end)

    return offers
end

local function FinishOfferQueue()
    local gearSet = offerState.gearSet
    local callback = offerState.callback
    local changed = offerState.changed
    local declinedSlots = offerState.declinedSlots

    if gearSet then
        LoadoutLocker.Gear.NormalizeGearSetKeys(gearSet)
    end

    offerState.gearSet = nil
    offerState.callback = nil
    offerState.saveTarget = nil
    offerState.changed = false
    offerState.declinedSlots = nil
    offerState.offerQueue = nil
    offerState.offerIndex = 1
    currentOffer = nil

    if callback then
        callback(gearSet, changed, declinedSlots)
    end
end

ShowNextOffer = function()
    if not offerState.gearSet or not offerState.offerQueue then
        return
    end

    while offerState.offerIndex <= #offerState.offerQueue do
        local nextOffer = offerState.offerQueue[offerState.offerIndex]
        if not offerState.declinedSlots[NormalizeInvSlot(nextOffer.invSlot)] then
            currentOffer = nextOffer
            ShowUpgradeFrame(nextOffer)
            return
        end
        offerState.offerIndex = offerState.offerIndex + 1
    end

    FinishOfferQueue()
end

function Upgrades.IsPromptActive()
    return offerState.gearSet ~= nil
end

function Upgrades.PromptForBetterItems(gearSet, options)
    local onComplete = options and options.onComplete

    if not gearSet or not next(gearSet) then
        if onComplete then
            onComplete(gearSet, false, nil)
        end
        return
    end

    if offerState.gearSet then
        return
    end

    LoadoutLocker.Gear.NormalizeGearSetKeys(gearSet)

    local offers = Upgrades.FindOffers(gearSet)
    if #offers == 0 then
        if onComplete then
            onComplete(gearSet, false, nil)
        end
        return
    end

    offerState.gearSet = gearSet
    offerState.callback = onComplete
    offerState.changed = false
    offerState.declinedSlots = {}
    offerState.offerQueue = offers
    offerState.offerIndex = 1
    currentOffer = nil

    if upgradeFrame and upgradeFrame:IsShown() then
        upgradeFrame:Hide()
    end

    if options and options.specID and options.configID then
        offerState.saveTarget = {
            specID = options.specID,
            configID = options.configID,
        }
    else
        offerState.saveTarget = nil
    end
    ShowNextOffer()
end
