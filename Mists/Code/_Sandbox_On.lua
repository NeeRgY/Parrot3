--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	Taint sandbox, part 2 of 3.

	Another addon in the session can taint the shared global `LibStub` table
	very early at login; every addon that then calls LibStub("Ace...")
	inherits that taint for the rest of its code. On modern retail a tainted
	addon may not call Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED"),
	and gets "secret" numbers back from GetSpellCooldown, combat-log
	payloads, UnitPower, ... which raise an error on the first comparison.

	For the span of Parrot's own load (this file .. _Sandbox_Off.lua) the
	global `LibStub` is pointed at a private instance built here, which no
	other addon has touched. Parrot's embedded Ace3 / LibSink / LibDBIcon /
	locale files register into it and Parrot reads from it; _Sandbox_Off.lua
	restores the real one so nothing else in the session is affected. As a
	side effect every library Parrot embeds becomes private, which also takes
	Parrot out of the shared-AceEvent-frame taint completely.
------------------------------------------------------------------------------]]
local _, ns = ...

local type, tonumber, error, assert, setmetatable, pairs, tostring, strmatch =
	type, tonumber, error, assert, setmetatable, pairs, tostring, string.match

-- Self-contained LibStub, same contract as Libs/LibStub/LibStub.lua. `minor`
-- is set high so the bundled copy that loads next sees a newer LibStub and
-- leaves this one in place.
local priv = { libs = {}, minors = {}, minor = 100 }

function priv:NewLibrary(major, minor)
	assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
	minor = assert(tonumber(strmatch(minor, "%d+")), "Minor version must either be a number or contain a number.")
	local oldminor = self.minors[major]
	if oldminor and oldminor >= minor then return nil end
	self.minors[major], self.libs[major] = minor, self.libs[major] or {}
	return self.libs[major], oldminor
end

function priv:GetLibrary(major, silent)
	if not self.libs[major] and not silent then
		error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
	end
	return self.libs[major], self.minors[major]
end

function priv:IterateLibraries() return pairs(self.libs) end
setmetatable(priv, { __call = priv.GetLibrary })

ns.LibStub = priv
_G.LibStub = priv
