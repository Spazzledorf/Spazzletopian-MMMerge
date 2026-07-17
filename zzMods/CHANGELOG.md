# Changelog

## 1.4.0 — 2026-07-17

### Highlights
- **Curated Item System is fully working** — enchantments survive saving and
  reloading, scale with your party's level, sell for fair prices, and items
  from older versions repair themselves on load.
- **Colored character sheet** — base stats, HP/SP, and resistances all get
  readable colors.
- **Town Portal continent selector is stable** — the old Escape / after-a-few-
  teleports crash is fixed at the root.
- **Party-wide quality of life** — Auto Heal, Party Merchant, Trap Perception,
  and one-key Loot All.
- **Four new skills** — Guardian, Mana Shield, Retaliation, Cleave — plus
  skill-slot cleanup (auto Identify/Repair, Disarm folded into Perception).
- **Quest followers** — Dyson Leland and Overdune Snapfinger no longer eat a
  party slot.

The detailed engineering log for this release follows.

### Changed
- **Curated Item System overhauled end-to-end** — this release takes the
  system from "never survived a reload" to fully working and play-verified:
  persistence across save/load, correct stat and skill application, balance
  matching the design doc, sell/buy value, and automatic repair/salvage of
  items from older versions. Final design: identity lives in a per-instance
  tag (`item.Charges`) resolved against the save's curated-entry table; the
  vanilla enchant roll is suppressed at curation (originals preserved per
  entry). (An intermediate "hybrid identity" composite-key design was tried
  and reverted during development — it double-applied bonuses; see Fixed.)
- **Skill-aware item targeting** — generated items that require a skill
  (weapons, body armor) now prefer party members whose class can reach
  Master+ in that skill; prefix/suffix selection avoids armor-skill
  conflicts.
- **Quality variance** — item quality scales `[0.35..1.00]` with average
  party level (over 124 levels); pool values are maximums that only a
  high-level party can roll. (An intermediate `[0.5..1.5]` range shipped
  briefly and was rolled back — it exceeded pool maximums by 50%.)

### Added
- **`zzRepairItems.lua`** — `RepairItems()` (clear orphaned Charges tags)
  and `RecurateItems()` (give items that lost their curated data a fresh
  enchantment) console tools; re-curation also runs automatically on save
  load. Old items restored this way get a NEW enchantment, not their
  original (that data is unrecoverable).

### Fixed
- **Potions and reagents are no longer curated (and get their power back)** —
  consumables store their potency in the same `Bonus` field the curation gate
  checked, so vanilla-enchanted potions/reagents were being curated and the
  "suppress vanilla enchant" step silently zeroed their strength. Curation is
  now restricted to equippable item types, and a load-time restore pass
  un-curates wrongly-tagged consumables, recovering their original power from
  the preserved entry data (a tagged consumable whose entry was lost earlier
  is untagged but its power is unrecoverable).
- **Resistance labels are now colored** — the colored-stat feature only ever
  touched base attributes/HP/SP. The resistance labels on the same page
  (Fire/Air/Water/Earth/Mind/Body) are now colored too, using their real
  runtime `GlobalTxt` indices (87/6/240/70/142/29), read from the live game
  via `DumpGxt()` — the reliable source, since MMMerge loads a merged text
  table that no static `global.txt` file matches. Note: the `\f` color parser
  mishandles values that format with a leading zero (e.g. `%.5d` of `0x07FF`),
  so light-blue Air uses `0x7FFF` to stay above that threshold.
- **Curated items now sell/buy for their worth** — curated items zero the
  vanilla Bonus for stat purposes, so the native value formula priced them at
  bare base cost. `structs.Item.GetValue` (MM8 `0x453CE7`) is now hooked to add
  a premium proportional to the item's applied curated bonuses. This was
  previously documented as an unfixable crash; the crash was a technique error
  (an unhandled throw in the hook callback corrupts the stack) — the new hook
  is fully error-isolated and additive (never mutates item fields).
