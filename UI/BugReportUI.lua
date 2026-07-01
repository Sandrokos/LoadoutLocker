LoadoutLocker = LoadoutLocker or {}

local BugReportUI = {}
LoadoutLocker.BugReportUI = BugReportUI

local C = LoadoutLocker.Constants
local Dungeons = LoadoutLocker.Dungeons
local Delves = LoadoutLocker.Delves
local PvP = LoadoutLocker.PvP
local Instance = LoadoutLocker.Instance
local Loadout = LoadoutLocker.Loadout
local Widgets = LoadoutLocker.MenuWidgets
local Style = Widgets.Style
local DB = LoadoutLocker.DB

local GITHUB_ISSUES_URL = "https://github.com/Sandrokos/LoadoutLocker/issues"
local MAX_CAPTURED_ERRORS = 1
local DEBUG_SCROLL_WIDTH = 340
local DEBUG_SCROLL_HEIGHT = 120
local DEBUG_BOX_INSET = 6

local reportFrame
local capturedErrors = {}
local lastScriptErrorText
local errorHandlerInstalled

local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata("LoadoutLocker", "Version") or "unknown"
    end
    return "unknown"
end

local function UpdateDebugScrollHeight(editBox, scrollFrame)
    local width = scrollFrame:GetWidth()
    if width > 0 then
        editBox:SetWidth(width)
    end

    local _, fontSize = editBox:GetFont()
    fontSize = fontSize or 12
    local text = editBox:GetText() or ""
    local lineCount = 1
    for _ in string.gmatch(text, "\n") do
        lineCount = lineCount + 1
    end

    local height = math.max(DEBUG_SCROLL_HEIGHT, lineCount * (fontSize + 2) + 8)
    editBox:SetHeight(height)
    scrollFrame:UpdateScrollChildRect()
end

