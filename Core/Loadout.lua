LoadoutLocker = LoadoutLocker or {}

local Loadout = {}
LoadoutLocker.Loadout = Loadout
local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB

local activeLoadoutBySpec = {}
local pendingLoadoutSwitch
local awaitingTalentSwitchAfterSpec
local loadoutSelectionHooked
local lastAppliedSpecID
local lastUpgradeCheckBySpec = {}
local talentCommitPending
local talentCastFrame
local castCompleteTimer
local castPollToken
local talentCommitCompleteHandler

local function IsPlayerCasting()
    return UnitCastingInfo("player") or UnitChannelInfo("player")
end

local function FinishTalentCommit()
    if castCompleteTimer then
        castCompleteTimer:Cancel()
        castCompleteTimer = nil
    end

    local pending = talentCommitPending
    if not pending then
        return
    end

    talentCommitPending = nil

    local specID = Loadout.GetSpecID()
    local configID = specID and Loadout.GetLoadoutConfigID(specID)
    if specID ~= pending.specID or configID ~= pending.configID then
        Loadout.AbortLoadoutSwitch("cancelled")
        return
    end

    if talentCommitCompleteHandler then
        talentCommitCompleteHandler(specID, configID)
    end
end

local function ScheduleFinishTalentCommit()
    if castCompleteTimer then
        castCompleteTimer:Cancel()
    end

    castCompleteTimer = C_Timer.NewTimer(C.TALENT_COMMIT_FINISH_DELAY, FinishTalentCommit)
end

local function OnTalentCastEvent(_, event)
    if not talentCommitPending then
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        talentCommitPending.waitingForCastStart = false
        talentCommitPending.sawCast = true
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if talentCommitPending and talentCommitPending.sawCast then
            Loadout.AbortLoadoutSwitch("cancelled")
        end
        return
    end

    if event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
    then
        if talentCommitPending.sawCast and not IsPlayerCasting() then
            ScheduleFinishTalentCommit()
        end
    end
end

local function EnsureTalentCastMonitor()
    if talentCastFrame then
        return
    end

    talentCastFrame = CreateFrame("Frame")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    talentCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    talentCastFrame:SetScript("OnEvent", OnTalentCastEvent)
end

local function PollTalentCastFallback(token)
    if token ~= castPollToken or not talentCommitPending then
        return
    end

    local elapsed = GetTime() - talentCommitPending.startedAt

    if talentCommitPending.waitingForCastStart then
        if IsPlayerCasting() then
            talentCommitPending.waitingForCastStart = false
            talentCommitPending.sawCast = true
        elseif elapsed >= C.TALENT_COMMIT_CAST_START_TIMEOUT then
            if IsPlayerCasting() then
                talentCommitPending.waitingForCastStart = false
                talentCommitPending.sawCast = true
            else
                FinishTalentCommit()
            end
            return
        end
    elseif talentCommitPending.sawCast and not IsPlayerCasting() and elapsed >= C.TALENT_COMMIT_FINISH_DELAY then
        ScheduleFinishTalentCommit()
        return
    end

    if elapsed >= C.TALENT_COMMIT_CAST_TIMEOUT then
        FinishTalentCommit()
        return
    end

    C_Timer.After(0.1, function()
        PollTalentCastFallback(token)
    end)
end

function Loadout.SetTalentCommitCompleteHandler(handler)
    talentCommitCompleteHandler = handler
end

function Loadout.IsTalentCommitInProgress()
    return talentCommitPending ~= nil
end

function Loadout.CancelTalentCommit()
    castPollToken = (castPollToken or 0) + 1
    talentCommitPending = nil
    if castCompleteTimer then
        castCompleteTimer:Cancel()
        castCompleteTimer = nil
    end
end

function Loadout.AbortLoadoutSwitch(reason)
    reason = reason or "cancelled"

    local PromptUtils = LoadoutLocker.PromptUtils
    if PromptUtils and PromptUtils.HasPendingPromptSwitch() then
        PromptUtils.FailPendingPromptSwitch(reason)
        return
    end

    Loadout.CancelTalentCommit()
    Loadout.ClearAwaitingTalentSwitchAfterSpec()
    Loadout.ClearPendingSwitch()

    local gear = LoadoutLocker.Gear
    if gear and gear.CancelLoadoutSwitch then
        gear.CancelLoadoutSwitch()
    end

    if reason == "cancelled" then
        LoadoutLocker.Print("Swap cancelled.")
    elseif PromptUtils and PromptUtils.PrintSwitchFailure then
        PromptUtils.PrintSwitchFailure(reason)
    end
