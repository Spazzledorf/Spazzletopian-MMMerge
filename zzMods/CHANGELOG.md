# Changelog

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
