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

MF.LogInit2(LogId)