end

function Loadout.NotifyTalentCommitComplete(specID, configID)
    Loadout.CancelTalentCommit()
    if talentCommitCompleteHandler then
        talentCommitCompleteHandler(specID, configID)
    end
end

function Loadout.BeginTalentCommit(specID, configID)
    specID = tonumber(specID)
    configID = tonumber(configID)
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return
    end

    if talentCommitPending
        and talentCommitPending.specID == specID
        and talentCommitPending.configID == configID
    then
        return
    end

    talentCommitPending = {
        specID = specID,
        configID = configID,
        waitingForCastStart = true,
        sawCast = false,
        startedAt = GetTime(),
    }

    EnsureTalentCastMonitor()

    C_Timer.After(0.3, function()
        if not talentCommitPending or talentCommitPending.sawCast then
            return
        end

        castPollToken = (castPollToken or 0) + 1
        PollTalentCastFallback(castPollToken)
    end)
end

function Loadout.GetSpecID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        return (C_SpecializationInfo.GetSpecializationInfo(specIndex))
    end
end

function Loadout.GetSpecName(specID)
    if not specID then
        return nil
    end

    if GetSpecializationInfoForSpecID then
        local _, name = GetSpecializationInfoForSpecID(specID)
        if name and name ~= "" then
            return name
        end
    end

    for _, spec in ipairs(Loadout.GetClassSpecList()) do
        if spec.specID == specID then
            return spec.name
        end
    end
end

function Loadout.GetPlayerClassID()
    local _, _, classID = UnitClass("player")
    return classID
end

local function AddUniqueSpecID(seen, specIDs, specID)
    if not specID or seen[specID] then
        return
    end

    seen[specID] = true
    specIDs[#specIDs + 1] = specID
end

local function GetPlayerSpecIDAtIndex(specIndex)
    if not specIndex or not C_SpecializationInfo.GetSpecializationInfo then
        return nil
    end

    local classID = Loadout.GetPlayerClassID()
    if classID then
        local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex, false, false, nil, nil, nil, classID))
        specID = tonumber(specID)
        if specID and specID > 0 then
            return specID
        end
    end

    return tonumber(select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex)))
end

local function IsInitialSpecName(name)
    return name == "Initial" or name == "Initial Spec"
end

local function ShouldIncludeClassSpecID(specID, name, isAllowed)
    if not specID or specID <= 0 or isAllowed == false then
        return false
    end
    return not IsInitialSpecName(name)
end

local function GetPlayerSpecSlotCount()
    local numPlayerSpecs = C_SpecializationInfo.GetNumSpecializations and C_SpecializationInfo.GetNumSpecializations() or 0
    local classID = Loadout.GetPlayerClassID()
    local numClassSpecs = 0
    if classID and C_SpecializationInfo.GetNumSpecializationsForClassID then
        numClassSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    end
    return math.max(numPlayerSpecs, numClassSpecs)
end

local function ForEachPlayerSpec(callback)
    for specIndex = 1, GetPlayerSpecSlotCount() do
        local specID = GetPlayerSpecIDAtIndex(specIndex)
        if specID and callback(specIndex, specID) then
            return
        end
    end
end

local function ForEachClassSpec(callback)
    local classID = Loadout.GetPlayerClassID()
    if not classID or not C_SpecializationInfo.GetSpecializationInfoForClassID then
        return
    end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID
        and C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
        or 0
    for specIndex = 1, numSpecs do
        local specID, name, _, _, _, _, _, isAllowed = C_SpecializationInfo.GetSpecializationInfoForClassID(classID, specIndex)
        specID = tonumber(specID)
        if ShouldIncludeClassSpecID(specID, name, isAllowed) and callback(specIndex, specID, name) then
            return
        end
    end
end

local function CollectSpecIDsFromClassAPI(seen, specIDs)
    ForEachClassSpec(function(_, specID)
        AddUniqueSpecID(seen, specIDs, specID)
    end)

    ForEachPlayerSpec(function(_, specID)
        AddUniqueSpecID(seen, specIDs, specID)
    end)
end

local function CollectSpecIDsFromSavedData(seen, specIDs)
    for specID, specData in pairs(LoadoutLockerDB) do
        if type(specID) == "number" and type(specData) == "table" then
            AddUniqueSpecID(seen, specIDs, specID)
        end
    end
end

