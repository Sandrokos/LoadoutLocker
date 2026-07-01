LoadoutLocker = LoadoutLocker or {}

function LoadoutLocker.Print(msg)
    print("|cff00ccffLoadoutLocker:|r " .. tostring(msg))
end

local C = LoadoutLocker.Constants

local Text = {}
LoadoutLocker.Text = Text

Text.COPY = {
    TAGLINE = "LoadoutLocker saves your equipped gear to each talent loadout and swaps it when you change builds.",
    OPTIONS_PATH = "Esc > Options > AddOns",
}

local function ColorCode(rgb)
    return string.format("cff%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
end

local HIGHLIGHT_COLOR = "cffffffff"
local COMMAND_COLOR = ColorCode(C.UI_TITLE_COLOR)

function Text.FormatHighlight(value)
    return "|" .. HIGHLIGHT_COLOR .. value .. "|r"
end

function Text.FormatCommand(subcommand)
    if subcommand then
        return "|" .. COMMAND_COLOR .. "/locker " .. subcommand .. "|r"
    end
    return "|" .. COMMAND_COLOR .. "/locker|r"
end

function Text.NormalizeName(value)
    if not value then
        return ""
    end

    value = string.lower(value)
    value = value:gsub("'", "")
    value = value:gsub("[^%w%s]", " ")
    value = value:gsub("%s+", " ")
    return strtrim(value)
end

function Text.BuildNormalizedPatterns(entity)
    local patterns = {}
    local name = Text.NormalizeName(entity.name)

    if name ~= "" then
        patterns[#patterns + 1] = name
    end

    for _, keyword in ipairs(entity.keywords or {}) do
        local normalizedKeyword = Text.NormalizeName(keyword)
        if normalizedKeyword ~= "" then
            patterns[#patterns + 1] = normalizedKeyword
        end
    end

    return patterns
end

function Text.PrepareEntity(entity)
    entity.normalizedPatterns = Text.BuildNormalizedPatterns(entity)
end

function Text.NameMatches(value, entity)
    local normalized = Text.NormalizeName(value)
    if normalized == "" then
        return false
    end

    local patterns = entity.normalizedPatterns or Text.BuildNormalizedPatterns(entity)

    for _, pattern in ipairs(patterns) do
        if normalized == pattern or normalized:find(pattern, 1, true) then
            return true
        end
    end

    return false
end
