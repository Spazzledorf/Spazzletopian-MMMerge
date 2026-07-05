-- Guardian (formerly "Cover"): repurposes the Identify Item skill slot
-- (ID 24), the same pattern Cleave.lua uses on Stealing. Identify Item
-- itself is baked in as always-succeeding (see events.CanIdentifyItem
-- below, using this project's own already-installed CanIdentifyItem hook
-- in ExtraEvents.lua) so nothing is lost by freeing the slot.
--
-- This replaces an earlier attempt at Cover as a genuinely new skill via
-- Malekitsu/Maw-Mod-MMMerge's Skillz.dll: that DLL crashed unrecoverably
-- (silently, no error, nothing in either log) when actually training a
-- skill in this build, even after fixing every missing-dependency error it
-- surfaced along the way (a missing Data/Tables/Race Skillz.txt, a missing
-- cave_api.dll). Confirms the risk flagged before attempting it: an
-- unverifiable compiled binary with no public source. Abandoned in favor of
-- this DLL-free approach. Skillz.dll, Scripts/Modules/SkillzDll.lua and the
-- ExeMods DLLs it needed are no longer used by anything -- fine to delete.
--
-- Renamed from "Cover" to "Guardian" to better fit the taunt bake-in below
-- (Guardian = protects allies AND draws attention, not just intercepts).
--
-- Unlike the Skillz.dll attempt, the "Show <skill> in character skills
-- screen" ASM patch Cleave.lua carries over from the original (disabled)
-- Scripts/General/Stealing.lua.disabled is intentionally NOT replicated
-- here: reading that original file's comment showed it exists specifically
-- to fix a display quirk for Stealing's own skill slot (hardcoded to compare
-- against 0x24, Stealing's ID). Identify Item is a normal, already
-- correctly-displayed vanilla skill, so it shouldn't need that fix -- worth
-- confirming in-game, but there's no reason to expect it does.
--
-- Mastery progression: auto-promotes with skill level, exactly like Cleave
-- (1/4/7/10 -> Normal/Expert/Master/GM), rather than MAW's own suggested
-- Cover thresholds (6/12/20) -- matching Cleave.lua's own pattern is more
-- useful here than matching MAW's specific tuning.
--
-- Mechanic (ported from MAW's Scripts/General/zzMAW-Skills.lua "Cover"
-- skill, for the original source): whenever a
-- monster attacks a party member, every OTHER conscious party member with
-- Guardian learned (mastery gated by attack type: Normal = physical,
-- Expert = other/projectile, Master = the monster's 3rd attack slot i.e.
-- usually spells) and "guarding" toggled on (default on, toggle key P while
-- on the Stats tab) rolls a chance -- 10% + 1% per skill point, capped at
-- 40%. Among successful rolls, whoever has the highest current HP takes
-- the hit instead of the original target.
--
-- Taunt (baked in, not a separate skill/slot): landing a melee hit grants a
-- flat bonus to this character's next Guardian roll, scaled by mastery
-- (Normal +5%, Expert +10%, Master +15%, GM +20%) instead of only at GM
-- like the original one-shot bonus. This is deliberately the "for now"
-- version of Taunt -- a passive threat bump riding the same proven
-- PlayerAttacked/CalcDamageToMonster hooks already used for the intercept
-- itself, rather than a real pre-emptive monster-targeting hook (unproven,
-- higher risk, not attempted). If a more assertive Taunt is wanted later
-- (biasing which party member a monster picks as its FIRST target, before
-- any Guardian roll happens at all), that needs its own native hook
-- discovery pass -- this bake-in only affects the reactive intercept odds.
--
-- Toggle: Extra Settings -> "Enable Guardian" (Game.GuardianEnabled,
-- default true). Delete this file to remove the feature entirely (Identify
-- Item reverts to normal, since events.CanIdentifyItem's always-succeed
-- handler goes with it).

local LogId = "Guardian"
local MF = Merge.Functions
MF.LogInit1(LogId)

local GUARDIAN_SKILL = const.Skills.IdentifyItem

Game.GuardianEnabled = (Game.GuardianEnabled == nil) and true or Game.GuardianEnabled

