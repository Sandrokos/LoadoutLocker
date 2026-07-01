LoadoutLocker = LoadoutLocker or {}

local OnboardingUI = {}
LoadoutLocker.OnboardingUI = OnboardingUI

local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Text = LoadoutLocker.Text
local Widgets = LoadoutLocker.MenuWidgets
local Menu = LoadoutLocker.Menu

local COPY = Text.COPY
local Cmd = Text.FormatCommand
local Label = Text.FormatHighlight

local FRAME_WIDTH = 440
local FRAME_HEIGHT = 278

local STEPS = {
    {
        title = "Welcome to LoadoutLocker",
        body = COPY.TAGLINE .. "\n\n"
            .. "Open the menu with " .. Cmd() .. ". This guide walks through the main features.\n\n"
            .. "Reopen it anytime with " .. Cmd("tutorial") .. ".",
    },
    {
        title = "Save Gear Per Loadout",
        body = "Equip the gear you want, select a talent loadout, then save it:\n\n"
            .. "• Click " .. Label("Save Gear") .. " on the talent panel\n"
            .. "• Or run " .. Cmd("save") .. "\n\n"
            .. "Re-saving updates that loadout's gear set. LoadoutLocker also mirrors it to a Blizzard equipment set.",
    },
    {
        title = "Automatic Gear Swapping",
        body = "When you switch talent loadouts, LoadoutLocker equips the saved gear set after talents apply. "
            .. "It also checks your bags for same-name items that are better upgrades.\n\n"
            .. "Run " .. Cmd("scan") .. " to run that check anytime. "
            .. "Upgrade prompts compare track, item level, and tertiary stats.",
    },
    {
        title = "Assign Content-Specific Loadouts",
        body = "Assign default and per-content loadouts on the "
            .. Label("Dungeons") .. ", " .. Label("Raids") .. ", "
            .. Label("Delves") .. ", and " .. Label("PvP") .. " tabs in " .. Cmd() .. ". "
            .. "Assignments can use loadouts from any specialization.\n\n"
            .. "When you enter matching content, LoadoutLocker prompts you to switch. "
            .. "Cross-spec switches change spec, talents, then gear in order.",
    },
    {
        title = "Menu & Commands",
        body = Cmd() .. " opens the menu with General, Priority, Loadouts, and content tabs.\n\n"
            .. Cmd("list") .. " — saved gear sets\n"
            .. Cmd("delete") .. " — remove saved gear\n"
            .. Cmd("debug") .. " — bug report info\n\n"
            .. "Also available under " .. Label(COPY.OPTIONS_PATH) .. ".",
    },
    {
        title = "You're Ready",
        body = "Start by saving gear for your current talent loadout, then assign loadouts to the content you run.\n\n"
            .. "Toggle prompt types on the " .. Label("General") .. " tab. Manage saved sets and ignored upgrade slots on "
            .. Label("Loadouts") .. ". Open " .. Cmd() .. " when you are ready.",
    },
}

for index, step in ipairs(STEPS) do
    step.progress = string.format("Step %d of %d", index, #STEPS)
    step.nextLabel = (index >= #STEPS) and "Get Started" or "Next"
end

local frame
local currentStep = 1
local loginShowTimer

local function CancelLoginShow()
    if loginShowTimer then
        loginShowTimer:Cancel()
        loginShowTimer = nil
    end
end

local function CloseTutorial(complete, openMenu)
    CancelLoginShow()
    if complete then
        DB:SetOnboardingComplete()
        if frame then
            frame.autoCompleteOnClose = false
        end
    end
    if frame then
        frame:Hide()
    end
    if openMenu then
        Menu.Show()
    end
end

local function SetStep(stepIndex)
    currentStep = stepIndex
    local step = STEPS[stepIndex]
    if not step or not frame then
        return
    end

    frame.title:SetText(step.title)
    frame.body:SetText(step.body)
    frame.progress:SetText(step.progress)

    if stepIndex <= 1 then
        frame.backButton:Hide()
    else
        frame.backButton:Show()
    end

    frame.nextButton:SetText(step.nextLabel)
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = Widgets.CreateDialogFrame({
        name = "LoadoutLockerOnboardingFrame",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        frameLevel = 360,
        titleOffsetY = -16,
        titleWidth = FRAME_WIDTH - 48,
        onClose = function(dialog)
            dialog:Hide()
        end,
    })
    frame.autoCompleteOnClose = false

    frame:SetScript("OnHide", function()
        if frame.autoCompleteOnClose then
            DB:SetOnboardingComplete()
            frame.autoCompleteOnClose = false
        end
    end)

    frame.progress = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.progress:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)

    frame.body = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -64)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 48)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetWordWrap(true)
    frame.body:SetSpacing(3)

    frame.skipButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.skipButton:SetSize(100, 22)
    frame.skipButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 18)
    frame.skipButton:SetText("Skip")
    frame.skipButton:SetScript("OnClick", function()
        CloseTutorial(true)
    end)

    frame.backButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.backButton:SetSize(80, 22)
    frame.backButton:SetPoint("LEFT", frame.skipButton, "RIGHT", 8, 0)
    frame.backButton:SetText("Back")
    frame.backButton:SetScript("OnClick", function()
        SetStep(currentStep - 1)
    end)

    frame.nextButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.nextButton:SetSize(110, 22)
    frame.nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 18)
    frame.nextButton:SetText("Next")
    frame.nextButton:SetScript("OnClick", function()
        if currentStep >= #STEPS then
            CloseTutorial(true, true)
            return
        end
        SetStep(currentStep + 1)
    end)

    return frame
end

function OnboardingUI.Show(options)
    options = options or {}
    if not options.force and DB:IsOnboardingComplete() then
        return
    end

    CancelLoginShow()
    EnsureFrame()
    frame.autoCompleteOnClose = not options.force
    SetStep(options.step or 1)
    frame:Show()
end

function OnboardingUI.TryShowOnLogin()
    if DB:IsOnboardingComplete() then
        return
    end

    CancelLoginShow()
    loginShowTimer = C_Timer.NewTimer(C.ONBOARDING_LOGIN_DELAY, function()
        loginShowTimer = nil
        if not DB:IsOnboardingComplete() then
            OnboardingUI.Show()
        end
    end)
end
