LoadoutLocker = LoadoutLocker or {}

local Catalog = {}
LoadoutLocker.DungeonCatalog = Catalog

local function D(key, name, expansion, instanceIDs, keywords, iconFileID, shortName, lfgDungeonIDs)
    return {
        key = key,
        name = name,
        expansion = expansion,
        instanceIDs = instanceIDs or {},
        keywords = keywords or {},
        iconFileID = iconFileID,
        shortName = shortName,
        lfgDungeonIDs = lfgDungeonIDs or {},
    }
end

Catalog.MIDNIGHT_DUNGEONS = {
    D("magisters_terrace", "Magisters' Terrace", "Midnight", { 585 }, { "Magister" }),
    D("maisara_caverns", "Maisara Caverns", "Midnight", {}, { "Maisara" }),
    D("nexus_point_xenas", "Nexus-Point Xenas", "Midnight", {}, { "Nexus-Point", "Nexus Point" }),
    D("windrunner_spire", "Windrunner Spire", "Midnight", {}, { "Windrunner Spire" }),
    D("murder_row", "Murder Row", "Midnight", {}, { "Murder Row" }),
    D("den_of_nalorakk", "Den of Nalorakk", "Midnight", {}, { "Den of Nalorakk", "Nalorakk" }),
    D("blinding_vale", "The Blinding Vale", "Midnight", {}, { "Blinding Vale", "Blinding" }),
    D("voidscar_arena", "Voidscar Arena", "Midnight", {}, { "Voidscar" }),
    D("altar_of_fangs", "Altar of Fangs", "Midnight", {}, { "Altar of Fangs", "Fangs" }),
}

Catalog.SEASON_ONE = {
    D("magisters_terrace", "Magisters' Terrace", "Midnight", { 585 }, { "Magister" }, nil, "Magisters'"),
    D("maisara_caverns", "Maisara Caverns", "Midnight", {}, { "Maisara" }, nil, "Maisara"),
    D("nexus_point_xenas", "Nexus-Point Xenas", "Midnight", {}, { "Nexus-Point", "Nexus Point" }, nil, "Nexus-Point"),
    D("windrunner_spire", "Windrunner Spire", "Midnight", {}, { "Windrunner Spire" }, nil, "Windrunner"),
    D("algethar_academy", "Algeth'ar Academy", "Dragonflight", { 2526 }, { "Algeth" }, nil, "Algeth'ar"),
    D("pit_of_saron", "Pit of Saron", "Wrath of the Lich King", { 658 }, { "Pit of Saron" }, nil, "Pit of Saron"),
    D("seat_of_the_triumvirate", "Seat of the Triumvirate", "Legion", { 1753 }, { "Triumvirate" }, nil, "Triumvirate"),
    D("skyreach", "Skyreach", "Warlords of Draenor", { 1209 }, { "Skyreach" }, nil, "Skyreach"),
}

Catalog.SEASON_TWO = {
    D("altar_of_fangs", "Altar of Fangs", "Midnight", {}, { "Altar of Fangs", "Fangs" }, nil, "Altar of Fangs"),
    D("murder_row", "Murder Row", "Midnight", {}, { "Murder Row" }, nil, "Murder Row"),
    D("den_of_nalorakk", "Den of Nalorakk", "Midnight", {}, { "Den of Nalorakk", "Nalorakk" }, nil, "Nalorakk"),
    D("blinding_vale", "The Blinding Vale", "Midnight", {}, { "Blinding Vale", "Blinding" }, nil, "Blinding Vale"),
    D("voidscar_arena", "Voidscar Arena", "Midnight", {}, { "Voidscar" }, nil, "Voidscar"),
    D("ruby_life_pools", "Ruby Life Pools", "Dragonflight", { 2521 }, { "Ruby Life" }, nil, "Ruby Life"),
    D("temple_of_sethraliss", "Temple of Sethraliss", "Battle for Azeroth", { 1877 }, { "Sethraliss" }, nil, "Sethraliss"),
    D("kings_rest", "Kings' Rest", "Battle for Azeroth", { 1762 }, { "Kings' Rest" }, nil, "Kings' Rest"),
}

