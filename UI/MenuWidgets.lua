LoadoutLocker = LoadoutLocker or {}

local Widgets = {}
LoadoutLocker.MenuWidgets = Widgets

local C = LoadoutLocker.Constants

Widgets.Style = {
    sidebarBg = { 0.10, 0.09, 0.08, 0.80 },
    buttonBg = { 0.14, 0.12, 0.10, 0.55 },
    buttonHover = { 0.50, 0.38, 0.14, 0.30 },
    buttonSelected = { 0.62, 0.48, 0.10, 0.45 },
    separator = { 0.48, 0.36, 0.14, 0.50 },
    title = C.UI_TITLE_COLOR,
    panelBg = { 0.12, 0.10, 0.09, 0.75 },
    panelBorder = { 0.48, 0.36, 0.14, 0.40 },
    codeBg = { 0.08, 0.07, 0.06, 0.95 },
    codeBorder = { 0.35, 0.28, 0.18, 0.50 },
}

local Style = Widgets.Style

local DF = _G.DetailsFramework
local OPTIONS_DROPDOWN_TEMPLATE = DF and DF:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE")

local dropdownSerial = 0
local activeDropdowns = {}

local ROW_HEIGHT = 28
local DROPDOWN_WIDTH = 220
local LABEL_WIDTH = 300
local SCROLLBAR_WIDTH = 26
Widgets.SCROLLBAR_WIDTH = SCROLLBAR_WIDTH
local SCROLL_RIGHT_INSET = SCROLLBAR_WIDTH + 4
local PANEL_INSET_X = 4

function Widgets.CreateCloseButton(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -12)
    close:SetScript("OnClick", onClick)
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.label:SetPoint("CENTER")
    close.label:SetText("X")
    close.label:SetTextColor(0.7, 0.65, 0.55)
    close:SetScript("OnEnter", function()
        close.label:SetTextColor(1, 0.88, 0.55)
    end)
    close:SetScript("OnLeave", function()
        close.label:SetTextColor(0.7, 0.65, 0.55)
    end)
    return close
end

function Widgets.CreateDialogFrame(options)
    options = options or {}

    local frame = CreateFrame("Frame", options.name, UIParent, "BackdropTemplate")
    frame:SetSize(options.width or 420, options.height or 330)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(options.frameLevel or 350)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(C.DIALOG_BACKDROP)
    frame:Hide()

    if options.name then
        tinsert(UISpecialFrames, options.name)
    end

    if options.title or options.titleWidth then
        frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        frame.title:SetPoint("TOP", frame, "TOP", 0, options.titleOffsetY or -16)
        frame.title:SetTextColor(Style.title[1], Style.title[2], Style.title[3])
        if options.titleWidth then
            frame.title:SetWidth(options.titleWidth)
            frame.title:SetWordWrap(true)
            frame.title:SetJustifyH("CENTER")
        end
        if options.title then
            frame.title:SetText(options.title)
        end
    end

    if options.onClose then
        Widgets.CreateCloseButton(frame, function()
            options.onClose(frame)
        end)
    end

    return frame
end

function Widgets.ConfigureReadOnlyEditBox(editBox, transparentBackground)
    editBox:SetScript("OnChar", function()
    end)
    if not transparentBackground then
        return
    end
    if editBox.Left then
        editBox.Left:SetAlpha(0)
    end
    if editBox.Middle then
        editBox.Middle:SetAlpha(0)
    end
    if editBox.Right then
        editBox.Right:SetAlpha(0)
    end
end

local PANEL_PAD_TOP = 6
local PANEL_PAD_BOTTOM = 6
local DROPDOWN_MENU_STRATA = "FULLSCREEN_DIALOG"

local function GetDropdownMenuFrameLevel(widget)
    local menuFrame = LoadoutLocker.MenuShell and LoadoutLocker.MenuShell.frame
    if menuFrame and menuFrame:IsShown() then
        return menuFrame:GetFrameLevel() + 50
    end

    return (widget:GetFrameLevel() or 0) + 100
