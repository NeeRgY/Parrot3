--[[--------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	CHANGED for the Parrot 3 fork on 2026-09-14:
	  - added Parrot:MigrateDB(): a versioned top-level database migration scaffold (db.global.dbVersion).
	  - added a Parrot:Print() helper (AceConsole is not embedded; also fixes latent Parrot:Print calls in Triggers.lua).
	  - added Parrot:TestMessages() and /parrot test|toggle|config sub-commands.
	  - added addon-compartment entry points (Parrot3_OnAddonCompartment*).
	  - added a minimap button via LibDBIcon-1.0 (/parrot toggle in the General options).
	  - added Parrot:SafeCall + /parrot errors (module lifecycle isolation).
	  - combat-log events on a private frame; COMBAT_LOG_EVENT_UNFILTERED is
	    requested from that frame's own PLAYER_LOGIN handler (a clean taint
	    context), since it is refused from any tainted path and addon load can
	    already be tainted by an earlier addon.
	  - all of Parrot's game events run through a private dispatch frame instead
	    of AceEvent-3.0's session-shared one, so another addon tainting the
	    shared dispatch can no longer turn Parrot's protected-API reads (spell
	    cooldowns, unit power, ...) into unusable "secret" values.
	  - private LibStub sandbox (Code/_Sandbox_*.lua): Parrot loads its embedded
	    libraries into a fresh private LibStub for the span of its own load, so a
	    session-wide LibStub already taint-poisoned by another addon (e.g. via
	    AccountPlayed / TipTac / EllesmereUI) can no longer taint Parrot - which
	    would otherwise block CLEU registration and make cooldown / combat
	    numbers unusable "secret" values. Every embedded lib, including
	    LibSharedMedia-3.0, is now private to Parrot.
	  - UpdateFCT()/ResetFCT() also set the "_v2" generation of the floating
	    combat text CVars (floatingCombatTextCombatDamage_v2 and friends) that
	    drives the newer, nameplate-anchored damage/heal numbers; Parrot 2 only
	    ever set the originals, so Blizzard's own numbers over enemies kept
	    showing regardless of Parrot's settings.
----------------------------------------------------------------------------]]
local _, ns = ...
ns.addon = {}

-- Parrot 3: use the private LibStub from _Sandbox_On.lua for every lookup,
-- load-time and runtime, so nothing here ever reads the session-wide (and
-- often taint-poisoned) global. See Code/_Sandbox_On.lua.
local LibStub = ns.LibStub or _G.LibStub
local Parrot = LibStub("AceAddon-3.0"):NewAddon(ns.addon, "Parrot", "AceEvent-3.0", "LibSink-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Parrot")

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- AceConfigDialog and AceGUI each keep a single tooltip frame for every
-- widget to share, created via CreateFrame("GameTooltip", "<fixed name>",
-- ...). CreateFrame with a name that already exists in _G returns the
-- EXISTING frame instead of making a new one, so even though Parrot loads
-- its own private copies of these libraries (see Code/_Sandbox_On.lua),
-- that privacy doesn't extend to frames registered under a global name -
-- whichever addon's copy created "AceConfigDialogTooltip"/"AceGUITooltip"
-- first "wins" the name, and every other addon's private copy ends up
-- sharing that one physical frame. GameTooltipTemplate also needs a real
-- frame name to lay out its own text regions correctly - an unnamed
-- replacement frame renders but shows no text at all - so the fix needs a
-- name that is both present and unique to Parrot.
do
	local function ownTooltip(name)
		return CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
	end
	if AceConfigDialog then AceConfigDialog.tooltip = ownTooltip("Parrot3AceConfigDialogTooltip") end
	local AceGUI = LibStub("AceGUI-3.0", true)
	if AceGUI then AceGUI.tooltip = ownTooltip("Parrot3AceGUITooltip") end
end

