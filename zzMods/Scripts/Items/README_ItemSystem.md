# MMMerge Curated Item System

## The Problem

Vanilla MM and unmodified MMMerge generate item enchantments randomly from large pools. Even veteran players frequently reach endgame with empty equipment slots because useful items simply never dropped. Worse, there is no in-world logic for why a craftsman would make a "Longsword of Fire Resistance" with "+2 Intellect" — it's just noise.

## The Solution

Every magic item has a clear, intentional identity. A player reads **"Blessed Iron Mace of the Crusader"** and immediately knows:

- **Blessed** → prefix, role-oriented: this item boosts Spirit/Mind/Body magic — divine schools
- **of the Crusader** → suffix, class-oriented: Crusader-specific stats (Repair, Mace GM, Shield GM)

No guesswork. The item screams who it's for.

---

## How the System Works

### Format

```
[Prefix]  [Material]  [Item Type]  [Suffix]
 Blessed    Iron        Mace        of the Crusader
```

### Prefixes = Role Oriented

Prefixes describe **what kind of fighter or caster** benefits from this item. They are assigned by *bucket* — a group of classes that share a playstyle and spell school access.

A **Pyromancer's** prefix means: this item boosts Fire magic and Intellect, so any class in the Hybrid Intellect bucket (Archer, Warrior Mage, Deerslayer, Thief, etc.) will find it useful.

### Suffixes = Class Oriented

Suffixes name a specific class or promotion tier. The stat pool for a suffix emphasizes **what is unique to that class** — skills only that class can Grandmaster, or primary combat identifiers.

A **Monk** item gives Unarmed and Dodge bonuses because *only Monks can Grandmaster those skills*. A Black Knight item gives Plate and dark flavor because that's the identity of a second-promotion dark Knight.

---

## Role Buckets

Each bucket shares prefix pools. Within a bucket, different class lines are distinguished by their suffixes.

| Bucket | Classes | Spell Schools |
|---|---|---|
| **Tank** | Knight, Cavalier, Champion, Black Knight | None |
| **Warrior** | Barbarian, Berserker, Warmonger | None |
| **Hybrid Intellect** | Archer line · Deerslayer line · Thief line | Fire, Air, Water, Earth |
| **Hybrid Personality** | Paladin line · Monk line · Vampire line · Minotaur line | Spirit, Mind, Body |
| **Intellect** | Sorcerer → Wizard → Archmage/Lich · Lich → Greater Lich → Power Lich | Fire, Air, Water, Earth + Light or Dark |
| **Personality** | Cleric/Priest line · Dragon line | Spirit, Mind, Body + Light or Dark |
| **Druid** | Druid → Great Druid → Arch Druid / Warlock | All 7 schools |
| **Ranger** | Ranger → Hunter → Ranger Lord / Bounty Hunter | Both groups (minor) |

---

## Prefix Tags

| Tag | Meaning |
|---|---|
| `gen` | Generalist — minor bonus to *all* schools for this bucket. Drops for any class in the bucket. |
| `spec` | Specialist — focuses on 1–2 schools or a primary stat. More useful for players building toward a specific school. |
| `light` | Light-path only — only paired with a light-aligned class suffix (e.g., of the Champion, of the Hero) |
| `dark` | Dark-path only — only paired with a dark-aligned class suffix (e.g., of the Black Knight, of the Assassin) |

---

## Suffix Tiers

| Tier | Meaning |
|---|---|
| `0` | Base class (modest bonuses) |
| `1` | First promotion (medium bonuses) |
| `2` | Second promotion (strongest bonuses; may be light/dark/any aligned) |

Items scale in power with tier. A tier-2 dark suffix will only pair with a `dark` or `gen` prefix.

---

## Spell Schools

Prefixes and suffixes explicitly reference spell schools by name:

- **Elemental** (Intellect-based): Fire · Air · Water · Earth
- **Divine** (Personality-based): Spirit · Mind · Body
- **Moral** (advanced, high promo only): Light · Dark

A **generalist** prefix for the Hybrid Personality bucket gives +1 Spirit/Mind/Body.
A **specialist** prefix gives +2 to one school (e.g., `Lifeguard's` = +2 Body) plus the bucket's primary stat.

---

## Capped Skills

Some skills reach 100% effectiveness at Grandmaster with **no further benefit from higher values**. These are included only as minor bonuses (`+1`) if at all — anything higher wastes item budget:

| Skill | Cap behavior |
|---|---|
| **Merchant** | GM = 100% price discount, cannot exceed |
| **Perception** | GM = 100% bonus on item find, no further scaling |
| **Identify Monster** | GM = complete monster info, no further scaling |

