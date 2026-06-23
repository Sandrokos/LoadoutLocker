LoadoutLocker = LoadoutLocker or {}
local DungeonUI = {}
LoadoutLocker.DungeonUI = DungeonUI
local DB = LoadoutLocker.DB
local Dungeons = LoadoutLocker.Dungeons
local Instance = LoadoutLocker.Instance
local Loadout = LoadoutLocker.Loadout
local PromptUtils = LoadoutLocker.PromptUtils
local Print = LoadoutLocker.Print
local promptFrame
local dismissedDungeonKey
local lastDungeonKey
local ScheduleEvaluate = PromptUtils.CreateScheduleEvaluate(function()
    DungeonUI.Evaluate()
end)
local function HidePrompt()
    if promptFrame then
        promptFrame:Hide()
    end
end
local function EnsurePromptFrame()
    if promptFrame then
        return promptFrame
    end
    local frame = PromptUtils.CreatePromptFrame({
        globalName = "LoadoutLockerDungeonPrompt",
        title = "Dungeon Loadout",
        height = 118,
    })
    frame.dungeon = PromptUtils.CreatePromptLabel(frame, frame.title)
    frame.loadout = PromptUtils.CreatePromptLabel(frame, frame.dungeon, -4, "GameFontGreenSmall")
    frame.swapButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.swapButton:SetSize(140, 22)
    frame.swapButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -8, 14)
    frame.swapButton:SetText("Switch Loadout")
    frame.swapButton:SetScript("OnClick", function()
        if not frame.configID then
            return
        end
        frame.swapButton:Disable()
        frame.dismissButton:Disable()
        if not PromptUtils.SwitchToLoadout(frame.configID, frame.specID) then
            frame.swapButton:Enable()
            frame.dismissButton:Enable()
            return
        end
        dismissedDungeonKey = frame.dungeonKey
        HidePrompt()
    end)
    frame.dismissButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 8, 14)
    frame.dismissButton:SetScript("OnClick", function()
        dismissedDungeonKey = frame.dungeonKey
        HidePrompt()
    end)
    promptFrame = frame
    return frame
end
function DungeonUI.ShowPrompt(dungeonKey, dungeon, configID, specID, options)
    options = options or {}
    if not options.force and not DB:AreDungeonPromptsEnabled() then
        return
    end
    if not options.force and dismissedDungeonKey == dungeonKey then
        return
    end
    local currentConfigID = Loadout.GetLoadoutConfigID(specID)
    if not configID or (not options.force and currentConfigID == configID) then
        return
    end
    local frame = EnsurePromptFrame()
    frame.dungeonKey = dungeonKey
    frame.configID = configID
    frame.specID = specID
    frame.dungeon:SetText(dungeon and dungeon.name or dungeonKey)
    frame.loadout:SetText("Switch to: " .. Loadout.GetLoadoutName(configID))
    frame.swapButton:Enable()
    frame.dismissButton:Enable()
    frame:Show()
end
function DungeonUI.HidePrompt()
    HidePrompt()
end
function DungeonUI.Evaluate()
    local instanceInfo = Instance.GetCurrent()
    if not Dungeons.IsInDungeonInstance(instanceInfo) then
        if lastDungeonKey then
            dismissedDungeonKey = nil
            lastDungeonKey = nil
        end
        HidePrompt()
        return
    end
    local dungeonKey, dungeon = Dungeons.ResolveCurrent(instanceInfo)
    if not dungeonKey then
        HidePrompt()
        return
    end
    lastDungeonKey = dungeonKey
    local specID = Loadout.GetSpecID()
    if not specID then
        return
    end
    local configID = DB:GetDungeonConfigID(specID, dungeonKey)
    if not configID then
        HidePrompt()
        return
    end
    DungeonUI.ShowPrompt(dungeonKey, dungeon, configID, specID)
end
function DungeonUI.Simulate()
    local specID = Loadout.GetSpecID()
    if not specID then
        Print("Select a specialization first.")
        return
    end
    local dungeonKey, dungeon = Dungeons.ResolveCurrent(Instance.GetCurrent())
    if not dungeon then
        local sections = Dungeons.GetMenuSections()
        local seasonSection = sections and sections[1]
        dungeon = seasonSection and seasonSection.dungeons and seasonSection.dungeons[1]
        dungeonKey = dungeon and dungeon.key
    end
    if not dungeon then
        Print("No dungeon data available to simulate.")
        return
    end
    local configID = DB:GetDungeonConfigID(specID, dungeonKey)
    if not configID then
        Print("Assign a dungeon loadout in /locker before simulating.")
        return
    end
    dismissedDungeonKey = nil
    DungeonUI.ShowPrompt(dungeonKey, dungeon, configID, specID, { force = true })
    Print("Showing simulated dungeon prompt for " .. dungeon.name .. ".")
end
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function()
    ScheduleEvaluate(0.5)
end)
