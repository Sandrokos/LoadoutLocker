LoadoutLocker = LoadoutLocker or {}

local DB = LoadoutLocker.DB
local PvP = LoadoutLocker.PvP
local ContentPromptUI = LoadoutLocker.ContentPromptUI

local PvPUI = ContentPromptUI.Create({
    globalName = "LoadoutLockerPvPPrompt",
    title = "PvP Loadout",
    label = "PvP",
    arePromptsEnabled = function()
        return DB:ArePvPPromptsEnabled()
    end,
    isInInstance = function(instanceInfo)
        return PvP.IsInPvPInstance(instanceInfo)
    end,
    resolveCurrent = function(instanceInfo)
        return PvP.ResolveCurrent(instanceInfo)
    end,
    getLoadoutRef = function(contentKey)
        return DB:GetPvPLoadoutRef(contentKey)
    end,
    getByKey = function(key)
        return PvP.GetByKey(key)
    end,
    getFallbackContent = function()
        local sections = PvP.GetMenuSections()
        local section = sections and sections[1]
        return section and section.modes and section.modes[1]
    end,
})

LoadoutLocker.PvPUI = PvPUI
