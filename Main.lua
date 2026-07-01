local ADDON_NAME = ...

local Print = LoadoutLocker.Print
local Text = LoadoutLocker.Text
local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Gear = LoadoutLocker.Gear
local Loadout = LoadoutLocker.Loadout
local Menu = LoadoutLocker.Menu
local PromptUtils = LoadoutLocker.PromptUtils
local DungeonUI = LoadoutLocker.DungeonUI
local RaidUI = LoadoutLocker.RaidUI
local DelveUI = LoadoutLocker.DelveUI
local PvPUI = LoadoutLocker.PvPUI
local OnboardingUI = LoadoutLocker.OnboardingUI

local loginSynced
local traitConfigUpdateTimer

local function PrintMenuReminder()
    Print("Type " .. Text.FormatCommand() .. " to open the menu.")
end

local function HandleTraitConfigUpdated()
    Loadout.InvalidateListCache()
    local specID = Loadout.GetSpecID()
    local configID = specID and Loadout.GetLoadoutConfigID(specID)
    local awaiting = Loadout.GetAwaitingTalentSwitchAfterSpec()
    if awaiting then
        if specID == awaiting.specID and configID == awaiting.configID then
            Loadout.ClearAwaitingTalentSwitchAfterSpec()
            Gear.OnTalentSwitchAfterSpecComplete()
        end
    else
        Gear.ScheduleLoadoutGearApply()
    end
    if specID and configID then
        PromptUtils.OnPromptLoadoutTalentsApplied(specID, configID)
    end
end

local function ScheduleTraitConfigUpdated()
    if traitConfigUpdateTimer then
        traitConfigUpdateTimer:Cancel()
    end
    traitConfigUpdateTimer = C_Timer.NewTimer(C.LOADOUT_APPLY_DELAY, function()
        traitConfigUpdateTimer = nil
        HandleTraitConfigUpdated()
    end)
end

local function ShowHelp()
    Print("Commands:")
    Print("/locker - Open the LoadoutLocker menu")
    Print("/locker save - Save currently equipped gear to the active talent loadout")
    Print("/locker list - List saved gear sets for your current specialization")
    Print("/locker delete - Remove the saved gear set for the active talent loadout")
    Print("/locker scan - Check bags for better versions of current loadout items")
    Print("/locker sim dungeon - Preview the dungeon loadout prompt")
    Print("/locker sim delve - Preview the delve loadout prompt")
    Print("/locker sim pvp [arena|battleground] - Preview the PvP loadout prompt")
    Print("/locker sim raid [march] - Simulate being inside a raid")
    Print("/locker sim raid stop - End raid simulation")
    Print("/locker debug - Open bug report with debug info")
    Print("/locker tutorial - Show the getting started guide")
    Print("/locker help - Show this help")
    Print("Use /locker and open the Dungeons, Raids, Delves, or PvP tab to assign loadouts.")
end

local function HandleSlashCommand(msg)
    msg = string.lower(strtrim(msg or ""))

    if msg == "" then
        Menu.Show()
    elseif msg == "help" then
        ShowHelp()
    elseif msg == "save" then
        Gear.Save()
    elseif msg == "list" then
        Gear.List()
    elseif msg == "scan" then
        Gear.ScanForUpgrades()
    elseif msg == "sim dungeon" or msg == "simdungeon" then
        DungeonUI.Simulate()
    elseif msg == "sim delve" or msg == "simdelve" then
        DelveUI.Simulate()
    elseif msg:match("^sim pvp") then
        local mode = strtrim(msg:sub(8))
        if mode == "" then
            PvPUI.Simulate()
        else
            PvPUI.Simulate(mode)
        end
    elseif msg == "sim raid stop" or msg == "sim raid off" then
        RaidUI.Simulate("stop")
    elseif msg == "sim raid" or msg == "simraid" then
        RaidUI.Simulate()
    elseif msg:match("^sim raid ") then
        RaidUI.Simulate(strtrim(msg:sub(10)))
    elseif msg == "debug" or msg == "debug raid" then
        LoadoutLocker.BugReportUI.ShowDebugOutput()
    elseif msg == "tutorial" or msg == "onboarding" or msg == "guide" then
        OnboardingUI.Show({ force = true })
    elseif msg == "delete" or msg == "clear" then
        Gear.Delete()
    else
        Print("Unknown command. Type /locker help for options.")
    end
end

SLASH_LOADOUTLOCKER1 = "/locker"
SLASH_LOADOUTLOCKER2 = "/loadoutlocker"
SlashCmdList["LOADOUTLOCKER"] = HandleSlashCommand

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DB:Initialize()
        Menu.RegisterWithSettings()
        LoadoutLocker.BugReportUI.InstallErrorCapture()
    elseif event == "PLAYER_LOGIN" then
        PrintMenuReminder()
        if not loginSynced and Loadout.RecordCurrent() then
            loginSynced = true
        end
        if not DB:IsOnboardingComplete() then
            OnboardingUI.TryShowOnLogin()
        end
    elseif event == "TRAIT_CONFIG_LIST_UPDATED" then
        Loadout.InvalidateListCache()
        if not loginSynced and Loadout.RecordCurrent() then
            loginSynced = true
        end
    elseif event == "TRAIT_CONFIG_UPDATED" then
        ScheduleTraitConfigUpdated()
    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        Loadout.InvalidateListCache()
        Gear.OnSpecChanged()
    end
end)
