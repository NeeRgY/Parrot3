--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-11 (Retail only):
	  Combat-log-free fallback feed. Some sessions taint Parrot's execution
	  before it can run a single line of its own code (see the taint sandbox
	  and secret-value-guard notes in CHANGELOG.md). On a tainted execution
	  path COMBAT_LOG_EVENT_UNFILTERED cannot be registered at all (see
	  Code/Parrot.lua's cleuFrame), so Parrot's normal combat-log-driven engine
	  (Code/CombatEvents.lua, Data/CombatEvents.lua) never receives anything.

	  This module is Parrot's fallback for exactly that case. It is completely
	  inert unless Parrot.combatLogBlocked was set (Code/Parrot.lua, right
	  after the blocked RegisterEvent attempt), and then approximates
	  damage/heal numbers from the legacy UNIT_COMBAT event.

	  Why UNIT_COMBAT works here when direct API calls don't: Blizzard's
	  "secret value" system (Code/API.lua, Data/TriggerConditions.lua) applies
	  to the RESULT of a protected function call made from tainted code
	  (GetSpellCooldown, UnitPower, UnitHealth all come back secret) - but
	  plain event arguments handed to a frame's OnEvent script by the event
	  dispatcher are not wrapped the same way. UNIT_COMBAT's (unitTarget,
	  action, flagText, amount, schoolMask) payload comes through as normal
	  numbers even while direct API calls return secret ones.

	  UNIT_COMBAT is a legacy event with a much thinner payload than the
	  combat log: no spell/ability name, no aura/proc/miss/dispel detail, and
	  on this client its damage/heal action is reported as "WOUND"/"HEAL" with
	  "CRITICAL" as a separate flagText rather than a boolean - these names
	  are not documented anywhere current, so if this stops matching on a
	  future client, this whole module simply goes quiet again rather than
	  showing wrong numbers. There is no equivalent fallback for outgoing
	  healing, procs, misses, dispels, loot, or anything trigger-condition
	  related - those still need the real combat log and stay silent while
	  it's blocked.

	  Icons: UNIT_COMBAT carries no spell id, so an icon is only ever shown
	  when something else gives real confidence about which spell it was -
	  never a guess. For outgoing damage, confidence comes from also tracking
	  UNIT_SPELLCAST_SUCCEEDED("player"), a real spell-id-bearing event: a hit
	  landing shortly after a cast is credited to that spell's real icon, a
	  hit during a tracked, still-active DoT to that DoT's icon, and a hit
	  with neither signal but confirmed auto-attack toggled on gets the
	  auto-attack icon. Incoming self-heals use the same recent-cast tracking,
	  restricted to helpful casts (see lastAnyCastSpellID below). There is no
	  equivalent signal for incoming damage (that would require knowing what
	  the attacker cast), so it never gets an icon.

	  Attribution vs. visibility: the same cast/auto-attack tracking above also
	  gates whether an outgoing hit is shown AT ALL (hasOutgoingSignal()), not
	  just which icon it gets. UNIT_COMBAT("target", ...) fires for a hit on
	  the player's target no matter who landed it, so without this a shared
	  open-world target (world boss, contested rare, ...) being hit by other,
	  unrelated players showed as the player's own damage. It's a heuristic,
	  not a guarantee - see hasOutgoingSignal()'s own comment.

	  DoTs: a periodic tick lands well after its cast, with no recent-cast
	  signal and (for most casters) no auto-attack either, so it would
	  otherwise go quiet a moment after the cast. DOT_SPELLS is a small,
	  explicit list (starting with Shadow Word: Pain) of casts to keep
	  tracking via the target's own debuff from the player. Add an entry for
	  whichever DoT is actually in use.

	  Feeds the SAME "Melee damage" (Incoming/Outgoing) and "Self heals"
	  (Incoming) entries Parrot 2 always had, through the normal
	  Parrot:TriggerCombatEvent pipeline - not new, unconfigured entries, which
	  would otherwise render in whatever scroll area Parrot defaults new
	  entries to rather than the one the user actually set up. The two paths
	  (real combat-log delivery vs. this fallback) never fire for the same
	  event at the same time, so there's no double-counting risk.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local module = Parrot:NewModule("CombatFeedFallback")

local uidCounter = 0
local function nextFallbackUID()
	uidCounter = uidCounter + 1
	return uidCounter
