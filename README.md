# 🎨 MMMerge Visual & QoL Enhancement Pack

**Make your Might and Magic 8 look better, play smoother, and actually tell you what items do.**

Tired of hunting through white-on-beige stat sheets? Annoyed when a "magic sword" turns out to be for a completely different class? This pack fixes the little things that make the game feel dated — colorful stat sheets, readable item tooltips, smarter loot, and a handful of new skills that actually work with the party-based gameplay M&M is known for.

Everything is toggle-able from the Extra Settings menu (gear icon on the main menu). Nothing is permanent. If you hate it, flip it off and it's gone.

*(Built and tested on cthscr's Merge Revamp, MMMerge Pack 2023-11-05.)*

---

## ✨ What You Get

### ⚔️ Curated Item System
Vanilla MMMerge throws random enchantments at items — loot your party can actually use is rare. This replaces the random rolls with deliberate prefix/suffix combos aimed at your party's classes:

**"Blessed Iron Mace of the Crusader"** → you know immediately who it's for.

- **Names tell the truth.** The prefix is the item's role, the suffix is the class it serves. Tooltips list exactly what it grants.
- **Quality scales with your level.** Early items roll well below their maximum; a high-level party can find near-perfect versions of the same enchant. There's always a better roll out there.
- **Focused, not encyclopedic.** Each item grants at most 4 bonuses — real choices instead of stat soup.
- **Training still matters.** A skill bonus from gear is capped at your own base skill in it (minimum +1). Stack items all you like — mastery comes from training.
- **Fair prices.** Buy/sell value includes the enchantment.
- **Self-healing.** Items from older pack versions are repaired or re-enchanted automatically on load. Manual tools (`RepairItems()`, `RecurateItems()` in the console) exist for the paranoid.

Toggle in Extra Settings → Combat & Items → "Curated Item System".

### 🌍 Town Portal Continent Selector
Casting Town Portal opens the continent selection screen — the gorgeous one from character creation. Click Jadame, Antagarich, or Enroth, and the next cast shows that continent's six destinations.

- **Auto-detection:** changing maps updates your current continent automatically; cross-continent travel just works.
- **Gateway destinations:** one slot per continent is always unlocked, so you can visit the other worlds early — Daggerwound Islands (Jadame), Castle Harmondale (Antagarich), New Sorpigal (Enroth).
- **Stable:** the crash that used to hit on Escape (or after a couple of teleports) is fixed at the root — teleport and cancel freely.

### 🎯 Colored Stat Text
Your stats aren't all the same — why should they look it? Might is red, Intellect is orange, Personality is blue, Endurance is green, Accuracy is yellow, Speed is purple, Luck is white. HP and SP get their own colors too. Your **resistances** get elemental colors on the same page — Fire red, Air light blue, Water blue, Earth brown, Mind purple, Body pink. The character sheet becomes readable at a glance.

*Zero crash risk — it's just color codes in the text, no engine hooks.*

### 💚 Auto Heal (Smart Cures)
Healing spells and condition cures become party-aware. No more hunting through portraits mid-combat:

- **HP heals** (Heal, Power Cure) auto-target the lowest-HP party member.
- **Condition cures** (Cure Poison, Remove Curse, …) clear the condition from the **whole party** in one cast.
- **No target dialog** — one click, optimal result.

### 🏪 Party Merchant
Buy/sell prices use the **best** Merchant skill in the party. Your Knight with Merchant 10 negotiates for everyone.

### 🔍 Trap Perception
Trapped chests are checked against the party's **highest** Perception — your best spotter covers everyone.

### ⚡ Loot All
Press **V** to hoover up all nearby ground items, gold piles, **and** monster corpses straight into your inventory. Only takes what's in front of you, in range, and in line of sight — no looting through walls. (Chests still open normally.)

### 🤝 Quest Followers (Dyson Leland & Overdune Snapfinger)
Vanilla MM8 forces these two quest NPCs into full party slots, benching one of your own. This pack (building on the MAW Redone mod) makes them **followers** — they tag along without taking a slot, and leave on their own when their quest wraps up.

### 🛡️ Four New Skills
Built on repurposed skill slots (no save corruption risk):

| Skill | What It Does |
|-------|-------------|
| **Guardian** | Dive in front of a hit meant for your squishy mage |
| **Mana Shield** | Burn SP instead of HP when you'd drop below 30% |
| **Retaliation** | Instant counterattack after guarding — melee vs melee, ranged vs ranged |
| **Cleave** | Multi-target melee sweeps |

All four auto-promote mastery as you level — no hunting down trainers.

### 🧹 Skill Slot Cleanup
- **Identify Item** — always succeeds automatically
- **Identify Monster** — tied to your highest magic school
- **Repair Item** — always works, no skill point tax
- **Disarm Traps** — folded into Perception, freeing the slot

### 🔢 Better Stat System
- **Smoother stat curves** — no dead zones where +1 does nothing
- **Tooltips on hover** — see exactly what each stat contributes
- **Party-wide stat barrels** — worldly stat boosts apply to everyone

---

## 🚀 One-Minute Install

1. Extract the release zip (`MMMerge-Visual-QoL-Pack-v1.4.0.zip`)
2. Copy `Scripts/` and `Data/` into your MMMerge game folder (merge folders)
3. Copy the two files from the `Patched/` folders over their base versions (30 seconds — see `INSTALL.md`)
4. Start the game

Existing saves are fine — old items are fixed up automatically on first load. Full steps, verification, and uninstall in **`INSTALL.md`**.

---

## 📦 What's Inside

| Folder | Contents |
|--------|----------|
| `Scripts/General/` | All gameplay scripts — drop in and play |
| `Scripts/General/Patched/` | Pre-patched `MenuExtraSettings.lua` (copy over the base one) |
| `Scripts/Core/Patched/` | Pre-patched `timers.lua` with crash fix (copy over the base one) |
| `Scripts/Global/` | Town Portal continent-switch logic |
| `Scripts/Items/` | Curated item pools + the item system design doc |
| `Data/Tables/` | Resistance data, spell learning, teleport coordinates |

---

## 🙏 Credits

Thanks to Malekith and the MAW mod community for inspiration, and to
GrayFace and cthscr for MMExtension and the Merge, without which none of
this would be moddable at all.
