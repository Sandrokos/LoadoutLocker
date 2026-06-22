LoadoutLocker = LoadoutLocker or {}

local Menu = {}
LoadoutLocker.Menu = Menu

local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Loadout = LoadoutLocker.Loadout
local Gear = LoadoutLocker.Gear

local menuFrame
local helpPanel
local priorityPanel
local loadoutsPanel
local priorityRows = {}
local ignoredRows = {}
local activeTab = "help"

local HELP_TEXT = "LoadoutLocker saves your equipped gear to each talent loadout and swaps it when you change builds.\n\n"
    .. "|cffffffffSave gear|r\n"
    .. "Equip the items you want, select a talent loadout, then click Save Gear on the talent panel or run |cffffffff/locker save|r.\n\n"
    .. "|cffffffffSwitch loadouts|r\n"
    .. "Selecting a different talent loadout automatically equips its saved gear set after talents apply.\n\n"
    .. "|cffffffffUpgrade prompts|r\n"
    .. "When applying a loadout, better same-name items in your bags can be offered. Disable this on the Priority tab or set tertiary stat order there. Check |cffffffffDo not ask again|r on a prompt to silence that slot for the loadout.\n\n"
    .. "|cffffffffCommands|r\n"
    .. "/locker opens this menu. Also: save, list, scan, delete, settings\n\n"
    .. "Find LoadoutLocker under |cffffffffEsc > Options > AddOns|r."

local selectedManageConfigID
local selectedCopySourceConfigID
local selectedCopyTargetConfigID

local function RefreshAddonUI()
    if LoadoutLocker.RefreshTalentUI then
        LoadoutLocker.RefreshTalentUI()
    end
end

local function FindListEntry(list, configID)
    for _, entry in ipairs(list) do
        if entry.configID == configID then
            return entry
        end
    end
end

local function GetDropdownLabel(list, configID, fallback)
    local entry = configID and FindListEntry(list, configID)
    return entry and entry.name or fallback or "Select..."
end

local function InitDropdown(dropdown, width)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_SetText(dropdown, "Select...")
end

