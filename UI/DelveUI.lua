LoadoutLocker = LoadoutLocker or {}

local DB = LoadoutLocker.DB
local Delves = LoadoutLocker.Delves
local ContentPromptUI = LoadoutLocker.ContentPromptUI

local DelveUI = ContentPromptUI.Create({
    globalName = "LoadoutLockerDelvePrompt",
    title = "Delve Loadout",
    label = "delve",
    arePromptsEnabled = function()
        return DB:AreDelvePromptsEnabled()
    end,
    isInInstance = function(instanceInfo)
        return Delves.IsInDelveInstance(instanceInfo)
    end,
    resolveCurrent = function(instanceInfo)
        return Delves.ResolveCurrent(instanceInfo)
    end,
    getConfigID = function(specID, key)
        return DB:GetDelveConfigID(specID, key)
    end,
    getByKey = function(key)
        return Delves.GetByKey(key)
    end,
    getFallbackContent = function()
        local sections = Delves.GetMenuSections()
        local section = sections and sections[1]
        return section and section.delves and section.delves[1]
    end,
    extraEvents = { "WALK_IN_DATA_UPDATE" },
})

LoadoutLocker.DelveUI = DelveUI