Catalog.EXPANSION_GROUPS = {
    {
        name = "Midnight",
        dungeons = Catalog.MIDNIGHT_DUNGEONS,
    },
    {
        name = "The War Within",
        dungeons = {
            D("ara_kara", "Ara-Kara, City of Echoes", "The War Within", { 2660 }),
            D("the_dawnbreaker", "The Dawnbreaker", "The War Within", { 2662, 2671, 2672 }),
            D("the_stonevault", "The Stonevault", "The War Within", { 2652 }),
            D("the_rookery", "The Rookery", "The War Within", { 2648 }),
            D("priory_of_the_sacred_flame", "Priory of the Sacred Flame", "The War Within", { 2649 }),
            D("darkflame_cleft", "Darkflame Cleft", "The War Within", { 2651 }),
            D("cinderbrew_meadery", "Cinderbrew Meadery", "The War Within", { 2661 }),
            D("city_of_threads", "City of Threads", "The War Within", { 2669 }),
            D("operation_floodgate", "Operation: Floodgate", "The War Within", { 2773 }),
        },
    },
    {
        name = "Dragonflight",
        dungeons = {
            D("brackenhide_hollow", "Brackenhide Hollow", "Dragonflight", { 2520 }),
            D("neltharus", "Neltharus", "Dragonflight", { 2519 }),
            D("the_nokhud_offensive", "The Nokhud Offensive", "Dragonflight", { 2516 }),
            D("the_azure_vault", "The Azure Vault", "Dragonflight", { 2515, 2590 }),
            D("uldaman_legacy", "Uldaman: Legacy of Tyr", "Dragonflight", { 2451 }),
            D("ruby_life_pools", "Ruby Life Pools", "Dragonflight", { 2521 }),
            D("halls_of_infusion", "Halls of Infusion", "Dragonflight", { 2527 }),
            D("dawn_of_the_infinite", "Dawn of the Infinite", "Dragonflight", { 2579 }),
        },
    },
    {
        name = "Shadowlands",
        dungeons = {
            D("the_necrotic_wake", "The Necrotic Wake", "Shadowlands", { 2286 }),
            D("plaguefall", "Plaguefall", "Shadowlands", { 2289 }),
            D("mists_of_tirna_scithe", "Mists of Tirna Scithe", "Shadowlands", { 2290 }),
            D("halls_of_atonement", "Halls of Atonement", "Shadowlands", { 2287 }),
            D("de_other_side", "De Other Side", "Shadowlands", { 2291 }),
            D("sanguine_depths", "Sanguine Depths", "Shadowlands", { 2284 }),
            D("spires_of_ascension", "Spires of Ascension", "Shadowlands", { 2285 }),
            D("tazavesh_streets", "Tazavesh: Streets of Wonder", "Shadowlands", { 2441 }, { "Streets of Wonder", "Streets" }),
            D("tazavesh_gambit", "Tazavesh: So'leah's Gambit", "Shadowlands", { 2441 }, { "Gambit", "So'leah" }),
        },
    },
    {
        name = "Battle for Azeroth",
        dungeons = {
            D("freehold", "Freehold", "Battle for Azeroth", { 1754 }),
            D("atal_dazar", "Atal'Dazar", "Battle for Azeroth", { 1763 }),
            D("tol_dagor", "Tol Dagor", "Battle for Azeroth", { 1771 }),
            D("siege_of_boralus", "Siege of Boralus", "Battle for Azeroth", { 1822 }),
            D("the_underrot", "The Underrot", "Battle for Azeroth", { 1841 }),
            D("waycrest_manor", "Waycrest Manor", "Battle for Azeroth", { 1862 }),
            D("shrine_of_the_storm", "Shrine of the Storm", "Battle for Azeroth", { 1864 }),
            D("temple_of_sethraliss", "Temple of Sethraliss", "Battle for Azeroth", { 1877 }),
            D("kings_rest", "Kings' Rest", "Battle for Azeroth", { 1762 }),
            D("mechagon_junkyard", "Operation: Mechagon - Junkyard", "Battle for Azeroth", { 2097 }, { "Junkyard", "Mechagon Junkyard" }, nil, "Junkyard", { 2027 }),
            D("mechagon_workshop", "Operation: Mechagon - Workshop", "Battle for Azeroth", { 2097 }, { "Workshop", "Mechagon Workshop" }, nil, "Workshop", { 2028 }),
        },
    },
    {
        name = "Legion",
        dungeons = {
            D("black_rook_hold", "Black Rook Hold", "Legion", { 1501 }),
            D("darkheart_thicket", "Darkheart Thicket", "Legion", { 1466 }),
            D("eye_of_azshara", "Eye of Azshara", "Legion", { 1456 }),
            D("neltharions_lair", "Neltharion's Lair", "Legion", { 1458 }),
            D("vault_of_the_wardens", "Vault of the Wardens", "Legion", { 1493 }),
            D("court_of_stars", "Court of Stars", "Legion", { 1571 }),
            D("the_arcway", "The Arcway", "Legion", { 1516 }),
            D("return_to_karazhan", "Return to Karazhan", "Legion", { 1651 }),
            D("cathedral_of_eternal_night", "Cathedral of Eternal Night", "Legion", { 1677 }),
        },
    },
    {
        name = "Warlords of Draenor",
        dungeons = {
            D("bloodmaul_slag_mines", "Bloodmaul Slag Mines", "Warlords of Draenor", { 1175 }),
            D("shadowmoon_burial_grounds", "Shadowmoon Burial Grounds", "Warlords of Draenor", { 1176 }),
            D("auchindoun", "Auchindoun", "Warlords of Draenor", { 1182 }),
            D("iron_docks", "Iron Docks", "Warlords of Draenor", { 1195 }),
            D("grimrail_depot", "Grimrail Depot", "Warlords of Draenor", { 1208 }),
            D("the_everbloom", "The Everbloom", "Warlords of Draenor", { 1279 }),
            D("upper_blackrock_spire", "Upper Blackrock Spire", "Warlords of Draenor", { 1358 }),
        },
    },
    {
        name = "Wrath of the Lich King",
        dungeons = {
            D("utgarde_keep", "Utgarde Keep", "Wrath of the Lich King", { 574 }),
            D("utgarde_pinnacle", "Utgarde Pinnacle", "Wrath of the Lich King", { 575 }),
            D("the_nexus", "The Nexus", "Wrath of the Lich King", { 576 }),
            D("culling_of_stratholme", "The Culling of Stratholme", "Wrath of the Lich King", { 595 }),
            D("halls_of_stone", "Halls of Stone", "Wrath of the Lich King", { 599 }),
            D("drak_tharon_keep", "Drak'Tharon Keep", "Wrath of the Lich King", { 600 }),
            D("azjol_nerub", "Azjol-Nerub", "Wrath of the Lich King", { 601 }),
            D("halls_of_lightning", "Halls of Lightning", "Wrath of the Lich King", { 602 }),
            D("gundrak", "Gundrak", "Wrath of the Lich King", { 604 }),
            D("ahnkahet", "Ahn'kahet: The Old Kingdom", "Wrath of the Lich King", { 619 }),
            D("forge_of_souls", "The Forge of Souls", "Wrath of the Lich King", { 632 }),
            D("halls_of_reflection", "Halls of Reflection", "Wrath of the Lich King", { 668 }),
        },
    },
    {
        name = "Cataclysm",
        dungeons = {
            D("grim_batol", "Grim Batol", "Cataclysm", { 670 }),
            D("throne_of_the_tides", "Throne of the Tides", "Cataclysm", { 643 }),
            D("vortex_pinnacle", "The Vortex Pinnacle", "Cataclysm", { 657 }),
            D("lost_city_of_the_tolvir", "Lost City of the Tol'vir", "Cataclysm", { 755 }),
        },
    },
    {
        name = "Mists of Pandaria",
        dungeons = {
            D("temple_of_the_jade_serpent", "Temple of the Jade Serpent", "Mists of Pandaria", { 960 }),
            D("stormstout_brewery", "Stormstout Brewery", "Mists of Pandaria", { 961 }),
            D("gate_of_the_setting_sun", "Gate of the Setting Sun", "Mists of Pandaria", { 962 }),
            D("shado_pan_monastery", "Shado-Pan Monastery", "Mists of Pandaria", { 959 }),
            D("siege_of_niuzao_temple", "Siege of Niuzao Temple", "Mists of Pandaria", { 1011 }),
        },
    },
}

function Catalog.GetAllDungeons()
    local all = {}

    local function add(dungeon)
        all[#all + 1] = dungeon
    end

    for _, dungeon in ipairs(Catalog.SEASON_ONE) do
        add(dungeon)
    end

    for _, dungeon in ipairs(Catalog.SEASON_TWO) do
        add(dungeon)
    end

    for _, group in ipairs(Catalog.EXPANSION_GROUPS) do
        for _, dungeon in ipairs(group.dungeons) do
            add(dungeon)
        end
    end

    return all
end