end

local function AnchorDropdownMenu(border, scroll, widget)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 0)
end

local function ElevateDropdownMenu(dropdown)
    local widget = dropdown.widget
    local border = dropdown.dropdown.dropdownborder
    local scroll = dropdown.dropdown.dropdownframe
    local frameLevel = GetDropdownMenuFrameLevel(widget)

    border:SetParent(UIParent)
    scroll:SetParent(UIParent)
    border:SetFrameStrata(DROPDOWN_MENU_STRATA)
    scroll:SetFrameStrata(DROPDOWN_MENU_STRATA)
    border:SetFrameLevel(frameLevel)
    scroll:SetFrameLevel(frameLevel + 1)
    AnchorDropdownMenu(border, scroll, widget)
end

local function RestoreDropdownMenu(dropdown)
    local widget = dropdown.widget
    local border = dropdown.dropdown.dropdownborder
    local scroll = dropdown.dropdown.dropdownframe

    border:SetParent(widget)
    scroll:SetParent(widget)
    border:SetFrameStrata("FULLSCREEN")
    scroll:SetFrameStrata("FULLSCREEN")
    AnchorDropdownMenu(border, scroll, widget)
end

local function CloseDropdownMenu(dropdown, originalClose)
    local border = dropdown.dropdown.dropdownborder
    local scroll = dropdown.dropdown.dropdownframe
    local onHide = border:GetScript("OnHide")

    border:SetScript("OnHide", nil)
    border:Hide()
    scroll:Hide()
    RestoreDropdownMenu(dropdown)
    border:SetScript("OnHide", onHide)

    dropdown.opened = false
    if originalClose then
        originalClose(dropdown)
    end
end

local function TruncateText(text, maxLength)
    if not text or #text <= maxLength then
        return text
    end
    return text:sub(1, maxLength - 3) .. "..."
end

local function OrderedList(map)
    local items = {}
    for key, label in pairs(map) do
        items[#items + 1] = { key = key, label = label }
    end
    table.sort(items, function(a, b)
        if a.key == "" then
            return true
        end
        if b.key == "" then
            return false
        end
        if a.key == "default" then
            return true
        end
        if b.key == "default" then
            return false
        end
        return a.label < b.label
    end)
    return items
end

local function GetScrollBar(scroll)
    if scroll.ScrollBar then
        return scroll.ScrollBar
    end

    local name = scroll:GetName()
    if name then
        return _G[name .. "ScrollBar"]
    end
end

function Widgets.UpdateScrollRange(scroll)
    if not scroll or not scroll.fullWidth then
        return
    end

    local scrollChild = scroll:GetScrollChild()
    if not scrollChild then
        return
    end

    local needsScroll = (scrollChild:GetHeight() or 0) > (scroll:GetHeight() or 0) + 2
    local scrollBar = GetScrollBar(scroll)
    local frameWidth = scroll.keepFrameWidth and (scroll:GetWidth() or scroll.fullWidth) or nil

    if needsScroll then
        local narrowWidth = (frameWidth or scroll.fullWidth) - scroll.scrollbarWidth
        if scroll.keepFrameWidth then
            scrollChild:SetWidth(narrowWidth)
        else
            scroll:SetWidth(narrowWidth)
            scrollChild:SetWidth(narrowWidth)
        end
        if scrollBar then
            scrollBar:Show()
        end
    else
        if scroll.keepFrameWidth then
            scrollChild:SetWidth(frameWidth or scroll.fullWidth)
        else
            scroll:SetWidth(scroll.fullWidth)
            scrollChild:SetWidth(scroll.fullWidth)
        end
        scroll:SetVerticalScroll(0)
        if scrollBar then
            scrollBar:Hide()
        end
    end

    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
end

function Widgets.CreateScroll(parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll.fullWidth = width
    scroll.scrollbarWidth = SCROLLBAR_WIDTH
    scroll:SetSize(width, height)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(width)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local scrollBar = GetScrollBar(scroll)
    if scrollBar then
        scrollBar:Hide()
    end

    return scroll, child
end

function Widgets.ConfigureMenuScroll(scroll, fullWidth)
    scroll.fullWidth = fullWidth
    scroll.keepFrameWidth = true
end

function Widgets.CreateSidebarButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 64,
    })
    btn:SetBackdropColor(unpack(Style.buttonBg))

    btn.hover = btn:CreateTexture(nil, "BACKGROUND")
    btn.hover:SetAllPoints()
    btn.hover:SetColorTexture(unpack(Style.buttonHover))
    btn.hover:Hide()

    btn.selected = btn:CreateTexture(nil, "BACKGROUND")
    btn.selected:SetAllPoints()
    btn.selected:SetColorTexture(unpack(Style.buttonSelected))
    btn.selected:Hide()

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.label:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetText(text)

    btn:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self.hover:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)

    function btn:SetSelected(state)
        self.isSelected = state
        self.selected:SetShown(state)
        self.hover:Hide()
        if state then
            self.label:SetFontObject("GameFontNormal")
            self.label:SetTextColor(unpack(Style.title))
        else
            self.label:SetFontObject("GameFontHighlight")
            self.label:SetTextColor(1, 1, 1)
        end
    end

    return btn
