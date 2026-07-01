LoadoutLocker = LoadoutLocker or {}

local DB = LoadoutLocker.DB
local Dungeons = LoadoutLocker.Dungeons
local ContentPromptUI = LoadoutLocker.ContentPromptUI

local DungeonUI = ContentPromptUI.Create({
    globalName = "LoadoutLockerDungeonPrompt",
    title = "Dungeon Loadout",
    label = "dungeon",
    arePromptsEnabled = function()
        return DB:AreDungeonPromptsEnabled()
    end,
    isInInstance = function(instanceInfo)
        return Dungeons.IsInDungeonInstance(instanceInfo)
    end,
    resolveCurrent = function(instanceInfo)
        return Dungeons.ResolveCurrent(instanceInfo)
    end,
    getLoadoutRef = function(contentKey)
        return DB:GetDungeonLoadoutRef(contentKey)
    end,
    getByKey = function(key)
        return Dungeons.GetByKey(key)
    end,
    getFallbackContent = function()
        local sections = Dungeons.GetMenuSections()
        local seasonSection = sections and sections[1]
        return seasonSection and seasonSection.dungeons and seasonSection.dungeons[1]
    end,
})

LoadoutLocker.DungeonUI = DungeonUI
