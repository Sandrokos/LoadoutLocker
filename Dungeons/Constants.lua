LoadoutLocker = LoadoutLocker or {}

local DungeonConstants = {}
LoadoutLocker.DungeonConstants = DungeonConstants

DungeonConstants.SEASON_ONE_HEADER = "Midnight Season 1"
DungeonConstants.SEASON_TWO_HEADER = "Midnight Season 2"

DungeonConstants.SEASON_TWO_UNLOCK = {
    year = 2026,
    month = 8,
    day = 12,
    hour = 0,
    min = 0,
    sec = 0,
}

function DungeonConstants.GetSeasonTwoUnlockTime()
    return time(DungeonConstants.SEASON_TWO_UNLOCK)
end
