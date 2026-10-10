--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-18:
	  WoW: Forever reports WOW_PROJECT_ID == WOW_PROJECT_MAINLINE, so the client
	  loads this Mainline tree (and its embedded libraries), but its Lua API
	  doesn't expose the modern specialization functions (it plays like a
	  classic-style client). LibDualSpec-1.0 assumes "isRetail" whenever
	  WOW_PROJECT_ID is WOW_PROJECT_MAINLINE and calls those functions
	  unconditionally, crashing on load. Define harmless stand-ins only if the
	  real functions are missing, before the library loads (see embeds.xml) -
	  numSpecs 0 makes the library's retail branch a no-op instead of erroring.
------------------------------------------------------------------------------]]
if not _G.GetNumSpecializationsForClassID then
	function _G.GetNumSpecializationsForClassID()
		return 0
	end
end
if not _G.GetSpecializationInfoForClassID then
	function _G.GetSpecializationInfoForClassID()
		return nil
	end
end
if not _G.GetSpecialization then
	function _G.GetSpecialization()
		return 0
	end
end
if not _G.GetSpecializationInfo then
	function _G.GetSpecializationInfo()
		return nil
	end
end