function Loadout.CollectKnownSpecIDs()
    if cachedKnownSpecIDs then
        return cachedKnownSpecIDs
    end

    local seen = {}
    local specIDs = {}

    CollectSpecIDsFromClassAPI(seen, specIDs)
    AddUniqueSpecID(seen, specIDs, Loadout.GetSpecID())
    CollectSpecIDsFromSavedData(seen, specIDs)

    table.sort(specIDs)
    cachedKnownSpecIDs = specIDs
    cachedKnownSpecIDSet = {}
    for _, knownSpecID in ipairs(specIDs) do
        cachedKnownSpecIDSet[knownSpecID] = true
    end
    return specIDs
end

function Loadout.GetClassSpecList()
    local specs = {}

    for _, specID in ipairs(Loadout.CollectKnownSpecIDs()) do
        local specName
        if GetSpecializationInfoForSpecID then
            specName = select(2, GetSpecializationInfoForSpecID(specID))
        end
        specs[#specs + 1] = {
            specIndex = Loadout.GetSpecIndex(specID),
            specID = specID,
            name = specName or ("Spec " .. tostring(specID)),
        }
    end

    return specs
end

function Loadout.IsKnownSpecID(specID)
    specID = tonumber(specID)
    if not specID then
        return false
    end

    if not cachedKnownSpecIDSet then
        Loadout.CollectKnownSpecIDs()
    end
    if cachedKnownSpecIDSet[specID] then
        return true
    end

    if GetSpecializationInfoForSpecID then
        return tonumber(select(1, GetSpecializationInfoForSpecID(specID))) == specID
    end

    return false
end

function Loadout.GetSpecIndex(specID)
    specID = tonumber(specID)
    if not specID then
        return nil
    end

    local foundIndex
    ForEachPlayerSpec(function(specIndex, playerSpecID)
        if playerSpecID == specID then
            foundIndex = specIndex
            return true
        end
    end)

    return foundIndex
end

function Loadout.EncodeLoadoutKey(specID, configID)
    if not specID or not configID then
        return ""
    end
    return tostring(specID) .. ":" .. tostring(configID)
end

function Loadout.DecodeLoadoutKey(key)
    if not key or key == "" or key == "default" then
        return nil, nil
    end

    local specID, configID = tostring(key):match("^(%d+):(%d+)$")
    return tonumber(specID), tonumber(configID)
end

function Loadout.ParseAssignmentValue(value, fallbackSpecID)
    local specID, configID = Loadout.DecodeLoadoutKey(value)
    if not specID then
        configID = tonumber(value)
        specID = fallbackSpecID
    end
    return specID, configID
end

local function SortLoadoutListBySpecAndName(list)
    table.sort(list, function(a, b)
        if a.specName == b.specName then
            return a.name < b.name
        end
        return a.specName < b.specName
    end)
end

function Loadout.FormatLoadoutLabel(specID, loadoutName)
    local specName = Loadout.GetSpecName(specID) or "Spec"
    local name = loadoutName or "Loadout"
    return specName .. "-" .. name
end

local cachedAllConfigList
local cachedAllSavedLoadoutList
local cachedSavedGearKeys
local cachedKnownSpecIDs
local cachedKnownSpecIDSet

function Loadout.InvalidateListCache()
    cachedAllConfigList = nil
    cachedAllSavedLoadoutList = nil
    cachedSavedGearKeys = nil
    cachedKnownSpecIDs = nil
    cachedKnownSpecIDSet = nil
end

local function GetSavedGearKeys()
    if cachedSavedGearKeys then
        return cachedSavedGearKeys
    end

    local keys = {}
    for _, entry in ipairs(DB:GetAllSavedGearEntries()) do
        keys[Loadout.EncodeLoadoutKey(entry.specID, entry.configID)] = true
    end

    cachedSavedGearKeys = keys
    return keys
end

function Loadout.GetAllConfigList()
    if cachedAllConfigList then
        return cachedAllConfigList
    end

    local list = {}
    local savedKeys = GetSavedGearKeys()

    for _, spec in ipairs(Loadout.GetClassSpecList()) do
        for _, entry in ipairs(Loadout.GetConfigList(spec.specID, savedKeys)) do
            list[#list + 1] = {
                specID = spec.specID,
                specName = spec.name,
                configID = entry.configID,
                name = entry.name,
                label = spec.name .. "-" .. entry.name,
                key = Loadout.EncodeLoadoutKey(spec.specID, entry.configID),
                hasSavedGear = entry.hasSavedGear,
            }
        end
    end

    SortLoadoutListBySpecAndName(list)

    cachedAllConfigList = list
    return list
