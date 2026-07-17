# Installation

## Requirements

- **Might and Magic 8 MMMerge (Pack 2023-11-05)** — built and tested on
  cthscr's Merge Revamp branch.
- MMExtension 2.x (included with MMMerge).

## Install from the Release Zip

You should have a file like `MMMerge-Visual-QoL-Pack-v1.4.0.zip`.

1. **Back up your save files** — copy the `Saves/` folder from your game
   directory somewhere safe. (Nothing here should harm saves, but you only
   regret the backup you didn't make.)

2. **Extract the zip** somewhere temporary and look inside. You'll see:

   ```
   Scripts/     Data/     README.md     CHANGELOG.md     INSTALL.md
   ```

3. **Copy `Scripts/` and `Data/` into your game folder** — the one where
   `MM8.exe` lives. When Windows asks, choose **merge folders** and allow
   overwriting. (The `.md` files are documentation; you don't need to copy
   them, but they're harmless if you do.)

4. **Two files need one extra step.** The pack modifies two files that base
   MMMerge also ships. To avoid silently clobbering yours, the modified
   versions are parked in `Patched/` subfolders — copy them over the base
   ones manually:

   ```
   Scripts/General/Patched/MenuExtraSettings.lua  →  <GameDir>/Scripts/General/MenuExtraSettings.lua
   Scripts/Core/Patched/timers.lua                →  <GameDir>/Scripts/Core/timers.lua
   ```

5. **Start the game.** That's it.

## Verify It Worked

- Open **Extra Settings** (gear icon on the main menu) → "Combat & Items"
  page. You should see toggles like **"Curated Item System"** and
  **"Colored Stat Text"**.
- Open a character's **Stats** tab — stat labels should be colored.
- Cast **Town Portal** — you should get the continent selection screen.

## Using an Existing Save?

Totally fine — and expected. On first load:

- New loot (shops, chests, drops) starts using the curated item system
  immediately.
- Items curated by **older versions of this pack** are automatically
  repaired or re-enchanted (fresh bonuses — the originals can't be
  recovered). This runs on its own for the first few loads and then
  stops; you don't need to do anything.
- Purely vanilla items are never touched.

If something ever looks wrong with items, the console (Ctrl+F1) commands
`RepairItems()` and `RecurateItems()` are the manual fix-it tools, and
`MMMergeLog.txt` in the game folder records what the item system did.

## Upgrading from an Older Version of This Pack

Same as installing: copy over the top (steps 3–4). Check `CHANGELOG.md`
for anything version-specific.

## Uninstalling

1. Delete the files this pack added (everything listed in the zip's
   `Scripts/` and `Data/` folders).
2. Restore `MenuExtraSettings.lua` and `timers.lua` from your base MMMerge
   install (or re-copy them from a fresh MMMerge download).
3. Saves keep working — curated items simply revert to acting like plain
   items (their curated data sits inert in the save).
