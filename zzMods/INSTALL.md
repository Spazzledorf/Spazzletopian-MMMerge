# Installation

## Requirements

- **Might and Magic 8 MMMerge (Pack 2023-11-05)** — built and tested on
  cthscr's Merge Revamp branch.
- MMExtension 2.x (included with MMMerge).

## Quick Install

1. **Back up your save files** (`Saves/` directory in your game folder).

2. **Copy `Scripts/` and `Data/`** from this package into your game root
   directory (where `MM8.exe` lives). When prompted, **merge folders**.

   **Important**: For `Scripts/General/MenuExtraSettings.lua` and
   `Scripts/Core/timers.lua`, use the **Patched** versions provided in
   this package:

   ```
   Scripts/General/Patched/MenuExtraSettings.lua  →  <GameDir>/Scripts/General/MenuExtraSettings.lua
   Scripts/Core/Patched/timers.lua                 →  <GameDir>/Scripts/Core/timers.lua
   ```

   All other files copy directly from their positions in the package.

3. **Restart the game.** Open Extra Settings (gear icon on main screen →
   "Combat & Items" page) to configure toggles.

## What Gets Installed

| Location | Files |
|----------|-------|
| `Scripts/General/` | All `.lua` files from `Scripts/General/` |
| `Scripts/General/MenuExtraSettings.lua` | Use the Patched version |
| `Scripts/Core/timers.lua` | Use the Patched version |
| `Scripts/Items/` | Item pools and design doc |
| `Data/Tables/` | TownPortalCoords.txt, Resistances.txt, SpellsLearning.txt |

## Verifying Installation

Launch the game and open Extra Settings (gear icon). You should see toggles
for "Curated Item System" and "Colored Stat Text" on the "Combat & Items"
page. Open the character Stats tab — stat labels should appear in their
assigned colors.

## Uninstalling

Delete all files copied from this package and restore the original
`MenuExtraSettings.lua` and `timers.lua` from a backup.
