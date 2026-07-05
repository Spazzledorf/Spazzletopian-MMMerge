[README.md](https://github.com/user-attachments/files/29668217/README.md)
# Spazzletopian-MMMerge
A QoL and Gameplay Smoother Mod for the MMMerge project
# MMMerge Visual & QoL Enhancement Pack

A comprehensive set of quality-of-life and visual enhancement scripts for
[cthscr's Merge Revamp](https://gitlab.com/cthscr/mmmerge) (MMMerge 2023-11-05).

All features are toggle-able from the Extra Settings menu (press the gear
icon on the main game screen → pages 1-3).

## Features

### Colored Stat Text
Stat labels on the character sheet colored to match the barrel/potion scheme.
Toggle: Extra Settings → Combat & Items → "Colored Stat Text".
- No hooks, no INT3 breakpoints, no crash risk.
- Uses MMExtension's `\f` color escape codes via GlobalTxt injection.

### XP Display
Replaces "Experience: M" on the Stats tab with
"XP: current / costForNextLevel / levelsAffordable".
- Always active (no toggle).

### Curated Item System
Replaces random enchantments with intentional prefix/suffix pairs.
Toggle: Extra Settings → Combat & Items → "Enable Curated Item System".

### Skill System
Four new skills using repurposed Misc slots:
- **Guardian** — intercept hits for party members
- **Mana Shield** — SP-absorbed damage reduction
- **Retaliation** — counter-attack on dodge
- **Skill Harmony** — auto-mastery progression

### Stat System
- **Stat Remix** — smoother stat curves
- **Stat Tooltips** — detailed per-stat breakdowns
- **Party Stat Liquids** — party-wide potion effects
- **Learning** — XP gain adjustments

## Files Included

| Category | Files |
|----------|-------|
| **Core Scripts** | `zzXPDisplay.lua`, `zzStatColors.lua`, `zzDumpGxt.lua` |
| **Item System** | `ItemSystem.lua`, `ItemSystemDisplay.lua`, `ItemSystemTooltip.lua`, `ItemSystemDebug.lua`, `Items/ItemPools.lua` |
| **Skills** | `Cleave.lua`, `Guardian.lua`, `ManaShield.lua`, `Retaliation.lua`, `SkillHarmony.lua` |
| **Stats** | `StatRemix.lua`, `StatTooltips.lua`, `PartyWideStatLiquids.lua`, `Learning.lua`, `PerceptionDisarmTraps.lua`, `RepairBakeIn.lua` |
| **Resistances** | `Resistances.lua`, `SpellsLearning.lua`, `Regeneration.lua` |
| **Data** | `Data/Tables/TownPortalCoords.txt`, `Resistances.txt`, `SpellsLearning.txt` |
| **Reference** | `zzMAW-Reference.lua.disabled`, `zzSkillSlots-Reference.lua.disabled` |

See `INSTALL.md` for setup instructions and `CHANGELOG.md` for version history.
