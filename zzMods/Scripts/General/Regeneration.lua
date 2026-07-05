-- =============================================================================
-- MMMerge Smooth Regeneration — Continuous HP/SP Regen
-- Scripts/General/Regeneration.lua
-- =============================================================================
-- Replaces the native lump-sum-per-minute regen with a smooth per-second
-- system that visually updates every ~100ms. Uses the same formulas as
-- MiscTweaks.lua's RegenTick handlers but subdivides the amounts so HP/SP
-- bars visibly rise in real time rather than jumping every game-minute.
--
-- HOW IT WORKS:
--   A repeating Timer fires every `const.Second / 10` (~100ms game time).
--   Each tick reads the player's Regeneration and Meditation skills (which
--   already include curated item bonuses via events.GetSkill), calculates
--   the per-tick regen amount using the standard formulas, and applies it.
--   Fractional HP/SP accumulate in an internal buffer so nothing is lost
--   to integer truncation.
-- =============================================================================

local LogId = "Regeneration"
Log(Merge.Log.Info, "Init started: %s", LogId)

local min = math.min
local floor = math.floor

local accum = {}  -- fractional HP/SP accumulator, keyed by player pointer
local INTERVAL
local SUBDIVISIONS = 10
local timerStarted = false

local function RegenTick()
    if Game.Paused or Game.MoveToMap.Defined then return end
    local ok, err = pcall(function()
    if not Party or not Party.count or Party.count < 1 then return end
    for i = 0, Party.count - 1 do
        local ok2, pl = pcall(function() return Party[i] end)
        if not ok2 or not pl then break end

        if pl.Dead == 0 and pl.Eradicated == 0 then
            local ptr = pl["?ptr"]
            if ptr and ptr > 0 then
                local buf = accum[ptr]
                if not buf then
                    buf = { hp = 0, sp = 0 }
                    accum[ptr] = buf
                end

                local cond = pl:GetMainCondition()

                -- HP regen from Regeneration skill (+ spell buff)
                if cond == 18 or cond < 14 then
                    local skill, mas = SplitSkill(pl:GetSkill(const.Skills.Regeneration))
                    local regP = (skill > 0 and 0.5 or 0) + skill / 10 * mas

                    local buff = pl.SpellBuffs[const.PlayerBuff.Regeneration]
                    if buff and buff.ExpireTime > Game.Time then
                        local bs, bm = SplitSkill(buff.Skill)
                        regP = regP + bs / 10 * bm + 0.5
                    end

                    if regP > 0 then
                        buf.hp = buf.hp + pl:GetFullHP() * regP / 100 / SUBDIVISIONS
                        if buf.hp >= 1 then
                            local whole = floor(buf.hp)
                            pl.HP = min(pl.HP + whole, pl:GetFullHP())
                            buf.hp = buf.hp - whole
                        end
                    end
                end

                -- SP regen from Meditation skill
                if cond == 18 or cond == 17 or cond < 14 then
                    local skill, mas = SplitSkill(pl:GetSkill(const.Skills.Meditation))
                    if mas > 0 then
                        buf.sp = buf.sp + (mas + floor(skill / 10)) / SUBDIVISIONS
                        if buf.sp >= 1 then
                            local whole = floor(buf.sp)
                            pl.SP = min(pl.SP + whole, pl:GetFullSP())
                            buf.sp = buf.sp - whole
                        end
                    end
                end

            end
        end
    end
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: RegenTick error: %s", LogId, tostring(err))
    end

end

-- Override native RegenTick to prevent double-application from
-- MiscTweaks.lua and ExtraArtifacts.lua. Our smooth timer is the
-- exclusive handler for skill-based HP/SP regeneration.
function events.RegenTick() end

function events.AfterLoadMap()
    if not timerStarted then
        timerStarted = true
        INTERVAL = floor(const.Second / 10)
        Timer(RegenTick, INTERVAL, true)
        Log(Merge.Log.Info, "%s: active (interval=%d ticks, ~%dms)", LogId, INTERVAL, floor(INTERVAL / const.Second * 1000))
    end
end

Log(Merge.Log.Info, "Init finished: %s", LogId)