-- ---------------------------------------------------------------------------
-- Identify Item: bake in as always-succeeding
-- ---------------------------------------------------------------------------

function events.CanIdentifyItem(t)
    t.CanIdentify = true
end

-- ---------------------------------------------------------------------------
-- UI: rename skill slot 24, set descriptions, grant to all classes
-- ---------------------------------------------------------------------------

function events.GameInitialized2()
    Game.SkillNames[GUARDIAN_SKILL] = "Guardian"

    Game.SkillDescriptions[GUARDIAN_SKILL] =
        "Guardian is a defensive skill enabling a character to shield allies by " ..
        "intercepting incoming attacks meant for them, and to draw attention by " ..
        "landing solid hits of their own. " ..
        "Mastery improves automatically as skill level rises: " ..
        "level 4 unlocks Expert, level 7 Master, level 10 Grandmaster. " ..
        "Grants 10%% plus 1%% chance per skill point to intercept an attack meant " ..
        "for an ally, up to 40%%. Landing a melee hit grants a taunt bonus to the " ..
        "next intercept roll, scaling with mastery (Normal +5%%, Expert +10%%, " ..
        "Master +15%%, GM +20%%). " ..
        "Press P (on the Stats tab) to enable/disable guarding for this character."

    Game.SkillDesNormal[GUARDIAN_SKILL] =
        "10%% plus 1%% chance per skill point (max 40%%) to intercept a " ..
        "physical attack meant for another party member. Landing a melee hit " ..
        "grants +5%% taunt bonus to the next intercept roll. " ..
        "Unlocks Expert mastery at level 4."

    Game.SkillDesExpert[GUARDIAN_SKILL] =
        "Also able to intercept ranged/projectile attacks. Taunt bonus rises to +10%%. " ..
        "Unlocks Master mastery at level 7."

    Game.SkillDesMaster[GUARDIAN_SKILL] =
        "Also able to intercept a monster's special (usually spell) attack. " ..
        "Taunt bonus rises to +15%%. Unlocks Grandmaster mastery at level 10."

    Game.SkillDesGM[GUARDIAN_SKILL] =
        "Taunt bonus rises to +20%% on the next intercept roll after landing a melee hit."

    -- Mirror Shield's per-class mastery caps onto Guardian instead of keeping
    -- Identify Item's -- Shield is thematically the closer fit (a defensive,
    -- protect-others skill) and vanilla class design already rates
    -- tank/melee classes highly on it, unlike Identify Item (a scholarly/
    -- merchant skill Knights have zero access to in this project's own
    -- Class Skills.txt, which is why Knight capped at Normal before this).
    local classCount = Game.Classes.Skills.count
    for classId = 0, classCount - 1 do
        local skills = Game.Classes.Skills[classId]
        if skills then
            skills[GUARDIAN_SKILL] = math.max(skills[const.Skills.Shield], 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Training: add Guardian to all Training halls
-- ---------------------------------------------------------------------------

events.PopulateLearnSkillsDialog = function(t)
    if not Game.GuardianEnabled then return end
    if t.PicType == const.HouseType.Training then
        t.Result[#t.Result + 1] = GUARDIAN_SKILL
    end
end

-- ---------------------------------------------------------------------------
-- Mastery: auto-promote with skill level, same thresholds as Cleave.lua
-- ---------------------------------------------------------------------------

local function MasteryFromLevel(level)
    if level >= 10 then return 4
    elseif level >= 7 then return 3
    elseif level >= 4 then return 2
    else return 1
    end
end

local function SyncGuardianMastery(player)
    if not player then return nil, 0 end
    local stored = player.Skills[GUARDIAN_SKILL]
    if not stored or stored == 0 then return nil, 0 end
    local level, curMastery = SplitSkill(stored)
    if level < 1 then return nil, 0 end
    local expected = MasteryFromLevel(level)

    local playerClass = player.Class
    if playerClass then
        local classMax = Game.Classes.Skills[playerClass][GUARDIAN_SKILL]
        if classMax and classMax > 0 and expected > classMax then
            expected = classMax
        end
    end

    if curMastery ~= expected then
        player.Skills[GUARDIAN_SKILL] = JoinSkill(level, expected)
    end
    return expected, level
end

function events.GetSkill(t)
    if not Game.GuardianEnabled then return end
    if t.Player and t.Skill == GUARDIAN_SKILL then
        local mastery = SyncGuardianMastery(t.Player)
        if mastery then
            local resultLevel, resultMastery = SplitSkill(t.Result)
            if mastery > resultMastery then
                t.Result = JoinSkill(resultLevel, mastery)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Guarding toggle (per character, default on)
-- ---------------------------------------------------------------------------

local function EnsureGuardingTable()
    if not vars.guarding then
        vars.guarding = {}
        for i = 0, 4 do
            vars.guarding[i] = true
        end
    end
end

function events.KeyDown(t)
    if not Game.GuardianEnabled then return end
    if t.Key ~= const.Keys.P then return end
    if Game.CurrentScreen ~= const.Screens.Inventory or Game.CurrentCharScreen ~= const.CharScreens.Stats then
        return
    end

    EnsureGuardingTable()
    local index = Game.CurrentPlayer
    if index < 0 then return end
    vars.guarding[index] = not vars.guarding[index]
    Game.ShowStatusText(vars.guarding[index] and "Guardian Enabled" or "Guardian Disabled")
end

-- ---------------------------------------------------------------------------
-- Taunt (baked in): landing a melee hit grants a mastery-scaled bonus to
-- this character's next Guardian intercept roll.
-- ---------------------------------------------------------------------------

local TAUNT_BONUS_BY_MASTERY = {0.05, 0.10, 0.15, 0.20}  -- Normal, Expert, Master, GM

local tauntBonus = {}

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
    if not Game.GuardianEnabled then return end
    if not (t.ByPlayer and t.Melee and t.Player) then return end
    if t.DamageKind ~= const.Damage.Phys then return end
    if not t.Result or t.Result <= 0 then return end

    local _, m = SplitSkill(t.Player.Skills[GUARDIAN_SKILL])
    if m >= 1 then
        local slot = FindPartySlot(t.Player)
        if slot then
            tauntBonus[slot] = TAUNT_BONUS_BY_MASTERY[m]
        end
    end
end

-- ---------------------------------------------------------------------------
-- Combat: intercept an attack meant for another party member
-- ---------------------------------------------------------------------------

function events.PlayerAttacked(t)
    if not Game.GuardianEnabled then return end
    if not t.Attacker or not t.Attacker.Monster then return end

    local action = t.Attacker.MonsterAction
    local masteryRequired
    if (action == 0 or action == 1) and t.Attacker.Monster["Attack" .. (action + 1)].Type == const.Damage.Phys then
        masteryRequired = 1
    elseif action == 2 then
        masteryRequired = 3
    else
        masteryRequired = 2
    end

    EnsureGuardingTable()

    local originalName = t.Player and t.Player.Name
    local bestIndex, bestHP = -1, -1
    for i = 0, Party.High do
        if i ~= t.PlayerSlot and vars.guarding[i] and Party[i]:IsConscious() then
            local s, m = SplitSkill(Party[i].Skills[GUARDIAN_SKILL])
            if s > 0 and m >= masteryRequired then
                local chance = math.min(0.10 + s * 0.01, 0.40)
                if tauntBonus[i] then
                    chance = chance + tauntBonus[i]
                    tauntBonus[i] = nil
                end
                if chance > math.random() and Party[i].HP > bestHP then
                    bestHP = Party[i].HP
                    bestIndex = i
                end
            end
        end
    end

    if bestIndex >= 0 then
        t.PlayerSlot = bestIndex
        Party[bestIndex]:ShowFaceAnimation(14)
        if originalName then
            Game.ShowStatusText(Party[bestIndex].Name .. " guards " .. originalName .. "!")
        end
        -- Marks a successful guard for Retaliation.lua to consume on this
        -- character's next hit (one-shot, no expiry -- cleared on first
        -- qualifying attack, or overwritten by the next guard). Guardian
        -- doesn't need to know whether Retaliation is learned or even
        -- installed -- just records that a guard happened, at this slot.
        vars.justGuarded = vars.justGuarded or {}
        vars.justGuarded[bestIndex] = true
    end
end

MF.LogInit2(LogId)
