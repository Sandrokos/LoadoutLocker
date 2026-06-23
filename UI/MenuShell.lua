LoadoutLocker = LoadoutLocker or {}

local Shell = {}
LoadoutLocker.MenuShell = Shell

local Widgets = LoadoutLocker.MenuWidgets
local Style = Widgets.Style

local FRAME_WIDTH = 820
local FRAME_HEIGHT = 640
local FRAME_INSET_LEFT = 14
local FRAME_INSET_RIGHT = 18
local FRAME_INSET_TOP = 36
local FRAME_INSET_BOTTOM = 18
local SIDEBAR_WIDTH = 148
local CONTENT_X = FRAME_INSET_LEFT + SIDEBAR_WIDTH + 8
local CONTENT_WIDTH = FRAME_WIDTH - CONTENT_X - FRAME_INSET_RIGHT
local CONTENT_HEIGHT = FRAME_HEIGHT - FRAME_INSET_TOP - FRAME_INSET_BOTTOM
local SUB_BAR_ROW_HEIGHT = 28
local SUB_BAR_ROW_GAP = 4
local SUB_BAR_HEIGHT = SUB_BAR_ROW_HEIGHT * 2 + SUB_BAR_ROW_GAP
local DUNGEON_HEADER_HEIGHT = 78

local MAIN_TABS = {
    { id = "general", label = "General" },
    { id = "priority", label = "Priority" },
    { id = "loadouts", label = "Loadouts" },
    { id = "dungeons", label = "Dungeons" },
    { id = "raids", label = "Raids" },
}

local function ClearChildren(frame)
    local children = { frame:GetChildren() }
    for i = #children, 1, -1 do
        children[i]:Hide()
        children[i]:SetParent(nil)
    end
end

function Shell:ClearFrame(frame)
    if frame then
        ClearChildren(frame)
    end
end

function Shell:ClearScroll(scrollChild)
    if scrollChild then
        ClearChildren(scrollChild)
        scrollChild:SetHeight(1)
        Widgets.UpdateScrollRange(scrollChild:GetParent())
    end
end

function Shell:EnsurePlainContent(tabFrame)
    if tabFrame.scrollChild then
        return tabFrame
    end

    local width = tabFrame:GetWidth()
    local height = tabFrame:GetHeight()
    local scroll, scrollChild = Widgets.CreateScroll(tabFrame, width, height)
    tabFrame.scroll = scroll
    tabFrame.scrollChild = scrollChild
    return tabFrame
end

function Shell:EnsureDungeonContent(tabFrame)
    if tabFrame.header then
        return tabFrame
    end

    local width = tabFrame:GetWidth()
    local height = tabFrame:GetHeight()
    local listHeight = height - SUB_BAR_HEIGHT - DUNGEON_HEADER_HEIGHT - 12

    local subBar = CreateFrame("Frame", nil, tabFrame)
    subBar:SetPoint("TOPLEFT", tabFrame, "TOPLEFT", 0, 0)
    subBar:SetSize(width, SUB_BAR_HEIGHT)

    local header = CreateFrame("Frame", nil, tabFrame)
    header:SetPoint("TOPLEFT", subBar, "BOTTOMLEFT", 0, -6)
    header:SetSize(width, DUNGEON_HEADER_HEIGHT)

    local scroll, scrollChild = Widgets.CreateScroll(tabFrame, width, listHeight)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)

    tabFrame.subBar = subBar
    tabFrame.header = header
    tabFrame.scroll = scroll
    tabFrame.scrollChild = scrollChild
    return tabFrame
end

function Shell:Ensure()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "LoadoutLockerMenu", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    tinsert(UISpecialFrames, frame:GetName())

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
    frame.title:SetText("LoadoutLocker")
    frame.title:SetTextColor(unpack(Style.title))

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -12)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
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

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_INSET_LEFT, -FRAME_INSET_TOP)
    sidebar:SetSize(SIDEBAR_WIDTH, CONTENT_HEIGHT)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 64,
    })
    sidebar:SetBackdropColor(unpack(Style.sidebarBg))

    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(unpack(Style.separator))
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_X - 2, -FRAME_INSET_TOP)
    separator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CONTENT_X - 2, FRAME_INSET_BOTTOM)

    self.tabButtons = {}
    self.tabContents = {}

    local y = -6
    for _, tab in ipairs(MAIN_TABS) do
        local button = Widgets.CreateSidebarButton(sidebar, tab.label, SIDEBAR_WIDTH - 10, 24)
        button:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, y)
        button.tabID = tab.id
        button:SetScript("OnClick", function()
            Shell:SelectTab(tab.id)
        end)
        self.tabButtons[tab.id] = button
        y = y - 24

        local tabFrame = CreateFrame("Frame", nil, frame)
        tabFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_X, -FRAME_INSET_TOP)
        tabFrame:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
        tabFrame:Hide()
        self.tabContents[tab.id] = tabFrame
    end

    self.frame = frame
    self.activeTab = nil
end

function Shell:SetOnTabSelected(callback)
    self.onTabSelected = callback
end

function Shell:SelectTab(tabID, options)
    options = options or {}
    self:Ensure()

    tabID = tabID or self.activeTab or "general"
    local tabChanged = self.activeTab ~= tabID

    if tabChanged then
        if self.activeTab and self.tabButtons[self.activeTab] then
            self.tabButtons[self.activeTab]:SetSelected(false)
            self.tabContents[self.activeTab]:Hide()
        end

        self.tabButtons[tabID]:SetSelected(true)
        self.tabContents[tabID]:Show()
        self.activeTab = tabID
    end

    if self.onTabSelected and (tabChanged or options.force) then
        self.onTabSelected(self.tabContents[tabID], tabID)
    end
end

function Shell:RefreshTab(tabID)
    self:SelectTab(tabID or self.activeTab, { force = true })
end

function Shell:Show(tabID)
    self:Ensure()
    self:SelectTab(tabID or self.activeTab or "general")
    self.frame:Show()
end

function Shell:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function Shell:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end
