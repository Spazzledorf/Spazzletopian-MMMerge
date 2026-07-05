-- StatTooltips: enriches the native right-click stat info box on the
-- character sheet with base/bonus/total numbers and a short description for
-- the 7 core attributes, and useful derived info (hit/dodge chance) for AC
-- and Melee/Ranged Attack.
--
-- Previous approach (screen/tab detection + mouse-Y hit-testing + a
-- CustomUI overlay tooltip drawn on top of the native one) never reliably
-- fired -- too much guesswork about undocumented screen/tab state and pixel
-- layout. This version instead hooks the native call that actually renders
-- the stat info box, the same mechanism the Maw mod uses (see
-- Malekitsu/Maw-Mod-MMMerge, Scripts/Structs/extraEditableDescriptions.lua,
-- "build stat description box" / events.BuildStatInformationBox). The native
-- code has already resolved which stat, which player, and has already built
-- correct header/text strings by the time this hook fires -- we just read
-- the stat index off the stack and append to the text before it renders, so
-- there's no screen/tab detection or pixel calibration to get wrong.
--
-- Stat index at the hook (confirmed against Malekitsu/Maw-Mod-MMMerge's own
-- BuildStatInformationBox handler, which uses the same hook): Might=0,
-- Intellect=1, Personality=2, Endurance=3, Accuracy=4, Speed=5, Luck=6, HP=7,
-- SP=8, ArmorClass=9, then several MAW-specific indices, MeleeAttack=15,
-- RangedAttack=17. This is the info box's own internal numbering, NOT the
-- same as const.Stats (e.g. const.Stats.MeleeAttack=25, not 15).
--
-- Toggle: Extra Settings -> "Enable Stat Tooltips" (Game.StatTooltipsEnabled,
-- default on). Delete this file to disable entirely.

local LogId = "StatTooltips"
local MF = Merge.Functions
MF.LogInit1(LogId)

local u1, u4 = mem.u1, mem.u4
local allocMM, freeMM = mem.allocMM, mem.freeMM

