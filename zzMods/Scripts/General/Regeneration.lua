-- =============================================================================
-- MMMerge Smooth Regeneration — Continuous HP/SP Regen
-- Scripts/General/Regeneration.lua
-- =============================================================================
-- Replaces the native lump-sum-per-minute regen with a smooth per-second
-- system that visually updates every ~100ms real time. Uses the same
-- formulas as MiscTweaks.lua's RegenTick handlers but subdivides the
-- amounts so HP/SP bars visibly rise in real time.
--
-- HOW IT WORKS:
--   events.Tick fires every frame. A real-time guard (timeGetTime) limits
--   regen application to once per 100ms of wall-clock time, so the rate is
--   constant regardless of game speed or frame rate.
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
local timeGetTime = timeGetTime  -- real-time millisecond counter (timers.lua)

local accum = {}  -- fractional HP/SP accumulator, keyed by player pointer
local SUBDIVISIONS = 10
local lastRT = 0  -- last real-time tick in ms (timeGetTime)

-- Applies one tick of regen for all valid party members.
-- Called from events.Tick when at least 100ms of real time has elapsed.
local function RegenTick()
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

-- Hook into the game's frame tick for real-time-based regen.
-- Unlike Timer (which uses Game.Time and scales with game speed),
-- timeGetTime() returns real wall-clock milliseconds, so the rate
-- stays constant regardless of game speed or frame rate.
Game.RegenerationSmooth = (Game.RegenerationSmooth == nil) and true or Game.RegenerationSmooth

function events.Tick()
    -- Gate on the same toggle MiscTweaks' RegenTick handlers check, so the two
    -- systems are mutually exclusive in BOTH states: smooth on -> MiscTweaks
    -- lump-sum returns early and this runs; smooth off -> this returns early and
    -- MiscTweaks' native-style lump-sum runs. Without this gate, turning the
    -- toggle off would run BOTH -> double regen (the original bug).
    if not Game.RegenerationSmooth then return end
    if Game.Paused or Game.MoveToMap.Defined then return end
    local now = timeGetTime()
    if now - lastRT >= 100 then
        lastRT = now
        RegenTick()
    end
end

Log(Merge.Log.Info, "Init finished: %s", LogId)