- **Skill cap capped by the wrong number** — an internal `SplitSkill` helper
  returned (mastery, level) instead of the codebase-standard (level, mastery),
  so the "can't exceed your training" cap read the mastery code (0/1/2/4): a
  level-10 Normal-mastery skill capped item bonuses at +1. Fixed to cap by
  actual skill level.
- **Quality never scaled with party level** — the quality roll read a
  nonexistent Player field (`ExpForLevel`), silently pinning average level to
  1 forever. Now reads the real `LevelBase` field.
- **"the Deerslayer"'s DisarmTrap bonus was dead weight** — it routed to the
  DisarmTraps skill slot, which this pack frees (disarming merged into
  Perception). Now grants Perception, the skill that actually disarms.
- **Entry-id ceiling raised (2,000 → 1,000,000)** — the per-item id counter
  only grows; a long playthrough could exhaust the old ceiling, after which
  new items would curate but silently display/apply nothing.
- **Legacy salvage is now one-shot per save** — after 3 consecutive loads
  with nothing to salvage, the pass finalizes: legacy markers are removed and
  the save is flagged done, ending the perpetual re-curation of plain common
  items whose Numbers matched old markers. Items still in unvisited chests
  after that window come back plain (documented limitation).
- **Per-player bonus cache restored** — stat/skill hooks fire dozens of times
  per recalculation and were re-scanning all 16 equipment slots every call;
  results are now cached per player, invalidated on equip changes, save load,
  toggle, and repair passes. Skill caps stay live (applied at query time).
  The cache key includes each equipped item's identity, not just its slot —
  an earlier version keyed on slot indices only, so swapping an item in
  place kept applying the previous item's bonuses until gear moved again.
- **Stat/skill distribution re-aligned to the design doc** — three drifts
  from `README_ItemSystem.md` compounded into overpowered items:
  (1) quality rolled `[0.5–1.5]` (up to 150% of pool maximums) instead of the
  documented `[0.35–1.00]`; (2) the top-4 bonus trim exempted all skills, so
  skill-heavy suffixes granted 6–10 bonuses instead of a focused 4 (the trim
  now sums same-name bonuses first, then ranks everything together, per the
  doc's worked example — the earlier "suffix gives no skills" symptom was
  actually the inflated quality bloating attribute values past them); and
  (3) magic schools and utility skills were routed through the uncapped stat
  channel, bypassing the "skill bonuses can't exceed your training" cap —
  all skill-type bonuses now flow through `GetSkill` with the cap applied to
  the cross-item total: `min(total, max(baseSkill, 1))`. The tooltip mirrors
  the exact same computation. Existing items keep their (possibly inflated)
  stored quality until re-rolled; newly generated and salvaged items follow
  the doc.
- **Items that lost both tag and bonuses are now salvaged** — earlier buggy
  sessions left some curated items with neither their id tag (entries pruned,
  dangling tags cleared) nor their vanilla bonuses (suppressed at curation),
  making them invisible to tag-based repair. A salvage pass on save load now
  identifies them via the legacy entries still in the save (which record the
  once-curated item Numbers) and gives them fresh enchantments. Known quirk:
  a genuinely-common item whose Number matches a legacy marker also gets
  curated — benign, it would be curated as a fresh drop anyway. Repair
  functions now also log to MMMergeLog.txt (previously console-only, which
  hid several failures from diagnosis).
- **Legacy-format save entries deadlocked recuration (second half of the
  "wiped on reload" bug)** — saves carried curated entries written by an
  older version under different field names (`itemNumber`/`origBonus*` vs
  `num`/`bonus*`) and an incompatible prefix/suffix id space. The current
  code couldn't read them, but their mere presence made items look "already
  curated", so the auto-repair skipped them forever: unusable to display,
  unrepairable by recuration. Entry accessors now read every format this
  project has ever saved, entries that can't resolve to a live prefix+suffix
  count as NOT curated (so recuration replaces them), and new entries use
  named string fields (the shape proven to survive the save pipeline).
