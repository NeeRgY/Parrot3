--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-14:
	  Loaded immediately AFTER locales.xml. Undo the GAME_LOCALE override that
	  PreLocale.lua set, so no other addon is affected.
------------------------------------------------------------------------------]]
if _G.Parrot_localeRestore ~= nil then
	_G.GAME_LOCALE = _G.Parrot_localeRestore or nil
	_G.Parrot_localeRestore = nil
end
