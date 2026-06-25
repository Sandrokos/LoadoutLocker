LoadoutLocker = LoadoutLocker or {}

local Dungeons = {}
LoadoutLocker.Dungeons = Dungeons

local Catalog = LoadoutLocker.DungeonCatalog
local DungeonConstants = LoadoutLocker.DungeonConstants
local Instance = LoadoutLocker.Instance
local Text = LoadoutLocker.Text

local byKey = {}
local byInstanceID = {}
local byLfgDungeonID = {}
local cachedSections
local cachedSeasonTwo

local function RegisterDungeon(dungeon)
    if byKey[dungeon.key] then
        return
    end

    Text.PrepareEntity(dungeon)
    byKey[dungeon.key] = dungeon

    for _, instanceID in ipairs(dungeon.instanceIDs) do
        local keys = byInstanceID[instanceID]
        if not keys then
            keys = {}
            byInstanceID[instanceID] = keys
        end
        keys[#keys + 1] = dungeon.key
    end

    for _, lfgDungeonID in ipairs(dungeon.lfgDungeonIDs or {}) do
        byLfgDungeonID[lfgDungeonID] = dungeon.key
    end
end

for _, dungeon in ipairs(Catalog.GetAllDungeons()) do
    RegisterDungeon(dungeon)
end

function Dungeons.IsSeasonTwoAvailable()
    return time() >= DungeonConstants.GetSeasonTwoUnlockTime()
end

function Dungeons.GetByKey(key)
    return byKey[key]
end

local function AddLinkedKey(keys, seen, key)
    if key and not seen[key] then
        seen[key] = true
        keys[#keys + 1] = key
    end
end

function Dungeons.GetLinkedAssignmentKeys(dungeonKey)
    local keys = {}
    local seen = {}
    AddLinkedKey(keys, seen, dungeonKey)

    local dungeon = byKey[dungeonKey]
    if not dungeon then
        return keys
    end

    for _, instanceID in ipairs(dungeon.instanceIDs) do
        for _, linkedKey in ipairs(byInstanceID[instanceID] or {}) do
            AddLinkedKey(keys, seen, linkedKey)
        end
    end

    return keys
end

local function ExpansionSectionKey(name)
    return "exp_" .. name:lower():gsub("'", ""):gsub("[^%w]+", "_"):gsub("^_", ""):gsub("_$", "")
end

local SHORT_TAB_NAMES = {
    ["The War Within"] = "TWW",
    ["Wrath of the Lich King"] = "WotLK",
    ["Battle for Azeroth"] = "BfA",
    ["Mists of Pandaria"] = "MoP",
    ["Warlords of Draenor"] = "WoD",
}

local function TabTextForGroup(name)
    return SHORT_TAB_NAMES[name] or name
end

local function BuildMenuSections()
    local sections = {}

    if Dungeons.IsSeasonTwoAvailable() then
        sections[#sections + 1] = {
            key = "season",
            tabText = "Season 2",
            header = DungeonConstants.SEASON_TWO_HEADER,
            dungeons = Catalog.SEASON_TWO,
        }
    else
        sections[#sections + 1] = {
            key = "season",
            tabText = "Season 1",
            header = DungeonConstants.SEASON_ONE_HEADER,
            dungeons = Catalog.SEASON_ONE,
        }
    end

    for _, group in ipairs(Catalog.EXPANSION_GROUPS) do
        sections[#sections + 1] = {
            key = ExpansionSectionKey(group.name),
            tabText = group.name,
            shortTabText = TabTextForGroup(group.name),
            header = group.name,
            dungeons = group.dungeons,
        }
    end

    return sections
end

function Dungeons.GetMenuSections()
    local seasonTwo = Dungeons.IsSeasonTwoAvailable()
    if not cachedSections or cachedSeasonTwo ~= seasonTwo then
        cachedSeasonTwo = seasonTwo
        cachedSections = BuildMenuSections()
    end

    return cachedSections
end

function Dungeons.IsInDungeonInstance(instanceInfo)
    instanceInfo = instanceInfo or Instance.GetCurrent()
    return instanceInfo.instanceType == "party"
end

function Dungeons.ResolveCurrent(instanceInfo)
    return Instance.Resolve(instanceInfo or Instance.GetCurrent(), "party", byKey, byInstanceID, byLfgDungeonID)
end
