-- Retaliation: repurposes the Learning skill slot (ID 38), the same pattern
-- Cleave.lua uses on Stealing, Guardian.lua uses on Identify Item, and
-- ManaShield.lua uses on Identify Monster. Learning's own gameplay effect
-- (training-time reduction) is normalized instead of lost -- see
-- Learning.lua's header for that change.
--
-- Mastery progression: auto-promotes with skill level, same thresholds as
-- Cleave.lua/Guardian.lua/ManaShield.lua (1/4/7/10 -> Normal/Expert/Master/GM).
-- Per-class caps mirror Armsmaster (melee prowess) instead of Learning's own
-- distribution, same reasoning as Guardian mirroring Shield.
--
-- Mechanic (designed for this project, not ported from MAW -- MAW's own
-- Retaliation damage formula depends on their calcPowerVitality(), which
-- this project doesn't have, same situation as StatRemix.lua's Luck floor
-- and ManaShield.lua's Mana Shield): after Guardian.lua successfully
-- redirects an attack onto a character (see Guardian.lua's vars.justGuarded
-- marker), that character's next hit on a monster has a 1% per skill point chance
-- (capped 50%) to deal bonus damage: +25% per mastery tier (Normal +25%,
-- Expert +50%, Master +75%, GM +100%). One shot per successful guard,
-- consumed whether the roll succeeds or not.
--
-- Toggle: Game.RetaliationEnabled (default true). Not wired into the Extra
-- Settings UI, same reasoning as Guardian.lua's toggle -- MenuExtraSettings.lua's
-- pixel-positioned layout needs its own pass to add more toggles.

local LogId = "Retaliation"
local MF = Merge.Functions
MF.LogInit1(LogId)

local RETALIATION_SKILL = const.Skills.Learning

Game.RetaliationEnabled = (Game.RetaliationEnabled == nil) and true or Game.RetaliationEnabled

-- ---------------------------------------------------------------------------
-- UI: rename skill slot 38, set descriptions, mirror Armsmaster's caps
-- ---------------------------------------------------------------------------

function events.GameInitialized2()
    Game.SkillNames[RETALIATION_SKILL] = "Retaliation"

    Game.SkillDescriptions[RETALIATION_SKILL] =
        "Retaliation lets a character strike back hard after successfully " ..
        "using Guardian to protect an ally. Mastery improves automatically as " ..
        "skill level rises: level 4 unlocks Expert, level 7 Master, " ..
        "level 10 Grandmaster. Grants 1%% chance per skill point (max 50%%) " ..
        "to deal bonus damage on the next hit after a successful Guardian."

    Game.SkillDesNormal[RETALIATION_SKILL] =
        "+25%% damage on a successful Retaliation. Unlocks Expert mastery at level 4."

    Game.SkillDesExpert[RETALIATION_SKILL] =
        "+50%% damage on a successful Retaliation. Unlocks Master mastery at level 7."

    Game.SkillDesMaster[RETALIATION_SKILL] =
        "+75%% damage on a successful Retaliation. Unlocks Grandmaster mastery at level 10."

    Game.SkillDesGM[RETALIATION_SKILL] =
        "+100%% (double) damage on a successful Retaliation."

    local classCount = Game.Classes.Skills.count
    for classId = 0, classCount - 1 do
        local skills = Game.Classes.Skills[classId]
        if skills then
            skills[RETALIATION_SKILL] = math.max(skills[const.Skills.Armsmaster], 1)
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
-- Combat: bonus damage on the hit after a successful Guardian
-- ---------------------------------------------------------------------------

local BONUS_PER_MASTERY = 0.25

local function FindPartySlot(player)
    local id = player:GetIndex()
    for i = 0, Party.High do
        if Party[i]:GetIndex() == id then
            return i
        end
    end
    return nil
end

function events.CalcDamageToMonster(t)
    if not Game.RetaliationEnabled then return end
    if not (t.ByPlayer and t.Player) then return end
    if not t.Result or t.Result <= 0 then return end
    if not vars.justGuarded then return end

    local slot = FindPartySlot(t.Player)
    if not slot or not vars.justGuarded[slot] then return end
    vars.justGuarded[slot] = nil

    local s, m = SplitSkill(t.Player.Skills[RETALIATION_SKILL])
    if s <= 0 then return end

    local chance = math.min(s * 0.01, 0.50)
    if chance <= math.random() then return end

    t.Result = math.floor(t.Result * (1 + BONUS_PER_MASTERY * m))
end

MF.LogInit2(LogId)