local function AppendZoneLines(lines, instanceInfo)
    local zoneNames = Instance.CollectZoneNames(instanceInfo)
    if #zoneNames > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "zoneNames:"
        for _, zoneName in ipairs(zoneNames) do
            lines[#lines + 1] = "  " .. zoneName
        end
    end
end

local function AppendInstanceLines(lines, instanceInfo)
    lines[#lines + 1] = "inInstance: " .. tostring(instanceInfo.inInstance)
    lines[#lines + 1] = "instanceType: " .. tostring(instanceInfo.instanceType)
    lines[#lines + 1] = "instanceName: " .. tostring(instanceInfo.name)
    lines[#lines + 1] = "instanceID: " .. tostring(instanceInfo.instanceID)
    lines[#lines + 1] = "difficultyID: " .. tostring(instanceInfo.difficultyID)
    lines[#lines + 1] = "zone: " .. tostring(GetZoneText()) .. " / " .. tostring(GetSubZoneText())
    lines[#lines + 1] = "realZone: " .. tostring(GetRealZoneText())
end

local function AppendLoadoutLine(lines, label, configID)
    lines[#lines + 1] = label .. ": " .. tostring(configID)
        .. " (" .. tostring(configID and Loadout.GetLoadoutName(configID)) .. ")"
end

local function AppendLoadoutRefLine(lines, label, ref)
    if not ref then
        lines[#lines + 1] = label .. ": nil"
        return
    end

    if type(ref) == "table" then
        lines[#lines + 1] = label .. ": "
            .. Loadout.FormatLoadoutLabel(ref.specID, Loadout.GetLoadoutName(ref.configID))
            .. " [" .. tostring(ref.specID) .. ":" .. tostring(ref.configID) .. "]"
        return
    end

    lines[#lines + 1] = label .. ": " .. tostring(ref)
        .. " (" .. tostring(Loadout.GetLoadoutName(ref)) .. ")"
end

local function AppendSimpleContentSection(lines, heading, active, resolvedKey, entityName, promptsEnabled, defaultRef, assignedRef)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "--- " .. heading .. " ---"
    lines[#lines + 1] = "active: " .. tostring(active)
    lines[#lines + 1] = "resolvedKey: " .. tostring(resolvedKey)
    lines[#lines + 1] = "resolvedName: " .. tostring(entityName)
    lines[#lines + 1] = "promptsEnabled: " .. tostring(promptsEnabled)
    AppendLoadoutRefLine(lines, "defaultLoadout", defaultRef)
    AppendLoadoutRefLine(lines, "assignedLoadout", assignedRef)
end

local function GetScriptErrorFrameText()
    local scriptErrors = _G.ScriptErrorsFrame
    if scriptErrors then
        local textWidget = scriptErrors.ScrollFrame and scriptErrors.ScrollFrame.Text
        if textWidget and textWidget.GetText then
            local text = textWidget:GetText()
            if text and text ~= "" then
                return text
            end
        end

        if scriptErrors.error and scriptErrors.error.GetText then
            local text = scriptErrors.error:GetText()
            if text and text ~= "" then
                return text
            end
        end
    end

    return lastScriptErrorText
end

local function RememberCapturedError(message, trace)
    capturedErrors[#capturedErrors + 1] = {
        time = date("%Y-%m-%d %H:%M:%S"),
        msg = tostring(message),
        trace = trace or "",
    }
    while #capturedErrors > MAX_CAPTURED_ERRORS do
        table.remove(capturedErrors, 1)
    end
end

local function FormatCapturedError(entry)
    local lines = {
        string.format("[%s]", entry.time),
        entry.msg,
    }
    if entry.trace and entry.trace ~= "" then
        lines[#lines + 1] = entry.trace
    end
    return table.concat(lines, "\n")
end

local function GetLastLuaErrorText()
    local entry = capturedErrors[#capturedErrors]
    if entry then
        return FormatCapturedError(entry)
    end

    return GetScriptErrorFrameText()
end

local function AppendLastLuaError(lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "--- Last Lua error ---"
    local errorText = GetLastLuaErrorText()
    if errorText and errorText ~= "" then
        lines[#lines + 1] = errorText
    else
        lines[#lines + 1] = "(none captured)"
    end
end

local function EnsureDebugTextWithError(text)
    if not text or text == "" then
        return BugReportUI.BuildDebugText()
    end

    if text:find("--- Last Lua error ---", 1, true) then
        return text
    end

    local lines = { text }
    AppendLastLuaError(lines)
    return table.concat(lines, "\n")
end

local function RefreshDebugPanel(frame, text)
    frame.debugStoredText = EnsureDebugTextWithError(text)
    frame.debugEditBox:SetText(frame.debugStoredText)
    C_Timer.After(0, function()
        if frame:IsShown() then
            UpdateDebugScrollHeight(frame.debugEditBox, frame.debugScroll)
        end
    end)
end

function BugReportUI.BuildDebugText()
    local instanceInfo = Instance.GetCurrent()
    local specID = Loadout.GetSpecID()
    local currentConfigID = specID and Loadout.GetLoadoutConfigID(specID) or nil
    local lines = {
        "Debug report",
        "",
        "addonVersion: " .. GetAddonVersion(),
    }

    AppendInstanceLines(lines, instanceInfo)
    AppendZoneLines(lines, instanceInfo)
    lines[#lines + 1] = "specID: " .. tostring(specID)
    AppendLoadoutLine(lines, "currentConfigID", currentConfigID)

    local dungeonKey, dungeon = Dungeons.ResolveCurrent(instanceInfo)
    local delveKey, delve = Delves.ResolveCurrent(instanceInfo)
    local pvpKey, pvpMode = PvP.ResolveCurrent(instanceInfo)

    AppendSimpleContentSection(
        lines,
        "Dungeons",
        Dungeons.IsInDungeonInstance(instanceInfo),
        dungeonKey,
        dungeon and dungeon.name,
        DB:AreDungeonPromptsEnabled(),
        DB:GetDungeonDefaultLoadoutRef(),
        dungeonKey and DB:GetDungeonLoadoutRef(dungeonKey)
    )

    local raidUI = LoadoutLocker.RaidUI
    if raidUI and raidUI.AppendDebugLines then
        raidUI.AppendDebugLines(lines, instanceInfo, specID)
    end

    AppendSimpleContentSection(
        lines,
        "Delves",
        Delves.IsInDelveInstance(instanceInfo),
        delveKey,
        delve and delve.name,
        DB:AreDelvePromptsEnabled(),
        DB:GetDelveDefaultLoadoutRef(),
        delveKey and DB:GetDelveLoadoutRef(delveKey)
    )

    AppendSimpleContentSection(
        lines,
        "PvP",
        PvP.IsInPvPInstance(instanceInfo),
        pvpKey,
        pvpMode and pvpMode.name,
        DB:ArePvPPromptsEnabled(),
        DB:GetPvPDefaultLoadoutRef(),
        pvpKey and DB:GetPvPLoadoutRef(pvpKey)
    )

    AppendLastLuaError(lines)

    return table.concat(lines, "\n")
end

local function HookScriptErrorsFrame()
    local frame = _G.ScriptErrorsFrame
    if not frame or frame.LoadoutLockerErrorHooked then
        return
    end

    frame.LoadoutLockerErrorHooked = true

    if frame.Display then
        hooksecurefunc(frame, "Display", function(_, message)
            if not message or message == "" then
                return
            end

            lastScriptErrorText = tostring(message)
            RememberCapturedError(message, debugstack and debugstack(2) or "")
        end)
    end
end

function BugReportUI.InstallErrorCapture()
    HookScriptErrorsFrame()

    if errorHandlerInstalled then
        return
    end

    local originalHandler = geterrorhandler and geterrorhandler()
    if not originalHandler then
        return
    end

    errorHandlerInstalled = true

    seterrorhandler(function(message)
        RememberCapturedError(message, debugstack(2))
        return originalHandler(message)
    end)
end

local function EnsureReportFrame()
    if reportFrame then
        return reportFrame
    end

    local frameWidth = 420
    local frame = CreateFrame("Frame", "LoadoutLockerBugReportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(frameWidth, 330)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(350)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(C.DIALOG_BACKDROP)
    frame:Hide()

    tinsert(UISpecialFrames, frame:GetName())

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("Bug Report & Feedback")

    Widgets.CreateCloseButton(frame, function()
        frame:Hide()
    end)

    local intro = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
    intro:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -40)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText("Copy the GitHub link below to submit feedback. Attach the debug info from the text area.")

    local linkBox = CreateFrame("EditBox", nil, frame)
    linkBox:SetAutoFocus(false)
    linkBox:EnableMouse(true)
    linkBox:SetFontObject("GameFontHighlight")
    linkBox:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    linkBox:SetPoint("TOPRIGHT", intro, "BOTTOMRIGHT", 0, -10)
    linkBox:SetHeight(20)
    linkBox:SetJustifyH("LEFT")
    linkBox:SetMaxLetters(0)
    linkBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    Widgets.ConfigureReadOnlyEditBox(linkBox)
    linkBox:SetText(GITHUB_ISSUES_URL)

    local debugHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    debugHint:SetPoint("TOPLEFT", linkBox, "BOTTOMLEFT", 0, -14)
    debugHint:SetPoint("TOPRIGHT", linkBox, "BOTTOMRIGHT", 0, -14)
    debugHint:SetJustifyH("LEFT")
    debugHint:SetWordWrap(true)
    debugHint:SetText("Click the debug text below, then press Ctrl+A and Ctrl+C to copy.")

    local debugBackground = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    debugBackground:SetSize(DEBUG_SCROLL_WIDTH + 24, DEBUG_SCROLL_HEIGHT + (DEBUG_BOX_INSET * 2))
    debugBackground:SetPoint("TOP", debugHint, "BOTTOM", 0, -10)
    debugBackground:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    debugBackground:SetBackdropColor(unpack(Style.codeBg))
    debugBackground:SetBackdropBorderColor(unpack(Style.codeBorder))

    local debugScroll = CreateFrame("ScrollFrame", nil, debugBackground, "UIPanelScrollFrameTemplate")
    debugScroll:SetPoint("TOPLEFT", debugBackground, "TOPLEFT", DEBUG_BOX_INSET, -DEBUG_BOX_INSET)
    debugScroll:SetPoint("BOTTOMRIGHT", debugBackground, "BOTTOMRIGHT", -DEBUG_BOX_INSET, DEBUG_BOX_INSET)

    local debugEditBox = CreateFrame("EditBox", nil, debugScroll)
    debugEditBox:SetMultiLine(true)
    debugEditBox:SetAutoFocus(false)
    debugEditBox:EnableMouse(true)
    debugEditBox:SetFontObject("GameFontHighlightSmall")
    debugEditBox:SetJustifyH("LEFT")
    debugEditBox:SetMaxLetters(0)
    debugEditBox:SetWidth(DEBUG_SCROLL_WIDTH)
    debugEditBox:SetHeight(DEBUG_SCROLL_HEIGHT)
    debugEditBox:SetTextInsets(4, 4, 4, 4)
    debugEditBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    Widgets.ConfigureReadOnlyEditBox(debugEditBox, true)
    debugEditBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.debugStoredText then
            self:SetText(frame.debugStoredText)
            return
        end
        UpdateDebugScrollHeight(self, debugScroll)
    end)

    debugScroll:SetScrollChild(debugEditBox)

    frame.linkBox = linkBox
    frame.debugScroll = debugScroll
    frame.debugEditBox = debugEditBox
    frame.debugStoredText = ""
    reportFrame = frame
    return frame
end

local function OpenReport(options)
    options = options or {}
    local menuShell = LoadoutLocker.MenuShell
    if menuShell then
        menuShell:Hide()
    end
    local frame = EnsureReportFrame()
    RefreshDebugPanel(frame, options.text)
    frame:Show()
    C_Timer.After(0, function()
        if not frame:IsShown() then
            return
        end
        if options.focusDebug and frame.debugEditBox then
            frame.debugEditBox:SetFocus()
            return
        end
        if frame.linkBox then
            frame.linkBox:SetFocus()
            frame.linkBox:HighlightText()
        end
    end)
end

function BugReportUI.Show()
    OpenReport()
end

function BugReportUI.ShowDebugOutput(text)
    OpenReport({ text = text, focusDebug = true })
end
