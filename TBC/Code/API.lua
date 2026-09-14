--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork:
	  Parrot.API - one place per game client to talk to the WoW spell / item
	  APIs. This file is the Classic (TBC) implementation, using the
	  global spell API.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local API = {}
Parrot.API = API

-- Spells --------------------------------------------------------------------
function API.GetSpellName(spell)
	return (GetSpellInfo(spell))
end

function API.GetSpellTexture(spell)
	return (GetSpellTexture(spell))
end

function API.DoesSpellExist(spell)
	return GetSpellInfo(spell) ~= nil
end

-- returns: startTime, duration, isEnabled
function API.GetSpellCooldown(spell)
	local start, duration, enabled = GetSpellCooldown(spell)
	return start, duration, enabled
end

function API.IsSpellUsable(spell)
	return IsUsableSpell(spell)
end

-- Items --------------------------------------------------------------------
function API.GetItemIcon(item)
	return (GetItemIcon(item))
end

function API.GetItemInfo(item)
	return GetItemInfo(item)
end

-- Power ------------------------------------------------------------------------
function API.GetComboPoints(unit, target)
	return GetComboPoints(unit or "player", target or "target")
end
