LoadoutLocker = LoadoutLocker or {}
local PromptUtils = {}
LoadoutLocker.PromptUtils = PromptUtils
local C = LoadoutLocker.Constants
local Loadout = LoadoutLocker.Loadout
local Print = LoadoutLocker.Print

function PromptUtils.PrintSwitchFailure(reason)
    if reason == "error" then
        Print("Could not switch talent loadout.")
    elseif reason == "combat" then
        Print("Cannot switch specialization or loadout in combat.")
    elseif reason == "spec" then
        Print("Could not switch specialization.")
    elseif reason == "talent" then
        Print("Could not switch talent loadout after specialization change.")
    elseif reason == "cancelled" then
        Print("Loadout switch cancelled.")
    elseif reason == "timeout" then
        Print("Loadout switch timed out. Please try again.")
    elseif reason ~= "unchanged" then
        Print("Talent loadout switch is not available right now.")
    end
end

local pendingPromptSwitch
local switchMonitorFrame

local function ClearPendingLoadoutSwitchState()
    Loadout.ClearAwaitingTalentSwitchAfterSpec()
    Loadout.ClearPendingSwitch()
end

local function FailWaitingSpecSwitch(reason)
    if not pendingPromptSwitch or not pendingPromptSwitch.waitingForSpec then
        return
    end

    if Loadout.IsAwaitingTalentSwitchAfterSpec() then
        local awaiting = Loadout.GetAwaitingTalentSwitchAfterSpec()
        if awaiting and Loadout.GetSpecID() == awaiting.specID then
            return
        end
    end

    ClearPendingLoadoutSwitchState()
    PromptUtils.FailPendingPromptSwitch(reason or "cancelled")
end

local function EnsureSwitchMonitor()
    if switchMonitorFrame then
        return
    end

    switchMonitorFrame = CreateFrame("Frame")
    switchMonitorFrame:RegisterEvent("PLAYER_STARTED_MOVING")
    switchMonitorFrame:SetScript("OnEvent", function()
        if not pendingPromptSwitch or not pendingPromptSwitch.waitingForSpec then
            return
        end

        C_Timer.After(0.2, function()
            FailWaitingSpecSwitch("cancelled")
        end)
    end)
end

local function HidePromptButtons(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsObjectType("Button") and child:IsShown() then
            child:Disable()
            child:Hide()
        end
    end
end

local DOT_SPINNER_COUNT = 8
local DOT_SPINNER_SIZE = 5
local DOT_SPINNER_RADIUS = 13
local DOT_SPINNER_STEP_TIME = 0.07
local DOT_SPINNER_COLOR_FALLBACK = { 1, 0.82, 0.35 }

local function GetSpinnerColor()
    local style = LoadoutLocker.MenuWidgets and LoadoutLocker.MenuWidgets.Style
    if style and style.title then
        return style.title
    end
    return DOT_SPINNER_COLOR_FALLBACK
end

local function CreateDotSpinner(spinner)
    spinner.dots = {}
    for index = 1, DOT_SPINNER_COUNT do
        local angle = (index - 1) * (2 * math.pi / DOT_SPINNER_COUNT)
        local dot = spinner:CreateTexture(nil, "OVERLAY")
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        dot:SetSize(DOT_SPINNER_SIZE, DOT_SPINNER_SIZE)
        dot:SetPoint(
            "CENTER",
            spinner,
            "CENTER",
            math.cos(angle) * DOT_SPINNER_RADIUS,
            math.sin(angle) * DOT_SPINNER_RADIUS
        )
        spinner.dots[index] = dot
    end
    spinner.activeIndex = 1
end

local function UpdateDotSpinner(spinner)
    local color = spinner.spinnerColor
    for index, dot in ipairs(spinner.dots) do
        local trail = (spinner.activeIndex - index) % DOT_SPINNER_COUNT
        local alpha = math.max(0.18, 1 - (trail * 0.11))
        dot:SetVertexColor(color[1], color[2], color[3], alpha)
    end
end

local function StartLoadingSpinnerAnimation(spinner)
    if not spinner.dots then
        CreateDotSpinner(spinner)
    end

    spinner.spinnerColor = GetSpinnerColor()
    spinner.activeIndex = 1
    UpdateDotSpinner(spinner)
    spinner:Show()

    if spinner.ticker then
        spinner.ticker:Cancel()
    end
    spinner.ticker = C_Timer.NewTicker(DOT_SPINNER_STEP_TIME, function()
        spinner.activeIndex = (spinner.activeIndex % DOT_SPINNER_COUNT) + 1
        UpdateDotSpinner(spinner)
    end)
end

local function StopLoadingSpinnerAnimation(spinner)
    if not spinner then
        return
    end
    if spinner.ticker then
        spinner.ticker:Cancel()
        spinner.ticker = nil
    end
    spinner:Hide()
end

function PromptUtils.HidePromptLoadingIndicator(frame)
    if not frame then
        return
    end
    if frame.loadingOverlay then
        StopLoadingSpinnerAnimation(frame.loadingSpinner)
        frame.loadingOverlay:Hide()
    end
    if frame.loadingText then
        frame.loadingText:Hide()
    end
end

function PromptUtils.EnsurePromptLoading(frame)
    if frame.loadingOverlay and frame.loadingSpinner and frame.loadingSpinner.dots then
        return
    end

    if frame.loadingOverlay then
        frame.loadingOverlay:Hide()
        frame.loadingOverlay = nil
        frame.loadingSpinner = nil
        frame.loadingText = nil
    end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 36)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    overlay:Hide()
    frame.loadingOverlay = overlay

    frame.loadingText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.loadingText:SetPoint("CENTER", overlay, "CENTER", 0, 16)
    frame.loadingText:SetWidth(300)
    frame.loadingText:SetJustifyH("CENTER")
    frame.loadingText:SetText("Please wait...")

    local spinner = CreateFrame("Frame", nil, overlay)
    spinner:SetSize(36, 36)
    spinner:SetPoint("TOP", frame.loadingText, "BOTTOM", 0, -12)
    frame.loadingSpinner = spinner
    CreateDotSpinner(spinner)
