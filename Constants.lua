LoadoutLocker = LoadoutLocker or {}

local Constants = {}
LoadoutLocker.Constants = Constants

Constants.STARTER_BUILD_CONFIG_ID = (
    _G.Constants
    and _G.Constants.TraitConsts
    and _G.Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID
) or -2

Constants.TALENT_UI_ADDON = "Blizzard_PlayerSpells"
LoadoutLocker.TALENT_UI_ADDON = Constants.TALENT_UI_ADDON

Constants.EQUIP_SLOT_DELAY = 0.15
Constants.LOADOUT_APPLY_DELAY = 0.25
Constants.SAVE_RETRY_DELAY = 0.15
Constants.OFFER_ADVANCE_DELAY = 0.05
Constants.MAX_SAVE_RETRIES = 8
Constants.MAX_SWAP_VERIFY_RETRIES = 8

Constants.EQUIP_SLOTS = {
    INVSLOT_HEAD,
    INVSLOT_NECK,
    INVSLOT_SHOULDER,
    INVSLOT_BODY,
    INVSLOT_CHEST,
    INVSLOT_WAIST,
    INVSLOT_LEGS,
    INVSLOT_FEET,
    INVSLOT_WRIST,
    INVSLOT_HAND,
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
    INVSLOT_BACK,
    INVSLOT_MAINHAND,
    INVSLOT_OFFHAND,
}

Constants.BAGS = {
    Enum.BagIndex.Backpack,
    Enum.BagIndex.Bag_1,
    Enum.BagIndex.Bag_2,
    Enum.BagIndex.Bag_3,
    Enum.BagIndex.Bag_4,
}

Constants.TERTIARY_PRIORITY = { "sockets", "avoidance", "leech", "speed" }

Constants.TERTIARY_LABELS = {
    sockets = "socket",
    avoidance = "Avoidance",
    leech = "Leech",
    speed = "Speed",
}

Constants.TERTIARY_STAT_KEYS = {
    avoidance = {
        "ITEM_MOD_CR_AVOIDANCE_SHORT",
        "ITEM_MOD_CR_AVOIDANCE",
    },
    leech = {
        "ITEM_MOD_CR_LEECH_SHORT",
        "ITEM_MOD_CR_LIFESTEAL",
        "ITEM_MOD_CR_LEECH",
    },
    speed = {
        "ITEM_MOD_CR_SPEED_SHORT",
        "ITEM_MOD_CR_SPEED",
    },
}

Constants.SWAP_PHASE = {
    UNEQUIP = "unequip",
    EQUIP = "equip",
}

Constants.TRACK_RANK = {
    { "ascendant voidforged", 10, "Ascendant Voidforged" },
    { "sporefused", 10, "Sporefused" },
    { "mythic", 5 },
    { "myth", 5 },
    { "heroic", 4 },
    { "hero", 4 },
    { "champion", 3 },
    { "veteran", 2 },
    { "adventurer", 1 },
}

Constants.TRACK_SCAN_MARKERS = {}
for _, entry in ipairs(Constants.TRACK_RANK) do
    if entry[2] >= 10 and entry[3] then
        Constants.TRACK_SCAN_MARKERS[#Constants.TRACK_SCAN_MARKERS + 1] = { entry[1], entry[3] }
    end
end
