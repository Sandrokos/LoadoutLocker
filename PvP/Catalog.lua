LoadoutLocker = LoadoutLocker or {}

local Catalog = {}
LoadoutLocker.PvPCatalog = Catalog

local function M(key, name, instanceType, keywords)
    return {
        key = key,
        name = name,
        instanceType = instanceType,
        keywords = keywords or {},
    }
end

Catalog.MODES = {
    M("arena", "Arena", "arena", { "Arena" }),
    M("battleground", "Battleground", "pvp", { "Battleground" }),
}

function Catalog.GetAllModes()
    return Catalog.MODES
end
