-- StatRemix: three attribute system improvements.
--
-- 1) Smooth high-end curve: attributes >=25 use floor(val/5) instead of the
--    native breakpoint table. Below 25 the native table is preserved. Matches
--    native exactly at 25/30/35/40, then provides smoother progression above.
--
-- 2) Accuracy weight: each point of Accuracy above 10 grants +2 to MeleeAttack
--    and RangedAttack via the skills bonus calculator. This improves to-hit and
--    damage calculation without touching other stats.
--
-- 3) Luck damage floor: melee/ranged hits are floored toward the weapon's own
--    max roll as Luck increases -- fraction = min(1, Luck/500), floor =
--    min + (max-min)*fraction (Luck 500 = always max roll). min/max come from
--    Player:GetMeleeDamageMin/Max() and GetRangedDamageMin/Max(), the same
--    native aggregate the character sheet's "Damage" line uses (confirmed via
--    in-game testing to match exactly, e.g. a 2H sword showing 6-18).
--    CalcDamageToMonster's Result is already post-defense by the time this
--    hook runs, so the weapon's pre-defense min/max is scaled by this hit's
--    own defense-reduction ratio (Result/Damage) before flooring, instead of
--    comparing pre- and post-defense numbers directly.
--
--    Spell coverage is NOT implemented (see disabled draft below the weapon
--    handler). events.CalcSpellDamage fires for monster-cast spells hitting
--    the party too (confirmed via SpellsExtra.lua's own MO.CalcSpellDamageCaster
--    tracking, which distinguishes "party casts at monster" from "object/
--    monster damages player" call sites), and there's no reliable way from
--    this event alone to confirm a hit was player-cast. Using Game.CurrentPlayer
--    as a stand-in caster does NOT filter this -- it's just "some character is
--    selected", true almost always -- so a naive implementation would risk
--    boosting monster spell damage against the party using the party's own
--    Luck. Needs the CasterType/CasterIndex bit-decode verified in-game before
--    enabling.
--
-- Toggle: Extra Settings -> "Enable Stat Remix" (Game.StatRemixEnabled, default on).
-- Delete this file to disable entirely.

local LogId = "StatRemix"
local MF = Merge.Functions
MF.LogInit1(LogId)

local floor = math.floor

-- ---------------------------------------------------------------------------
-- GetStatisticEffect: smooth high-end curve for all 7 core attributes
-- ---------------------------------------------------------------------------

function events.GetStatisticEffect(t)
    if not Game.StatRemixEnabled then return end
    if t.Value >= 25 then
        t.Result = floor(t.Value / 5)
    end
end

-- ---------------------------------------------------------------------------
-- CalcStatBonusBySkills: Accuracy weight -> MeleeAttack / RangedAttack
-- ---------------------------------------------------------------------------

function events.CalcStatBonusBySkills(t)
    if not Game.StatRemixEnabled then return end
    if not t.Player then return end
    if t.Stat == const.Stats.MeleeAttack or t.Stat == const.Stats.RangedAttack then
        local acc = t.Player.AccuracyBase + t.Player.AccuracyBonus
        t.Result = t.Result + math.max(0, (acc - 10) * 2)
    end
end

-- ---------------------------------------------------------------------------
-- Luck damage floor
-- ---------------------------------------------------------------------------

local LUCK_FLOOR_CAP = 500

local function LuckFraction(pl)
    local totalLuck = pl.LuckBase + pl.LuckBonus
    return math.min(1, totalLuck / LUCK_FLOOR_CAP)
end

-- Weapons (melee/ranged, physical damage only)
function events.CalcDamageToMonster(t)
    if not Game.StatRemixEnabled then return end
    if not (t.ByPlayer and t.Player and t.Damage > 0) then return end
    if t.DamageKind ~= const.Damage.Phys then return end

    local fraction = LuckFraction(t.Player)
    if fraction <= 0 then return end

    local dmgMin, dmgMax
    if t.Melee then
        dmgMin, dmgMax = t.Player:GetMeleeDamageMin(), t.Player:GetMeleeDamageMax()
    else
        dmgMin, dmgMax = t.Player:GetRangedDamageMin(), t.Player:GetRangedDamageMax()
    end
    if dmgMax <= dmgMin then return end

    -- Result is already post-defense; scale the weapon's pre-defense range
    -- by this hit's own defense-reduction ratio before flooring.
    if not t.Damage or t.Damage == 0 then return end
    local reduction = t.Result / t.Damage
    local floorDamage = floor((dmgMin + (dmgMax - dmgMin) * fraction) * reduction)
    if t.Result < floorDamage then
        t.Result = floorDamage
    end
end

-- Spells: not implemented, see file header.

MF.LogInit2(LogId)
