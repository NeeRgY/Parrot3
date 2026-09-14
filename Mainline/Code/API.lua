--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork:
	  Parrot.API - one place per game client to talk to the WoW spell / item
	  APIs. Modules call Parrot.API.* instead of C_Spell / GetSpellInfo / ...
	  directly, so a future API change only has to be handled here. This file
	  is the Retail (12.x) implementation.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local C_Spell = _G.C_Spell
local C_Item  = _G.C_Item
local Enum    = _G.Enum

local API = {}
Parrot.API = API

-- Parrot 3: on retail 11.0.7+, a value read while Parrot's execution is
-- tainted can come back "secret" - using it (even just comparing it) raises a
-- Lua error. Filter secret numbers out right here at the source, so every
-- caller of API.GetSpellCooldown just sees "no cooldown info" instead of
-- crashing. canaccessvalue/issecretvalue only exist where the concept does.
local function safeNumber(value)
	if type(value) ~= "number" then
		return value
	end
	if type(canaccessvalue) == "function" then
		local ok, accessible = pcall(canaccessvalue, value)
		if ok and not accessible then return nil end
	elseif type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, value)
		if ok and secret then return nil end
	end
	return value
end
API.SafeNumber = safeNumber

-- Spells --------------------------------------------------------------------
function API.GetSpellName(spell)
	return C_Spell.GetSpellName(spell)
end

function API.GetSpellTexture(spell)
	return C_Spell.GetSpellTexture(spell)
end

function API.DoesSpellExist(spell)
	return C_Spell.DoesSpellExist(spell)
end

-- returns a classic-style tuple: startTime, duration, isEnabled
function API.GetSpellCooldown(spell)
	local info = C_Spell.GetSpellCooldown(spell)
	if info then
		return safeNumber(info.startTime), safeNumber(info.duration), info.isEnabled
	end
end

function API.IsSpellUsable(spell)
	return C_Spell.IsSpellUsable(spell)
end

-- Items --------------------------------------------------------------------
function API.GetItemIcon(item)
	if C_Item and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(item)
	end
	return GetItemIcon(item)
end

function API.GetItemInfo(item)
	return GetItemInfo(item)
end

-- Power / vehicle --------------------------------------------------------------
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
function API.GetComboPoints(unit, target)
	if UnitHasVehicleUI and UnitHasVehicleUI("player") and GetComboPoints then
		return GetComboPoints(unit or "vehicle", target or "target")
	end
	return UnitPower("player", COMBO)
end
