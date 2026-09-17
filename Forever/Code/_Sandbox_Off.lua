--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-14 - taint sandbox, part 3 of 3.
	Put the session-wide LibStub back for everyone else. Parrot keeps using its
	private copy through ns.LibStub (its runtime files declare
	`local LibStub = ns.LibStub`).

	Note: because Parrot's LibSharedMedia-3.0 is now private, the font / sound
	pickers list only what Parrot bundles plus what Parrot itself registers -
	media added by a standalone SharedMedia addon is not merged in (doing so
	safely would risk pulling that addon's taint back into Parrot).
------------------------------------------------------------------------------]]
local _, ns = ...

-- Restore the shared LibStub. If there wasn't one (Parrot was the first addon
-- to need it) keep the private instance in place so the global still exists
-- for addons that load after Parrot.
_G.LibStub = _G.__Parrot3_globalLibStub or ns.LibStub
_G.__Parrot3_globalLibStub = nil
