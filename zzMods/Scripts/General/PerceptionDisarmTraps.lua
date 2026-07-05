-- Merges Disarm Traps (skill 31) into Perception (skill 29): whenever
-- native code asks for a player's Disarm Traps skill, it gets their
-- Perception skill instead, the same events.GetSkill redirect pattern
-- ManaShield.lua uses to tie Identify Monster to spell schools. Perception
-- itself is untouched -- its own existing uses (secret doors, treasure,
-- trap-damage reduction) are unaffected, since those all read
-- Player.Skills[Perception] directly, not through a Disarm-Traps query.
--
-- Frees skill slot 31 entirely -- nothing currently occupies it. Whatever
-- goes there next (a new trainable skill) will need its own decision on
-- how to avoid the ManaShield.lua situation (a GetSkill hook for a new
-- skill on this slot can't also serve a redirect purpose without the same
-- "which caller is asking" ambiguity already documented there).
--
-- UNVERIFIED, worth checking live: this catches any native code that reads
-- Disarm Traps through the same hooked function Cleave/Guardian/ManaShield/
-- Retaliation's own mastery-sync hooks use (proven to work for them). It's
-- less certain whether a scripted map event checking DisarmTrapsSkill via
-- evt.Cmp/evt.VarNum (a different, map-.evt-level pathway, not Player.Skills
-- read directly) goes through the same hook -- if some specific map's trap
-- puzzle behaves oddly, that's the mechanism to look at.

local LogId = "PerceptionDisarmTraps"
local MF = Merge.Functions
MF.LogInit1(LogId)

function events.GetSkill(t)
    if t.Skill ~= const.Skills.DisarmTraps or not t.Player then return end
    t.Result = t.Player.Skills[const.Skills.Perception]
end

MF.LogInit2(LogId)
