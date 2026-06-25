std = "lua51"
max_line_length = false
codes = true

exclude_files = {
	"**/Libs/**",
}

globals = {
	-- Addon namespace
	"LoadoutLocker",
	"LoadoutLockerDB",
	"SLASH_LOADOUTLOCKER1",
	"SLASH_LOADOUTLOCKER2",
	"SlashCmdList",

	-- Lua / WoW runtime
	"assert",
	"date",
	"debugstack",
	"error",
	"geterrorhandler",
	"hooksecurefunc",
	"ipairs",
	"pairs",
	"pcall",
	"print",
	"select",
	"seterrorhandler",
	"strtrim",
	"time",
	"tinsert",
	"tonumber",
	"tostring",
	"type",
	"unpack",
	"wipe",
	"xpcall",

	-- UI / frames
	"BackdropTemplate",
	"CreateFrame",
	"DetailsFramework",
	"HideUIPanel",
	"PlayerSpellsFrame",
	"Settings",
	"SettingsPanel",
	"UIParent",
	"UISpecialFrames",

	-- Blizzard API tables
	"C_AddOns",
	"C_ChallengeMode",
	"C_ClassTalents",
	"C_Container",
	"C_EncounterJournal",
	"C_EquipmentSet",
	"C_Item",
	"C_Map",
	"C_PartyInfo",
	"C_SpecializationInfo",
	"C_Spell",
	"C_Timer",
	"C_TooltipInfo",
	"C_Traits",
	"Enum",
	"ItemLocation",

	-- Blizzard API functions
	"ClearCursor",
	"EJ_GetInstanceForMap",
	"EJ_GetInstanceInfo",
	"GameTooltip",
	"GetAddOnMetadata",
	"GetInstanceInfo",
	"GetInventoryItemID",
	"GetInventoryItemLink",
	"GetItemInfo",
	"GetNumSavedInstances",
	"GetRealZoneText",
	"GetSavedInstanceEncounterInfo",
	"GetSavedInstanceInfo",
	"GetScriptErrorFrameText",
	"GetSpecializationInfoByID",
	"GetSpecializationInfoForSpecID",
	"GetSpellInfo",
	"GetSubZoneText",
	"GetZoneText",
	"InCombatLockdown",
	"IsInInstance",
	"PickupContainerItem",
	"PickupInventoryItem",
	"RequestRaidInfo",
}

ignore = {
	"212/self",
	"212/_",
	"1/[A-Z][A-Z][A-Z0-9_]+",
}