local function RefreshPriorityRows()
    if not priorityPanel then
        return
    end

    priorityPanel.upgradeCheck:SetChecked(DB:AreUpgradeChecksEnabled())

    local priority = DB:GetTertiaryPriority()
    for index, field in ipairs(priority) do
        local row = priorityRows[index]
        if row then
            row.rank:SetText(index .. ".")
            row.label:SetText(C.TERTIARY_SETTING_LABELS[field] or field)
            row.field = field
            row.upButton:SetEnabled(index > 1)
            row.downButton:SetEnabled(index < #priority)
        end
    end
end

local function RefreshIgnoredRows(specID, configID)
    if not loadoutsPanel then
        return
    end

    local slots = DB:GetIgnoredUpgradeSlotList(specID, configID)
    for index, row in ipairs(ignoredRows) do
        local slot = slots[index]
        if slot then
            row.label:SetText(C.GetSlotLabel(slot))
            row.slot = slot
            row:Show()
        else
            row.slot = nil
            row:Hide()
        end
    end

    loadoutsPanel.noIgnoredText:SetShown(#slots == 0)
    loadoutsPanel.clearIgnoredButton:SetEnabled(#slots > 0)
end

local function RefreshManageDropdown()
    local specID = Loadout.GetSpecID()
    if not specID then
        return
    end

    local savedSets = DB:GetSavedGearSetList(specID)
    if #savedSets == 0 then
        selectedManageConfigID = nil
        UIDropDownMenu_SetText(loadoutsPanel.manageDropdown, "No saved gear sets")
        return
    end

    if not selectedManageConfigID or not FindListEntry(savedSets, selectedManageConfigID) then
        selectedManageConfigID = savedSets[1].configID
    end

    UIDropDownMenu_SetText(
        loadoutsPanel.manageDropdown,
        GetDropdownLabel(savedSets, selectedManageConfigID, "Select loadout")
    )
    RefreshIgnoredRows(specID, selectedManageConfigID)
    loadoutsPanel.deleteButton:SetEnabled(selectedManageConfigID ~= nil)
end

local function RefreshCopyDropdowns()
    local specID = Loadout.GetSpecID()
    if not specID then
        return
    end

    local savedSets = DB:GetSavedGearSetList(specID)
    local loadouts = Loadout.GetConfigList(specID)

    if #savedSets == 0 then
        selectedCopySourceConfigID = nil
        UIDropDownMenu_SetText(loadoutsPanel.copySourceDropdown, "No saved gear sets")
    else
        if not selectedCopySourceConfigID or not FindListEntry(savedSets, selectedCopySourceConfigID) then
            selectedCopySourceConfigID = savedSets[1].configID
        end
        UIDropDownMenu_SetText(
            loadoutsPanel.copySourceDropdown,
            GetDropdownLabel(savedSets, selectedCopySourceConfigID, "Select source")
        )
    end

    if #loadouts == 0 then
        selectedCopyTargetConfigID = nil
        UIDropDownMenu_SetText(loadoutsPanel.copyTargetDropdown, "No loadouts found")
    else
        if not selectedCopyTargetConfigID or not FindListEntry(loadouts, selectedCopyTargetConfigID) then
            for _, entry in ipairs(loadouts) do
                if entry.configID ~= selectedCopySourceConfigID then
                    selectedCopyTargetConfigID = entry.configID
                    break
                end
            end
        end

        if selectedCopyTargetConfigID == selectedCopySourceConfigID then
            selectedCopyTargetConfigID = nil
            for _, entry in ipairs(loadouts) do
                if entry.configID ~= selectedCopySourceConfigID then
                    selectedCopyTargetConfigID = entry.configID
                    break
                end
            end
        end

        UIDropDownMenu_SetText(
            loadoutsPanel.copyTargetDropdown,
            GetDropdownLabel(loadouts, selectedCopyTargetConfigID, "Select target")
        )
    end

    loadoutsPanel.copyButton:SetEnabled(
        selectedCopySourceConfigID ~= nil
            and selectedCopyTargetConfigID ~= nil
            and selectedCopySourceConfigID ~= selectedCopyTargetConfigID
    )
end

local function RefreshLoadoutsPanel()
    if not loadoutsPanel then
        return
    end

    RefreshManageDropdown()
    RefreshCopyDropdowns()
end

local function SelectTab(tabID)
    activeTab = tabID
    helpPanel:SetShown(tabID == "help")
    priorityPanel:SetShown(tabID == "priority")
    loadoutsPanel:SetShown(tabID == "loadouts")

    menuFrame.helpTab:SetEnabled(tabID ~= "help")
    menuFrame.priorityTab:SetEnabled(tabID ~= "priority")
    menuFrame.loadoutsTab:SetEnabled(tabID ~= "loadouts")

    if tabID == "priority" then
        RefreshPriorityRows()
    elseif tabID == "loadouts" then
        RefreshLoadoutsPanel()
    end
end

local function CreateHelpPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -72)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 48)

    panel.text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0)
    panel.text:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, 0)
    panel.text:SetWidth(360)
    panel.text:SetWordWrap(true)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetSpacing(3)
    panel.text:SetText(HELP_TEXT)

    return panel
end