end

-- UnitGUID()/UnitName() are themselves protected function calls, same as
-- GetSpellCooldown/UnitPower/UnitHealth in the module doc above - under a
-- thoroughly tainted session they can come back "secret" too. A secret
-- VALUE doesn't error on creation, only later when something actually uses
-- it (comparing, concatenating, or indexing a table with it as the key -
-- "Melee damage" throttles on info.recipientID). This module never needs a
-- REAL GUID: only "player" or "target" ever call fire(), and those two
-- literal strings already uniquely identify them for throttling purposes,
-- so skip UnitGUID entirely instead of risking a secret one. The display
-- name still needs UnitName, so probe it with a cheap concatenation in a
-- pcall - a secret value fails that the same way it would fail rendering
-- into a tag - and fall back to a generic label instead of passing a secret
-- through to Data/CombatEvents.lua's tag translations.
local function safeUnitName(unit, fallback)
	local ok, name = pcall(UnitName, unit)
	if not ok or type(name) ~= "string" then
		return fallback
	end
	local usable = pcall(function() return name .. "" end)
	if not usable then
		return fallback
	end
	return name
end

-- UNIT_COMBAT carries no spell/ability id, so an icon here is only ever
-- shown when something ELSE gives real confidence about which spell it was
-- (a recent cast, an active tracked DoT, or a confirmed auto-attack) -
-- never a guess. A spellID of nil means Data/CombatEvents.lua's Icon tag
-- translation (retrieveIconFromAbilityName) just finds nothing and renders
-- no icon, exactly like a real combat-log entry with no ability name would.

local function fire(category, name, amount, placeholderSpellID, isCrit, recipientGUID, recipientName, sourceGUID, sourceName)
	if type(amount) ~= "number" or amount <= 0 then return end
	local info = Parrot.newList()
	info.uid = nextFallbackUID()
	info.amount = amount
	-- "Self heals" throttles on info.abilityName, "Melee damage" on
	-- info.recipientID - both must be non-nil or TriggerCombatEvent's
	-- throttle bucketing errors on a nil table index. realAmount is what the
	-- heal tag actually renders; there's no separate overheal figure here,
	-- so it mirrors amount.
	info.abilityName = ""
	info.realAmount = amount
	info.spellID = placeholderSpellID
	info.isCrit = not not isCrit
	info.hideCaster = false
	info.sourceName = sourceName or ""
	info.sourceID = sourceGUID or ""
	info.sourceFlags = 0
	info.recipientName = recipientName or ""
	info.recipientID = recipientGUID or ""
	info.destFlags = 0
	-- Last-resort safety net: this is a best-effort fallback feed by design
	-- (see the module doc), so one bad event silently failing beats a wall
	-- of repeated Lua errors for the rest of the fight.
	pcall(Parrot.TriggerCombatEvent, Parrot, category, name, info)
	Parrot.del(info)
end

-- action strings observed via UNIT_COMBAT on this client for damage/healing.
-- CRITICAL arrives separately as flagText, not folded into action.
local DAMAGE_ACTIONS = { WOUND = true }
local HEAL_ACTIONS = { HEAL = true }

-- Outgoing damage: UNIT_COMBAT never says which spell caused a hit, but
-- UNIT_SPELLCAST_SUCCEEDED("player", castGUID, spellID) does, as a real
-- event argument. Remember the last offensive spell the player successfully
-- cast, and if the next outgoing hit lands shortly after, credit it to that
-- spell's real icon instead of guessing from schoolMask. 0.9s is long
-- enough for an instant cast's travel time, short enough that an unrelated
-- later cast doesn't get misattributed (a heuristic, not a guarantee - two
-- damaging spells within the window can still pick the wrong one). No such
-- signal exists for incoming damage (that would require knowing what the
-- attacker cast) or for outgoing healing (no outgoing-heal path exists at
-- all, see the module doc above).
local ATTRIBUTION_WINDOW = 0.9
local lastCastSpellID, lastCastTime