end

function Widgets.CreateHeaderButton(parent, text, width, height)
    local btn = Widgets.CreateSidebarButton(parent, TruncateText(text, 16), width, height)
    btn.fullText = text
    btn.label:SetJustifyH("CENTER")
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    btn:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= self.label:GetText() then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.fullText, 1, 1, 1)
            GameTooltip:Show()
        end
        if not self.isSelected then
            self.hover:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.hover:Hide()
    end)
    return btn
end

function Widgets.NewBuilder(host)
    local parent = CreateFrame("Frame", nil, host)
    parent:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    local width = host:GetWidth()
    if not width or width <= 1 then
        local scroll = host:GetParent()
        width = (scroll and scroll.fullWidth) or 400
    end
    parent:SetWidth(width)
    parent:SetHeight(1)
    return {
        parent = parent,
        y = 0,
        dropdowns = {},
    }
end

function Widgets.AddGap(builder, height)
    builder.y = builder.y + (height or 10)
    return builder
end

function Widgets.AddInsetPanel(builder, buildContent, minHeight, width)
    local maxWidth = builder.parent:GetWidth() - PANEL_INSET_X * 2
    local panel = CreateFrame("Frame", nil, builder.parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", PANEL_INSET_X, -builder.y)
    panel:SetWidth(width or maxWidth)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    panel:SetBackdropColor(unpack(Style.panelBg))
    panel:SetBackdropBorderColor(unpack(Style.panelBorder))

    local inner = Widgets.NewBuilder(panel)
    inner.y = PANEL_PAD_TOP
    buildContent(inner)

    local contentHeight = inner.y + PANEL_PAD_BOTTOM
    if minHeight then
        contentHeight = math.max(contentHeight, minHeight)
    end

    panel:SetHeight(contentHeight)
    builder.y = builder.y + contentHeight + 4
    return builder, panel
end

function Widgets.AddLabel(builder, text, fontObject)
    local label = builder.parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    label:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    label:SetWidth(builder.parent:GetWidth() - 8)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(text)
    builder.y = builder.y + (label:GetStringHeight() or 16) + 6
    return builder
end

function Widgets.AddSeparator(builder)
    local line = builder.parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(Style.separator))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    line:SetPoint("TOPRIGHT", builder.parent, "TOPRIGHT", -4, -builder.y)
    builder.y = builder.y + 12
    return builder
end

function Widgets.AddTabIntro(builder, text)
    Widgets.AddLabel(builder, text)
    Widgets.AddGap(builder, 10)
    return builder
end

