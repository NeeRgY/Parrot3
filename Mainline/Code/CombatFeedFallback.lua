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
	  showing wrong numbers. There is no equivalent fallback for procs,
	  misses, dispels, loot, or anything trigger-condition related - those
	  still need the real combat log and stay silent while it's blocked.

	  NEW in the Parrot 3 fork on 2026-09-22: a second, independent fallback
	  for outgoing damage/healing via C_DamageMeter (see the "Outgoing
	  damage/healing via C_DamageMeter" comment further down) - some sessions
	  (seen on WoW: Forever's beta client) force taint so broadly that even
	  UNIT_COMBAT's RegisterEvent is refused, leaving the module above
	  completely silent. C_DamageMeter is a plain read API rather than an
	  event, so it still works there; it only gives the player's own running
	  totals per spell, polled a few times a second, with no incoming side
	  and no per-hit detail.

	  Icons: UNIT_COMBAT carries no spell id, so an icon is only ever shown
	  when something else gives real confidence about which spell it was -
	  never a guess. For outgoing damage, confidence comes from also tracking
	  UNIT_SPELLCAST_SUCCEEDED("player"), a real spell-id-bearing event: a hit
	  landing shortly after a cast is credited to that spell's real icon, a
	  hit during a tracked, still-active DoT to that DoT's icon, and a hit
	  with neither signal but confirmed auto-attack toggled on gets the
	  auto-attack icon. Incoming self-heals use the same recent-cast tracking
	  (lastPlayerSpellID below - any spell, not just ones Blizzard calls a
	  heal, see its own comment). There is no equivalent signal for incoming
	  damage (that would require knowing what the attacker cast), so it never
	  gets an icon.

	  Attribution vs. visibility: UNIT_COMBAT("target", ...) fires for a hit on
	  the player's target no matter who landed it, so in principle a shared
	  open-world target (world boss, contested rare, ...) being hit by other,
	  unrelated players could show as the player's own damage. Up to
	  2026-09-21 this module required a real attack signal (recent cast,
	  active DoT, or confirmed auto-attack) before showing anything at all, to
	  guard against exactly that. On WoW: Forever that signal turned out to be
	  unreliable enough to make outgoing damage go silent entirely (worse than
	  the misattribution risk) - see OnUnitCombat's outgoing branch. The cast/
	  auto-attack tracking now only decides the icon/name, never whether a hit
	  is shown.

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

local function fire(category, name, amount, placeholderSpellID, isCrit, recipientGUID, recipientName, sourceGUID, sourceName, abilityName)
	if type(amount) ~= "number" or amount <= 0 then return end
	local info = Parrot.newList()
	info.uid = nextFallbackUID()
	info.amount = amount
	-- "Self heals" throttles on info.abilityName, "Melee damage" on
	-- info.recipientID - both must be non-nil or TriggerCombatEvent's
	-- throttle bucketing errors on a nil table index. realAmount is what the
	-- heal tag actually renders; there's no separate overheal figure here,
	-- so it mirrors amount.
	info.abilityName = abilityName or ""
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
-- event argument. Remember the last spell the player successfully cast -
-- ANY spell, not just ones Blizzard's own IsSpellHarmful/IsSpellHelpful
-- would call offensive/a heal - and if the next outgoing hit or incoming
-- self-heal lands within the window, credit it to that spell's real icon
-- instead of guessing from schoolMask or showing nothing.
--
-- NEW in the Parrot 3 fork on 2026-09-22: this used to run the cast through
-- IsSpellHarmful/IsSpellHelpful first and keep two separate "last offensive
-- cast" / "last helpful cast" trackers, specifically to avoid crediting an
-- unrelated hit to a just-cast defensive/utility spell's icon. On WoW:
-- Forever, IsSpellHelpful has been seen returning unusable results, which
-- silently broke self-heal icons entirely (Holy Light showed no icon at
-- all) - and the harmful/helpful split still couldn't help with something
-- like Seal of Righteousness (cast once, then procs on every swing for a
-- long time afterward - not "recently cast" by the time it procs, and not
-- classified as harmful since the cast itself is a buff, not damage). A
-- single unfiltered tracker with a generous 4s window (same approach a
-- separately fixed reference addon on this same client uses, confirmed
-- working there) covers both cases at the cost of occasionally crediting a
-- hit to an unrelated recent cast - an acceptable trade for a best-effort
-- fallback that would otherwise show no icon at all.
local ATTRIBUTION_WINDOW = 4
local lastPlayerSpellID, lastPlayerSpellTime

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
	-- Mounting is a "spell cast" too and clearly isn't a damage/heal source,
	-- so exclude it here rather than showing a mount icon on the next hit.
	local mountOk, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
	if mountOk and mountID and mountID ~= 0 then return end
	lastPlayerSpellID = spellID
	lastPlayerSpellTime = GetTime()
end

local function hasRecentCast()
	return lastPlayerSpellID and lastPlayerSpellTime and (GetTime() - lastPlayerSpellTime) <= ATTRIBUTION_WINDOW
end

local function incomingHealSpell()
	if hasRecentCast() then
		return lastPlayerSpellID
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
-- the ranged equivalent (Auto Shot/Shoot). Neither legacy global exists on
-- WoW: Forever (seen via /run - both come back nil), so this prefers the
-- namespaced C_Spell replacement when present and falls back to the legacy
-- global otherwise (real Retail still has both).
local AUTO_ATTACK_SPELL = 6603
local IsCurrentSpellCompat = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell

local function isAutoAttacking()
	if IsCurrentSpellCompat then
		local ok, current = pcall(IsCurrentSpellCompat, AUTO_ATTACK_SPELL)
		if ok and current then return true end
	end
	if IsAutoRepeatSpell then
		local ok, autoRepeat = pcall(IsAutoRepeatSpell)
		if ok and autoRepeat then return true end
	end
	return false
end

-- Recent cast > active DoT > confirmed auto-attack > no icon (shown with
-- just the amount, no icon/name - see the 2026-09-22 note below). Unlike an
-- always-guessed icon, each of these three is a real, confirmed signal.
local function outgoingDamageSpell()
	if hasRecentCast() then
		return lastPlayerSpellID
	end
	local dot = activeDotSpell()
	if dot then
		return dot
	end
	if isAutoAttacking() then
		return AUTO_ATTACK_SPELL
	end
	return nil
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
		-- unrelated players does the exact same thing - there is no way to
		-- rule that out from this event alone.
		--
		-- NEW in the Parrot 3 fork on 2026-09-22: this used to also require
		-- a real attack signal (a recent cast, an active DoT, or confirmed
		-- auto-attack) before showing anything at all, to guard against the
		-- shared-target misattribution above. On WoW: Forever that signal
		-- turned out to be unreliable enough (UNIT_SPELLCAST_SUCCEEDED and/or
		-- the auto-attack API not cooperating under this session's taint) to
		-- make the whole outgoing side go silent - worse than the
		-- misattribution risk it was guarding against. Now every hit shows;
		-- outgoingDamageSpell() still only uses those same signals, just for
		-- the icon/name instead of visibility.
		if UnitExists("target") and UnitCanAttack("player", "target") then
			fire("Outgoing", "Melee damage", amount, outgoingDamageSpell(), isCrit, "target", safeUnitName("target", UNKNOWNOBJECT))
		end
	end
end

-- Outgoing damage/healing via C_DamageMeter, for sessions where UNIT_COMBAT
-- itself never fires either (WoW: Forever's beta client has been seen forcing
-- taint session-wide - "*** ForceTaint_Strong ***" in the Blizzard error log -
-- which blocks RegisterEvent for the events above too, not just the combat
-- log). C_DamageMeter is a plain read API, not an event registration, so it
-- is unaffected either way. It only exposes the PLAYER's own running totals
-- per spell (no per-hit detail, no target/recipient, no incoming side), so
-- this polls it a few times a second while in combat and turns each spell's
-- delta since the last poll into one synthetic hit - an approximation on top
-- of an approximation, only used when even the UNIT_COMBAT path above is
-- silent. combatSpells' spellID/totalAmount come back as Blizzard "secret
-- values" while in combat (patch 12.0's Secret Values system) - unlike the
-- rest of this file, Code/API.lua's canaccessvalue/issecretvalue-based
-- SafeNumber does not reliably unwrap these two fields specifically, so this
-- uses the simpler, confirmed-working trick instead: try "value + 0" in a
-- pcall and treat it as unusable (skip that entry) if that throws.
local API = Parrot.API
local damageMeterLastTotals = {}
local damageMeterTicker

local function damageMeterAvailable()
	return C_DamageMeter and Enum and Enum.DamageMeterType and true or false
end

local function safeAddZero(value)
	local ok, result = pcall(function() return value + 0 end)
	if ok and type(result) == "number" then
		return result
	end
	return nil
end

local function pollDamageMeterType(meterType, category, name)
	local ok, playerGUID = pcall(UnitGUID, "player")
	if not ok or not playerGUID then return end

	local okSource, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, 0, meterType, playerGUID)
	if not okSource or not source then return end

	local okSpells, combatSpells = pcall(function() return source.combatSpells end)
	if not okSpells or type(combatSpells) ~= "table" then return end

	for _, entry in ipairs(combatSpells) do
		local spellID = safeAddZero(entry.spellID)
		local totalAmount = safeAddZero(entry.totalAmount)
		if spellID and totalAmount and totalAmount > 0 then
			local key = meterType .. ":" .. spellID
			local previous = damageMeterLastTotals[key] or 0
			-- A drop below the last total means a new combat session (not a
			-- negative hit) - show the fresh total instead of going negative.
			local delta = totalAmount - previous
			if delta < 0 then delta = totalAmount end
			damageMeterLastTotals[key] = totalAmount

			if delta > 0 then
				fire(category, name, delta, spellID, false, nil, nil, playerGUID,
					safeUnitName("player", UNKNOWN), API.GetSpellName(spellID))
			end
		end
	end
end

local function pollDamageMeter()
	pollDamageMeterType(Enum.DamageMeterType.DamageDone, "Outgoing", "Melee damage")
	pollDamageMeterType(Enum.DamageMeterType.HealingDone, "Outgoing", "Heals")
end

function module:StartDamageMeterPolling()
	if not Parrot.combatLogBlocked or not damageMeterAvailable() or damageMeterTicker then return end
	wipe(damageMeterLastTotals)
	damageMeterTicker = C_Timer.NewTicker(0.5, pollDamageMeter)
end

function module:StopDamageMeterPolling()
	if damageMeterTicker then
		damageMeterTicker:Cancel()
		damageMeterTicker = nil
	end
end

function module:OnEnable()
	Parrot:RegisterBlizzardEvent(self, "UNIT_COMBAT", "OnUnitCombat")
	Parrot:RegisterBlizzardEvent(self, "UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellcastSucceeded")
	Parrot:RegisterBlizzardEvent(self, "PLAYER_REGEN_DISABLED", "StartDamageMeterPolling")
	Parrot:RegisterBlizzardEvent(self, "PLAYER_REGEN_ENABLED", "StopDamageMeterPolling")
end
