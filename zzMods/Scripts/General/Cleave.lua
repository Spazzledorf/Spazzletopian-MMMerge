-- Cleave: a melee sweep technique that reuses the Stealing skill slot (ID 36).
-- No display table patches — the existing Stealing entry in the character sheet
-- is simply renamed to "Cleave" via Game.SkillNames[36].
--
-- Mastery auto-promotes with skill level: 1→Normal, 4→Expert, 7→Master, 10→GM
-- Cap: class max mastery (inherited from whatever the class can train Stealing to).
--
-- Toggle: Extra Settings → "Enable Cleave" (Game.CleaveEnabled, default true).
-- Delete this file to disable entirely.

local LogId = "Cleave"
local MF = Merge.Functions
MF.LogInit1(LogId)

local floor, sqrt = math.floor, math.sqrt

local CLEAVE_RANGE   = 600

local DMG_BASE_BY_MASTERY = {40, 50, 60, 70}
local ExtraTargets = {1, 2, 3, 5}

-- Thresholds indexed by mastery (1-indexed): mastery N unlocks at MASTERY_THRESH[N]
local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

-- Sync stored mastery and return (mastery_tier, skill_level)
local function SyncCleaveMastery(player)
    if not player then return nil, 0 end
    local stored = player.Skills[const.Skills.Stealing]
    if not stored or stored == 0 then return nil, 0 end
    local level, curMastery = SplitSkill(stored)
    if level < 1 then return nil, 0 end
    local expected = MasteryFromLevel(level)

    -- Cap by class max mastery (inherited from the game's class-skills table)
    local playerClass = player.Class
    if playerClass then
        local classMax = Game.Classes.Skills[playerClass][const.Skills.Armsmaster]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end

    if curMastery ~= expected then
        player.Skills[const.Skills.Stealing] = JoinSkill(level, expected)
    end
    return expected, level
end

-- ---------------------------------------------------------------------------
-- UI: rename skill slot 36, set descriptions, grant Normal to all classes
-- ---------------------------------------------------------------------------

function events.GameInitialized2()
    Game.SkillNames[36] = "Cleave"

    Game.SkillDescriptions[36] =
        "Cleave is the art of continuing a weapon arc through multiple foes. " ..
        "Melee hits sweep through nearby enemies for reduced damage. " ..
        "Mastery improves automatically as skill level rises: " ..
        "level 4 unlocks Expert, level 7 Master, level 10 Grandmaster. " ..
        "Cleave damage starts at 40%% base (Normal) scaling up to 70%% base " ..
        "(GM), plus +1%% per extra skill point, up to 100%%."

    Game.SkillDesNormal[36] =
        "Sweeps through 1 additional nearby enemy. " ..
        "40%% base damage plus +1%% per skill point (max 100%%). Reach 600. " ..
        "Unlocks Expert mastery at level 4."

    Game.SkillDesExpert[36] =
        "Arc widens to catch 2 additional enemies. " ..
        "Base damage rises to 50%% plus +1%% per point. " ..
        "Unlocks Master mastery at level 7."

    Game.SkillDesMaster[36] =
        "3 additional enemies struck. " ..
        "Base damage rises to 60%% plus +1%% per point. " ..
        "Unlocks Grandmaster mastery at level 10."

    Game.SkillDesGM[36] =
        "5 additional enemies struck. " ..
        "70%% base damage plus +1%% per skill point. " ..
        "The warrior becomes a hurricane of steel."

    -- Mirror Armsmaster's per-class availability so Cleave mastery matches a
    -- melee combat skill rather than the thief skill it replaced.
    -- Only classes with Armsmaster access gain Cleave — no blanket Normal.
    local classCount = Game.Classes.Skills.count
    for classId = 0, classCount - 1 do
        local skills = Game.Classes.Skills[classId]
        if skills then
            skills[36] = skills[const.Skills.Armsmaster] or 0
        end
    end

    -- Show Cleave in the character skills screen
    -- Reuses the same slot and mechanism as the original Stealing system
    mem.asmpatch(0x419AE2, [[
    cmp dword ptr [0x4F3964], 0x24
    je @end
    mov dword ptr [0x4F3964], 0x24
    sub dword ptr [ebp-0x28], 4
    jmp absolute 0x419867
    @end:
    mov dword ptr [0x4F3964], 0x1A
    cmp dword ptr [ebp-0x2C], 0
    jnz absolute 0x419BDA
    ]])
end

-- ---------------------------------------------------------------------------
-- Training: add Cleave to all Training halls
-- ---------------------------------------------------------------------------

events.PopulateLearnSkillsDialog = function(t)
    if not Game.CleaveEnabled then return end
    if t.PicType == const.HouseType.Training then
        t.Result[#t.Result + 1] = const.Skills.Stealing
    end
end

-- ---------------------------------------------------------------------------
-- GetSkill: auto-promote mastery bits whenever the skill is read
-- ---------------------------------------------------------------------------

function events.GetSkill(t)
    if not Game.CleaveEnabled then return end
    if t.Player and t.Skill == const.Skills.Stealing then
        local mastery = SyncCleaveMastery(t.Player)
        if mastery then
            local resultLevel, resultMastery = SplitSkill(t.Result)
            if mastery > resultMastery then
                t.Result = JoinSkill(resultLevel, mastery)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Combat: sweep for extra targets
-- ---------------------------------------------------------------------------

local isCleaving = false

function events.CalcDamageToMonster(t)
    if not Game.CleaveEnabled then return end
    if isCleaving then return end
    if not (t.Melee and t.ByPlayer) then return end
    if not t.Player or not t.Monster then return end
    if t.Result <= 0 then return end

    local mastery, skillLevel = SyncCleaveMastery(t.Player)
    if not mastery or mastery < 1 then return end

    local dmgPct = math.min((DMG_BASE_BY_MASTERY[mastery] or 40) + (skillLevel or 0), 100)
    local cleaveDmg = floor(t.Result * dmgPct / 100)
    if cleaveDmg < 1 then return end

    local numExtra = ExtraTargets[mastery]
    local primIdx  = t.MonsterIndex
    local px, py, pz = t.Monster.X, t.Monster.Y, t.Monster.Z

    isCleaving = true
    local hit = 0
    for idx, mon in Map.Monsters do
        if hit >= numExtra then break end
        if idx ~= primIdx and mon.HP > 0 then
            local dx, dy, dz = px - mon.X, py - mon.Y, pz - mon.Z
            if sqrt(dx*dx + dy*dy + dz*dz) <= CLEAVE_RANGE then
                mon.HP = mon.HP - cleaveDmg
                hit = hit + 1
            end
        end
    end
    isCleaving = false
end

MF.LogInit2(LogId)