-- Mirrors StatRemix.lua's Luck damage floor: fraction = min(1, Luck/500),
-- floor = min + (max-min)*fraction on melee/ranged hits (Luck 500 guarantees
-- max damage every hit; spells aren't covered, see StatRemix.lua header).
-- Clamped to >=0 for display: cursed items can push total Luck negative,
-- which would otherwise show a nonsensical negative percentage even though
-- StatRemix.lua itself already no-ops the floor at fraction<=0.
local function LuckDamageFloorText(pl)
    if not Game.StatRemixEnabled then return nil end
    local total = pl.LuckBase + pl.LuckBonus
    local fraction = math.max(0, math.min(1, total / 500))
    return string.format("Stat Remix damage floor: %.1f%% of the way from minimum to maximum roll on melee/ranged hits (Luck %d/500 reaches 100%%)",
        fraction * 100, total)
end

-- Native to-hit formulas, from https://grayface.github.io/mm/mechanics/
-- (Sergey "GrayFace" Rozhenko -- the original MMExtension author's own
-- reverse-engineered reference, not MAW's approximation of it -- MAW's
-- equivalent AC tooltip shows a "damage reduction %" using their own custom
-- damage rework, calcMawDamage(), which this project doesn't have; native AC
-- only affects hit chance, it doesn't reduce damage amount, confirmed by the
-- absence of any AC-based damage reduction in this project's own
-- DamageTweaks.lua/MonstersTweaks.lua).
--   Player hit chance vs monster: (15 + Attack*2 + Bonus - DistancePenalty) / (30 + Attack*2 + MonsterAC)
--   Monster hit chance vs player: (5 + MonsterLevel*2) / (10 + MonsterLevel*2 + PlayerAC)
-- Bonus and DistancePenalty are situational (weapon skill, real-time range to
-- an actual target) and not meaningful for a static character-sheet tooltip,
-- so they're omitted here, same simplification MAW's own tooltip makes. The
-- opposing monster's level/AC isn't known outside actual combat, so these
-- use the player's own level as a stand-in for "a monster of similar level" --
-- an approximation, but using the real native formula rather than a
-- reinterpreted one.
local function ArmorClassHitChanceText(pl)
    local lvl = pl.LevelBase
    local ac = pl:GetArmorClass()
    local hitChance = (5 + lvl * 2) / (10 + lvl * 2 + ac) * 100
    return string.format("Chance to be hit by a same-level monster: %.1f%%", hitChance)
end

local function AttackHitChanceText(getAttack)
    return function(pl)
        local lvl = pl.LevelBase
        local atk = getAttack(pl)
        local hitChance = (15 + atk * 2) / (30 + atk * 2 + lvl) * 100
        return string.format("Chance to hit a same-level monster: %.1f%%", hitChance)
    end
end

-- Curated item bonuses (Scripts/General/ItemSystem.lua) are applied via
-- events.CalcStatBonusByItems which modifies the engine's per-stat t.Result
-- but does NOT update the cached pl.<Stat>Bonus fields that the native
-- Base/Bonus/Total tooltip reads. Instead of showing a separate disclaimer
-- line, we add the curated contribution directly into bonus/total here so
-- the tooltip reflects the actual effective stat totals.
local function GetCuratedBonus(pl, statName)
    if not Game.ItemSystemEnabled or not ItemSystemInternal then return 0 end
    local statId = const.Stats[statName]
    if not statId then return 0 end
    local statAcc, skillAcc = {}, {}
    ItemSystemInternal.SumCuratedBonuses(pl, statAcc, skillAcc)
    return statAcc[statId] or 0
end

local STAT_DATA = {
    [0] = { name = "Might",       desc = "Increases melee damage and melee attack." },
    [1] = { name = "Intellect",   desc = "Increases spell damage and magic skill bonus." },
    [2] = { name = "Personality", desc = "Increases healing, reputation, and merchant prices." },
    [3] = { name = "Endurance",   desc = "Increases hit points per level and endurance bonus." },
    [4] = { name = "Accuracy",    desc = "Increases attack value and ranged damage." },
    [5] = { name = "Speed",       desc = "Increases action speed, AC, and dodge." },
    [6] = { name = "Luck",        desc = "Increases critical hit chance and special effects.", extra = LuckDamageFloorText },
    [9] = { extra = ArmorClassHitChanceText },
    [15] = { extra = AttackHitChanceText(function(pl) return pl:GetMeleeAttack() end) },
    [17] = { extra = AttackHitChanceText(function(pl) return pl:GetRangedAttack() end) },
}

-- build stat description box
mem.hookcall(0x417BA5, 2, 0, function(d, def, headerPtr, textPtr)
    if not Game.StatTooltipsEnabled or Game.CurrentPlayer < 0 then
        return def(headerPtr, textPtr)
    end

    local data = STAT_DATA[u4[d.ebp - 8]]
    if not data then
        return def(headerPtr, textPtr)
    end

    local pl = Party[Game.CurrentPlayer]
    local text = mem.string(textPtr)

    if data.name then
        local base = pl[data.name .. "Base"] or 0
        local bonus = pl[data.name .. "Bonus"] or 0
        local curated = GetCuratedBonus(pl, data.name)
        local total = base + bonus + curated
        text = text .. string.format("\n\nBase: %d  Bonus: %+d  Total: %d\n%s",
            base, bonus + curated, total, data.desc)
    end

    if data.extra then
        local extraText = data.extra(pl)
        if extraText then
            text = text .. "\n\n" .. extraText
        end
    end

    local len = #text
    local newTextPtr = allocMM(len + 1)
    mem.copy(newTextPtr, text)
    u1[newTextPtr + len] = 0

    def(headerPtr, newTextPtr)

    freeMM(newTextPtr)
end)

MF.LogInit2(LogId)
