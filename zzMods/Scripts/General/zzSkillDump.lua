print("zzSkillDump: Party tracker + raw/Lua compare + Harmony test")

local PARTY_BASE  = 0x00B2187C
local PLAYER_SIZE = 0x1D28
local SKILL_OFF   = 0x378
local NUM_CHARS   = 5
local NUM_SKILLS  = 39

local MASTERY_NAMES = {[0]="None","Normal","Expert","Master","GM"}

local function DecodeMM8(val)
    if val == 0 then return 0, 0 end
    local level = val % 0x400
    if val >= 0x1000 then return level, 4 end
    if val >= 0x800 then return level, 3 end
    if val >= 0x400 then return level, 2 end
    return level, 1
end

local oldSnap = {}
local snapReady = false

function Game.SnapSkills()
    oldSnap = {}
    for charIdx = 0, NUM_CHARS - 1 do
        oldSnap[charIdx] = {}
        local sb = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF
        for s = 0, NUM_SKILLS - 1 do
            oldSnap[charIdx][s] = mem.u2[sb + s * 2]
        end
    end
    snapReady = true
    print("SNAP done")
end

function Game.ShowSkills(charIdx)
    charIdx = charIdx or 0
    local sb = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF
    print(string.format("Char%d raw 0x%X:", charIdx, sb))
    for s = 0, NUM_SKILLS - 1 do
        local v = mem.u2[sb + s * 2]
        if v ~= 0 then
            local l, m = DecodeMM8(v)
            print(string.format("  S%02d 0x%04X Lvl%2d %s", s, v, l, MASTERY_NAMES[m] or "?"))
        end
    end
end

function Game.CheckSkills()
    if not snapReady then print("Snap first"); return end
    local changed = {}
    for c = 0, NUM_CHARS - 1 do
        local sb = PARTY_BASE + c * PLAYER_SIZE + SKILL_OFF
        for s = 0, NUM_SKILLS - 1 do
            local nv = mem.u2[sb + s * 2]
            local ov = oldSnap[c][s]
            if nv ~= ov then
                local ol, om = DecodeMM8(ov); local nl, nm = DecodeMM8(nv)
                changed[#changed+1] = string.format("C%d S%02d: 0x%04X->0x%04X %s/%d->%s/%d",
                    c, s, ov, nv, MASTERY_NAMES[om] or "?", ol, MASTERY_NAMES[nm] or "?", nl)
                oldSnap[c][s] = nv
            end
        end
    end
    if #changed > 0 then
        print("[CHANGE] " .. table.concat(changed, " | "))
    else
        print("[NO CHANGE]")
    end
end

-- Strip mastery flag to test Harmony repair
function Game.StripMastery(charIdx, skillIdx)
    charIdx = charIdx or 0; skillIdx = skillIdx or 8
    local addr = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF + skillIdx * 2
    local oldVal = mem.u2[addr]
    local stripped = oldVal % 0x400  -- remove mastery flags
    if stripped ~= oldVal then
        mem.u2[addr] = stripped
        local l, m = DecodeMM8(oldVal); local sl, sm = DecodeMM8(stripped)
        print(string.format("S%02d: 0x%04X(%s Lvl%d) -> 0x%04X(%s Lvl%d). Wait for Harmony...",
            skillIdx, oldVal, MASTERY_NAMES[m] or "?", l,
            stripped, MASTERY_NAMES[sm] or "?", sl))
    else
        local l, m = DecodeMM8(oldVal)
        print(string.format("S%02d: 0x%04X already has no mastery flag (%s Lvl%d)", skillIdx, oldVal, MASTERY_NAMES[m] or "?", l))
    end
end

