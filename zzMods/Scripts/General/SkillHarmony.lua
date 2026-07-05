-- SkillHarmony: auto-advance mastery for all skills based on skill level.
--
-- Mastery thresholds: 1→Normal, 4→Expert, 7→Master, 10→GM
-- When a skill's level crosses a threshold AND the player's stored mastery
-- is lower, the mastery bits in Player.Skills[] are upgraded automatically.
--
-- Class mastery caps are respected — you cannot surpass what your class
-- can learn at a trainer.
--
-- Does NOT touch Cleave's slot (skill 36) — Cleave.lua handles itself.
-- Toggle: Extra Settings → "Enable SkillHarmony" (Game.SkillHarmonyEnabled).
-- Delete this file to disable entirely.

local LogId = "SkillHarmony"
local MF = Merge.Functions
MF.LogInit1(LogId)

local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

function events.GetSkill(t)
    if not Game.SkillHarmonyEnabled then return end
    if not t.Player then return end
    if t.Skill == const.Skills.Stealing then return end  -- Cleave owns this slot
    if t.Skill < 0 or t.Skill > 38 then return end

    local stored = t.Player.Skills[t.Skill]
    if not stored or stored == 0 then return end

    local level, storedMastery = SplitSkill(stored)
    if level < 1 then return end

    local expected = MasteryFromLevel(level)

    -- Cap by class max mastery
    local playerClass = t.Player.Class
    if playerClass then
        local classMax = Game.Classes.Skills[playerClass][t.Skill]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end

    -- Upgrade stored mastery if expected is higher
    if expected > storedMastery then
        t.Player.Skills[t.Skill] = JoinSkill(level, expected)
    end

    -- Sync t.Result mastery
    local resultLevel, resultMastery = SplitSkill(t.Result)
    if expected > resultMastery then
        t.Result = JoinSkill(resultLevel, expected)
    end
end

MF.LogInit2(LogId)
