-- SkillHarmony: auto-advance mastery for skills based on level.
-- Mastery thresholds: 1=Normal, 4=Expert, 7=Master, 10=GM
-- Writes to both Lua API (pl.Skills) and raw Party memory.
--
-- DISPLAY REFRESH CONSTRAINT:
-- The Skills tab caches formatted display text once during tab Init and
-- never re-reads during Draw. The game's GetSkillMastery function (0x455B09)
-- is called during Init, not during Draw. There is NO hook, event, or
-- overlay approach that can refresh the mastery text live.
--
-- Approaches proven non-working:
--   mem.autohook(0x455B09)     — fires during Init only, not Draw
--   font:Draw in PostRender     — D3D context inactive, text invisible
--   Game.CurrentCharScreen toggle — visual flash but no reliable re-Init
--   Game.NeedRedraw             — only affects minimap
--   CustomDialog wrapping       — items clipped by 3D viewport
--   Raw-cache clear             — text never re-read during Draw
--
-- Only reliable refresh: close Skills tab and reopen (toggle to Stats, or Esc+'C').

local LogId = "SkillHarmony"
local MF = Merge.Functions
MF.LogInit1(LogId)

local PARTY_BASE  = 0x00B2187C
local PLAYER_SIZE = 0x1D28
local SKILL_OFF   = 0x378

local frameCounter = 0

local function RawSkillAddr(charIdx, skillId)
    return PARTY_BASE + charIdx * PLAYER_SIZE + SKILL_OFF + skillId * 2
end

local function FindPlayerIndex(pl)
    for i, p in ipairs(Party.Players) do
        if p == pl then return i - 1 end
    end
end

local function WriteSkillToRaw(pl, skillId, val)
    local charIdx = FindPlayerIndex(pl)
    if charIdx then
        mem.u2[RawSkillAddr(charIdx, skillId)] = val
    end
end

local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

local function CheckAndUpgrade(pl, skillId, stored)
    local level, mastery = SplitSkill(stored)
    if level < 1 then return stored end
    local expected = MasteryFromLevel(level)
    local playerClass = pl.Class
    if playerClass then
        local classSkills = Game.Classes.Skills[playerClass]
        local classMax = classSkills and classSkills[skillId]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end
    if expected > mastery then
        local newVal = JoinSkill(level, expected)
        pl.Skills[skillId] = newVal
        WriteSkillToRaw(pl, skillId, newVal)
        return newVal
    end
    return stored
end

function events.GetPlayerSkillMastery(t)
    if not Game.SkillHarmonyEnabled then return end
    if not t.Player then return end
    local skillId = t.Skill
    if not skillId or skillId == const.Skills.Stealing or skillId == const.Skills.IdentifyItem or skillId == const.Skills.IdentifyMonster or skillId == const.Skills.Learning then return end
    local stored = t.Result
    if not stored or stored == 0 then return end
    local upgraded = CheckAndUpgrade(t.Player, skillId, stored)
    if upgraded ~= stored then
        t.Result = upgraded
    end
end

function events.GetSkill(t)
    if not Game.SkillHarmonyEnabled then return end
    if not t.Player then return end
    local skillId = t.Skill
    if not skillId or skillId == const.Skills.Stealing or skillId == const.Skills.IdentifyItem or skillId == const.Skills.IdentifyMonster or skillId == const.Skills.Learning then return end
    if skillId < 0 or skillId > 38 then return end
    local stored = t.Player.Skills[skillId]
    if not stored or stored == 0 then return end
    CheckAndUpgrade(t.Player, skillId, stored)
    local resultLevel, resultMastery = SplitSkill(t.Result)
    local expected = MasteryFromLevel(resultLevel)
    if expected > resultMastery then
        t.Result = JoinSkill(resultLevel, expected)
    end
end

function events.L2InterfaceUpd()
    if not Game.SkillHarmonyEnabled then return end

    frameCounter = frameCounter + 1
    if frameCounter < 10 then return end
    frameCounter = 0

    for _, pl in Party.Players do
        for skill = 0, 38 do
            if skill ~= const.Skills.Stealing and skill ~= const.Skills.IdentifyItem and skill ~= const.Skills.IdentifyMonster and skill ~= const.Skills.Learning then
                local stored = pl.Skills[skill]
                if stored and stored > 0 then
                    CheckAndUpgrade(pl, skill, stored)
                end
            end
        end
    end
end

MF.LogInit2(LogId)
