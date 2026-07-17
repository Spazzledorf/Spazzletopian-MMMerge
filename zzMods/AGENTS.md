# MMMerge Visual & QoL Enhancement Pack — Project Instructions

## Project
Custom enhancement mod for cthscr's Merge Revamp (MMMerge 2023-11-05).
Deployable package at `zzMods/`.

## Tech Stack
- Lua 5.1 via MMExtension 2.x (`Scripts/General/` auto-loaded by RunFiles)
- No compiled binaries, no INT3 breakpoints that crash during loading
- Windows-only (tested on GOG Galaxy install)

## File Structure
```
Scripts/General/          — All gameplay scripts (.lua)
Scripts/General/Patched/  — Pre-patched originals (e.g. MenuExtraSettings.lua)
Scripts/Core/Patched/     — Pre-patched core files (e.g. timers.lua)
Scripts/Items/            — Curated item pool data (ItemPools.lua)
Data/Tables/              — Data overrides (resistances, spells, etc.)
zzMods/                   — Deployable package (mirrors game root)
```

### ⚠️ Exception: `Scripts/General/ItemSystem.lua` is a redirect stub, NOT a mirror
Unlike every other pack file, `Scripts/General/ItemSystem.lua` is a deliberate
8-line stub (`dofile(AppPath.."zzMods/Scripts/General/ItemSystem.lua")`). The
REAL ~1100-line implementation lives ONLY in `zzMods/Scripts/General/ItemSystem.lua`.
This is intentional (a single source of truth for one large, frequently-edited
file), NOT a sync gap — do not "fix" it by copying either copy over the other.

**This already happened once and nearly destroyed the file permanently:** a
blind `Scripts/ -> zzMods/` sync (done to reconcile an unrelated audit's
findings) overwrote the real `zzMods/Scripts/General/ItemSystem.lua` with the
stub content, causing infinite `dofile` recursion (`stack overflow`) on every
game launch. It was only recoverable by extracting a complete prior version
from an old Claude Code session transcript (`~/.claude/projects/.../*.jsonl`)
— there was no git, no backup, and the working-tree copy was ALSO just the
stub, so this was one blind sync away from unrecoverable permanent data loss.

`check-sync.sh` knows about this file via its `REDIRECT_EXCEPTIONS` list and
will NOT flag it as stale — trust the script's "REDIRECT (ok)" line, don't
manually override it. If you ever add another file with this same
stub-in-Scripts/real-in-zzMods pattern, add it to that list too.