function Widgets.AddHeading(builder, text)
    return Widgets.AddLabel(builder, text, "GameFontNormalLarge")
end

function Widgets.AddCheckbox(builder, labelText, checked, onChanged)
    local check = CreateFrame("CheckButton", nil, builder.parent, "ChatConfigCheckButtonTemplate")
    check:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    check:SetChecked(checked)
    check.Text:SetText(labelText)
    check.Text:SetWidth(builder.parent:GetWidth() - 40)
    check:SetScript("OnClick", function(self)
        onChanged(self:GetChecked())
    end)
    builder.y = builder.y + ROW_HEIGHT + 4
    return builder
end

function Widgets.AddButton(builder, text, width, onClick, disabled)
    local button = CreateFrame("Button", nil, builder.parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    button:SetText(text)
    button:SetEnabled(not disabled)
    button:SetScript("OnClick", onClick)
    builder.y = builder.y + 30
    return builder
end

function Widgets.CreateDropdown(parent, width)
    dropdownSerial = dropdownSerial + 1
    local name = "LoadoutLockerMenuDropDown" .. dropdownSerial
    local dropdown
    dropdown = DF:CreateDropDown(parent, function()
        local options = {}
        for _, item in ipairs(dropdown.items) do
            local key = item.key
            options[#options + 1] = {
                label = item.label,
                value = key,
                onclick = function(dropdownObject, _, value)
                    if dropdownObject.disabled then
                        return
                    end
                    dropdownObject.selectedKey = value
                    if dropdownObject.onSelect then
                        dropdownObject.onSelect(value)
                    end
                end,
            }
        end
        return options
    end, false, width or DROPDOWN_WIDTH, 20, nil, name)

    dropdown:SetTemplate(OPTIONS_DROPDOWN_TEMPLATE)
    dropdown.items = {}
    dropdown.selectedKey = ""
    dropdown.disabled = false

    function dropdown:SetItems(map, selectedKey)
        self.items = OrderedList(map)
        self.selectedKey = selectedKey or ""
        self:Select(self.selectedKey, false, false, false)
        self:Refresh()
    end

    function dropdown:SetDisabled(state)
        self.disabled = state
        if state then
            self:Disable()
        else
            self:Enable()
        end
    end

    dropdown.refreshText = function()
        dropdown:Select(dropdown.selectedKey, false, false, false)
    end

    dropdown.OnMouseDownHook = function()
        ElevateDropdownMenu(dropdown)
    end

    local originalClose = dropdown.Close
    function dropdown:Close()
        CloseDropdownMenu(self, originalClose)
    end

    activeDropdowns[#activeDropdowns + 1] = dropdown
    return dropdown
end

function Widgets.CloseAllDropdowns()
    for i = #activeDropdowns, 1, -1 do
        local dropdown = activeDropdowns[i]
        if dropdown and dropdown.Close then
            dropdown:Close()
        end
    end
    wipe(activeDropdowns)
end

function Widgets.AddDropdown(builder, width, list, value, onSelect)
    local dropdown = Widgets.CreateDropdown(builder.parent, width or DROPDOWN_WIDTH)
    dropdown:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    dropdown.onSelect = onSelect
    dropdown:SetItems(list, value)
    builder.dropdowns[#builder.dropdowns + 1] = dropdown
    builder.y = builder.y + 34
    return builder, dropdown
end

function Widgets.AddDropdownButtonRow(builder, dropdownWidth, list, value, onSelect, buttonText, buttonWidth, onClick, buttonDisabled)
    local row = CreateFrame("Frame", nil, builder.parent)
    row:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 4, -builder.y)
    row:SetSize(builder.parent:GetWidth() - 8, 26)

    local dropdown = Widgets.CreateDropdown(row, dropdownWidth or DROPDOWN_WIDTH)
    dropdown:SetPoint("LEFT", row, "LEFT", 0, 0)
    dropdown.onSelect = onSelect
    dropdown:SetItems(list, value)

    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(buttonWidth or 120, 22)
    button:SetPoint("LEFT", dropdown.widget, "RIGHT", 8, 0)
    button:SetText(buttonText)
    button:SetEnabled(not buttonDisabled)
    button:SetScript("OnClick", onClick)

    builder.y = builder.y + 34
    return builder, dropdown, button
end

function Widgets.AddSlotClearRow(builder, labelText, onClear)
    local row = CreateFrame("Frame", nil, builder.parent)
    row:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 0, -builder.y)
    row:SetSize(builder.parent:GetWidth(), ROW_HEIGHT)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetWidth(math.max(72, row:GetWidth() - 84))
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(64, 22)
    button:SetPoint("LEFT", label, "RIGHT", 8, 0)
    button:SetText("Clear")
    button:SetScript("OnClick", onClear)

    builder.y = builder.y + ROW_HEIGHT + 2
    return builder
end

function Widgets.AddAssignmentRow(builder, labelText, getState, onSelect)
    local value, list = getState()
    local row = CreateFrame("Frame", nil, builder.parent)
    row:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 0, -builder.y)
    row:SetSize(builder.parent:GetWidth(), ROW_HEIGHT)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local dropdown = Widgets.CreateDropdown(row, DROPDOWN_WIDTH)
    dropdown:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    dropdown.onSelect = onSelect
    dropdown:SetItems(list, value)

    function dropdown:Refresh()
        local newValue, newList = getState()
        self:SetItems(newList, newValue)
    end

    builder.y = builder.y + ROW_HEIGHT + 2
    return dropdown