-- Incoming self-heals get similar treatment, with its own, much longer
-- attribution window (SELF_HEAL_ATTRIBUTION_WINDOW) to account for HoTs.
-- There's no equivalent-quality signal for who caused incoming damage (that
-- would require knowing what the other unit cast), so only healing uses
-- this.
--
-- Only a cast Blizzard itself calls helpful (a real self-heal - Word of
-- Glory, a health potion, Riptide on yourself, ...) or one in
-- INDIRECT_HEAL_TRIGGER_SPELLS below (a damage or utility spell known to
-- heal indirectly, e.g. a Discipline Priest's Atonement) updates this -
-- a plain damage cast does not, so a heal from someone else's cast falls
-- back to no icon instead of showing the player's own unrelated last cast.
local lastAnyCastSpellID, lastAnyCastTime

-- Add a [spellID] = true entry here for any damage/utility spell on your
-- class/spec that causes an indirect self-heal Blizzard's own
-- IsSpellHelpful() doesn't recognize as helpful (it checks the cast
-- itself, not side effects) - e.g. a Discipline Priest's Atonement trigger
-- spells. Empty by default; same opt-in-list idea as DOT_SPELLS below.
local INDIRECT_HEAL_TRIGGER_SPELLS = {
}

-- Small, explicit list of known damage-over-time spells, so a periodic tick
-- landing long after the cast (the player isn't "recently casting" again
-- for every tick) still counts as their own damage instead of going quiet.
-- Not a general DoT solution - a short, hand-picked list. Add an entry here
-- for whichever DoT is actually being used; [cast spellID] = aura spellID
-- to check for on the target (usually the same id). Only one DoT is tracked
-- at a time - casting a second DoT-listed spell replaces the tracked one,
-- so with two simultaneous DoTs from this list the other one is still
-- shown (as long as some other signal covers it) but without its own icon.
local DOT_SPELLS = {
	[589] = 589, -- Shadow Word: Pain (Priest)
}
local dotCastSpellID

function module:OnUnitSpellcastSucceeded(uid, event, unit, castGUID, spellID)
	if unit ~= "player" or not spellID then return end
	if DOT_SPELLS[spellID] then
		dotCastSpellID = spellID
	end
	-- Only a real self-heal, or a spell explicitly known to heal indirectly
	-- (INDIRECT_HEAL_TRIGGER_SPELLS above), counts as a possible source for
	-- an incoming heal - see the lastAnyCastSpellID comment above for why a
	-- plain damage/utility cast no longer qualifies.
	local ok, helpful = pcall(C_Spell.IsSpellHelpful, spellID)
	if (ok and helpful) or INDIRECT_HEAL_TRIGGER_SPELLS[spellID] then
		-- Mounting is technically a "helpful" cast too, and clearly can't be
		-- a heal source, so exclude it here.
		local mountOk, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
		local isMount = mountOk and mountID and mountID ~= 0
		if not isMount then
			lastAnyCastSpellID = spellID
			lastAnyCastTime = GetTime()
		end
	end
	-- Only remember offensive casts for outgoing-damage attribution. Without
	-- this, casting a purely defensive/utility spell (Power Word: Shield, a
	-- buff, ...) right before an unrelated hit lands (e.g. a normal
	-- auto-attack swing) credited that unrelated hit to the utility spell's
	-- icon.
	local ok, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
	if not ok or not harmful then return end
	lastCastSpellID = spellID
	lastCastTime = GetTime()
end

local function hasRecentCast()
	return lastCastSpellID and lastCastTime and (GetTime() - lastCastTime) <= ATTRIBUTION_WINDOW
end

-- Self-heals get a much more generous window than outgoing damage: a HoT
-- (Riptide, Rejuvenation, ...) keeps ticking for many seconds after the
-- cast, long past ATTRIBUTION_WINDOW's 0.9s. 12s covers most HoT durations
-- while staying short enough that a heal from several casts ago doesn't get
-- credited. A heuristic, not a guarantee - two different heals within the
-- window can still pick the wrong one.
local SELF_HEAL_ATTRIBUTION_WINDOW = 12

local function incomingHealSpell()
	if lastAnyCastSpellID and lastAnyCastTime and (GetTime() - lastAnyCastTime) <= SELF_HEAL_ATTRIBUTION_WINDOW then
		return lastAnyCastSpellID
	end
	return nil -- no confident source: no icon, rather than a guessed one
end

