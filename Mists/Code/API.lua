--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork:
	  Parrot.API - one place per game client to talk to the WoW spell / item
	  APIs. This file is the MoP Classic (5.5.x) implementation: it prefers the
	  modern C_Spell / C_Item namespaces where the client provides them and
	  falls back to the classic global spell API otherwise.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local C_Spell = _G.C_Spell
local C_Item  = _G.C_Item

local API = {}
Parrot.API = API

-- Spells --------------------------------------------------------------------
function API.GetSpellName(spell)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spell)
	end
	return (GetSpellInfo(spell))
end

function API.GetSpellTexture(spell)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spell)
	end
	return (GetSpellTexture(spell))
end

function API.DoesSpellExist(spell)
	if C_Spell and C_Spell.DoesSpellExist then
		return C_Spell.DoesSpellExist(spell)
	end
	return GetSpellInfo(spell) ~= nil
end

-- returns: startTime, duration, isEnabled
function API.GetSpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spell)
		if info then
			return info.startTime, info.duration, info.isEnabled
		end
		return
	end
	local start, duration, enabled = GetSpellCooldown(spell)
	return start, duration, enabled
end

function API.IsSpellUsable(spell)
	if C_Spell and C_Spell.IsSpellUsable then
		return C_Spell.IsSpellUsable(spell)
	end
	return IsUsableSpell(spell)
end

-- Items --------------------------------------------------------------------
function API.GetItemIcon(item)
	if C_Item and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(item)
	end
	return (GetItemIcon(item))
end

function API.GetItemInfo(item)
	return GetItemInfo(item)
end

-- Power ------------------------------------------------------------------------
function API.GetComboPoints(unit, target)
	return GetComboPoints(unit or "player", target or "target")
end