local function CreatePriorityPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -72)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 48)
    panel:Hide()

    panel.upgradeCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.upgradeCheck:SetSize(24, 24)
    panel.upgradeCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.upgradeCheck.text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.upgradeCheck.text:SetPoint("TOPLEFT", panel.upgradeCheck, "TOPRIGHT", 4, -2)
    panel.upgradeCheck.text:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.upgradeCheck.text:SetWordWrap(true)
    panel.upgradeCheck.text:SetJustifyH("LEFT")
    panel.upgradeCheck.text:SetText("Offer upgrade prompts when swapping loadouts")
    panel.upgradeCheck:SetScript("OnClick", function(self)
        DB:SetUpgradeChecksEnabled(self:GetChecked())
    end)

    panel.sectionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.sectionLabel:SetPoint("TOPLEFT", panel.upgradeCheck.text, "BOTTOMLEFT", -28, -16)
    panel.sectionLabel:SetText("Tertiary stat priority")

    panel.help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.help:SetPoint("TOPLEFT", panel.sectionLabel, "BOTTOMLEFT", 0, -6)
    panel.help:SetWidth(360)
    panel.help:SetWordWrap(true)
    panel.help:SetJustifyH("LEFT")
    panel.help:SetText("Higher stats at the top break ties when item level and track match.")

    local priorityCount = #C.DEFAULT_TERTIARY_PRIORITY
    for index = 1, priorityCount do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(360, 24)
        row:SetPoint("TOPLEFT", panel.help, "BOTTOMLEFT", 0, -10 - ((index - 1) * 28))

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.rank:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.rank:SetWidth(20)
        row.rank:SetJustifyH("RIGHT")

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row.rank, "RIGHT", 8, 0)
        row.label:SetWidth(180)
        row.label:SetJustifyH("LEFT")

        row.upButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.upButton:SetSize(52, 22)
        row.upButton:SetPoint("RIGHT", row, "RIGHT", -58, 0)
        row.upButton:SetText("Up")
        row.upButton:SetScript("OnClick", function()
            if row.field and DB:MoveTertiaryPriority(row.field, "up") then
                RefreshPriorityRows()
            end
        end)

        row.downButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.downButton:SetSize(52, 22)
        row.downButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.downButton:SetText("Down")
        row.downButton:SetScript("OnClick", function()
            if row.field and DB:MoveTertiaryPriority(row.field, "down") then
                RefreshPriorityRows()
            end
        end)

        priorityRows[index] = row
    end

    panel.resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.resetButton:SetSize(140, 22)
    panel.resetButton:SetPoint("TOPLEFT", priorityRows[priorityCount], "BOTTOMLEFT", 0, -14)
    panel.resetButton:SetText("Reset Priority")
    panel.resetButton:SetScript("OnClick", function()
        DB:ResetTertiaryPriority()
        RefreshPriorityRows()
    end)

    return panel
end

local function CreateIgnoredRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(360, 22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 24))

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(180)
    row.label:SetJustifyH("LEFT")

    row.clearButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.clearButton:SetSize(70, 20)
    row.clearButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.clearButton:SetText("Clear")
    row.clearButton:SetScript("OnClick", function()
        local specID = Loadout.GetSpecID()
        if specID and selectedManageConfigID and row.slot then
            DB:ClearIgnoredUpgradeSlot(specID, selectedManageConfigID, row.slot)
            RefreshLoadoutsPanel()
        end
    end)

    return row
end

