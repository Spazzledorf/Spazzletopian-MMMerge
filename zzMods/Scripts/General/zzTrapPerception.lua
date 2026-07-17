-- zzTrapPerception.lua
-- Chest trap checks use the party's highest Perception skill
-- (Disarm Traps is merged into Perception, so the best spotter
-- disarms for everyone).
-- Toggle: Game.TrapPerceptionEnabled via MenuExtraSettings.

Game.TrapPerceptionEnabled = (Game.TrapPerceptionEnabled == nil) and true or Game.TrapPerceptionEnabled

function events.GetDisarmTrapTotalSkill(t)
    if not Game.TrapPerceptionEnabled then return end
    local best = 0
    for i = 0, Party.High do
        local pl = Party[i]
        if pl and pl:IsConscious() then
            local raw = pl.Skills[const.Skills.Perception]
            if raw and raw > best then
                best = raw
            end
        end
    end
    if best > 0 then
        t.Result = best
    end
end