-- Parrot 3: private event dispatcher.
-- Parrot 2 used AceEvent-3.0, whose single frame and callback registry are
-- shared by every Ace-embedding addon loaded in the session. On modern retail,
-- once another addon's handler taints that shared dispatch, Parrot's handlers
-- run in the same tainted call and values Parrot then reads from protected APIs
-- (spell cooldowns, unit power, combat-log args) come back as "secret" numbers
-- that raise an error on the first comparison. Routing Parrot's own events
-- through a frame nobody else touches keeps the dispatch on a clean path.
-- API-compatible with the AceEvent-3.0 methods Parrot uses:
--   RegisterEvent(event [, "method" | func]), UnregisterEvent, UnregisterAllEvents
local Events = {}
do
	local frame = CreateFrame("Frame")
	local registry = {} -- [event] = { [target] = "method" | func | true }

	frame:SetScript("OnEvent", function(_, event, ...)
		local t = registry[event]
		if not t then return end
		for target, handler in next, t do
			if handler == true then
				target[event](target, event, ...)
			elseif type(handler) == "string" then
				target[handler](target, event, ...)
			else
				handler(event, ...)
			end
		end
	end)

	function Events.RegisterEvent(target, event, handler)
		local t = registry[event]
		if not t then
			t = {}
			registry[event] = t
			frame:RegisterEvent(event)
		end
		t[target] = handler or true
	end

	function Events.UnregisterEvent(target, event)
		local t = registry[event]
		if not t then return end
		t[target] = nil
		if not next(t) then
			registry[event] = nil
			frame:UnregisterEvent(event)
		end
	end

	function Events.UnregisterAllEvents(target)
		for event, t in next, registry do
			if t[target] ~= nil then
				t[target] = nil
				if not next(t) then
					registry[event] = nil
					frame:UnregisterEvent(event)
				end
			end
		end
	end

	function Events.Embed(target)
		target.RegisterEvent = Events.RegisterEvent
		target.UnregisterEvent = Events.UnregisterEvent
		target.UnregisterAllEvents = Events.UnregisterAllEvents
		return target
	end
end
Parrot.Events = Events
Events.Embed(Parrot)

-- Every Parrot submodule gets the private dispatcher too, overriding the
-- AceEvent-3.0 methods the modules still request in their :NewModule() calls.
do
	local _NewModule = Parrot.NewModule
	function Parrot:NewModule(name, ...)
		return Events.Embed(_NewModule(self, name, ...))
	end
end

-- Debug
local debug = function() end
--[==[@debug@
do
	local PARROT_DEBUG_FRAME = _G.ChatFrame4
	local function nilCacheFunc() return nil end
	local function writeFunc(self, msg) PARROT_DEBUG_FRAME:AddMessage(msg) end

	function debug(arg1, ...)
		if type(arg1) == "table" then
			local loaded = LoadAddOn("Blizzard_DebugTools")
			if not loaded then
				PARROT_DEBUG_FRAME:AddMessage("|cff00ff00Parrot|r: !!! table-dump skipped")
				return debug(...)
			end

			local context = {
				depth = 2,
				GetTableName = nilCacheFunc,
				GetFunctionName = nilCacheFunc,
				GetUserdataName = nilCacheFunc,
				Write = writeFunc,
			}
			PARROT_DEBUG_FRAME:AddMessage("|cff00ff00Parrot|r: +++ table-dump")
			_G.DevTools_RunDump(arg1, context)
			PARROT_DEBUG_FRAME:AddMessage("|cff00ff00Parrot|r: --- end of table-dump")
			return debug(...)
		else
			local text = strjoin(" ", tostringall(arg1, ...))
			PARROT_DEBUG_FRAME:AddMessage("|cff00ff00Parrot|r: " .. text)
		end
	end
end
--@end-debug@]==]
Parrot.debug = debug

-- Table recycling
local new, del
do
	local pool = setmetatable({}, {__mode = 'kv'})

	function new()
		local t = next(pool)
		if t then
			pool[t] = nil
		else
			t = {}
		end
		return t
	end

	function del(t)
		if not t then
			error(("Bad argument #1 to 'del'. Expected %q, got %q."):format("table", type(t)), 2)
		end
		setmetatable(t, nil)
		wipe(t)
		pool[t] = true
		return nil
	end
end

local function newList(...)
	local t = new()
	for i = 1, select('#', ...) do
		t[i] = select(i, ...)
	end
	return t
end

local function newDict(...)
	local t = new()
	for i = 1, select('#', ...), 2 do
		local k, v = select(i, ...)
		t[k] = v
	end
	return t
end

Parrot.newList = newList
Parrot.newDict = newDict
Parrot.del = del

