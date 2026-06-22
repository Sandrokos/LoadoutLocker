LoadoutLocker = LoadoutLocker or {}

local UI = {}
LoadoutLocker.UI = UI

local C = LoadoutLocker.Constants
local Gear = LoadoutLocker.Gear
local DB = LoadoutLocker.DB
local Talents = LoadoutLocker.Talents
local Upgrades = LoadoutLocker.Upgrades

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

local saveButton
local talentsFrame
local talentUIInitialized
local talentUIRefreshScheduled

local upgradeFrame
local upgradeOnRespond

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

local function CreateItemPanel(parent, name)
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
    panel.details:SetWidth(185)
    panel.details:SetWordWrap(true)
    panel.details:SetJustifyH("CENTER")
    panel.details:SetNonSpaceWrap(false)
    panel.details:SetSpacing(2)

    return panel
end

local function MeasureItemPanel(panel)
    local headerHeight = panel.header:GetStringHeight() or 12
    local nameHeight = panel.name:GetStringHeight() or 14
    local detailsHeight = panel.details:GetStringHeight() or 14
    return headerHeight + 8 + 40 + 6 + nameHeight + 6 + detailsHeight
end

local function SetItemPanel(panel, headerText, profile)
    panel.header:SetText(headerText)
    panel.name:SetText(Upgrades.GetItemDisplayName(profile.itemID) or "Unknown Item")

    local icon = Upgrades.GetItemIcon(profile.itemID, profile.itemLink)
    if icon then
        panel.icon:GetNormalTexture():SetTexture(icon)
    end

    panel.details:SetText(Upgrades.FormatProfileDetails(profile))
    AttachItemTooltip(panel.icon, profile.itemLink)
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
    frame:SetHeight(math.max(360, math.min(frameHeight, 560)))
end

local function EnsureUpgradeFrame()
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

    frame.currentPanel = CreateItemPanel(frame, "Current")
    frame.upgradePanel = CreateItemPanel(frame, "Upgrade")

    frame.arrow = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    frame.arrow:SetText("=>")

    frame.acceptButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.acceptButton:SetSize(120, 22)
    frame.acceptButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 16)
    frame.acceptButton:SetText("Use Upgrade")
    frame.acceptButton:SetScript("OnClick", function(self)
        if not upgradeOnRespond then
            return
        end
        self:Disable()
        frame.declineButton:Disable()
        upgradeOnRespond(true)
    end)

    frame.declineButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.declineButton:SetSize(120, 22)
    frame.declineButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 16)
    frame.declineButton:SetText("Keep Saved")
    frame.declineButton:SetScript("OnClick", function(self)
        if not upgradeOnRespond then
            return
        end
        self:Disable()
        frame.acceptButton:Disable()
        upgradeOnRespond(false)
    end)

    tinsert(UISpecialFrames, frame:GetName())
    upgradeFrame = frame
    return frame
end

function UI.ShowUpgradeOffer(offer, onRespond)
    upgradeOnRespond = onRespond

    local frame = EnsureUpgradeFrame()
    frame.acceptButton:Enable()
    frame.declineButton:Enable()
    frame.title:SetText(Upgrades.GetItemDisplayName(offer.candidate.itemID) or "Upgrade Found")
    frame.reason:SetText(offer.reason)
    SetItemPanel(frame.currentPanel, "Saved Item", offer.reference)
    SetItemPanel(frame.upgradePanel, "Upgrade", offer.candidate)
    LayoutUpgradeFrame(frame)
    frame:Show()
end

function UI.HideUpgradeOffer()
    upgradeOnRespond = nil
    if upgradeFrame then
        upgradeFrame:Hide()
    end
end

function UI.IsUpgradeOfferShown()
    return upgradeFrame and upgradeFrame:IsShown()
end

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
    if talentUIRefreshScheduled then
        return
    end

    talentUIRefreshScheduled = true
    C_Timer.After(0, function()
        talentUIRefreshScheduled = false
        RefreshSaveButton(false)
    end)
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
    saveButton:SetScript("OnClick", function()
        Gear.Save()
    end)

    talentsFrame = frame
    RefreshSaveButton(true)
end

local function InitializeTalentUI()
    if talentUIInitialized then
        return
    end

    local frame = GetTalentsFrame()
    if not frame or not frame.LoadSystem then
        return
    end

    talentUIInitialized = true
    frame:HookScript("OnShow", function()
        RefreshSaveButton(true)
    end)
    CreateSaveButton(frame)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == C.TALENT_UI_ADDON then
        InitializeTalentUI()
    elseif talentUIInitialized and (event == "TRAIT_CONFIG_LIST_UPDATED" or event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
        ScheduleSaveButtonRefresh()
    end
end)

if C_AddOns.IsAddOnLoaded(C.TALENT_UI_ADDON) then
    InitializeTalentUI()
end

LoadoutLocker.RefreshTalentUI = function()
    RefreshSaveButton(true)
end
