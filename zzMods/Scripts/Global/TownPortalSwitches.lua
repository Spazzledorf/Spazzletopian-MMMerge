
local JadamMaps		= {}
local AntagrichMaps	= {207}
local EnrothMaps	= {}
local MapsExtra = Game.Bolster.MapsSource

local function IsJadam(i)
	return (i >= 0 and i <= 61) or table.find(JadamMaps, i)
end

local function IsAntagrich(i)
	return (i >= 62 and i <= 136) or table.find(AntagrichMaps, i)
end

local function IsEnroth(i)
	return (i >= 137 and i <= 203) or table.find(EnrothMaps, i)
end

function TownPortalControls.MapOfContinent(Map)

	local MapId

	if type(Map) == "string" then
		for i,v in Game.MapStats do
			if v.FileName == Map then
				MapId = i
				break
			end
		end
	elseif type(Map) == "number" then
		MapId = Map
	else
		return TownPortalControls.GetCurrentSwitch()
	end

	if not MapId then
		return TownPortalControls.GetCurrentSwitch()
	end

	if MapsExtra[MapId] and MapsExtra[MapId].Continent then
		return MapsExtra[MapId].Continent
	elseif 	IsJadam(MapId) 		then return 1
	elseif 	IsAntagrich(MapId) 	then return 2
	elseif 	IsEnroth(MapId) 	then return 3
	end

end

function TownPortalControls.CheckSwitch()

	local i = Map.MapStatsIndex
	local SwitchTo = TownPortalControls.SwitchTo

	if MapsExtra[i] and MapsExtra[i].Continent then
		SwitchTo(MapsExtra[i].Continent)
	elseif 	IsJadam(i) 			then SwitchTo(1)
	elseif 	IsAntagrich(i) 		then SwitchTo(2)
	elseif 	IsEnroth(i) 		then SwitchTo(3)
	end

end

function TownPortalControls.IsArena()
	return Map.Name == "d42.blv" or Map.Name == "7d05.blv" or Map.Name == "zarena.blv"
end

-- Real-time grace window (not Game.Time -- that can stall in menus, and
-- frame count isn't safe either since FrameLimit is user-configurable up to
-- 360fps, see MenuExtraSettings.lua) between attempting a cast and giving up
-- on ever reaching the destination-choice screen. os.time() debouncing is
-- the established pattern in this project (see NPCMercenaries.lua's
-- LastDismissClick).
local CAST_GRACE_SECONDS = 2
local pendingCastTime = nil

function events.CanCastTownPortal(t)
	if TownPortalControls.AutoCasting then
		TownPortalControls.AutoCasting = nil
		return
	end
	t.Handled = true
	TownPortalControls.SelectingContinent = true
	pendingCastTime = os.time()
end

local function redirectToContinent()
	if TownPortalControls.SelectingContinent then
		local s = Game.CurrentScreen or 0
		if s ~= 97 then
			Game.CurrentScreen = 97
			pendingCastTime = nil
		end
	end
end

-- Deferred recast: after picking a continent, re-cast Town Portal on the next
-- interface-update tick rather than synchronously from inside the CustomUI
-- click handler (see AGENTS.md Follow-up 9). Doing it inline from a nested UI
-- callback skipped native cast setup and caused crashes; deferring to a clean
-- frame boundary fixed teleport reliability. The null-font crash that used to
-- follow this (and Escape-cancel) is fixed separately by the 0x4D1227 draw
-- guard in 1_TownPortalSwitch.lua -- so no Escape intercept is needed here.
local function processPendingRecast()
	if TownPortalControls.PendingRecast then
		TownPortalControls.PendingRecast = nil
		TownPortalControls.AutoCasting = true
		CastSpellDirect(31, 10, 4)
	end
end

function events.L2InterfaceUpd()
	redirectToContinent()
	processPendingRecast()
end

function events.CanCastLloyd(t)
	if TownPortalControls.IsArena() then
		t.Result = false
	end
end

function events.CanSaveGame(t)
	if TownPortalControls.IsArena() then
		t.Result = false
	end
end

function events.TownPortalDestinationName(t)
	local Set = TownPortalControls.Sets and TownPortalControls.Sets[t.Switch]
	local Dest = Set and Set[t.Slot + 1]
	if Dest then
		t.NamePtr = mem.topointer(Dest.Desc)
	end
end
