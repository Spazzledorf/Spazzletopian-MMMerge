-- zzHealTarget.lua
-- Auto-targets the lowest-HP party member for single-target heals.
-- Party-wide clears for condition cures (Cure Poison, etc.).
-- Plays TempleHeal face animation on all cured members.
-- Priority tree: heal if needed, otherwise attack (via Q key or fizzle).
-- Toggle: Game.AutoHealEnabled via MenuExtraSettings.

local u2 = mem.u2
local bit = bit

local HEAL_SPELLS = {68, 77}  -- Heal, PowerCure

Game.AutoHealEnabled = (Game.AutoHealEnabled == nil) and true or Game.AutoHealEnabled

local CURE_SPELLS = {
    [40] = {15},                    -- StoneToFlesh -> Stoned
    [49] = {0},                     -- RemoveCurse -> Cursed
    [57] = {3},                     -- RemoveFear -> Afraid
    [61] = {12},                    -- CureParalysis -> Paralyzed
    [64] = {5},                     -- CureInsanity -> Insane
    [67] = {1},                     -- CureWeakness -> Weak
    [72] = {6, 8, 10},             -- CurePoison -> Poison1, Poison2, Poison3
    [74] = {7, 9, 11},             -- CureDisease -> Disease1, Disease2, Disease3
}

local function needs_healing()
    local dead, eradicated = const.Condition.Dead, const.Condition.Eradicated
    for i = 0, Party.High do
        if Party[i].Conditions[dead] == 0 and Party[i].Conditions[eradicated] == 0
        and Party[i].HP < Party[i]:GetFullHP() then
            return true
        end
    end
    return false
end

-- Intercept Q key (attack spell) before the game selects the spell
function events.KeyDown(t)
    if not Game.AutoHealEnabled then return end
    if t.Key ~= const.Keys.Q or t.Handled then return end

    local CurPl = Game.CurrentPlayer
    if not CurPl or CurPl < 0 then return end
    local spellId = Party[CurPl].QuickSpell
    if spellId ~= HEAL_SPELLS[1] and spellId ~= HEAL_SPELLS[2] then return end

    if not needs_healing() then
        DoGameAction(23, 0, 0)
        t.Handled = true
    end
end

-- Bypass the target dialog for healing/cure spells
function events.SpellTargetType(t)
    if not Game.AutoHealEnabled then return end
    if not CURE_SPELLS[t.Spell] and not table.find(HEAL_SPELLS, t.Spell) then return end
    if bit.band(t.Flags, 0xE021) > 0 then return end  -- scroll/event/special

    if table.find(HEAL_SPELLS, t.Spell) then
        local bestSlot, bestHP = -1, 999999
        local dead, eradicated = const.Condition.Dead, const.Condition.Eradicated
        for i = 0, Party.High do
            if Party[i].Conditions[dead] == 0 and Party[i].Conditions[eradicated] == 0
            and Party[i].HP < Party[i]:GetFullHP() then
                if Party[i].HP < bestHP then
                    bestHP = Party[i].HP
                    bestSlot = i
                end
            end
        end
        if bestSlot >= 0 then
            u2[0x51d824] = bestSlot
            u2[0x51d82c] = bit.lshift(bestSlot, 3) + 4
            t.Flags = 0x1000
        else
            u2[0x51d824] = t.CasterSlot
            u2[0x51d82c] = bit.lshift(t.CasterSlot, 3) + 4
            t.Flags = 0x1000
            Game._xp_pending_attack = true
        end
    elseif CURE_SPELLS[t.Spell] then
        u2[0x51d824] = t.CasterSlot
        u2[0x51d82c] = bit.lshift(t.CasterSlot, 3) + 4
        t.Flags = 0x1000
    end
end

-- Execute pending attack from fizzled heal (only in gameplay, not menus)
function events.Tick()
    if Game._xp_pending_attack and Game.CurrentScreen == 0 then
        Game._xp_pending_attack = false
        DoGameAction(23, 0, 0)
    end
end

-- Apply party-wide condition removal for cure spells
function events.PlayerSpellProc(t)
    if not Game.AutoHealEnabled then return end
    local conds = CURE_SPELLS[t.Spell]
    if not conds then return end

    for i = 0, Party.High do
        for _, c in ipairs(conds) do
            Party[i].Conditions[c] = 0
        end
        Party[i]:ShowFaceAnimation(const.FaceAnimation.TempleHeal)
    end
end