---

## Dragon Class Notes

Dragons are in the Personality bucket (they use Body/Mind/Spirit spells) but have a unique combat profile:

- **DragonMagic** — their exclusive class skill that powers all 4 spell attack types
- **Fire breath** — ranged attack, no weapon skill needed
- **Claw attacks** — melee, scales with Might (worthwhile for melee builds)
- **SP (mana)** — required to fuel spell attacks; more SP = more casts

Dragon items get Personality prefixes (for their divine spell schools) and Dragon-specific suffixes (DragonMagic + SP + Might for melee). The prefix handles the Spirit/Mind/Body and Personality stat; the suffix handles what's unique to the Dragon.

---

## Stat Variance — Quality

Not every "Blessed Iron Mace of the Crusader" is created equal. Pool values in
`ItemPools.lua` are treated as **maximum possible values** — the actual bonus on
any given drop is scaled by a **quality multiplier** that depends on your
party's average level at the time the item was generated.

### Quality Formula

```
progress = min(1, (avgPartyLevel - 1) / 124)
minQ = 0.35 + progress * 0.40    →  [0.35 → 0.75]
maxQ = 0.55 + progress * 0.45    →  [0.55 → 1.00]
quality = minQ + random() × (maxQ - minQ)
```

Each stat on the selected prefix and suffix is then multiplied by `quality`
and rounded down:
```
actualBonus = max(1, floor(poolValue × quality))
```

### What This Means In-Game

| Party Level | Quality Range | A "Lich" item (Int=5) | A "Power Lich" item (Int=12) |
|---|---|---|---|
| 1 | 0.35 – 0.55 | Int +1–2 | Int +4–6 |
| 20 | 0.41 – 0.62 | Int +2–3 | Int +4–7 |
| 40 | 0.48 – 0.69 | Int +2–3 | Int +5–8 |
| 60 | 0.54 – 0.77 | Int +2–3 | Int +6–9 |
| 80 | 0.60 – 0.84 | Int +3–4 | Int +7–10 |
| 100 | 0.66 – 0.91 | Int +3–4 | Int +7–10 |
| 125 | 0.75 – 1.00 | Int +3–5 | Int +9–12 |

**Result:** early-game items are noticeably weaker than their pools suggest,
giving a real sense of progression. A max-level party can eventually find
near-perfect rolls, but never trivially — the random component always leaves
room for another try.

Existing items (from before this system was added) that lack a quality record
default to `0.60` — a middle-of-the-road value that keeps them useful but not
exceptional.

---

## Stat Count Cap — Focused Items

Even with quality scaling, a prefix + suffix pair together can list 8+ stats
(two from prefix, six from suffix). Having every item grant 6–8 different
bonuses drowns out the identity of any single stat and makes item choice
meaningless.

Curated items are **trimmed to the top 4 bonuses** (by value) after merging
the prefix and suffix's quality-adjusted stats. If two entries grant the same
stat (e.g. Endurance from both "Stalwart" and "the Knight"), they are summed
first, then ranking decides which 4 survive.

**What this means:** a "Power Lich" suffix (Int=12, Dark=4, Fire=2, Air=2,
Water=2, Earth=2, Meditation=3, SP=20) paired with an "Infernal" prefix
(Fire=2, Intellect=6) would normally grant 8 stats. After quality and trim,
only the 4 highest-value bonuses apply — typically Int, SP, Dark, and the
higher of Meditation or Fire. The item stays focused and the player has to
make real gear choices.

---

## Skill Bonus Cap — Progression Friendly

Magic items in vanilla MM only grant the **highest** skill bonus from equipped
gear — stacking was never allowed. The curated system deliberately changes
this (bonuses from different items do stack), but an unchecked stack can let
items replace the need to train skills at all.

To prevent this:

> **A curated skill bonus can never exceed the player's base skill level.**

```
finalBonus = min(curatedTotal, max(playerBaseSkill, 1))
```

| Base Skill | Total Curated Bonus | Applied Bonus | Effective Total |
|---|---|---|---|
| 4 | +10 | +4 | 8 |
| 4 | +3 | +3 | 7 |
| 14 | +10 | +10 | 24 |
| 1 | +8 | +1 | 2 |

**Result:** items complement training, they don't replace it. A low-skill
character gets modest help from gear; a mastered skill can be pushed further
by stacking items, but the cap keeps the ratio meaningful. The floor of `1`
ensures even an untrained skill gets a tiny bonus from items.

