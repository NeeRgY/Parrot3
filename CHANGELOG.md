# Parrot 3

**Parrot 3** is a maintained fork of **Parrot 2** by Neb
(<https://github.com/nebularg/Parrot2>), which is itself based on the original
**Parrot** by ckknight. Fork maintainer: **NeRgY**.

Parrot 3 is distributed under the **GNU Lesser General Public License,
version 2.1** (see `LICENSE.txt`) — the same license as its upstream.

---

## v3.0.0 (2026-09-10)

The first Parrot 3 release. It merges Parrot 2's two separate builds into one
addon, brings the code up to current game clients, refreshes the embedded
libraries, and adds a modern options interface.

### 1. One addon, four game versions

Parrot 2 shipped as two disconnected builds. Parrot 3 merges them into a
single addon with **a dedicated TOC and a fully separate code tree per game
version**:

| TOC | Client | `## Interface` | Code tree |
|-----|--------|----------------|-----------|
| `Parrot3_Mainline.toc` | Retail 12.1.0 / 12.1.5 | `120100, 120105` | `Mainline/` |
| `Parrot3_Vanilla.toc`  | Classic Era 1.15.9     | `11509`  | `Vanilla/` |
| `Parrot3_TBC.toc`      | TBC Classic 2.5.6      | `20506`  | `TBC/` |
| `Parrot3_Mists.toc`    | MoP Classic 5.5.4      | `50504`  | `Mists/` |

- `Libs/`, `Locales/` and `locales.xml` are shared by all four TOCs.
- All internal identifiers stay `Parrot` — existing Parrot 2 settings and
  profiles carry over unchanged.
- **Mists** additionally takes Parrot 2's Retail trigger system
  (spec-based default triggers, `focus` unit, spell-overlay condition) with a
  `C_Spell` compatibility shim for MoP's older spell API.

### 2. Licensing

`LICENSE.txt` (LGPL v2.1) kept; original authors credited (ckknight,
profalbert, nebularg); `## Author: NeRgY`, `## X-Fork-Maintainer: NeRgY`.
Every file this fork modified carries an in-file LGPL v2.1 change notice.

### 3. Bug fixes & optimisations

- Retail screen flash restored (missing `BackdropTemplate`).
- Item name/icon falls back to the link text when the client hasn't cached
  the item yet, instead of erroring or showing blank.
- Combat-log handler rejects untracked events/units before doing any work.
- `TriggerCombatEvent`'s runtime guards log and return instead of erroring.
- `Parrot:MigrateDB()` — a versioned top-level database migration scaffold.
- `Parrot:Print()` defined (AceConsole isn't embedded).

### 4. Retail (Mainline) API compatibility & taint hardening

Audited `Mainline/` against the current retail API and guarded the remaining
deprecated globals. Added `Parrot.API` (`Code/API.lua`, one implementation
per tree) so spell/item lookups go through one client-specific layer instead
of scattered `C_Spell`/`GetSpellInfo` calls. `Parrot:SafeCall()` wraps module
lifecycle/migration code in `pcall` so one broken module can't break profile
switching or the config window (`/parrot errors` shows what was caught).

**Taint safety** — on current retail, another addon can taint the shared
session state very early at login, which then blocks
`COMBAT_LOG_EVENT_UNFILTERED` registration and turns protected-API results
(spell cooldowns, unit power, combat-log payloads) into unusable "secret"
values for every addon that shares that tainted path. Parrot 3 hardens
against this on several levels:

- **Private event dispatch** (`Parrot.Events`) — Parrot's own event handling
  runs on a private frame instead of AceEvent-3.0's session-shared one, so
  another addon tainting that shared dispatch can no longer drag Parrot's
  handlers into the same tainted call.
- **Private LibStub sandbox** (`Code/_Sandbox_*.lua`) — Parrot loads its
  embedded libraries (Ace3, LibSink, LibDBIcon, LibSharedMedia, locale files)
  into a fresh private LibStub for the span of its own load, so a
  session-wide LibStub already poisoned by another addon can't taint Parrot.
- **Combat-log registration on a private frame** — `COMBAT_LOG_EVENT_UNFILTERED`
  is requested from a dedicated frame's own `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD`
  handler (a guaranteed clean context on the C side) instead of from
  `OnInitialize`/`OnEnable`, and `issecure()` predicts a refusal so Parrot
  skips the doomed call outright rather than triggering one.
- **Secret-value guards** (`Code/API.lua`, `Data/TriggerConditions.lua`) —
  retail 11.0.7+ exposes `issecretvalue()`/`canaccessvalue()`; cooldown reads
  and trigger-condition comparisons check a value before using it instead of
  crashing on first use. No-op on Classic/TBC/MoP, which have no such concept.
- **Combat-log-free fallback feed** (`Code/CombatFeedFallback.lua`, Retail
  only) — when taint still blocks the real combat log from registering at
  all, this module approximates "Melee damage"/"Self heals" numbers from the
  legacy `UNIT_COMBAT` event instead, whose arguments (unlike protected
  function-call results) are not subject to the same secret-value wrapping.
  It attributes an icon only when there's real confidence in the source spell
  (a recent matching cast, an active tracked DoT, or confirmed auto-attack) —
  never a guess — and stays completely silent for anything it can't
  reasonably attribute, including all outgoing healing, procs, misses, and
  loot. It is entirely inert unless the real combat log actually failed to
  register, so players unaffected by taint see no change in behavior.
- Both a helper-cast check (`C_Spell.IsSpellHelpful`) and an opt-in
  `INDIRECT_HEAL_TRIGGER_SPELLS` list keep the fallback's self-heal icon
  attribution from crediting an unrelated damage spell the player happened to
  cast recently, when the actual heal came from someone else.
- `UnitGUID`/`UnitName` are themselves protected calls and can return
  "secret" values under taint; the fallback module never calls `UnitGUID`
  (it only ever needs the fixed "player"/"target" identifiers) and probes
  `UnitName`'s result before using it, falling back to a generic label.

**Floating Combat Text control** — all four trees can now fully disable
Blizzard's own damage/healing numbers so only Parrot's own feed shows
(General tab → "Floating Combat Text"). This turned out to need more than
just `SetCVar`, discovered through testing on each client family:

- The relevant CVars are silently refused by `SetCVar` while the player is
  in combat on modern clients — writes now defer and retry on
  `PLAYER_REGEN_ENABLED`.
- Several of these CVars also have a matching **global variable** that the
  "on me" (self) combat-text engine reads directly (e.g. Miss/Dodge/Parry's
  actual switch is a separate global, not just the master toggle) — both the
  CVar and its backing global are now set together.
- Setting the master toggle CVar doesn't reliably apply live; flipping it
  through `"1"` and back to the desired value forces the engine to re-read it.
- Some CVars only exist under a newer "_v2" name depending on client build;
  which one applies is now auto-detected per CVar instead of assumed.

**Minor fixes found while testing all of the above:**

- Options-window drag handle restored (`Code/Skin.lua`) — the skin had moved
  the visible title text without moving AceGUI's separate, invisible drag
  hitbox; a dedicated drag strip now spans the whole top edge.
- Shared tooltip frames (AceConfigDialog, AceGUI, LibDBIcon) collided with
  other addons' private library copies under the same global frame name,
  rendering blank — each now gets its own uniquely-named frame.
- Fixed a `table index is nil` crash and a missing "()" artifact in the
  fallback heal feed's throttling/tag rendering.
- Fixed the in-game Changelog/About popups rendering completely empty (a
  FontString anchored on both sides can't have its width set directly —
  the parent frame's width has to be set instead).
- Fixed a Mists load-time error when another addon force-loads Parrot before
  the talent/specialization API has finished initializing.
- Fixed a `Cooldowns.lua` crash when a spellbook tab doesn't exist for the
  current class/spec.
- Silenced a legacy "Trigger spell missing" chat message that fired twice per
  login on every client — the safe substitution behind it was never touched.
- Completed all 20 UI strings this fork added (Settings tab, language
  selector, About/Changelog panel, minimap toggle, fallback-feed messages)
  across every shipped locale — `deDE`/`enUS` already had them, the other
  eight were missing them entirely and silently fell back to English.

### 5. Embedded libraries

- **Ace3 refreshed to current upstream releases** — fixes a
  `bad argument #5 to 'SetText'` error the previous bundle threw on newer
  clients.
- **LibDBIcon-1.0 r56** — new, for the minimap button.
- **LibSink-2.0 refreshed to v12.0.3** — its `MINOR` is bumped so this copy
  wins the LibStub version race when several addons ship LibSink.
- `embeds.xml` library paths repointed to the shared `Libs/` folder.

### 6. AddOn-list metadata (all four TOCs)

`## IconTexture`, `## Group: Parrot 3`, localised `## Category-*`, and
`## AddonCompartmentFunc` so Parrot appears in the retail minimap addon menu.

### 7. Minimap button

Parrot 2 registered a LibDataBroker launcher but bundled nothing to display
it. Added LibDBIcon-1.0: left-click opens the config, right-click toggles
the addon, shown/hidden via Settings → Minimap icon.

### 8. Slash sub-commands

`/parrot` (config) · `/parrot test` (sample messages) · `/parrot toggle`
(enable/disable) · `/parrot errors` (captured module errors).

### 9. Settings tab & interface language

New Settings group with the minimap toggle and a Language selector
(automatic, or any of 11 shipped languages; changing it prompts a reload).

### 10. Modern options skin (`Code/Skin.lua`)

A cosmetic skin for the AceGUI widgets the config window uses — flat dark
surfaces, a parrot-green accent, custom checkboxes/dropdowns/sliders/fields,
restyled window chrome and side-tab tree. AceConfigDialog still builds and
drives everything; every skinner runs in `pcall` so a future AceGUI change
can at worst leave one widget unstyled, never break the window.

### 11. Changelog / About panel (`Code/About.lua`)

Two buttons at the bottom-left of Parrot's options window open a scrolling
Changelog popup and an About popup with the fork lineage and copyable
GitHub / Ko-fi / Discord / Curseforge / Parrot 2 links.

### 12. Tooling

`.gitattributes` (LF, vendored libs) and `.luacheckrc`.

---

### Changed files (LGPL v2.1 §2(b) notices, all dated 2026-09-10)

New: the four `Parrot3_*.toc` files, `*/embeds.xml`, `*/Code/API.lua`,
`*/Code/Skin.lua`, `*/Code/About.lua`, `*/Code/PreLocale.lua`,
`*/Code/PostLocale.lua`, `*/Code/CombatFeedFallback.lua` (Mainline),
`*/Code/_Sandbox_*.lua`, `README.md`, `.gitattributes`, `.luacheckrc`,
`CHANGELOG.md`, `Libs/LibDBIcon-1.0/`.

Modified from the Parrot 2 build: `*/Code/Parrot.lua`, `*/Code/Display.lua`,
`*/Code/CombatEvents.lua`, `*/Data/Loot.lua`, `*/Data/Cooldowns.lua`,
`*/Data/Auras.lua`, `*/Code/Triggers.lua`, `*/Data/TriggerConditions.lua`,
`Mainline/Data/PointGains.lua`, `Mists/Code/Triggers.lua`,
`Mists/Code/TriggerConditions.lua`, `Mists/Data/TriggerConditions.lua`,
`Libs/Ace*` (replaced wholesale), `Libs/LibSink-2.0/`, `locales.xml`,
`Locales/enUS.lua`, `Locales/deDE.lua`.

Everything else under `Mainline/`, `Vanilla/`, `TBC/`, `Mists/`, `Locales/`
and the non-Ace, non-Sink `Libs/` is an unmodified copy of the corresponding
Parrot 2 build.

---

# Parrot 2 (upstream base)

## [v2.2.5](https://github.com/nebularg/Parrot2/tree/v2.2.5) (2024-08-15) — Retail base
## [v2.3.5-classic](https://github.com/nebularg/Parrot2/tree/v2.3.5-classic) (2024-08-15) — Classic base
[Previous releases](https://github.com/nebularg/Parrot2/releases)

- Only load in retail
- Make sure the triggers db is a table
- Cache all spellbook tabs (classic)
- Combined TOC for classic and update checks (classic)