end

function Loadout.GetAllSavedLoadoutList()
    if cachedAllSavedLoadoutList then
        return cachedAllSavedLoadoutList
    end

    local list = {}

    for _, entry in ipairs(DB:GetAllSavedGearEntries()) do
        local specName = Loadout.GetSpecName(entry.specID) or ("Spec " .. tostring(entry.specID))
        list[#list + 1] = {
            specID = entry.specID,
            specName = specName,
            configID = entry.configID,
            name = entry.name,
            label = specName .. "-" .. entry.name,
            key = Loadout.EncodeLoadoutKey(entry.specID, entry.configID),
            equipmentSetName = entry.equipmentSetName or "",
            hasSavedGear = true,
        }
    end

    SortLoadoutListBySpecAndName(list)

    cachedAllSavedLoadoutList = list
    return list
end

function Loadout.IsAssignedLoadoutActive(targetSpecID, targetConfigID)
    if not targetSpecID or not targetConfigID then
        return false
    end

    local currentSpecID = Loadout.GetSpecID()
    if currentSpecID ~= targetSpecID then
        return false
    end

    return Loadout.GetLoadoutConfigID(currentSpecID) == targetConfigID
end

function Loadout.SwitchToSpec(specID)
    specID = tonumber(specID)
    if not specID then
        return false
    end

    if Loadout.GetSpecID() == specID then
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    local specIndex = Loadout.GetSpecIndex(specID)
    if not specIndex or not C_SpecializationInfo.SetSpecialization then
        return false
    end

    if C_SpecializationInfo.SetSpecialization(specIndex) then
        return true
    end

    return Loadout.GetSpecID() == specID
end

function Loadout.ApplyAssignedLoadout(targetSpecID, targetConfigID)
    targetSpecID = tonumber(targetSpecID)
    targetConfigID = tonumber(targetConfigID)
    if not targetSpecID or not targetConfigID or Loadout.IsStarterBuild(targetConfigID) then
        return false, "invalid"
    end

    if Loadout.IsAssignedLoadoutActive(targetSpecID, targetConfigID) then
        return true, "unchanged"
    end

    if InCombatLockdown and InCombatLockdown() then
        return false, "combat"
    end

    local currentSpecID = Loadout.GetSpecID()
    if currentSpecID ~= targetSpecID then
        awaitingTalentSwitchAfterSpec = { specID = targetSpecID, configID = targetConfigID }
        pendingLoadoutSwitch = { specID = targetSpecID, configID = targetConfigID }
        if not Loadout.SwitchToSpec(targetSpecID) then
            pendingLoadoutSwitch = nil
            awaitingTalentSwitchAfterSpec = nil
            return false, "spec"
        end
        return true, "spec_changed"
    end

    return Loadout.SwitchTo(targetConfigID, targetSpecID)
end

function Loadout.GetLoadoutConfigID(specID)
    specID = specID or Loadout.GetSpecID()
    if specID then
        return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end
end

function Loadout.GetLoadoutName(configID)
    if not configID then
        return nil
    end

    if configID == C.STARTER_BUILD_CONFIG_ID then
        return "Starter Build"
    end

    local configInfo = C_Traits.GetConfigInfo(configID)
    return configInfo and configInfo.name or ("Loadout " .. tostring(configID))
end

function Loadout.ResolveLoadoutName(configID, cachedName)
    if cachedName and cachedName ~= "" then
        return cachedName
    end

    return Loadout.GetLoadoutName(configID)
end

function Loadout.SortByName(list)
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

function Loadout.IsStarterBuild(configID)
    return configID == C.STARTER_BUILD_CONFIG_ID
end

function Loadout.RememberActive(specID, configID)
    if specID and configID then
        activeLoadoutBySpec[specID] = configID
    end
end

function Loadout.GetActive(specID)
    specID = specID or Loadout.GetSpecID()
    if not specID then
        return nil
    end

    local configID = Loadout.GetLoadoutConfigID(specID)
    if not configID then
        return nil
    end

    local gear = DB:GetGearSet(specID, configID)

    return {
        specID = specID,
        configID = configID,
        name = Loadout.GetLoadoutName(configID),
        isStarter = Loadout.IsStarterBuild(configID),
        hasSavedGear = gear ~= nil,
        gear = gear,
    }
end

