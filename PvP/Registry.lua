LoadoutLocker = LoadoutLocker or {}

local PvP = {}
LoadoutLocker.PvP = PvP

local Catalog = LoadoutLocker.PvPCatalog
local PvPConstants = LoadoutLocker.PvPConstants
local Text = LoadoutLocker.Text

local byKey = {}
local byInstanceType = {}

local function RegisterMode(mode)
    if byKey[mode.key] then
        return
    end

    Text.PrepareEntity(mode)
    byKey[mode.key] = mode
    byInstanceType[mode.instanceType] = mode
end

for _, mode in ipairs(Catalog.GetAllModes()) do
    RegisterMode(mode)
end

function PvP.GetByKey(key)
    return byKey[key]
end

local cachedSections

function PvP.GetMenuSections()
    if not cachedSections then
        cachedSections = {
            {
                header = PvPConstants.HEADER,
                modes = Catalog.MODES,
            },
        }
    end

    return cachedSections
end

function PvP.IsInPvPInstance(instanceInfo)
    instanceInfo = instanceInfo or LoadoutLocker.Instance.GetCurrent()
    local instanceType = instanceInfo.instanceType
    return instanceType == "arena" or instanceType == "pvp"
end

function PvP.ResolveCurrent(instanceInfo)
    instanceInfo = instanceInfo or LoadoutLocker.Instance.GetCurrent()
    local mode = byInstanceType[instanceInfo.instanceType]
    if mode then
        return mode.key, mode, instanceInfo.name
    end
end