end

PromptUtils.STEP_CHANGING_SPEC = "Changing spec..."
PromptUtils.STEP_CHANGING_TALENTS = "Changing talents..."
PromptUtils.STEP_EQUIPPING_GEAR = "Equipping gear..."

function PromptUtils.ShowPromptLoading(frame)
    PromptUtils.EnsurePromptLoading(frame)
    HidePromptButtons(frame)
    if frame.content then
        frame.content:Hide()
    end
    if frame.loadout then
        frame.loadout:Hide()
    end
    if frame.help then
        frame.help:Hide()
    end
    if frame.raidName then
        frame.raidName:Hide()
    end
    frame.loadingOverlay:Show()
    frame.loadingSpinner:Show()
    StartLoadingSpinnerAnimation(frame.loadingSpinner)
    frame.loadingText:Show()
    frame.isLoading = true
end

function PromptUtils.SetPromptLoadingStep(stepText, frame)
    frame = frame or (pendingPromptSwitch and pendingPromptSwitch.frame)
    if not frame or not stepText then
        return
    end

    PromptUtils.EnsurePromptLoading(frame)
    frame.loadingOverlay:Show()
    frame.loadingSpinner:Show()
    StartLoadingSpinnerAnimation(frame.loadingSpinner)
    frame.loadingText:SetText(stepText)
    frame.loadingText:Show()
end

function PromptUtils.OnPromptLoadoutTalentsApplied(specID, configID)
    if not pendingPromptSwitch then
        return
    end

    specID = tonumber(specID)
    configID = tonumber(configID)
    if pendingPromptSwitch.specID ~= specID or pendingPromptSwitch.configID ~= configID then
        return
    end
    if not Loadout.IsAssignedLoadoutActive(specID, configID) then
        return
    end

    pendingPromptSwitch.talentsComplete = true
    PromptUtils.SetPromptLoadingStep(PromptUtils.STEP_EQUIPPING_GEAR)
end

function PromptUtils.NotifyPromptGearStepFinished(specID, configID)
    if not pendingPromptSwitch or not pendingPromptSwitch.talentsComplete then
        return
    end

    specID = tonumber(specID)
    configID = tonumber(configID)
    if pendingPromptSwitch.specID ~= specID or pendingPromptSwitch.configID ~= configID then
        return
    end

    PromptUtils.CompletePendingPromptSwitch()
end

function PromptUtils.HasPendingPromptSwitch()
    return pendingPromptSwitch ~= nil
end

function PromptUtils.MarkSpecSwitchComplete()
    if not pendingPromptSwitch then
        return
    end

    pendingPromptSwitch.waitingForSpec = false
    if pendingPromptSwitch.specWatch then
        pendingPromptSwitch.specWatch:Cancel()
        pendingPromptSwitch.specWatch = nil
    end
end

