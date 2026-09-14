--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-10:
	  Loaded immediately BEFORE locales.xml. If the user picked a fixed
	  interface language (Settings tab), point GAME_LOCALE at it so AceLocale-3.0
	  registers that locale's strings instead of the client's. PostLocale.lua
	  (loaded right after locales.xml) restores GAME_LOCALE. GAME_LOCALE is the
	  documented AceLocale hook for exactly this ("translators can test without
	  that client installed").
------------------------------------------------------------------------------]]
local VALID = {
	deDE = true, enUS = true, esES = true, esMX = true, frFR = true, itIT = true,
	koKR = true, ptBR = true, ruRU = true, zhCN = true, zhTW = true,
}

local sv = _G.ParrotDB
local chosen = sv and sv.global and sv.global.locale

if chosen and VALID[chosen] and chosen ~= GetLocale() then
	_G.Parrot_localeRestore = _G.GAME_LOCALE or false
	_G.GAME_LOCALE = chosen
end
