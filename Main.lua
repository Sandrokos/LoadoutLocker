local ADDON_NAME = ...

local Print = LoadoutLocker.Print
local DB = LoadoutLocker.DB
local Gear = LoadoutLocker.Gear

local loginSynced

local function ShowHelp()
    Print("Commands:")
    Print("/locker save - Save currently equipped gear to the active talent loadout")
    Print("/locker list - List saved gear sets for your current specialization")
    Print("/locker delete - Remove the saved gear set for the active talent loadout")
    Print("/locker help - Show this help")
end

local function HandleSlashCommand(msg)
    msg = string.lower(strtrim(msg or ""))

    if msg == "" or msg == "help" then
        ShowHelp()
    elseif msg == "save" then
        Gear.Save()
    elseif msg == "list" then
        Gear.List()
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
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DB:Initialize()
    elseif (event == "PLAYER_LOGIN" or event == "TRAIT_CONFIG_LIST_UPDATED") and not loginSynced then
        if Gear.RecordCurrentLoadout() then
            loginSynced = true
        end
    elseif event == "TRAIT_CONFIG_UPDATED" then
        Gear.ScheduleLoadoutGearApply()
    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        Gear.OnSpecChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Gear.OnRegenEnabled()
    end
end)
