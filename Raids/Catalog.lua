LoadoutLocker = LoadoutLocker or {}

local Catalog = {}
LoadoutLocker.RaidCatalog = Catalog

local function B(key, name, encounterIndex, keywords, requires)
    return {
        key = key,
        name = name,
        encounterIndex = encounterIndex,
        keywords = keywords or {},
        requires = requires or {},
    }
end

local function R(key, name, instanceIDs, keywords, bosses)
    return {
        key = key,
        name = name,
        instanceIDs = instanceIDs or {},
        keywords = keywords or {},
        bosses = bosses,
    }
end

Catalog.VOIDSPIRE = R(
    "voidspire",
    "The Voidspire",
    {},
    { "Voidspire" },
    {
        B("averzian", "Imperator Averzian", 1, { "Averzian" }),
        B("vorasius", "Vorasius", 2, { "Vorasius" }, { "averzian" }),
        B("salhadaar", "Fallen-King Salhadaar", 3, { "Salhadaar" }, { "averzian" }),
        B("vaelgor_ezzorak", "Vaelgor & Ezzorak", 4, { "Vaelgor", "Ezzorak" }, { "vorasius", "salhadaar" }),
        B("lightblinded_vanguard", "Lightblinded Vanguard", 5, { "Lightblinded", "Vanguard" }, { "vaelgor_ezzorak" }),
        B("crown_of_the_cosmos", "Crown of the Cosmos", 6, { "Crown of the Cosmos", "Cosmos" }, { "lightblinded_vanguard" }),
    }
)

Catalog.DREAMRIFT = R(
    "dreamrift",
    "Dreamrift",
    {},
    { "Dreamrift" },
    {
        B("chimaerus", "Chimaerus the Undreamt God", 1, { "Chimaerus", "Undreamt" }),
    }
)

Catalog.MARCH_ON_QUEL_DANAS = R(
    "march_on_quel_danas",
    "March on Quel'Danas",
    {},
    { "Quel'Danas", "Quel Danas", "Sunwell" },
    {
        B("beloren", "Belo'ren, Child of Al'ar", 1, { "Belo'ren", "Beloren", "Al'ar" }),
        B("midnight_falls", "Midnight Falls", 2, { "Midnight Falls", "L'ura", "Lura" }, { "beloren" }),
    }
)

Catalog.CURRENT_TIER = {
    Catalog.VOIDSPIRE,
    Catalog.DREAMRIFT,
    Catalog.MARCH_ON_QUEL_DANAS,
}