- **Stale id counters could overwrite live entries** — a save was observed
  with entry ids up to ~172 but a persisted counter of 70; generating or
  re-curating would have silently overwritten existing entries,
  cross-linking items. The counter is now repaired to above the highest
  existing id on every load.
- **Auto-prune on load destroyed shop-stock entries** — pruning marks only
  party-carried items as "in use", so every curated item sitting in a shop
  or chest lost its data on each load (150 of 172 entries deleted in one
  observed load). Auto-prune removed from the load path entirely; pruning
  is manual-only via `RepairItems(true)`.
- **Curated items never survived a reload — the root cause of every "items
  wiped" report** — the curated-data table was bound to `internal.SaveGameData`
  once at app startup, *before* any save loads; the real save's data table
  replaces that one, so reads never saw saved entries and writes went into a
  discarded table. Every session ever logged "Ready. 0 entries". Now uses the
  same proven pattern as the settings system: re-binds from the loaded save's
  data on each fresh load (`LoadMapScripts`) and writes into the current
  save's data at save time (`BeforeSaveGame`). Previously-orphaned items are
  re-curated with fresh enchantments on load (originals unrecoverable).
- **Curated items double-dipped: vanilla enchant applied invisibly alongside
  the curated bonuses** — the rework kept `item.Bonus` live for identity
  purposes, so the native engine kept applying the vanilla enchantment while
  only the curated text displayed. Curation now suppresses the vanilla roll
  again (originals preserved per-entry for revert); identity moved back to
  the per-instance `Charges` tag (with an entry↔item Number sanity check).
  Existing affected items are auto-suppressed on next save load.
- **Skill bonuses never applied ("of the Lich" gave no skills)** — the
  top-4-by-value trim appeared to starve skill bonuses (1–4 by design) out
  behind attribute values. The true cause was the inflated `[0.5..1.5]`
  quality range bloating attribute values past every skill; with the
  design-doc quality range restored (see the distribution re-alignment
  above), the doc's top-4 trim works as its own worked example shows —
  skills survive the ranking naturally. The tooltip mirrors the exact same
  computation.
- **PruneCuratedItems could wipe ALL curated data** — pruning with no party
  loaded (startup/main menu) marked nothing as in-use and deleted every
  entry. Now hard-guarded to only run with a live, iterable party, and
  matches items by tag instead of composite key.
- **Item generation completely broken in the 1.4.0 rework (pre-release)** —
  `GetItemRequiredSkill` was called before its `local` definition, so the
  call resolved to a nil global and EVERY generation errored (all items
  vanilla). Caught in the pre-ship audit via session-log evidence; fixed
  with a forward declaration.
- **Startup-stocked shops/chests skipped curation (regression)** — item
  generation that fires before the party loads found no party member and
  bailed, leaving initial shop stock vanilla (and spamming error logs).
  Restored the fallback: such items are curated toward a random valid
  class (respecting the skill gate where one applies).
- **Double HP/SP regeneration** — MiscTweaks' per-minute lump-sum RegenTick
  handlers and Regeneration.lua's smooth per-100ms system both ran. Now
  mutually exclusive via `Game.RegenerationSmooth` (default on: smooth).
- **SkillHarmony fighting repurposed skill slots** — auto-mastery no longer
  touches Guardian (24), Mana Shield (34), or Retaliation (38); those
  manage their own mastery.
- **Mana Shield character-sheet value** — slot 34 now shows the real
  trained Mana Shield level once trained (magic-school-derived value only
  shows while untrained).
- **StatRemix division-by-zero** — guarded `t.Result / t.Damage` against
  0-damage hits corrupting the result.
- **`TownPortalDestiantionName` typo** — renamed to
  `TownPortalDestinationName` (caller + handler together).
