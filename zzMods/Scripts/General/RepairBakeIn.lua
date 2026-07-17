-- Bakes in Repair Item (skill 26) as always-succeeding, the same pattern
-- Guardian.lua uses for Identify Item -- events.CanRepairItem is this
-- project's own already-installed hook (Scripts/General/ExtraEvents.lua),
-- writable t.CanRepair. No other Lua-visible gameplay effect found for this
-- skill beyond that pass/fail check.
--
-- Frees skill slot 26 entirely -- nothing currently occupies it.

local LogId = "RepairBakeIn"
local MF = Merge.Functions
MF.LogInit1(LogId)

function events.CanRepairItem(t)
    t.CanRepair = true
end

-- Remove Repair from all learn dialogs — it always succeeds regardless of skill
function events.PopulateLearnSkillsDialog(t)
    for i = #t.Result, 1, -1 do
        if t.Result[i] == const.Skills.Repair or t.Result[i] == const.Skills.RepairItem then
            table.remove(t.Result, i)
        end
    end
end

MF.LogInit2(LogId)
