# Installation

## Requirements

- **Might and Magic 8 MMMerge (Pack 2023-11-05)** — built and tested on
  cthscr's Merge Revamp branch.
- MMExtension 2.x (included with MMMerge).

## Quick Install

1. **Back up your save files** (`Saves/` directory in your game folder).

2. **Copy the entire `Scripts/` and `Data/` directories** from this package
   into your game root directory (where `MM8.exe` lives). When prompted,
   **merge folders**, do not overwrite entire directories.

3. **Patch existing files** (see below).

4. **Restart the game.** Open Extra Settings (gear icon on main screen) to
   configure toggles.

## Patching Existing Files

Two existing game files need small manual edits.

### 1. `Scripts/General/MenuExtraSettings.lua`

Add `"StatColorsEnabled"` to `VarsToStore` and its toggle on page 3.

**Change 1** — Add to `VarsToStore` (line ~166):
```lua
-- BEFORE:
local VarsToStore = {"UseMonsterBolster", "BolsterAmount", ..., "TownPortalFullList"}

-- AFTER:
local VarsToStore = {"UseMonsterBolster", "BolsterAmount", ..., "TownPortalFullList", "StatColorsEnabled"}
```

**Change 2** — Add toggle after the Town Portal toggle (after line ~324):
```lua
OnOffTumbler(ExSetScr3, 95, 405, VarsToStore[15])
CustomUI.CreateText{
    Text = "Colored Stat Text",
    X = 140, Y = 405, Width = 400, Height = 16,
    AlignLeft = true,
    Screen = ExSetScr3
}
```

**Change 3** — Add default in `LoadMapScripts` (near line ~408):
```lua
if ExSet.StatColorsEnabled == nil then
    ExSet.StatColorsEnabled = true
end
```

### 2. `Scripts/Core/timers.lua`

Add a nil guard to prevent a rare crash.

**Change** — At line ~100, before `timers[#timers+1] = ...`:
```lua
if not timers then timers = {} end
```

**Change** — At top of `RemoveTimer` (line ~177):
```lua
function RemoveTimer(f)
    if not timers then return end
    ...
```

## Verifying Installation

Open the Stats tab — stat labels should be colored. Open Extra Settings →
"Combat & Items" page — toggles for Curated Item System and Colored Stat
Text should appear.

## Uninstalling

Delete all files listed below, revert the two patch edits above.

## File Manifest

### `Scripts/General/`
| File | Purpose |
|------|---------|
| `zzXPDisplay.lua` | XP display on Stats tab |
| `zzStatColors.lua` | Colored stat text |
| `zzDumpGxt.lua` | GlobalTxt diagnostic tool |
| `Cleave.lua` | Cleave skill (auto-retaliation) |
| `Guardian.lua` | Guardian skill (intercept hits) |
| `ItemSystem.lua` | Curated Item System core |
| `ItemSystemDebug.lua` | Item System debug tools |
| `ItemSystemDisplay.lua` | Item System UI overlays |
| `ItemSystemTooltip.lua` | Item System tooltips |
| `Learning.lua` | XP/Learning skill tweaks |
| `ManaShield.lua` | Mana Shield skill |
| `PartyWideStatLiquids.lua` | Party-wide potion effects |
| `PerceptionDisarmTraps.lua` | Perception → Disarm merge |
| `Regeneration.lua` | Smooth HP/SP regen |
| `RepairBakeIn.lua` | Repair Item always-on |
| `Resistances.lua` | Race/class resistance bonuses |
| `Retaliation.lua` | Retaliation skill |
| `SkillHarmony.lua` | Auto-mastery progression |
| `SpellsLearning.lua` | Spell learning customization |
| `StatRemix.lua` | Smoother stat curves |
| `StatTooltips.lua` | Expanded stat tooltips |
| `zzMAW-Reference.lua.disabled` | Developer reference (MAW patterns) |
| `zzSkillSlots-Reference.lua.disabled` | Developer reference (slot usage) |

### `Scripts/Items/`
| File | Purpose |
|------|---------|
| `ItemPools.lua` | Curated prefix/suffix pools |
| `README_ItemSystem.md` | Item System design doc |

### `Data/Tables/`
| File | Purpose |
|------|---------|
| `TownPortalCoords.txt` | Reserved teleport coordinates |
| `Resistances.txt` | Race/class resistance data |
| `SpellsLearning.txt` | Spell learning data |
