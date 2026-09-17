--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-14 - taint sandbox, part 1 of 3.
	Stash the session-wide LibStub so _Sandbox_Off.lua can put it back. Reading
	it taints this tiny chunk, which is why it is on its own and does nothing
	else. See _Sandbox_On.lua for the full rationale.
------------------------------------------------------------------------------]]
-- Only a dedicated global holds the (possibly tainted) real LibStub; the addon
-- table `ns` is deliberately not touched here so its other fields stay clean.
_G.__Parrot3_globalLibStub = _G.LibStub