- Removed a stray `.bak` file from the shipped package.

### Recovery note
- `ItemSystem.lua` was destroyed by a bad sync mid-development and rebuilt
  from AI-session history plus the rework above. Existing saves' previously
  curated items lost their original enchantments permanently; on first load
  they are auto-re-curated with fresh enchantments (see `zzRepairItems.lua`).

## 1.3.2 — 2026-07-13

### Fixed
- **Town Portal crash on Escape / after 1-2 teleports (real root cause)** —
  Earlier entries (1.2.0, 1.3.0, 1.3.1) attributed this to native click/hook
  detection at `0x425B1A` and never actually resolved it. The true cause,
  found by disassembling `MM8.exe`, was a **NULL font pointer**: the Town
  Portal destination screen (drawn like a spellbook) renders its labels with
  `book2.fnt`, held in the global at `0x5DB920`. That font is loaded/freed as
  a group with `book.fnt` and `autonote.fnt` by the spellbook UI. Pressing
  Escape frees the fonts, but the TP draw routine runs one more frame with
  `book2.fnt` NULL, so the native text code dereferences a null pointer and
  crashes. (Patching the shared text classifier at `0x449C3B` only moved the
  crash one dereference further, to `0x44AB7A` = `[font+5]`, and corrupted
  text game-wide — that function is used by all text and was never the bug.)
  - **Fix:** `mem.autohook(0x4D1227, ...)` in `1_TownPortalSwitch.lua` guards
    the TP-specific draw function — if `book2.fnt` (`0x5DB920`) is null, it
    skips the draw for that frame (emulating the function's clean cdecl
    return) instead of dereferencing the null font. Pure pass-through when the
    font is loaded; touches no shared code, so no effect on any other screen.
- **Town Portal crash after 1-2 teleports** — The continent-picker recast was
  calling `CastSpellDirect(31, 10, 4)` synchronously from inside the CustomUI
  click handler, skipping native cast setup. Deferred it to the next
  `L2InterfaceUpd` tick (`processPendingRecast` in `TownPortalSwitches.lua`),
  which restored reliable teleporting.
- **Town Portal Continent Selector missing from the release package** —
  `Scripts/Global/TownPortalSwitches.lua` (which defines
  `TownPortalControls.CheckSwitch`, called on every map load) was absent from
  `zzMods/`, so an installed copy of the package would crash on the first map
  transition. Added the file (and the `Scripts/Global/` folder) to the
  package and synced the Town Portal fixes into it.

## 1.3.1 — 2026-07-12

### Fixed
- **Dyson Leland follower / inner chambers door** — `StdQuestsFollowers.lua`
  converts Dyson to a follower (no party slot), but the `Scripts/Maps/d19.lua`
  map patches that remove the party requirement for the inner chambers door
  (Event 15) and Skeleton Transformer (Event 131) were left commented out
  by the MAW Redone author. With Dyson as a follower (not a party member),
  `Players[34]` returns false, so the door wouldn't open and the transformer
  couldn't be destroyed. Uncommented the patch file — quest state (QBits
  19, 20) now controls access instead of party roster.
- **Overdune Snapfinger quest completion broken** — The MAW Redone version
  dropped the Event 197 patch from `Scripts/Maps/out03.lua` that awards
  XP/gold and sets alliance QBits (13–18, 59) when you return Overdune to
  the Merchant Guildhouse. Without it, `OverduneFollow2.CanShow` (which
  requires QBit 59) never fires, so Overdune can never be dismissed from
  the follower group and no quest rewards are given. Restored the patch
  from the original MAW mod.