This cap only applies to **skills** (weapon, armor, utility, magic schools)
via `events.GetSkill`. Core stats (Might, Intellect, etc.) applied through
`events.CalcStatBonusByItems` are **not** capped.

---

## How to Edit Pools

All prefix and suffix data lives in one file: `Scripts/Items/ItemPools.lua`.

### Add a new prefix

Find the right bucket table and add an entry:

```lua
-- In M.Prefixes.Warrior:
{ name = "Bloodthirsty", stats = { Might=8, Speed=3 }, tag = "spec" },
```

### Change a stat value

Pool stat values are **maximum possible values** — the actual bonus on a drop
is scaled by the party-level quality multiplier. Higher values mean stronger
*potential* items at max level, but early drops will still be proportionally
weaker.

Find the entry and edit the number:

```lua
-- Change Mighty from +5 to +7:
{ name = "Mighty", stats = { Might=7 }, tag = "gen" },
```

### Add a new suffix

Find the right class line table and add an entry:

```lua
-- In M.Suffixes.KnightLine:
{ name = "the Templar", stats = { Plate=3, Light=2, Personality=5 }, tier=2, alignment="light" },
```

### Remove an entry

Delete the line or comment it out:

```lua
-- { name = "Resolute", stats = { Endurance=7, HP=10 }, tag = "spec" },
```

### Stat name reference

All valid stat names are documented in the comment block at the top of `ItemPools.lua`.

---

## File Structure

```
Scripts/Items/
  ItemPools.lua              ← All prefix and suffix pool data. Edit this.
  README_ItemSystem.md       ← This file.

Scripts/General/
  ItemSystem.lua             ← Core runtime logic: generation, suppression,
                                per-instance tagging, toggle/revert, pruning,
                                stat/skill application, weapon-skill filter,
                                quality variance, stat trim, skill cap.
                                Exposes ItemSystemInternal for other files.
  ItemSystemDisplay.lua      ← Curated name in the item's title (e.g.
                                "Unyielding Titanic Trident of the Knight").
  ItemSystemTooltip.lua      ← Curated stat breakdown in the item's info box,
                                replacing the native "Charges: N" line. Now
                                displays quality-adjusted and trimmed values
                                to match what actually applies.
  ItemSystemDebug.lua        ← Console test tool (ItemTest.*). Ships with the
                                SOURCE only, not the release zip. Harmless if
                                present -- does nothing unless you call it.
  StatTooltips.lua           ← Pre-existing file (not part of this system),
                                extended with one addition -- see "Core
                                Attribute Display Gap" below.
```

---

## Design Notes

- Common (non-magic) items are unchanged — vendor fodder still exists.
- Prefix + suffix pairing should respect alignment: a `light` prefix only pairs with a `light` or `any` suffix, and vice versa for `dark`.
- Stat values in `ItemPools.lua` are starting points. Expect tuning during playtesting.

---

## Current Implementation Status (as ported into MMMerge TEST)

### Core system (`ItemSystem.lua`)

