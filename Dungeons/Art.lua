LoadoutLocker = LoadoutLocker or {}

local Art = {}
LoadoutLocker.DungeonArt = Art

local Text = LoadoutLocker.Text

local PLACEHOLDER_ICON = 134400
local iconByKey = {}
local byKey
local challengeModeResolved = false

function Art.Init(dungeonByKey)
    byKey = dungeonByKey
end

local function ResolveFromChallengeMode()
    if challengeModeResolved or not C_ChallengeMode or not C_ChallengeMode.GetMaps then
        return
    end

    challengeModeResolved = true

    local maps = C_ChallengeMode.GetMaps()
    if not maps or not byKey then
        return
    end

    for _, challengeMapID in ipairs(maps) do
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        if name and texture and texture ~= 0 then
            for _, dungeon in pairs(byKey) do
                if not iconByKey[dungeon.key] and Text.NameMatches(name, dungeon) then
                    iconByKey[dungeon.key] = texture
                end
            end
        end
    end
end

local function ResolveFromInstanceID(instanceID)
    if not instanceID then
        return nil
    end

    if C_EncounterJournal and C_EncounterJournal.GetInstanceForMap then
        local journalInstanceID = C_EncounterJournal.GetInstanceForMap(instanceID)
        if journalInstanceID and EJ_GetInstanceInfo then
            local _, _, _, buttonImage = EJ_GetInstanceInfo(journalInstanceID)
            if buttonImage and buttonImage ~= 0 then
                return buttonImage
            end
        end
    end

    if EJ_GetInstanceForMap and EJ_GetInstanceInfo then
        local journalInstanceID = EJ_GetInstanceForMap(instanceID)
        if journalInstanceID then
            local _, _, _, buttonImage = EJ_GetInstanceInfo(journalInstanceID)
            if buttonImage and buttonImage ~= 0 then
                return buttonImage
            end
        end
    end
end

function Art.GetIcon(dungeon)
    if not dungeon then
        return PLACEHOLDER_ICON
    end

    if iconByKey[dungeon.key] then
        return iconByKey[dungeon.key]
    end

    if dungeon.iconFileID then
        iconByKey[dungeon.key] = dungeon.iconFileID
        return dungeon.iconFileID
    end

    ResolveFromChallengeMode()

    if iconByKey[dungeon.key] then
        return iconByKey[dungeon.key]
    end

    for _, instanceID in ipairs(dungeon.instanceIDs) do
        local icon = ResolveFromInstanceID(instanceID)
        if icon then
            iconByKey[dungeon.key] = icon
            return icon
        end
    end

    iconByKey[dungeon.key] = PLACEHOLDER_ICON
    return PLACEHOLDER_ICON
end

function Art.ShortName(dungeon, maxLength)
    local name = dungeon.shortName or dungeon.name
    maxLength = maxLength or 16

    if #name <= maxLength then
        return name
    end

    return name:sub(1, maxLength - 3) .. "..."
end