- **Town Portal silent crash on Escape (slot highlighted)** — Replaced
	`mem.hookfunction(0x425B1A, ...)` with `mem.hookcall` on just the
	specific CALL instruction inside the asmpatch's relocated code.
	`hookfunction` intercepts ALL callers of 0x425B1A (click, Escape
	teardown, Wizard Eye, Hour of Power), which required fragile
	return-address or memory-flag detection to distinguish them.
	`hookcall` replaces only the one `CALL 0x425B1A` instruction in
	the asmpatch's relocated code (the one that runs for TP destination
	clicks via event 0xBD). Escape teardown, Wizard Eye, Hour of Power
	call 0x425B1A directly at different call sites — they are never
	intercepted. No detection logic needed.

## 1.3.0 — 2026-07-09

### Added
- **Perception mastery expanded** — Archer (0), WarriorMage (1), Pathfinder
  line (20-27), Ranger line (76-83), and Thief line (84-91) all raised to
  Grandmaster (was Master). Dragons (28-29) and Minotaurs (52-53) remain at
  Master.

### Changed
- **Retaliation rework** — Replaced chance-based bonus damage (1%/skill-pt,
  max 50%) with a guaranteed instant weapon counterattack after a successful
  Guardian intercept. Counterattack uses melee weapon against melee attacks,
  ranged weapon against ranged/spell attacks. Damage scales with mastery:
  50/75/100/125% melee, 40/60/80/100% ranged. Status text now shows
  "X retaliates for Y damage!".
- **Training hall level caps removed** — All 29 training hall entries in
  `House rules.txt` set to `-1` (no cap). Any training hall trains to any
  level.

### Fixed
- **Retaliation 1-HP bug** — Counterattack damage now uses
  `monster:CalcTakenDamage()` instead of direct `monster.HP =` assignment,
  properly triggering death check, XP, and loot.
- **Town Portal crash** — Hook now targets `0x425B1A` (the native TP
  destination processing function) directly instead of relying on event
  `0xBD` which didn't fire for all click paths. Catches all TP destination
  clicks regardless of which native event triggers them.

## 1.2.0 — 2026-07-09

### Added
- **Town Portal Gateway Destinations** — One slot per continent is always
  unlocked regardless of map discovery: Daggerwound islands (Jadame),
  Castle Harmondale (Antagarich), New Sorpigal (Enroth). Enables
  cross-continent travel before the normal means are available.
  No toggle — always on.
- **XP Multiplier page** — Moved XP Multiplier toggle and regulator from
  Loot & QoL to its own dedicated page (page 5) in Extra Settings.

### Fixed
- **ItemSystem always picks Knight** — `FindSuitablePartyMember` was using
  `elseif not best[1]` for non-skill-gated items (rings, amulets, belts,
  boots, helms, cloaks, gauntlets), always selecting Party[0] (Knight).
  Changed to `else best[#best + 1] = p` so all eligible members are
  collected and one is picked at random.
- **ItemSystem sell price too low** — Hooked `structs.Item.GetValue` via
  `mem.hookfunction(addr, 1, 0, ...)` (thiscall fix, no EAccessViolation).
  Curated items now sell for base × (1 + quality × 2): 1.7×–3× base price.
- **XP Multiplier NumberRegulator step** — Fixed step defaulting to 5
  (jump 2→7→10) instead of 1 (2→3→4).

## 1.1.0 — 2026-07-05

### Added
- **Auto Heal** — `zzHealTarget.lua`: HP heals auto-target lowest-HP party
  member; condition cures clear party-wide with face animation on all 5 members.
  Toggle via Extra Settings.
- **Party Merchant** — `zzMerchantParty.lua`: Vendor prices use the party's
  highest Merchant skill instead of each individual's skill.
  Toggle via Extra Settings.
- **Trap Perception** — `zzTrapPerception.lua`: Chest trap checks use the
  party's highest Perception skill instead of each individual's skill.
  Toggle via Extra Settings.