local function TearDownPendingSwitch()
    local pending = pendingPromptSwitch
    if not pending then
        return nil
    end

    if pending.timeout then
        pending.timeout:Cancel()
    end
    if pending.specWatch then
        pending.specWatch:Cancel()
    end
    pendingPromptSwitch = nil

    if pending.frame then
        PromptUtils.HidePromptLoadingIndicator(pending.frame)
        pending.frame.isLoading = nil
        pending.frame:Hide()
    end

    return pending
end

function PromptUtils.CompletePendingPromptSwitch()
    local pending = TearDownPendingSwitch()
    if pending and pending.onSuccess then
        pending.onSuccess()
    end
end

function PromptUtils.FailPendingPromptSwitch(reason)
    if not TearDownPendingSwitch() then
        return
    end

    ClearPendingLoadoutSwitchState()
    PromptUtils.PrintSwitchFailure(reason)
end

function PromptUtils.BeginPromptLoadoutSwitch(frame, specID, configID, onSuccess)
    if frame and frame.isLoading then
        return
    end

    specID = tonumber(specID)
    configID = tonumber(configID)
    if not frame or not specID or not configID then
        return
    end

    PromptUtils.ShowPromptLoading(frame)
    EnsureSwitchMonitor()

    local needsSpecChange = Loadout.GetSpecID() ~= specID

    pendingPromptSwitch = {
        frame = frame,
        specID = specID,
        configID = configID,
        onSuccess = onSuccess,
        waitingForSpec = false,
        timeout = C_Timer.After(20, function()
            if pendingPromptSwitch
                and pendingPromptSwitch.specID == specID
                and pendingPromptSwitch.configID == configID
            then
                PromptUtils.FailPendingPromptSwitch("timeout")
            end
        end),
    }

    PromptUtils.SetPromptLoadingStep(
        needsSpecChange and PromptUtils.STEP_CHANGING_SPEC or PromptUtils.STEP_CHANGING_TALENTS,
        frame
    )

    local ok, reason = Loadout.ApplyAssignedLoadout(specID, configID)
    if not ok then
        PromptUtils.FailPendingPromptSwitch(reason)
        return
    end

    if reason == "spec_changed" then
        pendingPromptSwitch.waitingForSpec = true
        pendingPromptSwitch.specWatch = C_Timer.After(12, function()
            if pendingPromptSwitch
                and pendingPromptSwitch.waitingForSpec
                and pendingPromptSwitch.specID == specID
            then
                FailWaitingSpecSwitch("cancelled")
            end
        end)
    elseif Loadout.IsAssignedLoadoutActive(specID, configID) then
        PromptUtils.OnPromptLoadoutTalentsApplied(specID, configID)
        LoadoutLocker.Gear.ScheduleLoadoutGearApply()
    end
end

function PromptUtils.SwitchToLoadout(specID, configID)
    local ok, reason = Loadout.ApplyAssignedLoadout(specID, configID)
    if not ok then
        PromptUtils.PrintSwitchFailure(reason)
        return false
    end
    return true
end

function PromptUtils.ConfigureLoadoutSwitchButton(button, specID, configID, onSuccess)
    specID = tonumber(specID)
    configID = tonumber(configID)
    if not specID or not configID or Loadout.IsStarterBuild(configID) then
        return false
    end
    if not Loadout.IsKnownSpecID(specID) then
        return false
    end

    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
    button:SetScript("PreClick", nil)
    button:SetScript("OnClick", function()
        PromptUtils.BeginPromptLoadoutSwitch(button:GetParent(), specID, configID, onSuccess)
    end)
    return true
end

function PromptUtils.CreateScheduleEvaluate(evaluateFn)
    local pendingEvaluate
    return function(delay)
        if pendingEvaluate then
            pendingEvaluate:Cancel()
        end
        pendingEvaluate = C_Timer.NewTimer(delay or 0.5, evaluateFn)
    end
end
function PromptUtils.CreatePromptFrame(options)
    options = options or {}
    local frame = CreateFrame("Frame", options.globalName, UIParent, "BackdropTemplate")
    frame:SetSize(options.width or 360, options.height or 118)
    frame:SetPoint("TOP", UIParent, "TOP", 0, options.offsetY or -180)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(200)
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetBackdrop(C.DIALOG_BACKDROP)
    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
    frame.title:SetText(options.title or "")
    frame.dismissButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.dismissButton:SetSize(100, 22)
    frame.dismissButton:SetText("Not Now")
    return frame
end
function PromptUtils.CreatePromptLabel(parent, anchor, offsetY, fontObject)
    local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormal")
    label:SetPoint("TOP", anchor, "BOTTOM", 0, offsetY or -6)
    label:SetWidth(320)
    label:SetWordWrap(true)
    label:SetJustifyH("CENTER")
    return label
end
