LoadoutLocker = LoadoutLocker or {}

local Catalog = {}
LoadoutLocker.DelveCatalog = Catalog

local function D(key, name, instanceIDs, keywords)
    return {
        key = key,
        name = name,
        instanceIDs = instanceIDs or {},
        keywords = keywords or {},
    }
end

Catalog.KHAZ_ALGAR_DELVES = {
    D("fungal_folly", "Fungal Folly", { 2664 }, { "Fungal Folly" }),
    D("mycomancer_cavern", "Mycomancer Cavern", { 2679 }, { "Mycomancer" }),
    D("earthcrawl_mines", "Earthcrawl Mines", { 2680 }, { "Earthcrawl" }),
    D("kriegvals_rest", "Kriegval's Rest", { 2681 }, { "Kriegval" }),
    D("zekvirs_lair", "Zekvir's Lair", { 2682 }, { "Zekvir" }),
    D("the_waterworks", "The Waterworks", { 2683 }, { "Waterworks" }),
    D("the_dread_pit", "The Dread Pit", { 2684 }, { "Dread Pit" }),
    D("skittering_breach", "Skittering Breach", { 2685 }, { "Skittering" }),
    D("nightfall_sanctum", "Nightfall Sanctum", { 2686 }, { "Nightfall" }),
    D("the_sinkhole", "The Sinkhole", { 2687 }, { "Sinkhole" }),
    D("the_spiral_weave", "The Spiral Weave", { 2688 }, { "Spiral Weave" }),
    D("tak_rethan_abyss", "Tak-Rethan Abyss", { 2689 }, { "Tak-Rethan", "Tak Rethan" }),
    D("the_underkeep", "The Underkeep", { 2690 }, { "Underkeep" }),
    D("archival_assault", "Archival Assault", { 2803 }, { "Archival" }),
    D("excavation_site_9", "Excavation Site 9", { 2815 }, { "Excavation Site" }),
    D("sidestreet_sluice", "Sidestreet Sluice", { 2826 }, { "Sidestreet" }),
    D("demolition_dome", "Demolition Dome", { 2831 }, { "Demolition" }),
    D("voidrazor_sanctuary", "Voidrazor Sanctuary", { 2951 }, { "Voidrazor" }),
}

Catalog.MIDNIGHT_DELVES = {
    D("collegiate_calamity", "Collegiate Calamity", { 2933 }, { "Collegiate Calamity" }),
    D("the_shadow_enclave", "The Shadow Enclave", { 2952 }, { "Shadow Enclave" }),
    D("parhelion_plaza", "Parhelion Plaza", { 2953 }, { "Parhelion Plaza" }),
    D("twilight_crypts", "Twilight Crypts", { 2961 }, { "Twilight Crypts" }),
    D("atal_aman", "Atal'Aman", { 2962 }, { "Atal'Aman", "Atal Aman" }),
    D("the_grudge_pit", "The Grudge Pit", { 2963 }, { "Grudge Pit" }),
    D("the_gulf_of_memory", "The Gulf of Memory", { 2964 }, { "Gulf of Memory" }),
    D("sunkiller_sanctum", "Sunkiller Sanctum", { 2965 }, { "Sunkiller Sanctum" }),
    D("torments_rise", "Torment's Rise", { 2966 }, { "Torment's Rise", "Torments Rise" }),
    D("shadowguard_point", "Shadowguard Point", { 2979 }, { "Shadowguard Point" }),
    D("the_darkway", "The Darkway", { 3003 }, { "The Darkway", "Darkway" }),
}

function Catalog.GetAllDelves()
    local all = {}
    for _, delve in ipairs(Catalog.KHAZ_ALGAR_DELVES) do
        all[#all + 1] = delve
    end
    for _, delve in ipairs(Catalog.MIDNIGHT_DELVES) do
        all[#all + 1] = delve
    end
    return all
end
