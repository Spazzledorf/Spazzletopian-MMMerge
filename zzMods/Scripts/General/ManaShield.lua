-- Mana Shield: repurposes the Identify Monster skill slot (ID 34), the same
-- pattern Cleave.lua uses on Stealing and Guardian.lua uses on Identify Item.
-- Identify Monster's own native effect isn't lost -- it's tied to spell
-- schools instead of its own dedicated slot (see events.GetSkill below):
-- whichever school a character has trained furthest determines their
-- monster-recognition, on the idea that deep knowledge of a school includes
-- knowing what wields it.
--
-- UNVERIFIED, worth checking live: the same events.GetSkill hook that ties
-- Identify Monster to spell schools also answers the character sheet's own
-- query for slot 34's value (now labeled "Mana Shield"), since both go
-- through the same native call with no way to tell them apart. The actual
-- mechanic below reads Player.Skills[] directly (a raw memory array,
-- confirmed independent of this hook) so it works correctly regardless --
-- but the character sheet's displayed level/mastery for Mana Shield, and
-- whatever the training-hall UI computes for "cost to train further", might
-- show the spell-school-derived number instead of Mana Shield's real
-- trained level. If that's confusing in practice, the fix is narrowing when
-- the override applies (e.g. only when Mana Shield's own raw level is 0),
-- not a re-architecture -- flag it if seen and it can be tightened.
--
-- Mastery progression: auto-promotes with skill level, same thresholds as
-- Cleave.lua and Guardian.lua (1/4/7/10 -> Normal/Expert/Master/GM). Per-class
-- caps mirror Meditation (a mana-management skill) instead of Identify
-- Monster's own distribution, same reasoning as Guardian mirroring Shield.
--
-- Mechanic (designed for this project, not ported from MAW -- MAW's own
-- Mana Shield is entangled in their complete CalcDamageToPlayer rewrite,
-- not portable in isolation, same situation StatRemix.lua's header
-- describes for the Luck floor and spells): when a hit would bring a
-- character below 30% of max HP, consume SP to absorb some of that damage
-- instead. Efficiency (damage absorbed per SP spent) scales with mastery:
-- Normal 1:1, Expert 1:2, Master 1:3, GM 1:4. Capped by available SP.
--
-- Toggle: Game.ManaShieldEnabled (default true), plus a per-character
-- enable/disable via key M while on the Stats tab, mirroring Guardian's P key.

local LogId = "ManaShield"
local MF = Merge.Functions
MF.LogInit1(LogId)

local MANA_SHIELD_SKILL = const.Skills.IdentifyMonster
local HP_THRESHOLD_PCT = 0.30

Game.ManaShieldEnabled = (Game.ManaShieldEnabled == nil) and true or Game.ManaShieldEnabled

-- ---------------------------------------------------------------------------
-- UI: rename skill slot 34, set descriptions, mirror Meditation's caps
-- ---------------------------------------------------------------------------

function events.GameInitialized2()
    Game.SkillNames[MANA_SHIELD_SKILL] = "Mana Shield"

    Game.SkillDescriptions[MANA_SHIELD_SKILL] =
        "Mana Shield lets a character spend spell points to absorb damage " ..
        "that would otherwise bring them dangerously low on hit points. " ..
        "Mastery improves automatically as skill level rises: " ..
        "level 4 unlocks Expert, level 7 Master, level 10 Grandmaster. " ..
        "Press M (on the Stats tab) to enable/disable this character's Mana Shield."

    Game.SkillDesNormal[MANA_SHIELD_SKILL] =
        "Absorbs 1 damage per spell point spent, when a hit would bring HP " ..
        "below 30%% of maximum. Unlocks Expert mastery at level 4."

    Game.SkillDesExpert[MANA_SHIELD_SKILL] =
        "Absorbs 2 damage per spell point. Unlocks Master mastery at level 7."

    Game.SkillDesMaster[MANA_SHIELD_SKILL] =
        "Absorbs 3 damage per spell point. Unlocks Grandmaster mastery at level 10."

    Game.SkillDesGM[MANA_SHIELD_SKILL] =
        "Absorbs 4 damage per spell point."

    local classCount = Game.Classes.Skills.count
    for classId = 0, classCount - 1 do
        local skills = Game.Classes.Skills[classId]
        if skills then
            skills[MANA_SHIELD_SKILL] = math.max(skills[const.Skills.Meditation], 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Training: add Mana Shield to all Training halls
-- ---------------------------------------------------------------------------

events.PopulateLearnSkillsDialog = function(t)
    if not Game.ManaShieldEnabled then return end
    if t.PicType == const.HouseType.Training then
        t.Result[#t.Result + 1] = MANA_SHIELD_SKILL
    end
end

-- ---------------------------------------------------------------------------
-- Mastery auto-promotion (raw storage) + Identify Monster spell-school tie-in
-- ---------------------------------------------------------------------------

local MAGIC_SCHOOLS = {
    const.Skills.Fire, const.Skills.Air, const.Skills.Water, const.Skills.Earth,
    const.Skills.Spirit, const.Skills.Mind, const.Skills.Body,
}

local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

local function SyncManaShieldMastery(player)
    local stored = player.Skills[MANA_SHIELD_SKILL]
    if not stored or stored == 0 then return end
    local level, curMastery = SplitSkill(stored)
    if level < 1 then return end
    local expected = MasteryFromLevel(level)

    local playerClass = player.Class
    if playerClass then
        local classMax = Game.Classes.Skills[playerClass][MANA_SHIELD_SKILL]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end

    if curMastery ~= expected then
        player.Skills[MANA_SHIELD_SKILL] = JoinSkill(level, expected)
    end
end

function events.GetSkill(t)
    if not Game.ManaShieldEnabled then return end
    if t.Skill ~= MANA_SHIELD_SKILL or not t.Player then return end

    SyncManaShieldMastery(t.Player)

    local best = 0
    for _, school in ipairs(MAGIC_SCHOOLS) do
        local raw = t.Player.Skills[school]
        if raw and raw > best then
            best = raw
        end
    end
    t.Result = best
end

-- ---------------------------------------------------------------------------
-- Toggle (per character, default on)
-- ---------------------------------------------------------------------------

local function EnsureManaShieldTable()
    if not vars.manaShield then
        vars.manaShield = {}
        for i = 0, 4 do
            vars.manaShield[i] = true
        end
    end
end

function events.KeyDown(t)
    if not Game.ManaShieldEnabled then return end
    if t.Key ~= const.Keys.M then return end
    if Game.CurrentScreen ~= const.Screens.Inventory or Game.CurrentCharScreen ~= const.CharScreens.Stats then
        return
    end

    EnsureManaShieldTable()
    local index = Game.CurrentPlayer
    if index < 0 then return end
    vars.manaShield[index] = not vars.manaShield[index]
    Game.ShowStatusText(vars.manaShield[index] and "Mana Shield Enabled" or "Mana Shield Disabled")
end

-- ---------------------------------------------------------------------------
-- Combat: absorb damage with SP when it would bring HP below 30% of max
-- ---------------------------------------------------------------------------

local function FindPartySlot(player)
    local id = player:GetIndex()
    for i = 0, Party.High do
        if Party[i]:GetIndex() == id then
            return i
        end
    end
    return nil
end

function events.CalcDamageToPlayer(t)
    if not Game.ManaShieldEnabled then return end
    if not t.Player or not t.Result or t.Result <= 0 then return end

    EnsureManaShieldTable()
    local slot = FindPartySlot(t.Player)
    if not slot or not vars.manaShield[slot] then return end

    local _, mastery = SplitSkill(t.Player.Skills[MANA_SHIELD_SKILL])
    if mastery <= 0 then return end

    local maxHP = t.Player:GetFullHP()
    local hpAfterHit = t.Player.HP - t.Result
    if hpAfterHit >= maxHP * HP_THRESHOLD_PCT then return end

    local sp = t.Player.SP
    if sp <= 0 then return end

    local efficiency = mastery
    local maxAbsorb = sp * efficiency
    local absorb = math.min(t.Result, maxAbsorb)
    if absorb <= 0 then return end

    local spCost = math.ceil(absorb / efficiency)
    t.Player.SP = sp - spCost
    t.Result = t.Result - absorb
end

MF.LogInit2(LogId)
