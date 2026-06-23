LoadoutLocker = LoadoutLocker or {}

local Text = {}
LoadoutLocker.Text = Text

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