**Recovery outcome (2026-07-14, three rounds, final round used opencode's DB):**

Round 1: extracted Read/Write tool-result content for `ItemSystem.lua` out of
Claude Code's own `~/.claude/projects/.../*.jsonl` session transcripts (search
for a large string containing `"MMMerge Curated Item System"` +
`"function IsCuratedItem"`; cross-checking two independent extraction paths —
e.g. `.toolUseResult.file.content` vs. the line-numbered transcript display
text with numbers stripped — matching byte-for-byte was strong evidence the
capture wasn't truncated). This got the game booting again but the recovered
version was missing `ItemSystemInternal.GetCuratedEntry`/`MAX_ITEM_STATS`
(manually patched in, see git-less history in this file's own comments).

Round 2 (**the actually-useful lesson**): this project is edited by multiple
AI tools between sessions (Claude Code AND opencode/DeepSeek — see the
user-memory note on that), and **each tool keeps its own separate local
session history in its own storage.** The most complete version of this file
was written in an **opencode** session, so it was never going to be in
Claude's transcripts no matter how thoroughly searched. opencode's session
history lives in `~/.local/share/opencode/opencode.db` (SQLite; tables
`session`, `message`, `part` — `part.data` is JSON, walk it for large strings
containing your target file's distinctive markers, same technique as the
jsonl search). **A `write`-tool call's captured content is complete and
unpaginated; a `read`-tool call's captured content may be silently truncated**
(this project's opencode config caps tool output at 50KB — a truncated read
result literally ends mid-file with a `"(Output capped at 50 KB...)"` marker;
watch for that marker and prefer `write`/`edit` tool-call captures over `read`
captures when both exist, they're the actual authoritative source of what got
written to disk). The recovered version confirmed `MAX_ITEM_STATS` was
correctly tooltip-display-only (never used inside `SumCuratedBonuses`) —
Round 1's manual reconstruction of that had been correct by inference.

**Still NOT recoverable (searched both Claude and opencode storage):** an
even later version (visible only via its distinct `"Ready. N entries (lookup
X, migrated Y, restored Z, cleared W)"` log line in a rotated `MMMergeLog.2.txt`)
had explicit orphaned-tag migration logic on top of everything Round 2
recovered. Never found in either tool's history — possibly written and lost
entirely (edited, then the edit itself was later lost some other way), or
captured in a storage location neither search covered. **Symptom if this
matters again:** old items with `item.Charges > 0` set by that lost version's
id scheme have no matching `CuratedItems[id]` entry, so `GetCuratedEntry`
self-heals them (clears the tag, reverting the item to plain) instead of
leaking the raw id as a bogus "Charges: N" line — implemented directly in
`GetCuratedEntry` in the current file (re-added after each of the two
replacement rounds; if this file is ever replaced wholesale again, re-check
this self-heal is still present). New items generated going forward tag and
register correctly in the same function, so this is a one-time/save-carryover
cosmetic issue, not an ongoing bug.

## Class-Mastery Suffix Filter (ItemSystem, 2026-07-14)

`RandomPartyMember(requiredSkill)` now accepts optional `requiredSkill`. When
set, only party members whose class has `Game.Classes.Skills[class][skill] >= 3`
(Master+) are eligible. Prevents inappropriate suffix lines (e.g. `MonkLine`)
from rolling on items the class can't use at Master+ (e.g. Chain Mail on Monks).

`GetItemRequiredSkill(item)` returns the skill ID for weapons, body armor, and
shields by checking `t.EquipStat` against `EQUIP_SKILL_SLOTS`:
```lua
local EQUIP_SKILL_SLOTS = {
    [0] = true, [1] = true, [2] = true,       -- Weapon(1H), Weapon2H, Missile
    [3] = true,                                 -- Armor
    [4] = true,                                 -- Shield
    [22] = true, [23] = true, [24] = true,     -- Sword, Dagger, Axe (extended)
    [25] = true, [26] = true, [27] = true,     -- Spear, Bow, Mace (extended)
    [28] = true, [29] = true,                   -- Club, Staff (extended)
    [30] = true, [31] = true, [32] = true,      -- Leather, Chain, Plate (extended)
    [33] = true,                                 -- Shield_ (extended)
}
```
Items with other EquipStat values (rings, amulets, helms, belts, etc.) return
nil — no filter, any class rolls as before.

Both functions exposed via `ItemSystemInternal`. `zzRepairItems.lua` uses them
instead of its own stale copy of `RandomPartyMember`.

**Tested working:** Monk "Initiate" no longer appears on Chain Mail. Spear
items roll only from classes with Master+ Spear. Accessories unaffected.

## Toggle Convention
Every feature uses `Game.FeatureEnabled` with a default of `true`:
```lua
Game.FeatureEnabled = (Game.FeatureEnabled == nil) and true or Game.FeatureEnabled
```
Register in `MenuExtraSettings.lua` (Combat & Items page or appropriate page).
Patch file at `Scripts/General/Patched/MenuExtraSettings.lua`.

## Skill Slot Reuse
Repurpose existing Misc skill slots to avoid save corruption:
| Skill              | Slot   | Status                        |
|--------------------|--------|-------------------------------|
| Cleave             | 36     | Replaces Stealing             |
| Guardian           | 24     | Replaces Identify Item        |
| Mana Shield        | 34     | Replaces Identify Monster     |
| Retaliation        | 38     | Replaces Learning             |
| Repair Item        | 26     | Freed (always-on, baked in)   |
| Disarm Traps       | 31     | Freed (merged into Perception)|

Mastery auto-promotes: 1→Normal, 4→Expert, 7→Master, 10→GM.
Cap via `Game.Classes.Skills[classId][mirrorSkill]` (e.g. Armsmaster for Cleave).

## Coding Conventions
- `local` aliases for frequently used globals (`u2`, `bit`, `random`)
- `GlobalTxt` `\f` color injection preferred over `mem.hook` (zero crash risk)
- Condition clearing: `Party[i].Conditions[const.Condition.X] = 0`
- Event systems safe when direct memory writes are risky
- `table.find(t, v)` is available (defined in `RSFunctions.lua`)
- `SplitSkill(val)` / `JoinSkill(level, mastery)` for skill encode/decode
- `pcall` guards on Party iteration during loading (`GameInitialized2`)

## Key Events
| Event               | Hook Point                         | t fields                          |
|---------------------|------------------------------------|-----------------------------------|
| SpellTargetType     | Target selection phase             | Spell, CasterSlot, Flags          |
| PlayerSpellProc     | Right before spell effect          | Spell, Caster, Flags              |
| PlayerCastSpell     | Before spell processing (cancellable)| SpellId, Player, Handled         |
| L2InterfaceUpd      | Every interface frame              | (none)                            |
| ItemGenerated       | When an item is created            | Item                              |
| CalcStatBonusByItems| Stat calculation (per stat)        | Player, PlayerIndex, Stat, Result |
| GetSkill            | Skill value read (per skill)       | Player, PlayerIndex, Skill, Result|

## Deployment
After editing any file under `Scripts/` (or `Data/`), copy it to the matching
`zzMods/` path. README.md, CHANGELOG.md, INSTALL.md live at `zzMods/` root.
The two trees are NOT auto-synced and `zzMods/` is what ships.

**Before packaging/shipping, run `bash check-sync.sh` (repo root) — it must exit 0.**
It compares every shipped file under `zzMods/{Scripts,Data}` to its working-tree
source and FAILS on any stale copy (a fix applied to `Scripts/` but not deployed).
Run the full check after every fix — fixes routinely touch more files than you
expect, and that's exactly how the last deployment gap shipped (a regen fix
edited `MiscTweaks.lua` but only the obvious `Regeneration.lua` got synced).
Orphan warnings (e.g. `Core/Patched/timers.lua`, which is deploy-only and has no
working-tree twin) are informational, not failures.

## Test Environment
Path: `E:\Games\GOG Galaxy\Games\Might and Magic 8 - MMMerge TEST\`

---

# MMExtension Modding Techniques Reference

> **Ground rules — read before touching native code:**
> - **Every hex address in this reference is build-specific.** They are for the
>   `MM8.exe` / `MM8patch.dll` shipped with cthscr's Merge Revamp (MMMerge
>   2023-11-05). If the base mod or exe is ever updated, assume ALL of them can
>   shift — re-derive by disassembly (§3.0) instead of trusting the numbers here.
> - **The authoritative API reference is in the repo root:** `MMExtension.htm`
>   (English) and `MMExtensionRu.htm` (Russian) — GrayFace's own docs for
>   `events.*`, `mem.*`, `structs.*`, `Game.*`. When an event field name or a
>   `mem.*` signature is uncertain, check there before guessing.
> - **Prefer the least-powerful technique that works** (Risk Scale below):
>   events > data-table edits > memory writes > hooks > asm patches.

## Risk Scale
- **SAFE** — Pure Lua, version-independent, no side effects
- **MODERATE** — Address-dependent but isolated
- **FRAGILE** — Version-specific addresses, complex register state

---

## 0. DEBUGGING & FINDING ADDRESSES

### 0.1 ErrorLog.txt — read it FIRST on any crash
The game writes every unhandled crash to `ErrorLog.txt` at the game root, with
a full call stack (module + offset per frame), a register dump, and the raw
stack. It is the primary crash-diagnosis tool — the entire Town Portal saga was
solved from it plus disassembly.
- **"Access violation ... Read of address 0000000X"** (a low address) = a
  null-pointer dereference: the faulting instruction did something like
  `mov eax,[reg+X]` with `reg == 0`. Disassemble the crash address (§3.0), see
  which register/global feeds that pointer, then trace why it is null.
- Frames read as `MM8.exe + NNNNN` (an RVA) — add `0x400000` for the VA to
  disassemble (e.g. `MM8.exe + 49C3B` → `0x449C3B`).
- Entries are timestamped; the **newest crash is at the BOTTOM** of the file.
- A pure-Lua error (not a native crash) shows an MMExtension error box in-game
  and usually does NOT reach ErrorLog.txt — those are your own script bugs and
  are far easier to fix.

### 0.2 Finding the address for a NEW feature (proactive)
When you need to intercept something that has no event:
- Search the exe for a **string** the feature uses (a UI label, a filename like
  `book2.fnt`), then find code referencing that string's address (as a 4-byte
  little-endian constant) — the code you want is usually right there.
- Find a **function's callers**: scan `.text` for `E8 rel32` where
  `addr + 5 + rel32 == functionVA`.
- Find who **reads/writes a global**: search `.text` for the global's 4-byte LE
  address.
- Confirm **calling convention** before hooking or emulating a return: bare
  `ret` = cdecl/no-args; `ret N` = stdcall (callee pops N arg bytes); `ecx` used
  as `this` = thiscall.
- The capstone recipe + a VA↔file-offset mapper live in §3.0. Always prefer
  hooking a **feature-specific** function over a shared one (see §3.0).

---

## 1. SAFE TECHNIQUES

### 1.1 Event Subscriptions
Most reliable way to hook into game behavior. No addresses, no assembly.
```lua
function events.SpellTargetType(t) end   -- t.Spell, t.CasterSlot, t.Flags
function events.PlayerSpellProc(t) end   -- t.Spell, t.Caster, Flags
function events.PlayerCastSpell(t) end   -- t.SpellId, t.Player, t.Handled
function events.L2InterfaceUpd() end     -- every interface frame
function events.ItemGenerated(t) end     -- t.Item
function events.GetSkill(t) end          -- t.Player, t.Skill, t.Result
function events.CalcDamageToMonster(t) end
function events.CalcDamageToPlayer(t) end
function events.KeyDown(t) end           -- t.Key, t.Handled
function events.GameInitialized2() end   -- after structs loaded
function events.AfterLoadMap(WasInGame) end
function events.PopulateLearnSkillsDialog(t) end  -- t.PicType, t.Result
```
**When to use:** Always prefer events over hooks. Safe, version-independent.

### 1.2 GlobalTxt `\f` Color Injection
Color stat labels, UI text with zero crash risk.
```lua
-- \fNNNNN where NNNNN = 5-digit decimal 16-bit RGB565 color
-- 0xF800=Red, 0xFD20=Orange, 0x001F=Blue, 0x07E0=Green, 0xFFE0=Yellow
Game.GlobalTxt[index] = string.format("\f%.5d%s", color16bit, text)
-- Save/restore pattern in L2InterfaceUpd:
local orig = Game.GlobalTxt[idx]
-- ... modify ...
Game.GlobalTxt[idx] = orig  -- restore when leaving screen
```

### 1.3 Skill Slot Repurpose
Reuse existing Misc skill slots to add new skills safely.
```lua
Game.SkillNames[SLOT_ID] = "New Name"
Game.SkillDescriptions[SLOT_ID] = "Description"
-- Mirror another skill's per-class caps:
for classId = 0, Game.Classes.Skills.count - 1 do
    local skills = Game.Classes.Skills[classId]
    if skills then skills[SLOT_ID] = math.max(skills[REF_SKILL], 1) end
end
-- Add to training halls:
function events.PopulateLearnSkillsDialog(t)
    if t.PicType == const.HouseType.Training then
        t.Result[#t.Result + 1] = SLOT_ID
    end
end
-- Auto-mastery via events.GetSkill
```

### 1.4 Party Condition Manipulation
```lua
Party[i].Conditions[const.Condition.Cursed] = 0  -- clear
Party[i].Conditions[const.Condition.Weak] = Game.Time  -- set (inflict now)
-- Condition IDs: Cursed=0, Weak=1, Insane=5, Poison1=6, Disease1=7,
--   Poison2=8, Disease2=9, Poison3=10, Disease3=11, Paralyzed=12,
--   Dead=14, Stoned=15, Eradicated=16
```

### 1.5 Safe Party Iteration
```lua
-- Pattern 1: Party.Players (pairs):
for _, pl in Party.Players do ... end

-- Pattern 2: Slot-based with nil guard (safe during world load):
if not Party or not Party.count or Party.count < 1 then return end
for i = 0, Party.count - 1 do
    local ok, p = pcall(function() return Party[i] end)
    if ok and p and p.Class and p.Class >= 0 then ... end
end

-- Pattern 3: Party.High (highest valid index):
for i = 0, Party.High do ... end
```

### 1.6 Skill Encode/Decode
```lua
local level, mastery = SplitSkill(player.Skills[skillId])  -- unpack
-- level = bits 0-5, mastery = bits 6-7 (1=Normal, 2=Expert, 3=Master, 4=GM)
player.Skills[skillId] = JoinSkill(level, mastery)  -- re-pack
-- Auto-mastery thresholds: 1→Normal, 4→Expert, 7→Master, 10→GM
```

### 1.7 Toggle Convention
```lua
Game.FeatureEnabled = (Game.FeatureEnabled == nil) and true or Game.FeatureEnabled
-- Register in MenuExtraSettings.lua (Patched version in General/Patched/)
-- Saved via vars.ExtraSettings in BeforeSaveGame / LoadMapScripts
```

### 1.8 Save-Scoped State
```lua
-- vars.* - persists across saves/maps (automatic serialization):
vars.myData = vars.myData or {}
vars.myData.value = 42

-- internal.SaveGameData.* - for complex tables (manual init):
local sgd = internal and internal.SaveGameData
if sgd then sgd.MyTable = sgd.MyTable or {} end

-- mapvars.* - per-map, resets on map change:
mapvars.tempFlag = true
```

### 1.9 UI Customization (CustomUI)
```lua
local CustomUI = require("CustomUI")  -- or global if MMExtension provides it
-- Tumbler toggle:
OnOffTumbler(ScreenId, X, Y, "Game.VarName")
-- Number regulator:
NumberRegulator(ScreenId, X, Y, "Game.VarName", callback, reprFunc, init, min, max, step)
-- Settings page:
CustomUI.NewSettingsPage("Name", "Header", "Icon")
```
**Text positioning next to toggles:** TmblrOn/TmblrOff icons are ~120px wide. Place
toggle at X=95, label text at X=215 (120px gap) with Width=385 to clear the right
nav arrow (X=554). Verify positions with in-game screenshots — icon sizes differ
from the small arrow icons used by NumberRegulator (ar_lt_up/ar_rt_up are ~20px).
Reference: `MenuExtraSettings.lua` for the working layout pattern.

### 1.10 Face Animation Feedback
```lua
Party[slot]:ShowFaceAnimation(const.FaceAnimation.TempleHeal)   -- 82 = heal
Party[slot]:ShowFaceAnimation(const.FaceAnimation.CastSpell)     -- 49
Party[slot]:ShowFaceAnimation(const.FaceAnimation.SkillIncreased)-- 14
Party[slot]:ShowFaceAnimation(const.FaceAnimation.Damaged)       -- 24
```

---

## 2. MODERATE-RISK TECHNIQUES

### 2.1 CastSpellDirect — Queue Spell Via Slot Write
```lua
CastSpellDirect(SpellId, Skill, Mastery, Caster, Target, Flags, TargetKind)
-- Writes to 0x51D820/0x51D822/0x51D828/0x51D82A. Game processes asynchronously.
-- JoinSkill(Skill, Mastery): mastery 4=0x100, 3=0x80, 2=0x40, 1=0x0
-- AutoCasting flag + CanCastTownPortal: set flag before write, clear on first
--   SpellFailCheck call. Return to 3D (Screen = 0), game handles the rest.
-- Console debug: Game.UnlockTPSlots() — sets all 6 TP slot QBits + data
--   across all 3 continents for testing all destinations.
```
**Pattern:** Set a flag → `CastSpellDirect(spell, skill, mastery)` → `Game.CurrentScreen = 0` → let game process async → event handler consumes flag to allow pass-through. Used for Town Portal auto-recast after continent selection.

**⚠️ Call from a clean frame boundary — never synchronously from inside a UI click handler.** Calling `CastSpellDirect` directly inside a `CustomUI` button `Action` (a nested, mid-frame callback) skips native cast setup and crashes (it manifested as the null-spellbook-font Town Portal crash). Defer it: set a flag in the click handler, then run the actual `CastSpellDirect` on the next `L2InterfaceUpd` tick. See `processPendingRecast` in `TownPortalSwitches.lua` and the Town Portal deep-dive below.

### 2.2 Direct Memory Read/Write
```lua
local u2, u4 = mem.u2, mem.u4
u2[0x51d824] = slot      -- Spell target slot override
u2[0x51d82c] = bit.lshift(slot, 3) + 4  -- Target reference
u4[0x4fdfa4 + i*4] = v   -- Condition priority order
```
**Key addresses:**
| Address | Width | Purpose |
|---------|-------|---------|
| 0x51d820 | u2 | Current spell ID being cast |
| 0x51d822 | u2 | Caster slot index |
| 0x51d824 | u2 | Spell target slot |
| 0x51d82c | u2 | Target reference encode |
| 0xB20E90 | u4 | Party struct base pointer |
| 0x4fdfa4 | u4[17] | Condition priority table |

### 2.3 mem.call — Call Native Functions
```lua
mem.call(0x42D776)                     -- cdecl (convention 0 or omitted)
mem.call(0x455D97, 1, ecx, arg1, arg2)-- stdcall (1)
mem.call(0x4026F4, 2, ecx, arg)       -- thiscall (2), ecx = this
mem.call(0x46306B, 2, 0x5E1020, val)  -- thiscall: registry write (HKCU)
mem.call(0x462D28, 2, 0x5E1020, default) -- thiscall: registry read
```
**Conventions:** 0=cdecl, 1=stdcall, 2=thiscall, 3=fastcall (ecx, edx)

### 2.4 mem.StaticAlloc — Persistent Buffer
```lua
local buf = mem.StaticAlloc(size_bytes)  -- survives map loads
mem.u4[buf] = value  -- read/write
```

### 2.5 mem.hook — Callback at Native Address
```lua
mem.hook(address, function(d)
    -- d.eax/d.ecx/d.edx/d.ebx/d.esi/d.edi/d.ebp/d.esp — registers
    -- d:push(newAddr) + return true — redirect execution
    -- Modify registers by assigning to d.eax etc.
end)
```
**Use when:** An event doesn't exist and you need to intercept a specific code point.

### 2.6 mem.autohook / mem.autohook2 — Lighter Hooks
```lua
mem.autohook2(address, function(d)
    d.eax = newValue  -- just modifies register
end)
-- autohook: can return true + d:push() to redirect
```

### 2.7 mem.IgnoreProtection — Write to Code Memory
```lua
mem.IgnoreProtection(true)
u4[0x404D5F] = newCodeAddr
mem.IgnoreProtection(false)
```
**Risk:** Crash while protection is disabled may corrupt memory.

### 2.8 mem.string / mem.copy / mem.topointer
```lua
local s = mem.string(ptr)  -- read null-terminated string from memory
mem.copy(destAddr, str .. string.char(0))  -- write string to memory
local p = mem.topointer(str)  -- get managed pointer to Lua string
```

---

## 3. FRAGILE TECHNIQUES (Use as Last Resort)

### 3.0 DISASSEMBLE THE BINARY FIRST — do not guess at native addresses

Before writing ANY `mem.asmpatch` / `mem.hook` / `mem.hookfunction` against a
raw address — and *immediately* after the first one that misbehaves — get
ground truth from the actual bytes. Guessing from crash logs, x32dbg
screenshots, or "the last patch was almost right" is how this project shipped
three game-corrupting patches in one session (see root `AGENTS.md`, the Town
Portal saga). The whole thing was solved in one pass the moment someone
actually disassembled `MM8.exe` instead of iterating on guesses.

**When to reach for it:**
- Any crash whose stack bottoms out in `MM8.exe`/`MM8patch.dll` at a bare
  address (an access violation reading a low address like `0x0`/`0x5` is a
  null-pointer deref — trace what register/global feeds that pointer).
- Before patching a shared function: confirm it's actually the culprit and
  isn't reached by unrelated callers (patching shared text code broke ALL
  text here). Prefer patching a *feature-specific* function instead.
- After ANY native patch that doesn't behave exactly as predicted — stop
  tweaking, disassemble, and verify the assembled bytes and the surrounding
  control flow before trying again. Two failures = wrong model, not wrong
  patch.

**The recipe (capstone is available in this environment's Python):**
```python
import struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
data = open(r"...\MM8.exe","rb").read()
# PE: ImageBase 0x400000; .text VA 0x401000, raw 0x1000 (parse the section
# table to map VA->file offset; do not assume VA-0x400000). See the scripts
# written during the Town Portal fix for a full VA->offset mapper + xref/
# caller finder (they were in the session scratchpad; re-create as needed).
md = Cs(CS_ARCH_X86, CS_MODE_32)
```
Use it to: disassemble the crash site and its caller chain; find who
writes/reads a global (search for the 4-byte LE address in `.text`); find a
function's callers (scan for `E8 rel32` targeting it); confirm calling
convention (bare `ret` = cdecl/no-args; `ret N` = stdcall) before emulating a
return from a hook. `mem.asmpatch` size MUST cover whole instructions and be
≥ the assembled length, or it silently overflows into the next function.

### 3.1 mem.asmpatch — Assembly Replacement
```lua
mem.asmpatch(address, [[
    mov eax, dword ptr [ebp-0xC]
    cmp eax, 1
    jg @party
    @party:
    call absolute 0x42D776
]], optional_explicit_size)
```
**Risks:** Addresses change per game version; wrong instruction boundaries crash; no thread safety.

### 3.2 mem.hookfunction — Replace Native Function
```lua
mem.hookfunction(address, callingConvention, stackPop, function(d, def, arg1, arg2)
    local result = def(arg1, arg2) -- call original
    return result
end)
```
**Risks:** Wrong convention corrupts stack; requires matching `def` signature exactly.

### 3.3 mem.asmproc — Standalone Assembly Block
```lua
local code = mem.asmproc([[ retn ]])  -- compile + allocate, don't patch
-- Then patch to jump to it: mem.asmpatch(addr, "jmp absolute " .. code)
```

---

## 4. SPELL TARGETING FLAGS
```lua
bit.band(t.Flags, 0xE021)  -- mask for special sources:
-- 0x01 = scroll cast, 0x20 = event cast, 0xE000 = special/signature
t.Flags = 0x1000  -- bypass target dialog (Ctrl-click)
```

## 5. ITEM STRUCTURE
```lua
item.Number         -- base item ID
item.Bonus          -- STDITEMS enchantment index
item.BonusStrength  -- enchantment quality
item.Bonus2         -- SPCITEMS enchantment (independent!)
item.Charges        -- can be repurposed if MaxCharges == 0
item:Identified     -- boolean
item:T()            -- returns item type definition
```

## 6. GAME VERSION CHECK
```lua
-- mmver global: 6=MM6, 7=MM7, 8=MM8
-- Conditional struct offsets:
mmv(mm6_val, mm7_val, mm8_val)  -- picks value by version
```

## 7. KEY MODULE REFERENCES
| File | Techniques Used |
|------|----------------|
| SpellsExtra.lua | Extensive asmpatch, mastery tables, party-wide buff loops (~4800 lines) |
| ExtraEvents.lua | autohook/autohook2/asmhook/hookfunction for 30+ events |
| zzStatColors.lua | GlobalTxt \f injection (SAFE, zero hooks) |
| zzHealTarget.lua | SpellTargetType + PlayerSpellProc, memory writes |
| Summoner.lua | Spell events + StaticAlloc + flag manipulation |
| Guardian.lua | Skill slot reuse, MonsterChooseTargetPlayer, PlayerAttacked |
| zzLootAll.lua | KeyDown/KeyUp events, mem.call (PickCorpse), swap-with-last array removal, SpritesToDraw buffer cleanup (u4/u2/i4 at 0x43CBF1/0x529F40), view-cone + PathfinderDll.TraceLine filtering |
| TownPortalSwitches.lua + 1_TownPortalSwitch.lua + MenuChooseContinent.lua | Continent selector (Screen 97) + deferred TP recast + null-font crash fix. `TownPortalSwitches.lua` lives in `Scripts/Global/` and MUST ship in `zzMods/Scripts/Global/`. Full detail in the Town Portal deep-dive below. |
| NPCFollowers.lua | asmpatch + asmproc + hook + vars persistence |
| MenuExtraSettings.lua | CustomUI settings pages, toggle save/load |
| AutoMage.lua | CanCastSpell + CanLearnSpell events, spell learning restrictions |
| SkillHarmony.lua | GetPlayerSkillMastery + GetSkill + L2InterfaceUpd events |
| CombatLog.lua | Tick key polling (L/Esc), Keys.IsPressed, ShowStatusText, CalcDamageToMonster/Player, MonsterKilled, MonsterKillExp |
| zzStatusBar.lua | L2InterfaceUpd, ShowStatusText, Game.CombatLog.entries sharing |

---

# Part 3: Per-Feature Deep Dives

Non-obvious internals and abandoned approaches for specific features, recorded
so they aren't re-investigated from scratch.

## SkillHarmony — Auto-Mastery Upgrade

File: `Scripts/General/SkillHarmony.lua`
Toggle: `Game.SkillHarmonyEnabled`
Thresholds: Lvl 4→Expert, 7→Master, 10→GM
Class cap: Respects per-class max via `Game.Classes.Skills[class][skill]`

**How it works:**
- `events.GetPlayerSkillMastery` — fires when game reads raw skill mastery (for (+1) indicator). Harmony upgrades the skill by writing to both `pl.Skills[]` (Lua API) and raw Party memory (`mem.u2[0xB2187C + ...]`).
- `events.GetSkill` — fires when game reads a skill value. Also upgrades.
- `events.L2InterfaceUpd` — periodic scan every 10 interface frames as safety net.

**Known limitation:** The Skills tab caches formatted text during tab Init and does not re-read during Draw. Mastery text only updates when the tab is closed and reopened (switch to another tab and back, or close/reopen character screen).

**Diagnostic tools** (in `zzSkillDump.lua`):
- `Game.Fz(charIdx, skillIdx)` — strips a high-level skill to Normal, lets Harmony repair it. Verify with `Game.SnapSkills()` then `Game.CheckSkills()` after a few seconds.
- `Game.HarmonyTest(charIdx, skillIdx)` — sets skill to Lvl4 Normal (triggers Expert upgrade). Watch Skills tab after tab close/reopen.
- `Game.Cmp(charIdx, skillIdx)` — compares raw vs Lua value, shows "OK" or "MISMATCH"

**Display refresh approaches (all abandoned):**

| Approach | Result |
|----------|--------|
| Draw hook + cache clear | Mastery text is never re-read during Draw — the formatted text is baked at Init |
| `mem.autohook(0x455B09)` (GetSkillMastery) | Function IS called, but only during tab Init, not during Draw |
| `Game.CurrentCharScreen` toggle (Stats→Skills) | Tab flash visible but doesn't reliably trigger re-Init; inconsistent |
| `Game.NeedRedraw` | Only affects minimap, not text strings |
| `font:Draw(nil, nil, ...)` in PostRender/AfterDrawDialogs | Text is completely invisible — D3D rendering context is not active in these hooks |
| `Game.ShowStatusText` for mastery update | Works technically, but status bar is ephemeral — not a permanent skill-text replacement |
| `CustomDialog{}` wrapping `Game.Dialogs[0]` | Items ARE drawn but only in the border areas (~60px edges); the 3D viewport clips center items. No reliable way to overlay text over the skill list |
| `Game.NewDialog` from event handler | Native function conflicts mid-cycle — freezes the game |

The only reliable refresh is tab close/reopen (toggle to Stats and back, or Esc then 'C').

---

## CombatLog — Combat Event Log

File: `Scripts/General/CombatLog.lua`
Toggle: `Game.CombatLogEnabled`
Toggle key: `L` (in-game only)

**Captures events:**
- `CalcDamageToMonster` — damage dealt to monsters
- `CalcDamageToPlayer` — damage taken from monsters
- `MonsterKilled` — monster death events
- `MonsterKillExp` — experience awarded

**Status bar display:**
- L enters "log mode", shows latest event in the native status bar
- L again cycles through older events
- Esc exits log mode
- New combat events while in log mode auto-update the display
- 500-entry ring buffer in `Game.CombatLog.entries`

**Shared data:** `Game.CombatLog.entries` accessible by `zzStatusBar.lua`.

**Dialog/overlay approaches tried and abandoned:**
- `CustomDialog{}` — freezes game when called mid-game (native dialog creation conflicts)
- `Game.NewDialog` — same freeze issue
- `Game.Dialogs[0]` wrapping — items render behind 3D view or clipped by viewport frame
- `AfterDrawDialogs` / `PostRender` `font:Draw` — text is invisible (rendering context not active)

---

## zzStatusBar — Status Bar Combat Feed

File: `Scripts/General/zzStatusBar.lua`
Toggle: `Game.StatusBarEnabled`

**Shows during gameplay** (every ~30 L2InterfaceUpd frames):
- Latest combat event via `Game.ShowStatusText` in the native status bar
- Reads from `Game.CombatLog.entries`
- Updates only when the latest entry changes (no spam)

---

## Town Portal Continent Selector — architecture & the null-font crash

Files: `Scripts/General/1_TownPortalSwitch.lua` (native hooks + per-continent
destination data), `Scripts/Global/TownPortalSwitches.lua` (event glue +
deferred recast), `Scripts/General/MenuChooseContinent.lua` (Screen 97 picker).

**Flow:** Cast TP → `CanCastTownPortal` sets `SelectingContinent`; redirect to
Screen 97 (CustomUI globe picker) on the next `L2InterfaceUpd` → pick a
continent → `SlChosen` sets `PendingRecast` → `processPendingRecast` (next
`L2InterfaceUpd`) runs `SwitchTo(continent)` + a deferred
`CastSpellDirect(31,10,4)` → the native TP destination screen shows that
continent's 6 slots.

**Why the recast is deferred, not inline:** calling `CastSpellDirect`
synchronously from the CustomUI click handler skipped native cast setup and
crashed after 1-2 teleports. Deferring it to a clean frame fixed it (see §2.1).

**The null-font crash (Escape / intermittent) and its fix:** The TP destination
screen is drawn like a spellbook and renders its labels with `book2.fnt`, held
in global `0x5DB920` (loaded/freed as a group with `book.fnt` at `0x5DB924` and
`autonote.fnt` at `0x5DB910` by the spellbook UI). Pressing Escape frees those
fonts, but the TP draw runs one more frame with `book2.fnt` NULL → the native
text routine dereferences the null font → access violation. **Fix:**
`mem.autohook(0x4D1227)` (the TP-specific draw function — it reads the TP slot
global `0x1006130`) skips the whole draw when `mem.u4[0x5DB920] == 0`, emulating
the function's clean cdecl return.

**Do NOT patch the shared char-classifier at `0x449C3B`.** Three attempts all
corrupted text game-wide — it was never the bug (it merely dereferenced the
null font; the deref just happened to surface there). Full blow-by-blow in the
root `AGENTS.md`.