- **Vanilla enchantments ARE replaced, not stacked.** When a curated pick succeeds, `item.Bonus`/`BonusStrength` AND `item.Bonus2` are all zeroed on that specific item — these are two *independent* vanilla enchantment slots (STDITEMS.TXT and SPCITEMS.TXT respectively; an item can roll either alone or both at once) — and the item is tagged with a per-instance curated id stored in `item.Charges`. All of the item's magic-bonus stats/skills come from the curated pool from then on, applied via `events.CalcStatBonusByItems` / `events.GetSkill`. `item.Bonus2` only ever holds `0` or the item's own original vanilla-rolled value (restored on revert) — we never write an *encoded id* into it, which is what caused crashes in an earlier version of this system (see file header). This was tightened after testing found a real item ("Exquisite Long Dagger") that rolled *only* `Bonus2` (Bonus=0, Bonus2=64) — the original gate only checked `Bonus`, so items like it were silently skipped and left fully vanilla, including any that had rolled both slots simultaneously (in which case the Bonus2 half would have kept stacking with the curated bonus even after the "toggle overwrites vanilla" fix).
- **Identity is per-instance**, not "any item with the same rolled stats." Each curated item carries its own id in `item.Charges`, so two structurally-identical drops no longer collide or share an identity. This only works for item types that never use charges natively (`item.MaxCharges == 0` at generation time) — charge-based items (wands) are left completely untouched by this system.
- **Toggle overwrites vanilla, and reverts cleanly.** `Game.ItemSystemEnabled` (default `true`) gates all hooks. Available in-game via Extra Settings → Page 3 "Combat & Items" → "Enable Curated Item System". Toggling it off and calling `SyncItemSystemToggle()` restores every currently-tagged item's original vanilla `Bonus`/`BonusStrength`/`Bonus2`. Toggling back on and re-syncing re-tags any item whose current stats still match a previously recorded curated entry. The sync also runs automatically once per game load.
- **Performance:** stat/skill bonus lookups are cached per player per equipped-item state (invalidated automatically when gear changes), instead of rescanning all 16 equipment slots on every single stat/skill query.
- **Quality variance:** pool values are maximum possible. Each item rolls a quality multiplier based on party level at generation time — see [Stat Variance — Quality](#stat-variance--quality) above. Backward-compat entries default to 0.60.
- **Stat count cap:** each item is trimmed to the top 4 bonus values after quality adjustment — see [Stat Count Cap — Focused Items](#stat-count-cap--focused-items) above.
- **Skill bonus cap:** curated skill bonuses are capped at the player's base skill level so items complement training instead of replacing it — see [Skill Bonus Cap — Progression Friendly](#skill-bonus-cap--progression-friendly) above.
- **Pruning:** stale `CuratedItems` entries (items no longer in the party's possession) are cleared out on game load, with a grace window so freshly-dropped items can't be swept before they're even picked up. Items sitting in an unvisited chest or on the ground at prune time can lose their entry while away — picking them back up later just makes them a plain item again, not a crash. Pruning only runs while the toggle is on — while it's off, every item has been reverted and its `Charges` tag cleared, so there's no way to tell "still owned but reverted" apart from "gone"; running the prune sweep in that state would have deleted every entry and made re-enabling permanently unable to restore anything.
- **Weapon-skill filter:** a weapon can only ever benefit from *its own* weapon skill — a Mace boosting Sword skill made no sense, since equipping a Mace never uses Sword skill. `ApplyStats`/`FilterStatsForItem` drop any of the 8 weapon-skill stats (Sword/Axe/Mace/Dagger/Staff/Spear/Bow/Unarmed) that don't match the equipped item's own weapon skill, read from `item:T().Skill`, cross-checked against `item:T().EquipStat` (only items that actually equip in a weapon category — melee 1H/2H/ranged — are restricted at all; rings, armor, gauntlets, amulets, belts, boots are never touched by this filter regardless of what stats they roll). Suffix/prefix *selection* stays independent of base item type — a Mace can still roll "the Knight" for flavor — but the mismatched stat just won't apply or display. One deliberate exception: Staff and Unarmed are treated as compatible (Monks train in both), so a Staff can grant both; every other pairing requires an exact match. This same filter is shared with the tooltip display (`ItemSystemTooltip.lua`) via `ItemSystemInternal.FilterStatsForItem`, so the tooltip can never *claim* a bonus that isn't actually applying.
- **Sell price:** curated items suppress `item.Bonus` (=0), so native `structs.Item.GetValue` prices them at bare base cost. Fixed 2026-07 by hooking `GetValue` (MM8 `0x453CE7`, a clean thiscall entry confirmed by disassembly) and ADDING a premium of `GOLD_PER_BONUS_POINT × (sum of the item's applied curated bonuses)` — additive, never mutates item fields. The earlier `mem.hookfunction` crash was a technique error (an unhandled throw in the callback skips the trampoline's `d:ret()` and corrupts the stack, the same class as the Town Portal `0x425B1A` bug); every path in the current hook is `pcall`-isolated and always returns a number. Works for salvaged items too (priced by current curated bonuses, not a stored vanilla roll).

### Name display (`ItemSystemDisplay.lua`) — confirmed working in-game

Curated items show their prefix/suffix in the title, e.g. **"Unyielding Titanic Trident of the Knight"**, exactly matching the format this README describes. Implemented by porting the `GetName`/`GetIdentifiedName` hook mechanism from Malekitsu/Maw-Mod-MMMerge (`Scripts/Structs/extraEditableDescriptions.lua`, "ITEM NAME HOOK" section) — the original abandoned attempt at this (mentioned in older revisions of this doc) hit a short-jump obstacle at `structs.Item.GetName`'s entry point that a plain `mem.hookfunction` can't intercept directly; MAW's approach patches the exact 6-byte dispatch to make the branch explicit instead of implicit, which then *is* hookable normally. Addresses (`0x453D3E`/`0x453D58`) confirmed matching this project's own `structs.Item.GetName`/`GetIdentifiedName` definitions before use.

### Tooltip / stat breakdown (`ItemSystemTooltip.lua`) — confirmed working in-game

The item's info box shows a stat breakdown (e.g. "AC +3, Endurance +6, Shield +2") in place of the native "Charges: N" line that would otherwise leak the per-instance tag id as a nonsensical number on non-wand items. Stats from both prefix and suffix are merged by name (so a stat granted by both, like Endurance from two different sources, shows as one combined total rather than two separate lines — this was a real bug caught during testing and fixed).

The tooltip applies the same **quality multiplier** and **stat count trim** that the actual stat/skill application uses — displayed values always match what `SumCuratedBonuses` applies. Quality is read per-item from the curated entry (defaulting to 0.60 for backward-compat items). Trimming keeps only the top 4 merged bonus values.

This needed a much larger hook than the name change: the item info box is built from five text rows (Type, BasicStat, Enchantment, Description, Name) sharing one indexed lookup table that the native height-calculation and draw passes iterate unconditionally — all five had to be wired up (four of them just passing text through unchanged) even though only Enchantment is actively rewritten, because leaving any row's lookup slot unpopulated would mean the native code dereferences a null pointer for it. This class of bug (an under-populated shared data structure) is what caused an actual crash earlier in this project's development, from a different, now-removed approach to spawning test items — see `ItemSystemDebug.lua`'s header for that history.

### Core attribute display gap (`StatTooltips.lua`) — resolved

The 7 core attributes (Might/Intellect/Personality/Endurance/Accuracy/Speed/Luck) have their own character-sheet tooltip (a file that predates this system) which reads `pl.<Stat>Bonus` as a **raw cached player-struct field**, not by calling `events.CalcStatBonusByItems` live. Skills (via `events.GetSkill`) *are* queried live every time their own tooltip renders, which is why a Sword-skill bonus showed up immediately and correctly in testing — but the core-attribute cache is apparently never refreshed by anything this mod can see or trigger from Lua (confirmed via research: no script in this codebase writes to `pl.MightBonus`/`pl.EnduranceBonus`/etc., and no documented native "recalculate" hook exists for it). The underlying bonus is real and does affect gameplay (confirmed: HP correctly reflects a curated Endurance bonus) — it just never appears in that specific native "Bonus:" line.

Fix applied: `StatTooltips.lua` now `GetCuratedBonus(pl, statName)` which calls `ItemSystemInternal.SumCuratedBonuses` and folds the result directly into the displayed `Bonus` and `Total` values, so the tooltip reflects the actual effective stat totals in one line rather than appending a separate disclaimer.

**Note on `ItemTest.DumpPlayerBonuses`:** this console helper calls `SumCuratedBonuses` directly, bypassing the per-player equipment cache — if it shows no bonuses, the item's `Charges` tag may have been cleared (e.g. by a toggle-off event). Check `ItemTest.DumpInventory(0)` to confirm the item's Charges/tag state, then toggle the item system off and back on (or call `SyncItemSystemToggle()`) to re-tag. This is not a runtime bug — `CalcStatBonusByItems` and `GetSkill` use the cached path and will show the correct bonus in-game as long as `Game.ItemSystemEnabled` is true.

### Testing (`ItemSystemDebug.lua`)

> This tool ships with the **source repository**, not the player release zip
> (it's a development aid). If you installed from the zip and want it, grab
> `ItemSystemDebug.lua` from the source.

Console-callable helpers (`ItemTest.*`, via the debug console — Ctrl+F1) for exercising each piece independently: pool/class mapping, real item generation, inspection, toggle round-trip, and pruning. See the file's own header for the full command list.

One important lesson baked into its current design: `ItemTest.GenerateItem` **re-rolls an item already sitting in inventory, in place** (`item:Randomize(...)` called directly on an existing `player.Items[slot]`), rather than trying to manufacture a new inventory entry from Lua. Two earlier approaches — `Mouse:ReleaseItem()` (silently failed to land the item in inventory when called from the console) and manually copying a generated item's fields into a "free" slot found by scanning for `Number == 0` — both tried to create a new inventory entry, and the second one **crashed the game** (`EAccessViolation` inside `Mouse:RemoveItem()`, most likely from not also updating the separate `Inventory[]` grid-mapping array the UI depends on). The re-roll-in-place approach, ported from how Malekitsu/Maw-Mod-MMMerge re-enchants existing chest/map-object items, only ever mutates an item the engine already owns and placed — nothing is ever inserted from Lua. Because of this, `GenerateItem` requires an explicit slot argument and **overwrites whatever is currently there** — check `ItemTest.DumpInventory(playerIndex)` first and pick something you don't mind losing.