local function CreateLoadoutsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -72)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 48)
    panel:Hide()

    panel.manageLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.manageLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.manageLabel:SetText("Manage saved gear set")

    panel.manageDropdown = CreateFrame("Frame", "LoadoutLockerManageDropdown", panel, "UIDropDownMenuTemplate")
    panel.manageDropdown:SetPoint("TOPLEFT", panel.manageLabel, "BOTTOMLEFT", -16, -6)
    InitDropdown(panel.manageDropdown, 220)
    UIDropDownMenu_Initialize(panel.manageDropdown, function()
        local specID = Loadout.GetSpecID()
        if not specID then
            return
        end

        local savedSets = DB:GetSavedGearSetList(specID)
        for _, entry in ipairs(savedSets) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name
            info.func = function()
                selectedManageConfigID = entry.configID
                UIDropDownMenu_SetText(panel.manageDropdown, entry.name)
                RefreshIgnoredRows(specID, selectedManageConfigID)
                panel.deleteButton:SetEnabled(true)
                RefreshCopyDropdowns()
            end
            info.checked = selectedManageConfigID == entry.configID
            UIDropDownMenu_AddButton(info)
        end
    end)

    panel.ignoredLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.ignoredLabel:SetPoint("TOPLEFT", panel.manageDropdown, "BOTTOMLEFT", 16, -12)
    panel.ignoredLabel:SetText("Ignored upgrade slots")

    panel.ignoredContainer = CreateFrame("Frame", nil, panel)
    panel.ignoredContainer:SetPoint("TOPLEFT", panel.ignoredLabel, "BOTTOMLEFT", 0, -4)
    panel.ignoredContainer:SetSize(360, 120)

    panel.noIgnoredText = panel.ignoredContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.noIgnoredText:SetPoint("TOPLEFT", panel.ignoredContainer, "TOPLEFT", 0, 0)
    panel.noIgnoredText:SetText("No ignored upgrade prompts for this loadout.")

    for index = 1, #C.EQUIP_SLOTS do
        ignoredRows[index] = CreateIgnoredRow(panel.ignoredContainer, index)
        ignoredRows[index]:Hide()
    end

    panel.clearIgnoredButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clearIgnoredButton:SetSize(150, 22)
    panel.clearIgnoredButton:SetPoint("TOPLEFT", panel.ignoredContainer, "BOTTOMLEFT", 0, -8)
    panel.clearIgnoredButton:SetText("Clear All Ignored")
    panel.clearIgnoredButton:SetScript("OnClick", function()
        local specID = Loadout.GetSpecID()
        if specID and selectedManageConfigID and DB:ClearAllIgnoredUpgradeSlots(specID, selectedManageConfigID) then
            RefreshLoadoutsPanel()
        end
    end)

    panel.deleteButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.deleteButton:SetSize(150, 22)
    panel.deleteButton:SetPoint("LEFT", panel.clearIgnoredButton, "RIGHT", 8, 0)
    panel.deleteButton:SetText("Delete Gear Set")
    panel.deleteButton:SetScript("OnClick", function()
        if selectedManageConfigID and Gear.DeleteSavedGear(selectedManageConfigID) then
            RefreshLoadoutsPanel()
        end
    end)

    panel.copyDivider = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.copyDivider:SetPoint("TOPLEFT", panel.clearIgnoredButton, "BOTTOMLEFT", 0, -20)
    panel.copyDivider:SetText("Copy gear set")

    panel.copySourceLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.copySourceLabel:SetPoint("TOPLEFT", panel.copyDivider, "BOTTOMLEFT", 0, -10)
    panel.copySourceLabel:SetText("From")

    panel.copySourceDropdown = CreateFrame("Frame", "LoadoutLockerCopySourceDropdown", panel, "UIDropDownMenuTemplate")
    panel.copySourceDropdown:SetPoint("TOPLEFT", panel.copySourceLabel, "BOTTOMLEFT", -16, -4)
    InitDropdown(panel.copySourceDropdown, 220)
    UIDropDownMenu_Initialize(panel.copySourceDropdown, function()
        local specID = Loadout.GetSpecID()
        if not specID then
            return
        end

        for _, entry in ipairs(DB:GetSavedGearSetList(specID)) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name
            info.func = function()
                selectedCopySourceConfigID = entry.configID
                UIDropDownMenu_SetText(panel.copySourceDropdown, entry.name)
                RefreshCopyDropdowns()
            end
            info.checked = selectedCopySourceConfigID == entry.configID
            UIDropDownMenu_AddButton(info)
        end
    end)

    panel.copyTargetLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.copyTargetLabel:SetPoint("TOPLEFT", panel.copySourceDropdown, "BOTTOMLEFT", 16, -8)
    panel.copyTargetLabel:SetText("To")

    panel.copyTargetDropdown = CreateFrame("Frame", "LoadoutLockerCopyTargetDropdown", panel, "UIDropDownMenuTemplate")
    panel.copyTargetDropdown:SetPoint("TOPLEFT", panel.copyTargetLabel, "BOTTOMLEFT", -16, -4)
    InitDropdown(panel.copyTargetDropdown, 220)
    UIDropDownMenu_Initialize(panel.copyTargetDropdown, function()
        local specID = Loadout.GetSpecID()
        if not specID then
            return
        end

        for _, entry in ipairs(Loadout.GetConfigList(specID)) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.hasSavedGear and (entry.name .. " (saved)") or entry.name
            info.func = function()
                selectedCopyTargetConfigID = entry.configID
                UIDropDownMenu_SetText(panel.copyTargetDropdown, entry.name)
                RefreshCopyDropdowns()
            end
            info.checked = selectedCopyTargetConfigID == entry.configID
            UIDropDownMenu_AddButton(info)
        end
    end)

    panel.copyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.copyButton:SetSize(120, 22)
    panel.copyButton:SetPoint("TOPLEFT", panel.copyTargetDropdown, "BOTTOMLEFT", 16, -10)
    panel.copyButton:SetText("Copy Gear Set")
    panel.copyButton:SetScript("OnClick", function()
        if Gear.CopyGearSetToLoadout(selectedCopySourceConfigID, selectedCopyTargetConfigID) then
            RefreshLoadoutsPanel()
            RefreshAddonUI()
        end
    end)

    return panel
