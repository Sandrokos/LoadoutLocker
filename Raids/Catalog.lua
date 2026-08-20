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
    { 2912 },
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
    { 2939 },
    { "Dreamrift" },
    {
        B("chimaerus", "Chimaerus the Undreamt God", 1, { "Chimaerus", "Undreamt" }),
    }
)

Catalog.MARCH_ON_QUEL_DANAS = R(
    "march_on_quel_danas",
    "March on Quel'Danas",
    { 2913 },
    { "Quel'Danas", "Quel Danas", "Sunwell" },
    {
        B("beloren", "Belo'ren, Child of Al'ar", 1, { "Belo'ren", "Beloren", "Al'ar" }),
        B("midnight_falls", "Midnight Falls", 2, { "Midnight Falls", "L'ura", "Lura" }, { "beloren" }),
    }
)

Catalog.SPOREFALL = R(
    "sporefall",
    "Sporefall",
    { 2940 },
    { "Sporefall", "Rotmire" },
    {
        B("rotmire", "Rotmire", 1, { "Rotmire" }),
    }
)

Catalog.VENOMOUS_ABYSS = R(
    "venomous_abyss",
    "The Venomous Abyss",
    {},
    { "Venomous Abyss", "Venomous" },
    {
        B("nekzali", "Nek'zali the Soulcoiler", 1, { "Nek'zali", "Nekzali", "Soulcoiler" }),
        B("entombed_sentinels", "Entombed Sentinels", 2, { "Entombed Sentinels", "Sentinels" }, { "nekzali" }),
        B("lost_explorers", "The Lost Explorers", 3, { "Lost Explorers", "Explorers" }, { "nekzali" }),
        B("vashnik", "Vashnik the Malignant", 4, { "Vashnik" }, { "entombed_sentinels" }),
        B("sszorak", "Sszorak", 5, { "Sszorak" }, { "lost_explorers" }),
        B("twin_fangs", "The Twin Fangs", 6, { "Twin Fangs", "Vexhul", "Ithraz" }, { "vashnik", "sszorak" }),
        B("coiled_altar", "The Coiled Altar", 7, { "Coiled Altar" }, { "twin_fangs" }),
        B("ulatek", "Ula'tek", 8, { "Ula'tek", "Ulatek" }, { "coiled_altar" }),
    }
)

Catalog.TIDEBOUND_GROTTO = R(
    "tidebound_grotto",
    "Tidebound Grotto",
    {},
    { "Tidebound", "Grotto" },
    {
        B("nymrissa", "Nymrissa Wavecaller", 1, { "Nymrissa", "Wavecaller" }),
    }
)

Catalog.SEASON_ONE = {
    Catalog.VOIDSPIRE,
    Catalog.DREAMRIFT,
    Catalog.MARCH_ON_QUEL_DANAS,
    Catalog.SPOREFALL,
}

Catalog.SEASON_TWO = {
    Catalog.VENOMOUS_ABYSS,
    Catalog.TIDEBOUND_GROTTO,
}
