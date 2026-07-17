-- Retaliation: repurposes the Learning skill slot (ID 38), the same pattern
-- Cleave.lua uses on Stealing, Guardian.lua uses on Identify Item, and
-- ManaShield.lua uses on Identify Monster. Learning's own gameplay effect
-- (training-time reduction) is normalized instead of lost -- see
-- Learning.lua's header for that change.
--
-- Mastery progression: auto-promotes with skill level, same thresholds as
-- Cleave.lua/Guardian.lua/ManaShield.lua (1/4/7/10 -> Normal/Expert/Master/GM).
-- Per-class caps mirror Guardian (Shield distribution) instead of Learning's own
-- distribution, same reasoning as Guardian mirroring Shield.
--
-- Mechanic: after Guardian.lua successfully redirects an attack onto a character
-- (see Guardian.lua's vars.lastGuardSlot marker), that character instantly
-- counterattacks the attacker with their weapon -- melee if guarding a melee
-- attack, ranged if guarding a ranged/spell attack. Damage scales with mastery;
-- no chance roll.

local LogId = "Retaliation"
local MF = Merge.Functions
MF.LogInit1(LogId)

local RETALIATION_SKILL = const.Skills.Learning

Game.RetaliationEnabled = (Game.RetaliationEnabled == nil) and true or Game.RetaliationEnabled

local MELEE_DMG_PCT = {[1] = 50, [2] = 75, [3] = 100, [4] = 125}
local RANGED_DMG_PCT = {[1] = 40, [2] = 60, [3] = 80, [4] = 100}

-- ---------------------------------------------------------------------------
-- UI: rename skill slot 38, set descriptions, mirror Guardian's caps
-- ---------------------------------------------------------------------------

function events.GameInitialized2()
    Game.SkillNames[RETALIATION_SKILL] = "Retaliation"

    Game.SkillDescriptions[RETALIATION_SKILL] =
        "Retaliation lets a character instantly counterattack after " ..
        "successfully using Guardian to protect an ally. Mastery improves " ..
        "automatically as skill level rises: level 4 unlocks Expert, " ..
        "level 7 Master, level 10 Grandmaster. Counters with melee weapon " ..
        "against melee attacks, or ranged weapon against ranged/spell attacks."

    Game.SkillDesNormal[RETALIATION_SKILL] =
        "Counterattack deals 50%% melee / 40%% ranged weapon damage. " ..
        "Unlocks Expert mastery at level 4."

    Game.SkillDesExpert[RETALIATION_SKILL] =
        "Counterattack deals 75%% melee / 60%% ranged weapon damage. " ..
        "Unlocks Master mastery at level 7."

    Game.SkillDesMaster[RETALIATION_SKILL] =
        "Counterattack deals 100%% melee / 80%% ranged weapon damage. " ..
        "Unlocks Grandmaster mastery at level 10."

    Game.SkillDesGM[RETALIATION_SKILL] =
        "Counterattack deals 125%% melee / 100%% ranged weapon damage."

    -- Mirror Guardian's distribution so Retaliation matches who can guard.
    -- Guardian.lua (loaded first alphabetically) populates slot 24 already.
    local classCount = Game.Classes.Skills.count
    for classId = 0, classCount - 1 do
        local skills = Game.Classes.Skills[classId]
        if skills then
            skills[RETALIATION_SKILL] = skills[const.Skills.IdentifyItem] or 0
        end
    end
end

-- ---------------------------------------------------------------------------
-- Training: add Retaliation to all Training halls
-- ---------------------------------------------------------------------------

events.PopulateLearnSkillsDialog = function(t)
    if not Game.RetaliationEnabled then return end
    if t.PicType == const.HouseType.Training then
        t.Result[#t.Result + 1] = RETALIATION_SKILL
    end
end

-- ---------------------------------------------------------------------------
-- Mastery: auto-promote with skill level
-- ---------------------------------------------------------------------------

local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

local function SyncRetaliationMastery(player)
    if not player then return nil, 0 end
    local stored = player.Skills[RETALIATION_SKILL]
    if not stored or stored == 0 then return nil, 0 end
    local level, curMastery = SplitSkill(stored)
    if level < 1 then return nil, 0 end
    local expected = MasteryFromLevel(level)

    local playerClass = player.Class
    if playerClass then
        local classMax = Game.Classes.Skills[playerClass][RETALIATION_SKILL]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end

    if curMastery ~= expected then
        player.Skills[RETALIATION_SKILL] = JoinSkill(level, expected)
    end
    return expected, level
end

function events.GetSkill(t)
    if not Game.RetaliationEnabled then return end
    if t.Player and t.Skill == RETALIATION_SKILL then
        local mastery = SyncRetaliationMastery(t.Player)
        if mastery then
            local resultLevel, resultMastery = SplitSkill(t.Result)
            if mastery > resultMastery then
                t.Result = JoinSkill(resultLevel, mastery)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Combat: instant counterattack after a successful Guardian
-- ---------------------------------------------------------------------------

function events.PlayerAttacked(t)
    if not Game.RetaliationEnabled then return end
    if not t.Attacker or not t.Attacker.Monster then return end
    if not vars.lastGuardSlot then return end

    local slot = vars.lastGuardSlot
    vars.lastGuardSlot = nil

    local player = Party[slot]
    if not player or not player:IsConscious() then return end

    local s, m = SplitSkill(player.Skills[RETALIATION_SKILL])
    if s <= 0 then return end

    local action = t.Attacker.MonsterAction
    local useRanged = (action ~= 0 and action ~= 1)

    local dmgMin, dmgMax
    if useRanged then
        dmgMin, dmgMax = player:GetRangedDamageMin(), player:GetRangedDamageMax()
    else
        dmgMin, dmgMax = player:GetMeleeDamageMin(), player:GetMeleeDamageMax()
    end
    if not dmgMin or dmgMin <= 0 then return end

    local pct = useRanged and (RANGED_DMG_PCT[m] or 100) or (MELEE_DMG_PCT[m] or 100)
    local dmg = math.max(1, math.floor(math.random(dmgMin, dmgMax) * pct / 100))

    Game.ShowStatusText(player.Name .. " retaliates for " .. dmg .. " damage!")
    t.Attacker.Monster:CalcTakenDamage(const.Damage.Phys, dmg)
end

MF.LogInit2(LogId)
