LoadoutLocker = LoadoutLocker or {}
local PromptUtils = {}
LoadoutLocker.PromptUtils = PromptUtils
local C = LoadoutLocker.Constants
local Loadout = LoadoutLocker.Loadout
local Print = LoadoutLocker.Print
function PromptUtils.SwitchToLoadout(configID, specID)
    local ok, reason = Loadout.SwitchTo(configID, specID)
    if not ok then
        if reason == "error" then
            Print("Could not switch talent loadout.")
        elseif reason ~= "unchanged" then
            Print("Talent loadout switch is not available right now.")
        end
        return false
    end
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
