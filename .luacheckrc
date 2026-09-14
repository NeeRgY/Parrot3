-- Luacheck configuration for Parrot 3
-- Run:  luacheck .
-- (install: luarocks install luacheck)

std = "lua51"
max_line_length = false
codes = true

exclude_files = {
	"Libs/",
	"Locales/",       -- AceLocale files are huge generated tables
	".luacheckrc",
}

-- Warnings we deliberately ignore project-wide.
ignore = {
	"11./SLASH_.*",   -- writing to SLASH_* globals is the WoW slash-command API
	"11./BINDING_.*",
	"212",            -- unused argument (event handlers frequently ignore args)
	"432",            -- shadowing an upvalue argument
	"542",            -- empty if branch (used as intentional no-op placeholders)
}

-- Globals the WoW client provides that this addon reads or writes.
read_globals = {
	-- core namespaces
	"C_Spell", "C_Item", "C_CurrencyInfo", "C_Timer", "C_PartyInfo",
	"C_UnitAuras", "C_AddOns", "AuraUtil", "Constants", "Enum",
	-- libs / embeds
	"LibStub",
	-- frames & templates
	"CreateFrame", "UIParent", "GameTooltip", "BackdropTemplateMixin",
	-- unit / spell / item API
	"UnitGUID", "UnitClass", "UnitName", "UnitPower", "UnitHealth", "UnitExists",
	"UnitIsUnit", "UnitCanAttack", "UnitAura", "UnitBuff", "UnitDebuff",
	"GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "GetSpellLink",
	"GetItemInfo", "GetItemCount", "GetInventoryItemLink", "GetInventoryItemCooldown",
	"GetTime", "GetCVar", "GetCVarDefault", "GetPVPRankInfo", "GetPVPSessionStats",
	"UnitPVPRank", "GetComboPoints", "UnitHasVehicleUI", "GetShapeshiftForm",
	"GetSpecialization", "GetSpecializationInfo", "GetSpecializationInfoByID",
	-- misc
	"CombatLogGetCurrentEventInfo", "geterrorhandler", "wipe", "strsplit",
	"debugprofilestop", "hooksecurefunc", "IsInInstance", "GetInstanceInfo",
	"ITEM_QUALITY_COLORS", "COMBATLOG_OBJECT_AFFILIATION_MINE",
	"COMBATLOG_OBJECT_REACTION_FRIENDLY", "COMBATLOG_OBJECT_CONTROL_PLAYER",
	"WOW_PROJECT_ID", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
	"WOW_PROJECT_CATACLYSM_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC", "WOW_PROJECT_MAINLINE",
	"loadstring", "setfenv", "getfenv", "bit", "table", "string", "math",
}

-- Globals this addon is allowed to define / assign.
globals = {
	"SlashCmdList",
	"SLASH_PARROT1", "SLASH_PARROT2",
	"CONFIGMODE_CALLBACKS",
	"SetCVar",
	"ParrotFrame", "ParrotFlash",
}