- **Loot All** — `zzLootAll.lua`: Press V to loot all nearby
  ground items, gold piles, and monster corpses in front of you.
  View-cone + line-of-sight + range filtering (configurable via
  `Game.LootAllRange`, default 2000). Ground sprites removed via
  SpritesToDraw buffer cleanup. Corpses use native PickCorpse
  (`mem.call 0x424E3D`, cc=0) for correct treasure table drops.
  Duplication prevented via per-session corpse tracking.
  Toggle via Extra Settings.
- **Town Portal Continent Selector** — Casting Town Portal opens
  Screen 97 (the character-creation continent picker). Select
  Jadame, Antagarich, or Enroth, then recast TP to see that
  continent's 6 destinations. Auto-detects continent on map change.
- **Cleave mastery now mirrors Armsmaster** — Knights get Expert Cleave
  matching their Armsmaster cap (previously capped at Normal via Stealing).
- **ManaShield mastery from highest magic school** — Dynamic cap follows the
  player's best magic school instead of a fixed skill.

### Fixed
- **ItemSystem RandomPartyMember** — During character creation, items now key
  to the character being equipped (newest party member) instead of always
  defaulting to the Knight (slot 0).
- **ItemSystem save persistence** — Fixed items rerolling on every reload.
  `GameInitialized2` was initializing `CuratedItems` before save data was
  loaded into `internal.SaveGameData`, so the saved table was overwritten by
  an empty one on both save and load. Existing items became orphans and got
  new random prefixes/suffixes every reload.
- **ItemSystem chest items** — Fixed chest items showing "Charges: N" instead
  of curated names on save load. `GameInitialized2` now restores
  `NextCuratedId` from saved data to avoid ID collisions between chest items
  (generated during map load) and saved entries. `AfterLoadMap` now **merges**
  saved entries into the existing `CuratedItems` table instead of replacing it,
  preserving chest items' curated entries alongside saved character items.
- **ItemSystem orphan cleanup** — `GetCuratedEntry` now clears `item.Charges`
  when the curated entry doesn't exist, preventing "Charges: N" display on
  items orphaned by the old save-overwrite bug.
- **DisarmTraps and Repair removed from training** — Both are now
  removed from training halls (via `PopulateLearnSkillsDialog`) and guild
  learn topics (via `HousesTweaks.lua`). DisarmTraps merged into Perception;
  Repair always-on regardless of skill.
  - PerceptionDisarmTraps.lua, RepairBakeIn.lua: PopulateLearnSkillsDialog
  - HousesTweaks.lua: CLT.DisarmTraps and CLT.Repair removed from guild topics
- **Item pools now map DisarmTrap to Perception** — `ItemSystem.lua` `StatMap`
  moved `DisarmTrap` to `SkillMap` → `const.Skills.Perception` so item bonuses
  with "DisarmTrap" grant Perception instead of the defunct DisarmTraps stat.
- **ManaShield nil guard** — `SplitSkill` safely handles uninitialized skill
  entries in the magic school scan.

## 1.0.0 — 2026-07-04

Initial packaged release. Collects all custom enhancements built on top of
cthscr's Merge Revamp (MMMerge 2023-11-05).

### Added
- **Colored Stat Text** — Stat labels colored via `\f` escape code injection
  (no hooks, zero crash risk). Barrel/potion color scheme.
- **XP Display** — "Experience: M" replaced with XP/cost/levels-affordable.
- **Curated Item System** — Intentional prefix/suffix pairs instead of random
  enchantments. Quality variance, stat count cap, skill bonus cap.
- **Skills** — Guardian, Mana Shield, Retaliation, Cleave, Skill Harmony
  (four new Misc-slot skills with auto-mastery).
- **Stat System** — Stat Remix, Stat Tooltips, Party Stat Liquids, Learning tweaks.
- **Resistances** — Race/class-based resistance bonuses.
- **Diagnostic Tool** — `DumpGxt()` for inspecting GlobalTxt entries.

### Fixed
- **Timers** — Nil guard in `timers.lua` to prevent crash when `Timer()`
  is called before `StartTimers()` initializes the timers array.
