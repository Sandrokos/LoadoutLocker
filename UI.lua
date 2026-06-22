local TALENT_UI_ADDON = LoadoutLocker.TALENT_UI_ADDON
local Gear = LoadoutLocker.Gear
local DB = LoadoutLocker.DB
local Talents = LoadoutLocker.Talents

local UI = CreateFrame("Frame")
UI:RegisterEvent("ADDON_LOADED")
UI:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
UI:RegisterEvent("TRAIT_CONFIG_UPDATED")
UI:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

local saveButton
local talentsFrame
local initialized
local refreshScheduled

local function GetTalentsFrame()
    return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local function IsInspectingTalents()
    if not talentsFrame or not talentsFrame.IsInspecting then
        return false
    end

    return talentsFrame:IsInspecting()
end

local function RefreshSaveButton(checkInspecting)
    if not saveButton then
        return
    end

    if checkInspecting and IsInspectingTalents() then
        saveButton:Hide()
        return
    end

    saveButton:Show()

    local specID = Talents.GetSpecID()
    local configID = Talents.GetLoadoutConfigID(specID)
    local loadoutName = configID and Talents.GetLoadoutName(configID)
    local canSave = specID and configID and not Talents.IsStarterBuild(configID)
    local hasSaved = canSave and DB:HasGearSet(specID, configID)

    if canSave then
        saveButton:Enable()
        saveButton:SetText(hasSaved and "Update Gear" or "Save Gear")
    else
        saveButton:Disable()
        saveButton:SetText("Save Gear")
    end

    saveButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(saveButton, "ANCHOR_RIGHT")
        if not canSave then
            GameTooltip:SetText("Select a saved talent loadout to store gear.", 1, 1, 1)
        elseif hasSaved then
            GameTooltip:SetText("Update saved gear for " .. loadoutName, 1, 1, 1)
            GameTooltip:AddLine("Replaces the gear set linked to this talent loadout.", 1, 0.82, 0, true)
        else
            GameTooltip:SetText("Save current gear to " .. loadoutName, 1, 1, 1)
            GameTooltip:AddLine("Gear will automatically equip when you switch to this loadout.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)

    saveButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function ScheduleSaveButtonRefresh()
    if refreshScheduled then
        return
    end

    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        RefreshSaveButton(false)
    end)
end

local function OnSaveButtonClick()
    Gear.Save()
end

local function CreateSaveButton(frame)
    if saveButton then
        return
    end

    local loadSystem = frame.LoadSystem
    if not loadSystem then
        return
    end

    local dropdown = loadSystem.GetDropdown and loadSystem:GetDropdown() or loadSystem

    saveButton = CreateFrame("Button", "LoadoutLockerSaveButton", frame, "UIPanelButtonTemplate")
    saveButton:SetHeight(22)
    saveButton:SetPoint("TOP", dropdown, "BOTTOM", 0, -4)
    saveButton:SetPoint("LEFT", dropdown, "LEFT", 0, 0)
    saveButton:SetPoint("RIGHT", dropdown, "RIGHT", 0, 0)
    saveButton:SetText("Save Gear")
    saveButton:SetScript("OnClick", OnSaveButtonClick)

    talentsFrame = frame
    RefreshSaveButton(true)
end

local function InitializeTalentUI()
    if initialized then
        return
    end

    local frame = GetTalentsFrame()
    if not frame or not frame.LoadSystem then
        return
    end

    initialized = true
    frame:HookScript("OnShow", function()
        RefreshSaveButton(true)
    end)
    CreateSaveButton(frame)
end

UI:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == TALENT_UI_ADDON then
        InitializeTalentUI()
    elseif initialized and (event == "TRAIT_CONFIG_LIST_UPDATED" or event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
        ScheduleSaveButtonRefresh()
    end
end)

if C_AddOns.IsAddOnLoaded(TALENT_UI_ADDON) then
    InitializeTalentUI()
end

LoadoutLocker.RefreshTalentUI = function()
    RefreshSaveButton(true)
end