-- True (and the DoT's spell id) only while the tracked DoT's own debuff, from
-- the player, is still on the current target - confirms it's still ticking
-- and still the player's, not just "was cast at some point". Clears the
-- tracked spell once the aura is gone (expired, dispelled, target changed,
-- ...) so a stale DoT doesn't keep attributing later, unrelated hits.
local function activeDotSpell()
	if not dotCastSpellID then return nil end
	local auraSpellID = DOT_SPELLS[dotCastSpellID]
	local ok, aura = pcall(AuraUtil.FindAuraBySpellID, auraSpellID, "target", "HARMFUL|PLAYER")
	if ok and aura then
		return dotCastSpellID
	end
	dotCastSpellID = nil
	return nil
end

-- AUTOSHOT_SPELL_ID (6603 = melee Attack) works with IsCurrentSpell() to
-- tell whether melee auto-attack is toggled on; IsAutoRepeatSpell() covers
-- the ranged equivalent (Auto Shot/Shoot).
local AUTO_ATTACK_SPELL = 6603

local function isAutoAttacking()
	local ok, current = pcall(IsCurrentSpell, AUTO_ATTACK_SPELL)
	if ok and current then return true end
	local ok2, autoRepeat = pcall(IsAutoRepeatSpell)
	return ok2 and autoRepeat == true
end

-- Recent cast > active DoT > confirmed auto-attack > no icon. The
-- auto-attack case only fires here because hasOutgoingSignal() already
-- required one of these three to be true before outgoingDamageSpell() is
-- even called - by elimination, if neither of the first two matched, it's
-- auto-attack that let the hit through, so crediting AUTO_ATTACK_SPELL's
-- icon is a confirmed fact, not a guess.
local function outgoingDamageSpell()
	if hasRecentCast() then
		return lastCastSpellID
	end
	local dot = activeDotSpell()
	if dot then
		return dot
	end
	return AUTO_ATTACK_SPELL
end

-- Whether to show an outgoing hit AT ALL, not just which icon to give it.
-- UNIT_COMBAT("target", ...) fires for a hit on the player's target no
-- matter who landed it - a group check alone doesn't help against, say, a
-- world boss or contested rare that other, unrelated players are also
-- attacking. Only show the hit when there is a real signal that the player
-- is the one attacking: a recent offensive cast, or auto-attack (melee or
-- ranged) currently toggled on. Two hits landing inside one swing (e.g. a
-- windfury-style proc) can both show, rather than exactly one.
local function hasOutgoingSignal()
	return hasRecentCast() or isAutoAttacking() or activeDotSpell() ~= nil
end

function module:OnUnitCombat(uid, event, unitTarget, action, flagText, amount, schoolMask)
	if not Parrot.combatLogBlocked then return end
	if type(amount) ~= "number" or amount <= 0 then return end

	local isCrit = flagText == "CRITICAL"

	if unitTarget == "player" then
		-- Incoming: unambiguous, it's always about the player. No icon
		-- signal exists for damage at all (would need to know what the
		-- attacker cast), so that's always nil.
		if DAMAGE_ACTIONS[action] then
			fire("Incoming", "Melee damage", amount, nil, isCrit, "player", safeUnitName("player", UNKNOWN))
		elseif HEAL_ACTIONS[action] then
			fire("Incoming", "Self heals", amount, incomingHealSpell(), isCrit, "player", safeUnitName("player", UNKNOWN))
		end
	elseif unitTarget == "target" and DAMAGE_ACTIONS[action] then
		-- Outgoing: best-effort. UNIT_COMBAT doesn't say who caused this -
		-- "target" just means "something happened to the unit the player has
		-- targeted". In a group any party/raid member (or a pet) hitting the
		-- same target reports here too; outside a group, a shared open-world
		-- target (a world boss, a contested rare, ...) being hit by other,
		-- unrelated players does the exact same thing. hasOutgoingSignal()
		-- guards against showing someone else's hit as the player's: only
		-- show it when there's a real sign the player is the one attacking.
		-- AoE/cleave damage to other enemies ("nameplateN") is not
		-- attributed to the player either, for the same reason.
		if UnitExists("target") and UnitCanAttack("player", "target") and hasOutgoingSignal() then
			fire("Outgoing", "Melee damage", amount, outgoingDamageSpell(), isCrit, "target", safeUnitName("target", UNKNOWNOBJECT))
		end
	end
end

function module:OnEnable()
	Parrot:RegisterBlizzardEvent(self, "UNIT_COMBAT", "OnUnitCombat")
	Parrot:RegisterBlizzardEvent(self, "UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellcastSucceeded")
end