function Game.Cmp(charIdx, skillIdx)
    charIdx = charIdx or 0; skillIdx = skillIdx or 1
    local addr = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF + skillIdx * 2
    local raw = mem.u2[addr]
    local lua = 0
    if Party and Party.Players and Party.Players[charIdx+1] then
        lua = Party.Players[charIdx+1].Skills[skillIdx] or 0
    end
    local rl, rm = DecodeMM8(raw); local ll, lm = DecodeMM8(lua)
    print(string.format("C%d S%02d  raw=0x%04X Lvl%d %s | Lua=0x%04X Lvl%d %s  %s",
        charIdx, skillIdx, raw, rl, MASTERY_NAMES[rm] or "?",
        lua, ll, MASTERY_NAMES[lm] or "?", raw == lua and "OK" or "MISMATCH"))
end

function Game.SplitVal(sv)
    if not sv or sv == 0 then return 0, 0 end
    local level = sv % 0x400
    if sv >= 0x1000 then return level, 4 end
    if sv >= 0x800 then return level, 3 end
    if sv >= 0x400 then return level, 2 end
    return level, 1
end

function Game.JoinVal(level, mastery)
    if mastery == 4 then return level + 0x1000
    elseif mastery == 3 then return level + 0x800
    elseif mastery == 2 then return level + 0x400
    else return level
    end
end

function Game.MasteryFromLvl(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

-- Force a mastery mismatch, then verify Harmony repairs raw memory.
-- Usage: Game.SnapSkills(); Game.Fz(0, 1); wait 10s+; Game.CheckSkills()
function Game.Fz(charIdx, skillIdx)
    charIdx = charIdx or 0; skillIdx = skillIdx or 1
    local addr = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF + skillIdx * 2
    local pl = Party.Players[charIdx + 1]
    local raw = mem.u2[addr]
    local lua = pl.Skills[skillIdx] or 0
    local rl, rm = Game.SplitVal(raw)
    local ll, lm = Game.SplitVal(lua)
    print(string.format("C%d S%02d  BEFORE: raw=0x%04X Lvl%d %s | Lua=0x%04X Lvl%d %s",
        charIdx, skillIdx, raw, rl, MASTERY_NAMES[rm] or "?",
        lua, ll, MASTERY_NAMES[lm] or "?"))
    local level = (rl ~= 0 and rl) or ll
    if level < 4 then
        print("Level " .. level .. " < 4, nothing to demote.")
        return
    end
    local expected = Game.MasteryFromLvl(level)
    if rm >= expected then
        local stripped = (rl ~= 0 and rl) or ll
        local newRaw = Game.JoinVal(stripped, 1)
        mem.u2[addr] = newRaw
        pl.Skills[skillIdx] = newRaw
        print(string.format("  STRIPPED to 0x%04X (Lvl%d Normal). Harmony should upgrade to mastery %d.",
            newRaw, stripped, expected))
        print("  Wait for L2InterfaceUpd, then Game.CheckSkills()")
    else
        print("  Mastery already below expected, nothing to strip.")
    end
end

-- Force a skill to Normal/Level 4 to trigger Harmony upgrade to Expert.
-- Use ANY skill (regardless of level). The display should flash and update.
function Game.HarmonyTest(charIdx, skillIdx)
    charIdx = charIdx or 0; skillIdx = skillIdx or 1
    local pl = Party.Players[charIdx + 1]
    if not pl then print("Invalid charIdx " .. tostring(charIdx)); return end
    local addr = PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF + skillIdx * 2
    mem.u2[addr] = 0x0004
    pl.Skills[skillIdx] = 0x0004
    print(string.format("C%d S%02d set to 0x0004 (Lvl4 Normal). Watch Skills tab for flash and Expert text.", charIdx, skillIdx))
end

print("Harmony raw-write test:")
print("  1. Game.SnapSkills()")
print("  2. Game.Fz(charIdx, skillIdx)    -- strip a high-level skill to Normal")
print("  3. Game.SnapSkills()             -- snap the stripped state")
print("  4. Wait 10s (for L2InterfaceUpd)")
print("  5. Game.CheckSkills()            -- should show Harmony repaired it")
print("  6. Game.Cmp(charIdx, skillIdx)   -- verify raw==Lua after repair")
print("---")
print("Display refresh test:")
print("  Game.HarmonyTest(charIdx, skillIdx)  -- sets skill to Lvl4 Normal, watch display flash")
