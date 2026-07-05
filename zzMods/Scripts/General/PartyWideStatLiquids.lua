-- Party-Wide Stat Liquids: dungeon barrels/pedestals (Might, Intellect,
-- Personality, Endurance, Speed, Accuracy, Luck) and cauldrons (Fire, Air,
-- Water, Earth resistance) normally grant their +2 bonus only to whichever
-- character opens/drinks them. When this is enabled, the bonus is instead
-- applied to every member of the party.
--
-- Toggle: Extra Settings -> Cleave & Skills -> "Party-Wide Stat Liquids"
-- (Game.PartyLiquidsEnabled, default true -- turn off to restore vanilla
-- single-character behavior; the barrel/cauldron is still consumed either way).
--
-- The vanilla barrel/cauldron handlers live in
-- Scripts/Structs/After/GlobalEventsNewHandler.lua and call out to
-- Merge.Functions.GrantLiquidStat() below instead of granting the stat
-- directly, so this file is the single place that owns the toggle behavior.
-- Delete this file (and the calls to GrantLiquidStat in
-- GlobalEventsNewHandler.lua) to remove the feature entirely.

local LogId = "PartyWideStatLiquids"
local MF = Merge.Functions
MF.LogInit1(LogId)

function MF.GrantLiquidStat(StatVar, Amount)
	if Game.PartyLiquidsEnabled then
		evt.ForPlayer("All").Add{StatVar, Amount}
	else
		evt.ForPlayer("Current").Add{StatVar, Amount}
	end
end

MF.LogInit2(LogId)
