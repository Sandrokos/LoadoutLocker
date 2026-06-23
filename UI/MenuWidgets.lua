LoadoutLocker = LoadoutLocker or {}

local Widgets = {}
LoadoutLocker.MenuWidgets = Widgets

Widgets.Style = {
    sidebarBg = { 0.10, 0.09, 0.08, 0.80 },
    buttonBg = { 0.14, 0.12, 0.10, 0.55 },
    buttonHover = { 0.50, 0.38, 0.14, 0.30 },
    buttonSelected = { 0.62, 0.48, 0.10, 0.45 },
    separator = { 0.48, 0.36, 0.14, 0.50 },
    title = { 1, 0.82, 0.35 },
    panelBg = { 0.12, 0.10, 0.09, 0.75 },
    panelBorder = { 0.48, 0.36, 0.14, 0.40 },
}

local Style = Widgets.Style

local DF = _G.DetailsFramework
local OPTIONS_DROPDOWN_TEMPLATE = DF and DF:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE")

local dropdownSerial = 0

local ROW_HEIGHT = 28
local DROPDOWN_WIDTH = 220
local LABEL_WIDTH = 300
local SCROLLBAR_WIDTH = 26
local PANEL_INSET_X = 4
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

    if needsScroll then
        local narrowWidth = scroll.fullWidth - scroll.scrollbarWidth
        scroll:SetWidth(narrowWidth)
        scrollChild:SetWidth(narrowWidth)
        if scrollBar then
            scrollBar:Show()
        end
    else
        scroll:SetWidth(scroll.fullWidth)
        scrollChild:SetWidth(scroll.fullWidth)
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

function Widgets.NewBuilder(scrollChild)
    return {
        parent = scrollChild,
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
    line:SetColorTexture(0.45, 0.38, 0.22, 0.45)
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

    return dropdown
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
    builder.parent:SetHeight(height)
    Widgets.UpdateScrollRange(builder.parent:GetParent())
    return builder
end