end

local OVERVIEW_SPEC_WIDTH = 0.20
local OVERVIEW_NAME_WIDTH = 0.38
local OVERVIEW_EM_WIDTH = 0.42
local OVERVIEW_MAX_LIST_HEIGHT = ROW_HEIGHT * 6 + 10

local function AddOverviewColumnText(row, text, x, width, fontObject, color)
    local label = row:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", x, 0)
    label:SetWidth(math.max(40, width - 4))
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    if color then
        label:SetTextColor(unpack(color))
    end
    label:SetText(TruncateText(text, 42) or text)
    return label
end

function Widgets.AddLoadoutOverviewTable(builder, rows)
    local parent = builder.parent
    local listWidth = parent:GetWidth() - SCROLL_RIGHT_INSET - 4
    local specWidth = math.floor(listWidth * OVERVIEW_SPEC_WIDTH)
    local nameWidth = math.floor(listWidth * OVERVIEW_NAME_WIDTH)
    local emWidth = listWidth - specWidth - nameWidth - 8
    local specX = 4
    local nameX = specX + specWidth
    local emX = nameX + nameWidth
    local headerColor = Style.title
    local separatorGap = 12
    local bottomGap = 8

    local innerY = 0
    if not rows or #rows == 0 then
        innerY = ROW_HEIGHT
    else
        innerY = #rows * (ROW_HEIGHT + 2)
    end

    local listHeight = math.min(math.max(innerY, 1), OVERVIEW_MAX_LIST_HEIGHT)
    local blockHeight = ROW_HEIGHT + separatorGap + listHeight + bottomGap

    local block = CreateFrame("Frame", nil, parent)
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -builder.y)
    block:SetSize(listWidth, blockHeight)

    local header = CreateFrame("Frame", nil, block)
    header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    header:SetSize(listWidth, ROW_HEIGHT)
    AddOverviewColumnText(header, "Spec", specX, specWidth, "GameFontNormalSmall", headerColor)
    AddOverviewColumnText(header, "Talent name", nameX, nameWidth, "GameFontNormalSmall", headerColor)
    AddOverviewColumnText(header, "Equipment set", emX, emWidth, "GameFontNormalSmall", headerColor)

    local line = block:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(Style.separator))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", block, "TOPLEFT", 4, -ROW_HEIGHT)
    line:SetPoint("TOPRIGHT", block, "TOPRIGHT", -4, -ROW_HEIGHT)

    local scroll, scrollChild = Widgets.CreateScroll(block, listWidth, listHeight)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(ROW_HEIGHT + separatorGap))
    Widgets.ConfigureMenuScroll(scroll, listWidth)

    innerY = 0
    if not rows or #rows == 0 then
        local emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        emptyLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -innerY)
        emptyLabel:SetWidth(listWidth - 8)
        emptyLabel:SetJustifyH("LEFT")
        emptyLabel:SetText("No saved gear sets.")
        innerY = innerY + ROW_HEIGHT
    else
        for _, rowData in ipairs(rows) do
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -innerY)
            row:SetSize(listWidth, ROW_HEIGHT)

            local nameText = rowData.name
            if rowData.isActive then
                nameText = nameText .. " (active)"
            end
            local nameColor = rowData.isActive and Style.title or nil
            AddOverviewColumnText(row, rowData.specName or "—", specX, specWidth, "GameFontHighlightSmall", nameColor)
            AddOverviewColumnText(row, nameText, nameX, nameWidth, "GameFontHighlight", nameColor)

            local emName = rowData.equipmentSetName
            if not emName or emName == "" then
                emName = "—"
            end
            AddOverviewColumnText(row, emName, emX, emWidth, "GameFontHighlightSmall")

            innerY = innerY + ROW_HEIGHT + 2
        end
    end

    scrollChild:SetHeight(math.max(innerY, 1))
    scroll:SetHeight(listHeight)
    Widgets.UpdateScrollRange(scroll)

    builder.y = builder.y + blockHeight
    return builder