-- LibDeformat-3.0 replacement
-- This is Jerry's GetPattern function from LibItemBonus-2.0.
local GetPattern
do
	-- This is very much a ripoff of Deformat, simplified in that it does not
	-- handle merged patterns

	local next, ipairs, assert, loadstring = next, ipairs, assert, loadstring
	local tconcat = table.concat
	local function donothing() end

	local cache = {}
	local sequences = {
		["%d*d"] = "%%-?%%d+",
		["s"] = ".+",
		["[fg]"] = "%%-?%%d+%%.?%%d*",
		["%%%.%d[fg]"] = "%%-?%%d+%%.?%%d*",
		["c"] = ".",
	}

	local function get_first_pattern(s)
		local first_pos, first_pattern
		for pattern in next, sequences do
			local pos = s:find("%%%%"..pattern)
			if pos and (not first_pos or pos < first_pos) then
				first_pos, first_pattern = pos, pattern
			end
		end
		return first_pattern
	end

	local function get_indexed_pattern(s, i)
		for pattern in next, sequences do
			if s:find("%%%%" .. i .. "%%%$" .. pattern) then
				return pattern
			end
		end
	end

	local function unpattern_unordered(unpattern, f)
		local i = 1
		while true do
			local pattern = get_first_pattern(unpattern)
			if not pattern then return unpattern, i > 1 end

			unpattern = unpattern:gsub("%%%%" .. pattern, "(" .. sequences[pattern] .. ")", 1)
			f[i] = (pattern ~= "c" and pattern ~= "s")
			i = i + 1
		end
	end

	local function unpattern_ordered(unpattern, f)
		local i = 1
		while true do
			local pattern = get_indexed_pattern(unpattern, i)
			if not pattern then return unpattern, i > 1 end

			unpattern = unpattern:gsub("%%%%" .. i .. "%%%$" .. pattern, "(" .. sequences[pattern] .. ")", 1)
			f[i] = (pattern ~= "c" and pattern ~= "s")
			i = i + 1
		end
	end

	function GetPattern(pattern)
		local unpattern, f, matched = '^' .. pattern:gsub("([%(%)%.%*%+%-%[%]%?%^%$%%])", "%%%1") .. '$', {}
		if not pattern:find("%1$", nil, true) then
			unpattern, matched = unpattern_unordered(unpattern, f)
			if not matched then
				return donothing
			else
				local locals, returns = {}, {}
				for index, number in ipairs(f) do
					local l = ("v%d"):format(index)
					locals[index] = l
					if number then
						returns[#returns + 1] = "n("..l..")"
					else
						returns[#returns + 1] = l
					end
				end
				locals = tconcat(locals, ",")
				returns = tconcat(returns, ",")
				local code = ("local m, n = string.match, tonumber return function(s) local %s = m(s, %q) return %s end"):format(locals, unpattern, returns)
				return assert(loadstring(code))()
			end
		else
			unpattern, matched = unpattern_ordered(unpattern, f)
			if not matched then
				return donothing
			else
				local i, o = 1, {}
				pattern:gsub("%%(%d)%$", function(w) o[i] = tonumber(w); i = i + 1; end)
				local sorted_locals, returns = {}, {}
				for index, number in ipairs(f) do
					local l = ("v%d"):format(index)
					sorted_locals[index] = ("v%d"):format(o[index])
					if number then
						returns[#returns + 1] = "n("..l..")"
					else
						returns[#returns + 1] = l
					end
				end
				sorted_locals = tconcat(sorted_locals, ",")
				returns = tconcat(returns, ",")
				local code =("local m, n = string.match, tonumber return function(s) local %s = m(s, %q) return %s end"):format(sorted_locals, unpattern, returns)
				return assert(loadstring(code))()
			end
		end
	end

	function Parrot.Deformat(text, pattern)
		local func = cache[pattern]
		if not func then
			func = GetPattern(pattern)
			cache[pattern] = func
		end
		return func(text)
	end
end

-- Init
local db = nil
local defaults = {
	global = {
		locale = "auto",
	},
	profile = {
		gameText = true,
		gameSelf = false,
		gameDamage = false,
		gamePetDamage = false,
		gameHealing = false,
		gameLowHealth = false,
		gameReactives = false,
	}
}

-- Locales Parrot ships translations for.
local PARROT_LOCALES = {
	deDE = "Deutsch", enUS = "English",
	esES = "Espa\195\177ol (EU)", esMX = "Espa\195\177ol (AL)",
	frFR = "Fran\195\167ais", itIT = "Italiano",
	koKR = "\237\149\156\234\181\173\236\150\180", ptBR = "Portugu\195\170s",
	ruRU = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",
	zhCN = "\231\174\128\228\189\147\228\184\173\230\150\135",
	zhTW = "\231\185\129\233\171\148\228\184\173\230\150\135",
}
local PARROT_LOCALE_ORDER = { "auto", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

StaticPopupDialogs["PARROT3_RELOAD"] = {
	text = "Parrot 3\n\n" .. (L["Reload your interface now to apply the language change?"] or "Reload UI now?"),
	button1 = _G.OKAY or "Okay",
	button2 = _G.CANCEL or "Cancel",
	OnAccept = ReloadUI,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
	preferredIndex = 3,
}

-- Database schema versioning.
-- Per-module trigger data has its own versioned migration in Triggers.lua
-- (db.dbver2). This handles cross-cutting / top-level schema changes: bump
-- PARROT_DB_VERSION and add a step function when the stored layout changes.
local PARROT_DB_VERSION = 3

local dbMigrations = {
	-- [n] = function(profile, profileName) ... end, -- upgrades profile from v(n-1) to v(n)
}

-- Error isolation: run module lifecycle / migration calls through pcall so one
-- broken module can't abort the whole chain. Collected errors: /parrot errors.
Parrot.errors = {}
function Parrot:SafeCall(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local e = self.errors
		e[#e + 1] = ("|cffff8080%s|r  %s"):format(where, tostring(err))
		if #e > 40 then table.remove(e, 1) end
		geterrorhandler()("Parrot 3: " .. where .. "\n" .. tostring(err))
	end
	return ok
end

function Parrot:MigrateDB()
	local sv = self.db.global
	local from = sv.dbVersion or 0
	if from >= PARROT_DB_VERSION then return end
	for v = from + 1, PARROT_DB_VERSION do
		local step = dbMigrations[v]
		if step then
			for name, profile in pairs(self.db.profiles) do
				self:SafeCall("db migration " .. v, step, profile, name)
			end
		end
	end
	sv.dbVersion = PARROT_DB_VERSION
end

function Parrot:OnProfileChanged(event, database)
	db = self.db.profile
	for _, mod in self:IterateModules() do
		if type(mod.OnProfileChanged) == "function" then
			self:SafeCall("module '" .. (mod.moduleName or "?") .. "':OnProfileChanged",
				mod.OnProfileChanged, mod, event, database)
		end
	end
	self:UpdateFCT()

	local LDBIcon = LibStub("LibDBIcon-1.0", true)
	if LDBIcon and LDBIcon:IsRegistered("Parrot") then
		self.db.profile.minimap = self.db.profile.minimap or {}
		LDBIcon:Refresh("Parrot", self.db.profile.minimap)
	end
end

-- Simple chat print helper (AceConsole is not embedded).
function Parrot:Print(...)
	local n = select("#", ...)
	local msg
	if n <= 1 then
		msg = tostring((...))
	else
		local t = {}
		for i = 1, n do t[i] = tostring(select(i, ...)) end
		msg = table.concat(t, " ")
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Parrot 3|r: " .. msg)
end

-- Fire a sample message into every scroll area (/parrot test).
function Parrot:TestMessages()
	if not self:IsEnabled() then
		self:Print("addon is disabled - use /parrot toggle to enable it")
		return
	end
	local count = 0
	for area in next, self:GetScrollAreasChoices() do
		count = count + 1
		self:ShowMessage(("Parrot test %d"):format(count), area, false, math.random(), math.random(), math.random())
		self:ShowMessage(("Crit %d!"):format(count), area, true, 1, 1, 0)
	end
	if count == 0 then
		self:ShowMessage("Parrot test", "Notification", false, 1, 1, 1)
	end
end

-- Addon compartment (retail minimap addon menu) entry points; wired up in the TOC.
function Parrot3_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		if Parrot:IsEnabled() then Parrot:Disable() else Parrot:Enable() end
		Parrot:Print(Parrot:IsEnabled() and "enabled" or "disabled")
	else
		Parrot:ShowConfig()
	end
end

function Parrot3_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	GameTooltip:AddLine("Parrot 3")
	GameTooltip:AddLine("|cffffffffLeft-click|r  open configuration", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffRight-click|r  enable / disable", 1, 1, 1)
	GameTooltip:Show()
end

function Parrot3_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

function Parrot:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ParrotDB", defaults, true)
	LibStub("LibDualSpec-1.0"):EnhanceDatabase(self.db, "Parrot")
	db = self.db.profile

	self:MigrateDB()
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	self.options = {
		name = L["Parrot"],
		desc = L["Floating Combat Text of awesomeness. Caw. It'll eat your crackers."],
		type = "group",
		icon = [[Interface\Icons\Spell_Nature_ForceOfNature]],
		args = {},
	}

	-- stub options table to show in Interface Options
	local options = CopyTable(self.options)
	options.args.load = {
		type = "execute",
		name = L["Load config"],
		desc = L["Load configuration options"],
		func = "ShowConfig",
		handler = self,
	}
	AceConfig:RegisterOptionsTable("Parrot/Blizzard", options)
	AceConfigDialog:AddToBlizOptions("Parrot/Blizzard", L["Parrot"])

	SLASH_PARROT1 = "/parrot"
	SLASH_PARROT2 = "/par"
	function SlashCmdList.PARROT(input)
		input = (input or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if input == "test" then
			self:TestMessages()
		elseif input == "toggle" then
			if self:IsEnabled() then self:Disable() else self:Enable() end
			self:Print(self:IsEnabled() and "enabled" or "disabled")
		elseif input == "errors" then
			if #self.errors == 0 then
				self:Print("no captured errors.")
			else
				self:Print(("captured errors (%d):"):format(#self.errors))
				for _, line in ipairs(self.errors) do
					DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
				end
			end
		elseif input == "" or input == "config" or input == "options" then
			self:ShowConfig()
		else
			self:Print("|cffffffff/parrot|r open config   |cffffffff/parrot test|r sample messages   |cffffffff/parrot toggle|r enable/disable   |cffffffff/parrot errors|r show captured errors")
		end
	end

	local LibSink = LibStub("LibSink-2.0")
	local function sink(addon, text, r, g, b, font, size, outline, sticky, location, icon)
		local storage = LibSink.storageForAddon[addon]
		if storage then
			location = storage.sink20ScrollArea or location or "Notification"
			sticky = storage.sink20Sticky or sticky
		end
		self:ShowMessage(text, location, sticky, r, g, b, font, size, outline, icon)
	end
	local function getScrollAreasChoices()
		local tmp = {}
		for k, v in next, self:GetScrollAreasChoices() do
			tmp[#tmp+1] = v
		end
		return tmp
	end
	self:RegisterSink("Parrot", L["Parrot"], nil, sink, getScrollAreasChoices, true)

	local ldbObject = LibStub("LibDataBroker-1.1"):NewDataObject("Parrot", {
		type = "launcher",
		icon = [[Interface\Icons\Spell_Nature_ForceOfNature]],
		OnClick = function(_, button)
			if button == "RightButton" then
				if Parrot:IsEnabled() then Parrot:Disable() else Parrot:Enable() end
				Parrot:Print(Parrot:IsEnabled() and "enabled" or "disabled")
			else
				Parrot:ShowConfig()
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("Parrot 3", 1, 1, 1)
			tt:AddLine("Left-click  open configuration", 1, 1, 1)
			tt:AddLine("Right-click  enable / disable", 1, 1, 1)
		end,
		label = L["Parrot"],
	})

	local LDBIcon = LibStub("LibDBIcon-1.0", true)
	if LDBIcon then
		-- Same global-tooltip-frame-name collision as AceConfigDialog/AceGUI
		-- above - LibDBIcon-1.0 creates its shared tooltip as
		-- CreateFrame("GameTooltip", "LibDBIconTooltip", ...), so Parrot's
		-- private copy can end up sharing a physical frame with whichever
		-- addon's copy of the library created that name first.
		if not LDBIcon.__parrotOwnTooltip then
			LDBIcon.tooltip = CreateFrame("GameTooltip", "Parrot3LibDBIconTooltip", UIParent, "GameTooltipTemplate")
			LDBIcon.__parrotOwnTooltip = true
		end
		self.db.profile.minimap = self.db.profile.minimap or {}
		LDBIcon:Register("Parrot", ldbObject, self.db.profile.minimap)
	end

end

do
	local fct = {
	  "enableFloatingCombatText",
	  "floatingCombatTextCombatDamage",
	  "floatingCombatTextCombatDamageAllAutos",
	  "floatingCombatTextCombatLogPeriodicSpells",
	  "floatingCombatTextPetMeleeDamage",
	  "floatingCombatTextPetSpellDamage",
	  "floatingCombatTextCombatHealing",
	  "floatingCombatTextCombatHealingAbsorbTarget",
	  "floatingCombatTextCombatHealingAbsorbSelf",
	  "floatingCombatTextReactives",
	  "floatingCombatTextLowManaHealth",
	  "floatingCombatTextDodgeParryMiss",
	  "floatingCombatTextCombatState",
	  "floatingCombatTextDamageReduction",
		-- The newer "_v2" generation of these CVars drives the
		-- nameplate-anchored damage/heal numbers. Not every CVar has a
		-- "_v2" variant, so which one applies is auto-detected per CVar
		-- (see cvarExists()/realCVarName() below) rather than listed here.
	}

	-- SetCVar alone doesn't make Blizzard's already-running CombatText
	-- frame re-read these settings - the default UI's own options panel
	-- explicitly pokes it via CombatText_UpdateDisplayedMessages() after
	-- changing the CVars. Without this, a live toggle only took effect
	-- after the next /reload even though the CVar itself was already set
	-- correctly.
	local function refreshBlizzardCombatText()
		if CombatText_UpdateDisplayedMessages then
			CombatText_UpdateDisplayedMessages()
		end
	end

	-- Several floatingCombatTextXXX CVars have a matching GLOBAL VARIABLE
	-- that the "on me" (self) combat-text engine actually reads - e.g.
	-- Miss/Dodge/Parry's real switch is the global
	-- COMBAT_TEXT_SHOW_DODGE_PARRY_MISS, not just SHOW_COMBAT_TEXT (which
	-- is only the master "on me" toggle). SetCVar-ing
	-- enableFloatingCombatText alone also doesn't reliably get picked up
	-- live - flipping it through "1" and back to the desired value forces
	-- the engine to re-read it.
	local GLOBAL_FOR_CVAR = {
		enableFloatingCombatText = "SHOW_COMBAT_TEXT",
		floatingCombatTextLowManaHealth = "COMBAT_TEXT_SHOW_LOW_HEALTH_MANA",
		floatingCombatTextCombatState = "COMBAT_TEXT_SHOW_COMBAT_STATE",
		floatingCombatTextDodgeParryMiss = "COMBAT_TEXT_SHOW_DODGE_PARRY_MISS",
		floatingCombatTextDamageReduction = "COMBAT_TEXT_SHOW_RESISTANCES",
		floatingCombatTextReactives = "COMBAT_TEXT_SHOW_REACTIVES",
	}

	local function cvarExists(name)
		return GetCVarDefault(name) ~= nil
	end

	local function realCVarName(cvar)
		if cvarExists(cvar .. "_v2") then
			return cvar .. "_v2"
		end
		return cvar
	end

	local function setFCT(cvar, on)
		SetCVar(realCVarName(cvar), on and "1" or "0")
		local gvar = GLOBAL_FOR_CVAR[cvar]
		if gvar then
			_G[gvar] = on and "1" or "0"
		end
	end

	-- The master "on me" toggle needs the flip-through-1 trick to actually
	-- apply (see point 2 above) regardless of which value it's heading to.
	local function forceApplyEnableFCT(on)
		setFCT("enableFloatingCombatText", true)
		setFCT("enableFloatingCombatText", on)
	end

	function Parrot:ResetFCT()
		for _, var in next, fct do
			SetCVar(var, GetCVarDefault(var))
			if cvarExists(var .. "_v2") then
				SetCVar(var .. "_v2", GetCVarDefault(var .. "_v2"))
			end
		end
		forceApplyEnableFCT(true)
		_G.COMBAT_TEXT_SHOW_LOW_HEALTH_MANA = "1"
		_G.COMBAT_TEXT_SHOW_COMBAT_STATE = "1"
		_G.COMBAT_TEXT_SHOW_DODGE_PARRY_MISS = "1"
		_G.COMBAT_TEXT_SHOW_RESISTANCES = "1"
		_G.COMBAT_TEXT_SHOW_REACTIVES = "1"
		refreshBlizzardCombatText()
	end

	-- Current Retail silently refuses SetCVar for these particular CVars
	-- while the player is in combat (no error, the write just doesn't take).
	-- Deferred writes retry once combat ends via PLAYER_REGEN_ENABLED below.
	local pendingFCTUpdate = false

	function Parrot:UpdateFCT()
		if InCombatLockdown() then
			pendingFCTUpdate = true
			return
		end
		pendingFCTUpdate = false
		if db.gameText then
			forceApplyEnableFCT(db.gameSelf)
			setFCT("floatingCombatTextDodgeParryMiss", db.gameSelf)
			setFCT("floatingCombatTextCombatState", db.gameSelf)
			setFCT("floatingCombatTextDamageReduction", db.gameSelf)
			setFCT("floatingCombatTextReactives", db.gameReactives)
			setFCT("floatingCombatTextLowManaHealth", db.gameLowHealth)

			setFCT("floatingCombatTextCombatDamage", db.gameDamage)
			setFCT("floatingCombatTextCombatDamageAllAutos", db.gameDamage)
			setFCT("floatingCombatTextCombatLogPeriodicSpells", db.gameDamage)

			setFCT("floatingCombatTextPetMeleeDamage", db.gamePetDamage)
			setFCT("floatingCombatTextPetSpellDamage", db.gamePetDamage)

			setFCT("floatingCombatTextCombatHealing", db.gameHealing)
			setFCT("floatingCombatTextCombatHealingAbsorbTarget", db.gameHealing)
			setFCT("floatingCombatTextCombatHealingAbsorbSelf", db.gameHealing)

			refreshBlizzardCombatText()
		end
	end

	-- Retry any FCT update that InCombatLockdown() deferred above, as soon
	-- as combat ends (this event itself always fires in a clean, secure
	-- context, so the retried SetCVar calls are safe here).
	Parrot:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pendingFCTUpdate then
			Parrot:UpdateFCT()
		end
	end)
end

function Parrot:OnEnable()
	self:UpdateFCT()
end

-- Event handling
local nextUID
do
	local uid = 0
	function nextUID()
		uid = uid + 1
		return uid
	end
end

do
	local combatLogHandlers = {}

	-- Parrot 3: combat-log events are delivered on a private frame.
	-- On modern retail, Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") is
	-- refused from any *tainted* execution path. During the loading screen every
	-- addon that loads after a taint-spreading one (common with error-grabber
	-- and data-broker addons) inherits that taint in its own main chunk *and*
	-- through the whole AceAddon OnInitialize/OnEnable cascade, so neither is a
	-- safe place to register. Instead this frame requests the event from its own
	-- PLAYER_LOGIN / PLAYER_ENTERING_WORLD handler: those the C side dispatches
	-- to us in a clean taint context, and they are not themselves restricted, so
	-- asking for them from the main chunk is fine. The CLEU handler is a no-op
	-- until a module calls Parrot:RegisterCombatLog.
	local cleuFrame = CreateFrame("Frame")
	local cleuRegistered = false

	cleuFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
			if not cleuRegistered then
				cleuRegistered = true
				cleuFrame:UnregisterEvent("PLAYER_LOGIN")
				cleuFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
				-- Parrot 3: RegisterEvent for a restricted event is silently
				-- refused (no catchable Lua error) when the execution is
				-- tainted, but it still logs an ADDON_ACTION_FORBIDDEN entry
				-- via BugGrabber/the default error handler - issecure() lets
				-- us predict the refusal and skip the call outright instead
				-- of triggering that log entry for nothing. IsEventRegistered
				-- stays as a fallback check in case issecure() and the actual
				-- RegisterEvent policy ever disagree. Either way, if we don't
				-- get COMBAT_LOG_EVENT_UNFILTERED, Code/CombatFeedFallback.lua
				-- takes over with a best-effort, non-combat-log damage/heal
				-- feed.
				if issecure() then
					cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				end
				if not cleuFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
					Parrot.combatLogBlocked = true
					Parrot:Print(L["Combat log access is blocked this session (likely an addon conflict) - switching to a simplified, approximate damage/heal feed. /parrot errors has no details for this since it isn't a Lua error."])
				end
			end
			return
		end
		if not next(combatLogHandlers) then return end
		local uid = nextUID()
		for mod in next, combatLogHandlers do
			mod:HandleCombatlogEvent(uid, CombatLogGetCurrentEventInfo())
		end
	end)
	cleuFrame:RegisterEvent("PLAYER_LOGIN")
	cleuFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

	function Parrot:RegisterCombatLog(mod)
		if type(mod.HandleCombatlogEvent) ~= "function" then
			error("Bad argument #1 for 'RegisterCombatLog'. Module must contain a function named HandleCombatlogEvent")
		end
		combatLogHandlers[mod] = true
	end

	function Parrot:UnregisterCombatLog(mod)
		combatLogHandlers[mod] = nil
	end
end

do
	local blizzardEventHandlers = {}

	local function OnBlizzardEvent(event, ...)
		local uid = nextUID()
		for mod, func in next, blizzardEventHandlers[event] do
			mod[func](mod, uid, event, ...)
		end
	end

	function Parrot:RegisterBlizzardEvent(mod, event, func)
		if func then
			if type(mod[func]) ~= "function" then
				error(("Bad argument #3 for 'RegisterBlizzardEvent'. Module must contain a function named %s"):format(func))
			end
		elseif type(mod[event]) ~= "function" then
			error(("Bad argument #2 for 'RegisterBlizzardEvent'. Module must contain a function named %s"):format(event))
		end

		if not blizzardEventHandlers[event] then
			blizzardEventHandlers[event] = {}
			self:RegisterEvent(event, OnBlizzardEvent)
		end
		if not blizzardEventHandlers[event][mod] then
			blizzardEventHandlers[event][mod] = {}
		end
		blizzardEventHandlers[event][mod] = func or event
	end

	function Parrot:UnregisterBlizzardEvent(mod, event)
		blizzardEventHandlers[event][mod] = nil
		if not next(blizzardEventHandlers[event]) then
			self:UnregisterEvent(event)
			blizzardEventHandlers[event] = nil
		end
	end

	function Parrot:UnregisterAllBlizzardEvents(mod)
		for _, modules in next, blizzardEventHandlers do
			modules[mod] = nil
		end
	end
end

-- Config
do
	local LibSharedMedia = LibStub("LibSharedMedia-3.0")

	Parrot.soundValues = LibSharedMedia:List("sound")
	Parrot.fontValues = LibSharedMedia:List("font")
	Parrot.fontWithInheritValues = {}

	local function rebuild(_, mediatype)
		if mediatype == "font" then
			wipe(Parrot.fontWithInheritValues)
			for i, v in next, Parrot.fontValues do
				Parrot.fontWithInheritValues[i] = v
			end
			Parrot.fontWithInheritValues[-1] = L["Inherit"]
		end
	end
	rebuild(nil, "font")

	LibSharedMedia.RegisterCallback(Parrot, "LibSharedMedia_Registered", rebuild)
end

function Parrot:ShowConfig()
	if self.OnOptionsCreate then
		self:SafeCall("Parrot:OnOptionsCreate", self.OnOptionsCreate, self)

		for _, mod in self:IterateModules() do
			if type(mod.OnOptionsCreate) == "function" then
				self:SafeCall("module '" .. (mod.moduleName or "?") .. "':OnOptionsCreate",
					mod.OnOptionsCreate, mod)
			end
		end
		if not self.options.args.settings then
			self.db.profile.minimap = self.db.profile.minimap or {}
			local localeValues = {}
			for _, lc in ipairs(PARROT_LOCALE_ORDER) do
				if lc == "auto" then
					localeValues.auto = L["Automatic (client language)"]
				else
					localeValues[lc] = PARROT_LOCALES[lc] or lc
				end
			end
			self:AddOption("settings", {
				type = "group",
				name = L["Settings"],
				desc = L["Addon settings"],
				order = 2,
				args = {
					minimapIcon = {
						type = "toggle",
						name = L["Minimap icon"],
						desc = L["Show a Parrot icon on the minimap."],
						order = 1,
						width = "full",
						hidden = function() return not LibStub("LibDBIcon-1.0", true) end,
						get = function() return not Parrot.db.profile.minimap.hide end,
						set = function(_, value)
							Parrot.db.profile.minimap.hide = not value
							local ic = LibStub("LibDBIcon-1.0", true)
							if ic then
								if value then ic:Show("Parrot") else ic:Hide("Parrot") end
							end
						end,
					},
					language = {
						type = "select",
						name = L["Language"],
						desc = L["The language Parrot's interface uses. Takes effect after a UI reload."],
						order = 2,
						values = localeValues,
						sorting = PARROT_LOCALE_ORDER,
						get = function() return Parrot.db.global.locale or "auto" end,
						set = function(_, value)
							Parrot.db.global.locale = value
							StaticPopup_Show("PARROT3_RELOAD")
						end,
					},
				},
			})
		end

		AceConfig:RegisterOptionsTable("Parrot", self.options)

		self.OnOptionsCreate = nil
	end

	AceConfigDialog:Open("Parrot")
end

function Parrot:AddOption(name, args)
	self.options.args[name] = args
end

function Parrot:OnOptionsCreate()
	local function setCVarOption(info, value)
		db[info[#info]] = value
		self:UpdateFCT()
	end
	local function disabled()
		return not db.gameText
	end

	self:AddOption("profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
	self.options.args.profiles.order = -1
	LibStub("LibDualSpec-1.0"):EnhanceOptions(self.options.args.profiles, self.db)

	self:AddOption("general", {
		type = "group",
		name = L["General"],
		desc = L["General settings"],
		disabled = function() return not self:IsEnabled() end,
		order = 1,
		args = {
			gameText = {
				type = "group",
				inline = true,
				name = _G.COMBAT_TEXT_LABEL, -- Floating Combat Text
				get = function(info) return db[info[#info]] end,
				set = setCVarOption,
				args = {
					gameText = {
						type = "toggle",
						name = L["Control game options"],
						desc = L["Whether Parrot should control the default interface's options below.\nThese settings always override manual changes to the default interface options."],
						descStyle = "inline",
						set = function(info, value)
							db[info[#info]] = value
							if value then
								self:UpdateFCT()
							else
								self:ResetFCT()
							end
						end,
						order = 0,
						width = "full",
					},
					gameSelf = {
						type = "toggle",
						name = _G.COMBAT_SELF, -- Combat Self
						desc = _G.OPTION_TOOLTIP_SHOW_COMBAT_TEXT, -- Checking this will enable additional combat messages to appear in the playfield.
						disabled = disabled,
						order = 1,
					},
					gameDamage = {
						type = "toggle",
						name = _G.SHOW_DAMAGE_TEXT, -- Damage
						desc = _G.OPTION_TOOLTIP_SHOW_DAMAGE, -- Display damage numbers over hostile creatures when damaged.
						disabled = disabled,
						order = 2,
					},
					gamePetDamage = {
						type = "toggle",
						name = _G.SHOW_PET_MELEE_DAMAGE, -- Pet Damage
						desc = _G.OPTION_TOOLTIP_SHOW_PET_MELEE_DAMAGE, -- Show damage caused by your pet.
						disabled = disabled,
						order = 3,
					},
					gameHealing = {
						type = "toggle",
						name = _G.SHOW_COMBAT_HEALING, -- Healing
						desc = _G.OPTION_TOOLTIP_SHOW_COMBAT_HEALING, -- Display amount of healing you did to the target.
						disabled = disabled,
						order = 4,
					},
					gameLowHealth = {
						type = "toggle",
						name = _G.COMBAT_TEXT_SHOW_LOW_HEALTH_MANA_TEXT, -- Low Mana & Health
						desc = _G.OPTION_TOOLTIP_COMBAT_TEXT_SHOW_LOW_HEALTH_MANA, -- Shows a message when you fall below 20% mana or health.
						disabled = disabled,
						order = 5,
					},
					gameReactives = {
						type = "toggle",
						name = _G.COMBAT_TEXT_SHOW_REACTIVES_TEXT, -- Spell Alerts
						desc = _G.OPTION_TOOLTIP_COMBAT_TEXT_SHOW_REACTIVES, -- Show alerts when certain important events occur.
						disabled = disabled,
						order = 6,
					},
				},
			},
		}
	})
end

_G.Parrot = Parrot