function Loadout.GetActiveGearSetCopy(specID)
    local context = Loadout.GetActive(specID)
    if not context or not context.gear then
        return nil, context
    end

    return DB:CopyGearSet(context.gear), context
end

function Loadout.QueueSwitch(specID, configID)
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return
    end

    pendingLoadoutSwitch = { specID = specID, configID = configID }
end

function Loadout.ClearPendingSwitch()
    pendingLoadoutSwitch = nil
end

function Loadout.GetLastAppliedSpecID()
    return lastAppliedSpecID
end

function Loadout.RememberAppliedSpec(specID)
    lastAppliedSpecID = specID
end

function Loadout.ShouldApplyGearForSwitch(specID, configID)
    if not specID or not configID then
        return false
    end

    local previousConfigID = Loadout.GetPreviousConfigID(specID)
    if lastAppliedSpecID ~= specID then
        return true
    end

    if previousConfigID == nil then
        return true
    end

    return previousConfigID ~= configID
end

function Loadout.ConsumePendingSwitch()
    local switch = pendingLoadoutSwitch
    pendingLoadoutSwitch = nil
    return switch
end

function Loadout.PeekPendingSwitch()
    return pendingLoadoutSwitch
end

function Loadout.IsAwaitingTalentSwitchAfterSpec()
    return awaitingTalentSwitchAfterSpec ~= nil
end

function Loadout.GetAwaitingTalentSwitchAfterSpec()
    return awaitingTalentSwitchAfterSpec
end

function Loadout.ClearAwaitingTalentSwitchAfterSpec()
    awaitingTalentSwitchAfterSpec = nil
end

function Loadout.ShouldRunUpgradeCheck(specID, configID)
    if not specID or not configID then
        return false
    end

    return lastUpgradeCheckBySpec[specID] ~= configID
end

function Loadout.RememberUpgradeCheck(specID, configID)
    if specID and configID then
        lastUpgradeCheckBySpec[specID] = configID
    end
end

function Loadout.ClearUpgradeCheck(specID)
    if specID then
        lastUpgradeCheckBySpec[specID] = nil
    end
end

function Loadout.GetPreviousConfigID(specID)
    return activeLoadoutBySpec[specID]
end

function Loadout.HookSelection()
    if loadoutSelectionHooked or not C_ClassTalents or not C_ClassTalents.UpdateLastSelectedSavedConfigID then
        return
    end

    loadoutSelectionHooked = true

    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function(specID, configID)
        if not specID or not configID or Loadout.IsStarterBuild(configID) then
            return
        end

        if Loadout.GetSpecID() ~= specID then
            return
        end

        if Loadout.IsAwaitingTalentSwitchAfterSpec() then
            return
        end

        pendingLoadoutSwitch = { specID = specID, configID = configID }
        Loadout.BeginTalentCommit(specID, configID)
    end)
end

function Loadout.RecordCurrent()
    local specID = Loadout.GetSpecID()
    local configID = specID and Loadout.GetLoadoutConfigID(specID)
    if specID and configID then
        Loadout.RememberActive(specID, configID)
        Loadout.RememberAppliedSpec(specID)
        return true
    end
end

function Loadout.GetConfigList(specID, savedKeys)
    specID = specID or Loadout.GetSpecID()
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then
        return {}
    end

    savedKeys = savedKeys or GetSavedGearKeys()
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID) or {}
    local list = {}

    for _, configID in ipairs(configIDs) do
        if not Loadout.IsStarterBuild(configID) then
            list[#list + 1] = {
                configID = configID,
                name = Loadout.GetLoadoutName(configID),
                hasSavedGear = savedKeys[Loadout.EncodeLoadoutKey(specID, configID)] == true,
            }
        end
    end

    Loadout.SortByName(list)

    return list
end

function Loadout.SwitchTo(configID, specID)
    specID = specID or Loadout.GetSpecID()
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return false, "invalid"
    end

    if Loadout.GetLoadoutConfigID(specID) == configID then
        return true, "unchanged"
    end

    if not C_ClassTalents or not C_ClassTalents.LoadConfig then
        return false, "api"
    end

    local result = C_ClassTalents.LoadConfig(configID, true)
    if result == 0 then
        return false, "error"
    end

    if C_ClassTalents.UpdateLastSelectedSavedConfigID then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    else
        pendingLoadoutSwitch = { specID = specID, configID = configID }
    end

    Loadout.BeginTalentCommit(specID, configID)

    return true, result
end

Loadout.HookSelection()