end

function Widgets.AddPriorityRow(builder, rank, labelText, onUp, onDown, upDisabled, downDisabled)
    local row = CreateFrame("Frame", nil, builder.parent)
    row:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", 0, -builder.y)
    row:SetSize(builder.parent:GetWidth(), ROW_HEIGHT)

    local rankLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankLabel:SetPoint("LEFT", row, "LEFT", 4, 0)
    rankLabel:SetWidth(24)
    rankLabel:SetText(rank .. ".")

    local statLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statLabel:SetPoint("LEFT", rankLabel, "RIGHT", 4, 0)
    statLabel:SetWidth(220)
    statLabel:SetJustifyH("LEFT")
    statLabel:SetText(labelText)

    local upButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    upButton:SetSize(52, 22)
    upButton:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    upButton:SetText("Up")
    upButton:SetEnabled(not upDisabled)
    upButton:SetScript("OnClick", onUp)

    local downButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    downButton:SetSize(52, 22)
    downButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    downButton:SetText("Down")
    downButton:SetEnabled(not downDisabled)
    downButton:SetScript("OnClick", onDown)

    builder.y = builder.y + ROW_HEIGHT + 2

    function row:Refresh(newRank, newLabelText, newUpDisabled, newDownDisabled)
        rankLabel:SetText(newRank .. ".")
        statLabel:SetText(newLabelText)
        upButton:SetEnabled(not newUpDisabled)
        downButton:SetEnabled(not newDownDisabled)
    end

    return builder, row
end

function Widgets.AddEmptyDropdown(builder, width, message, disabled)
    local nextBuilder, dropdown = Widgets.AddDropdown(builder, width or DROPDOWN_WIDTH, { [""] = message }, "")
    if disabled then
        dropdown:SetDisabled(true)
    end
    return nextBuilder, dropdown
end

function Widgets.FinishBuilder(builder)
    local height = math.max(builder.y + 16, 1)
    local host = builder.parent:GetParent()
    builder.parent:SetHeight(height)
    if not host then
        return builder
    end

    host:SetHeight(height)
    local scroll = host:GetParent()
    if scroll and scroll.GetScrollChild and scroll:GetScrollChild() == host then
        Widgets.UpdateScrollRange(scroll)
        builder.parent:SetWidth(host:GetWidth())
    end
    return builder
end
