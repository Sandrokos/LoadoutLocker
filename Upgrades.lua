LoadoutLocker = LoadoutLocker or {}

local Upgrades = {}
LoadoutLocker.Upgrades = Upgrades

local C = LoadoutLocker.Constants
local Items = LoadoutLocker.Items
local Gear = LoadoutLocker.Gear

local scanTooltip

local offerState = {
    callback = nil,
    gearSet = nil,
    changed = false,
    declinedSlots = nil,
    offerQueue = nil,
    offerIndex = 1,
}
local currentOffer
local ShowNextOffer
local AcceptCurrentOffer
local RespondToOffer

local function IterGearSetSlots(gearSet)
    local slots = {}
    local seen = {}

    for invSlot in pairs(gearSet) do
        local normalized = Gear.NormalizeInvSlot(invSlot)
        if type(normalized) == "number" and not seen[normalized] then
            seen[normalized] = true
            slots[#slots + 1] = normalized
        end
    end

    table.sort(slots)
    return slots
end

local function GetInstanceLocationKey(profile)
    return Items.GetLocationKey(profile)
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
    Gear.SetGearSetEntry(
        offerState.gearSet,
        currentOffer.invSlot,
        Items.ToGearEntryFromLink(
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
        offerState.declinedSlots[Gear.NormalizeInvSlot(currentOffer.invSlot)] = true
    end

    currentOffer = nil

    LoadoutLocker.UI.HideUpgradeOffer()

    offerState.offerIndex = offerState.offerIndex + 1
    C_Timer.After(C.OFFER_ADVANCE_DELAY, ShowNextOffer)
end

local function GetItemName(itemID)
    return Items.GetDisplayName(itemID)
end

local function ItemsShareName(itemIDA, itemIDB)
    return Items.MatchesFamily(itemIDA, itemIDB)
end

local function MatchTrackEntry(trackString, tierOnly)
    if not trackString or trackString == "" then
        return nil
    end

    local lower = string.lower(trackString)
    for _, entry in ipairs(C.TRACK_RANK) do
        if (not tierOnly or entry[2] < 10) and string.find(lower, entry[1], 1, true) then
            return entry
        end
    end
end

local function GetExplicitTierEntry(trackString)
    return MatchTrackEntry(trackString, true)
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

function Upgrades.GetItemDisplayName(itemID)
    return GetItemName(itemID)
end

function Upgrades.FormatProfileDetails(profile)
    local parts = {
        string.format("%s | ilvl %d", GetTrackLabel(profile.trackString), profile.itemLevel),
    }

    if profile.sockets > 0 then
        parts[#parts + 1] = profile.sockets == 1 and "1 socket" or (profile.sockets .. " sockets")
    end

    for _, field in ipairs(C.TERTIARY_PRIORITY) do
        if field ~= "sockets" and profile[field] > 0 then
            parts[#parts + 1] = C.TERTIARY_LABELS[field]
        end
    end

    if #parts == 1 then
        parts[#parts + 1] = "No bonus stats"
    end

    return table.concat(parts, ", ")
end

function Upgrades.GetItemIcon(itemID, itemLink)
    if itemLink and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return select(5, C_Item.GetItemInfo(itemID))
end

local function GetItemLevel(itemLink, itemLocation)
    return Items.GetItemLevel(itemLink, itemLocation)
end

local function GetSavedItemLevel(gearEntry)
    return Items.GetSavedItemLevel(gearEntry)
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

local function ForEachTooltipLine(callback)
    local tooltip = EnsureScanTooltip()
    for i = 1, tooltip:NumLines() do
        for _, lineKey in ipairs({ "TextLeft", "TextRight" }) do
            local line = _G["LoadoutLockerUpgradeScanTooltip" .. lineKey .. i]
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

local function MatchStandardTrackFromText(text)
    if not text then
        return nil
    end

    local lower = string.lower(text)
    for _, entry in ipairs(C.TRACK_RANK) do
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

    return ForEachTooltipLine(function(text)
        for _, marker in ipairs(C.TRACK_SCAN_MARKERS) do
            local familyLabel = marker[2]
            local tier = string.match(text, familyLabel .. "%s*:%s*(%S+)")
            if tier then
                return familyLabel .. ": " .. tier
            end
            if string.find(string.lower(text), marker[1], 1, true) then
                return familyLabel
            end
        end

        return MatchStandardTrackFromText(text)
    end)
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

    local function trackFromUpgradeInfo(info)
        if info and info.trackString and info.trackString ~= "" then
            return info.trackString
        end
    end

    if itemLocation and C_Item.GetItemUpgradeInfo then
        local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemLocation)
        if ok and info then
            upgradeInfo = info
            local track = trackFromUpgradeInfo(info)
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
                local track = trackFromUpgradeInfo(info)
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
                local track = trackFromUpgradeInfo(info)
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

    ForEachTooltipLine(function(text)
        for field, marker in pairs(C.TERTIARY_LABELS) do
            if field ~= "sockets" and string.find(text, marker, 1, true) then
                stats[field] = 1
            end
        end
    end)

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
        for field, keys in pairs(C.TERTIARY_STAT_KEYS) do
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

local function BuildItemProfile(itemIDOrLocation, itemLink, bag, slot, invSlot)
    local location
    if type(itemIDOrLocation) == "table" then
        location = itemIDOrLocation
    else
        location = {
            itemID = itemIDOrLocation,
            itemLink = itemLink,
            bag = bag,
            slot = slot,
            invSlot = invSlot,
        }
    end

    local itemID = location.itemID
    local itemLink = location.itemLink
    local bag = location.bag
    local slot = location.slot
    local invSlot = location.invSlot
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

local function ItemMatchesSavedFamily(savedItemID, itemID)
    return Items.MatchesFamily(savedItemID, itemID)
end

local function CollectPlayerItemProfiles()
    return Items.CollectPlayerProfiles()
end

local function IsBetterBonusProfile(candidate, reference)
    for _, field in ipairs(C.TERTIARY_PRIORITY) do
        local candidateValue = candidate[field]
        local referenceValue = reference[field]
        if candidateValue ~= referenceValue then
            return candidateValue > referenceValue
        end
    end

    return false
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

    return IsBetterBonusProfile(candidate, reference)
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

local function FindReferenceProfile(savedItemID, invSlot, savedItemLink, gearEntry, playerProfiles)
    local savedLink = savedItemLink or GetSavedItemLink(gearEntry)

    if savedLink then
        return ApplySavedEntryStats(BuildItemProfile(savedItemID, savedLink), gearEntry)
    end

    local profile

    if invSlot and playerProfiles then
        for _, itemProfile in ipairs(playerProfiles) do
            if itemProfile.invSlot == invSlot
                and ProfileMatchesSavedEntry(itemProfile.itemLink, gearEntry)
                and ItemMatchesSavedFamily(savedItemID, itemProfile.itemID) then
                profile = itemProfile
                break
            end
        end
    elseif invSlot then
        local equipped = Items.FromEquippedSlot(invSlot)
        if equipped and ProfileMatchesSavedEntry(equipped.itemLink, gearEntry)
            and ItemMatchesSavedFamily(savedItemID, equipped.itemID) then
            profile = BuildItemProfile(equipped)
        end
    end

    if not profile and playerProfiles then
        local savedLevel = GetSavedItemLevel(gearEntry)
        for _, itemProfile in ipairs(playerProfiles) do
            if ItemMatchesSavedFamily(savedItemID, itemProfile.itemID) then
                if ProfileMatchesSavedEntry(itemProfile.itemLink, gearEntry) then
                    profile = itemProfile
                    break
                end
                if savedLevel > 0
                    and (itemProfile.itemLevel == 0 or itemProfile.itemLevel == savedLevel) then
                    profile = itemProfile
                    break
                end
            end
        end
    elseif not profile then
        local savedLevel = GetSavedItemLevel(gearEntry)

        Items.ForEachBagItem(function(location)
            if profile then
                return
            end

            if ItemMatchesSavedFamily(savedItemID, location.itemID) then
                if ProfileMatchesSavedEntry(location.itemLink, gearEntry) then
                    profile = BuildItemProfile(location)
                elseif savedLevel > 0 then
                    local bagProfile = BuildItemProfile(location)
                    if bagProfile.itemLevel == 0 or bagProfile.itemLevel == savedLevel then
                        profile = bagProfile
                    end
                end
            end
        end)
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

local function FindBestUpgrade(savedItemID, referenceProfile, reservedInstances, targetInvSlot, playerProfiles)
    if not GetItemName(savedItemID) or not playerProfiles then
        return nil
    end

    reservedInstances = reservedInstances or {}
    local bestCandidate

    local function consider(profile)
        if ItemMatchesSavedFamily(savedItemID, profile.itemID) then
            bestCandidate = ConsiderUpgradeCandidate(
                profile,
                referenceProfile,
                reservedInstances,
                bestCandidate
            )
        end
    end

    if targetInvSlot then
        for _, profile in ipairs(playerProfiles) do
            if profile.invSlot == targetInvSlot then
                consider(profile)
            end
        end
    end

    for _, profile in ipairs(playerProfiles) do
        if profile.invSlot ~= targetInvSlot then
            consider(profile)
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

    local linkMods = Items.ParseItemLinkModifiers(itemLink)
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
        for _, field in ipairs(C.TERTIARY_PRIORITY) do
            if candidate[field] > reference[field] then
                if field == "sockets" then
                    reasons[#reasons + 1] = candidate.sockets > 1 and "extra sockets" or "extra socket"
                elseif reference[field] > 0 then
                    reasons[#reasons + 1] = "more " .. C.TERTIARY_LABELS[field]
                else
                    reasons[#reasons + 1] = C.TERTIARY_LABELS[field]
                end
            end
        end
    end

    if #reasons == 0 then
        return "better upgrade"
    end

    return table.concat(reasons, ", ")
end

function Upgrades.BuildComparisonProfile(location)
    return BuildItemProfile(location)
end

function Upgrades.FindOffers(gearSet, options)
    options = options or {}
    local slotFilter = options.slots

    local offers = {}
    local reservedInstances = {}
    local offeredSlots = {}
    local playerProfiles = CollectPlayerItemProfiles()

    for _, invSlot in ipairs(IterGearSetSlots(gearSet)) do
        local normalizedSlot = Gear.NormalizeInvSlot(invSlot)
        if (not slotFilter or slotFilter[normalizedSlot]) and not offeredSlots[normalizedSlot] then
            local gearEntry = Gear.GetGearSetEntry(gearSet, invSlot)
            local savedItemID = GetSavedItemID(gearEntry)
            if savedItemID then
                local referenceProfile = FindReferenceProfile(
                    savedItemID,
                    normalizedSlot,
                    GetSavedItemLink(gearEntry),
                    gearEntry,
                    playerProfiles
                )
                local candidate = FindBestUpgrade(
                    savedItemID,
                    referenceProfile,
                    reservedInstances,
                    normalizedSlot,
                    playerProfiles
                )
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
        Gear.NormalizeGearSetKeys(gearSet)
    end

    offerState.gearSet = nil
    offerState.callback = nil
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
        if not offerState.declinedSlots[Gear.NormalizeInvSlot(nextOffer.invSlot)] then
            currentOffer = nextOffer
            LoadoutLocker.UI.ShowUpgradeOffer(nextOffer, RespondToOffer)
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

    Gear.NormalizeGearSetKeys(gearSet)

    local offers = options and options.offers or Upgrades.FindOffers(gearSet, {
        slots = options and options.slotFilter,
    })
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

    LoadoutLocker.UI.HideUpgradeOffer()

    ShowNextOffer()
end