end

local function EnsureMenuFrame()
    if menuFrame then
        return menuFrame
    end

    local frame = CreateFrame("Frame", "LoadoutLockerMenuFrame", UIParent, "BackdropTemplate")
    frame:SetSize(400, 560)
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
    frame.title:SetText("LoadoutLocker")

    frame.helpTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.helpTab:SetSize(90, 22)
    frame.helpTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
    frame.helpTab:SetText("Help")
    frame.helpTab:SetScript("OnClick", function()
        SelectTab("help")
    end)

    frame.priorityTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.priorityTab:SetSize(90, 22)
    frame.priorityTab:SetPoint("LEFT", frame.helpTab, "RIGHT", 6, 0)
    frame.priorityTab:SetText("Priority")
    frame.priorityTab:SetScript("OnClick", function()
        SelectTab("priority")
    end)

    frame.loadoutsTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.loadoutsTab:SetSize(90, 22)
    frame.loadoutsTab:SetPoint("LEFT", frame.priorityTab, "RIGHT", 6, 0)
    frame.loadoutsTab:SetText("Loadouts")
    frame.loadoutsTab:SetScript("OnClick", function()
        SelectTab("loadouts")
    end)

    helpPanel = CreateHelpPanel(frame)
    priorityPanel = CreatePriorityPanel(frame)
    loadoutsPanel = CreateLoadoutsPanel(frame)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(80, 22)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    frame.closeButton:SetText("Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    tinsert(UISpecialFrames, frame:GetName())
    menuFrame = frame
    return frame
end

function Menu.Show(tabID)
    local frame = EnsureMenuFrame()
    selectedManageConfigID = Loadout.GetLoadoutConfigID()
    SelectTab(tabID or activeTab or "help")
    frame:Show()
end

function Menu.Toggle(tabID)
    local frame = EnsureMenuFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        selectedManageConfigID = Loadout.GetLoadoutConfigID()
        SelectTab(tabID or activeTab or "help")
        frame:Show()
    end
end

function Menu.IsShown()
    return menuFrame and menuFrame:IsShown()
end

local optionsPanel
local optionsCategory
local optionsRegistered

local function EnsureOptionsPanel()
    if optionsPanel then
        return optionsPanel
    end

    local panel = CreateFrame("Frame", "LoadoutLockerOptionsPanel")
    panel.name = "LoadoutLocker"
    panel:SetScript("OnShow", function()
        C_Timer.After(0, function()
            if SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
            Menu.Show()
        end)
    end)

    optionsPanel = panel
    return panel
end

function Menu.RegisterWithSettings()
    if optionsRegistered then
        return
    end

    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    local panel = EnsureOptionsPanel()
    optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, "LoadoutLocker")
    optionsCategory.ID = "LoadoutLocker"
    Settings.RegisterAddOnCategory(optionsCategory)
    optionsRegistered = true
end

function Menu.OpenInGameOptions()
    Menu.RegisterWithSettings()
    if optionsCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
    end
end
