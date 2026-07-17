--~ Town Portal Switcher script for Might and Magic 6, 7 and 8, release 10.12.2016
--~ Put this script into your ...Scripts/GENERAL folder.
--~ Use TownPortalSwitch.txt following this scipt instead of Town Portal.txt
--~ Leave any questions at http://www.celestialheavens.com/forum/10/10423
--~ This script require MMExtension 2.1 by Grayface
--~ - Rod

---- Variables ----

TownPortalControls = TownPortalControls or {}

local DefAdrTable = {}

if Game.Version == 8 then

	DefAdrTable[1] = {Map = 0x4fca98, X = 0x4fca88, Y = 0x4fca8c, Z = 0x4fca90, Dir = 0x4fca94, LA = 0x4fca96, IN = 0x50267c, IX = 0x501bc8, IY = 0x501bd4, QBI = 181, Desc = 0x4d12be}
	DefAdrTable[2] = {Map = 0x4FCAAC, X = 0x4fca9c, Y = 0x4fcaa0, Z = 0x4fcaa4, Dir = 0x4fcaa8, LA = 0x4fcaaa, IN = 0x502688, IX = 0x501bca, IY = 0x501bd6, QBI = 180, Desc = 0x4d12b7}
	DefAdrTable[3] = {Map = 0x4fcac0, X = 0x4fcab0, Y = 0x4fcab4, Z = 0x4fcab8, Dir = 0x4fcabc, LA = 0x4fcabe, IN = 0x502690, IX = 0x501bcc, IY = 0x501bd8, QBI = 184, Desc = 0x4d12b0}
	DefAdrTable[4] = {Map = 0x4fcad4, X = 0x4fcac4, Y = 0x4fcac8, Z = 0x4fcacc, Dir = 0x4fcad0, LA = 0x4fcab6, IN = 0x50269c, IX = 0x501bce, IY = 0x501bda, QBI = 183, Desc = 0x4d12a9}
	DefAdrTable[5] = {Map = 0x4fcae8, X = 0x4fcad8, Y = 0x4fcadc, Z = 0x4fcae0, Dir = 0x4fcae4, LA = 0x4fcad2, IN = 0x5026a8, IX = 0x501bd0, IY = 0x501bdc, QBI = 182, Desc = 0x4d12a2}
	DefAdrTable[6] = {Map = 0x4fcafc, X = 0x4fcaec, Y = 0x4fcaf0, Z = 0x4fcaf4, Dir = 0x4fcaf8, LA = 0x4fcae6, IN = 0x5026b4, IX = 0x501bd2, IY = 0x501bde, QBI = 185, Desc = 0x4d129b}
	DefAdrTable.TPScreen = 0x5026bc

elseif Game.Version == 7 then

	DefAdrTable[1] = {IN = 0x4e26d0, QBI = 206, Desc = 0x433a9a}
	DefAdrTable[2] = {IN = 0x4e26c8, QBI = 208, Desc = 0x433a93}
	DefAdrTable[3] = {IN = 0x4e26bc, QBI = 207, Desc = 0x433a8c}
	DefAdrTable[4] = {IN = 0x4e26b0, QBI = 211, Desc = 0x433a85}
	DefAdrTable[5] = {IN = 0x4e26a4, QBI = 209, Desc = 0x433a7e}
	DefAdrTable[6] = {IN = 0x4e269c, QBI = 210, Desc = 0x433a77}
	DefAdrTable.TPScreen = 0x4e26dc

elseif Game.Version == 6 then

	DefAdrTable[1] = {IN = nil, QBI = nil, Desc = 0x42e52e, DescReg = "eax"}
	DefAdrTable[2] = {IN = nil, QBI = nil, Desc = 0x42e518, DescReg = "edx"}
	DefAdrTable[3] = {IN = nil, QBI = nil, Desc = 0x42e4e9, DescReg = "eax"}
	DefAdrTable[4] = {IN = nil, QBI = nil, Desc = 0x42e4d3, DescReg = "edx"}
	DefAdrTable[5] = {IN = nil, QBI = nil, Desc = 0x42e500, DescReg = "ecx"}
	DefAdrTable[6] = {IN = nil, QBI = nil, Desc = 0x42e545, DescReg = "ecx"}
	DefAdrTable.TPScreen = 0x4bcc14

end

local TPSets = {}
local CurrentSwitch = 1

---- Init functions ----

local function ProcessTPTable()

	local TPTable = io.open("Data/Tables/TownPortalSwitch.txt")

	if not TPTable then
		return false
	end

	local TPn = 0
	local TPmapn = 0
	local TabMap = {Map = 2, X = 3, Y = 4, Z = 5, Dir = 6, LA = 7, IX = 9, IY = 10, IW = 11, IH = 12, QBI = 13}
	for line in TPTable:lines() do
		if string.sub(line, 1, 1) == "@" then
			local TPScreenInfo = string.split(line, "\9")
			TPn = TPn + 1
			TPSets[TPn] = {}
			TPSets[TPn].TPScreen = TPScreenInfo[2]
			TPSets[TPn].SwitchBit = tonumber(TPScreenInfo[3])
			TPmapn = 1
		elseif TPn ~= 0 then
			local TPSet = string.split(line, "\9")

			TPSets[TPn][TPmapn] = {}

			for k,v in pairs(TabMap) do
				TPSets[TPn][TPmapn][k] = tonumber(TPSet[v])
			end

			TPSets[TPn][TPmapn].IN 	= TPSet[8]
			if TPSets[TPn][TPmapn].Map == 0 then
				if string.len(TPSet[14]) > 0 then
					TPSets[TPn][TPmapn].Desc = TPSet[14]
				else
					TPSets[TPn][TPmapn].Desc = " "
				end
			else
				TPSets[TPn][TPmapn].Desc = Game.MapStats[TPSets[TPn][TPmapn].Map].Name
			end
			TPSets[TPn][TPmapn].DescAdr = mem.topointer(TPSets[TPn][TPmapn].Desc)
			TPmapn = TPmapn + 1
		end
	end
	io.close(TPTable)

	return true

end

local function SwitchTo(Si)

	if Si == nil then
		return "Switch is not defined."
	elseif type(Si) == "string" then
		for i = 1, table.getn(TPSets) do
			if TPSets[i].TPScreen == Si then
				Si = i
				break
			end
		end
		if type(Si) == "string" then
			return "Incorrect switch name."
		end
	elseif type(Si) == "number" then
		if Si > table.getn(TPSets) then
			return "Incorrect switch index."
		end
	else return "Incorrect type of switch value."
	end

	local function SetPicName(dest, name)
		mem.u1[dest - 1] = 0x0
		mem.copy(dest, name, #name)
		mem.u1[dest + #name] = 0x0
	end

	-- Put current TP qbits into storage.
	-- cthscr: don't do it, QBits should be set by maps
	--[[
	if Game.Version > 6 then
		for i = 1, #TPSets[CurrentSwitch] do
			Party.QBits[TPSets[CurrentSwitch][i].QBI] = Party.QBits[DefAdrTable[i].QBI]
		end
	end
	]]
	-- ~cthscr

	-- Set new TP settings.

	for i = 1, #TPSets do
		Party.QBits[TPSets[i].SwitchBit] = i == Si
	end

	SetPicName(DefAdrTable.TPScreen, TPSets[Si].TPScreen)

	local CurSet = TPSets[Si]
	mem.IgnoreProtection(true)
	for i = 1, #CurSet do

		if Game.Version > 6 then
			Party.QBits[DefAdrTable[i].QBI] = Party.QBits[CurSet[i].QBI]
		end

		Game.TownPortalInfo[i-1].MapStatsIndex = CurSet[i].Map
		Game.TownPortalInfo[i-1].X = CurSet[i].X
		Game.TownPortalInfo[i-1].Y = CurSet[i].Y
		Game.TownPortalInfo[i-1].Z = CurSet[i].Z
		Game.TownPortalInfo[i-1].Direction = CurSet[i].Dir
		Game.TownPortalInfo[i-1].LookAngle = CurSet[i].LA

		Game.TownPortalX[i-1] = CurSet[i].IX
		Game.TownPortalY[i-1] = CurSet[i].IY

		if Game.Version < 8 then
			Game.TownPortalWidth[i-1]	= CurSet[i].IW
			Game.TownPortalHeight[i-1]	= CurSet[i].IH
		end

		if Game.Version > 6 then
			SetPicName(DefAdrTable[i].IN, CurSet[i].IN)
		end
	end
	mem.IgnoreProtection(false)

	-- Clear excess qbits in case, current TP have less than 6 points to travel.

	if Game.Version > 6 then
		if #CurSet < 6 then
			for i = #CurSet - 1, 6 do
				Party.QBits[DefAdrTable[i].QBI] = false
			end
		end
	end

	-- Always-unlocked gateway destinations (starting places of each game)
	-- These slots are visible regardless of whether the player has visited
	-- the destination normally, enabling cross-continent TP early.

	if Game.Version > 6 then
		local GatewaySlots = {
			[1] = 6,  -- Jadame: slot 6 → Daggerwound islands
			[2] = 1,  -- Antagarich: slot 1 → Castle Harmondale
			[3] = 4,  -- Enroth: slot 4 → New Sorpigal
		}
		if GatewaySlots[Si] then
			Party.QBits[DefAdrTable[GatewaySlots[Si]].QBI] = true
		end
	end

	-- Setting CurrentSwitch - index and qbits

	CurrentSwitch = Si

end

local function GetCurrentSwitch()
	for i = 1, #TPSets do
		if Party.QBits[TPSets[i].SwitchBit] then
			CurrentSwitch = i
			return CurrentSwitch
		end
	end
	CurrentSwitch = CurrentSwitch or 1
	Party.QBits[TPSets[CurrentSwitch].SwitchBit] = true
	return CurrentSwitch
end

---- Initialization ----

function events.GameInitialized2()

	if not ProcessTPTable() then
		return
	end

	if Game.Version == 8 then
		-- Confirmed via ErrorLog.txt bisection (AGENTS.md) that this hook is
		-- NOT the source of the MM8.exe+449C3B crash -- disabling it entirely
		-- produced an identical crash. Kept null-guarded (rather than the
		-- original bare passthrough) since that's strictly safer and free.
		local FallbackNamePtr = mem.topointer(" ")
		mem.autohook(0x4d12c8, function(d)
			local t = {
				NamePtr = d.eax,
				Slot = mem.u4[0x1006130],
				Switch = CurrentSwitch}

			events.Call("TownPortalDestinationName", t)
			d.eax = (t.NamePtr ~= 0 and t.NamePtr) or FallbackNamePtr
		end)
		-- ROOT-CAUSE FIX for the Escape/intermittent-teleport crash (see
		-- AGENTS.md Follow-up 16 for the full disassembly-based diagnosis).
		--
		-- The crash was NEVER in the shared text classifier at 0x449C3B (the
		-- three asmpatch attempts there were all wrong -- do NOT retry them).
		-- The classifier merely dereferenced a NULL *font* pointer. The TP
		-- destination screen is drawn like a spellbook and uses book2.fnt,
		-- held in the global at 0x5DB920. That font is loaded/freed as a
		-- group with book.fnt (0x5DB924) and autonote.fnt (0x5DB910) by the
		-- spellbook UI. Pressing Escape (or reaching this screen via our
		-- synthetic CastSpellDirect recast) can leave the TP draw routine
		-- running for a frame while book2.fnt is NULL -> the native text draw
		-- dereferences [font+0], [font+1], [font+5]... -> access violation
		-- (this is exactly why patching one deref just moved the crash to the
		-- next: crash #1 at 0x449C3B reading 0x0, crash #2 at 0x44AB7A
		-- reading 0x5 == [font+5]).
		--
		-- The TP screen draw is a self-contained, TP-specific cdecl function
		-- at 0x4D1227 (it reads the TP slot global 0x1006130 and dispatches
		-- the 6 destination slots; it is NOT shared with other screens). It
		-- draws the "Town Portal" title (font from 0x5DB920) then the
		-- highlighted destination name (font from 0x5DB920 again at 0x4D12C8)
		-- -- both use the same null-when-freed font. Guarding just one draw
		-- is insufficient; guard the whole function.
		--
		-- Fix: hook the function entry; if book2.fnt is null, skip the entire
		-- draw for that frame (emulate the function's clean cdecl `ret`)
		-- rather than letting native code dereference the null font. When the
		-- font is loaded (the normal case, including every working teleport),
		-- this is a pure pass-through -- zero behavior change. This uses
		-- mem.autohook (safe trampoline, preserves the original prologue via
		-- MyCopyCode) on a TP-only function, so unlike the 0x449C3B asmpatch
		-- attempts it cannot affect text rendering anywhere else in the game.
		local Book2FontPtr = 0x5DB920  -- global holding the spellbook font
		mem.autohook(0x4D1227, function(d)
			if mem.u4[Book2FontPtr] ~= 0 then
				return  -- font loaded: draw the TP screen normally
			end
			-- book2.fnt is NULL (freed, e.g. mid-Escape teardown): skip the
			-- whole draw by returning immediately to the caller. The function
			-- is cdecl/no-args (bare `ret` at 0x4D12E6), reached via `call`,
			-- so [esp] is the return address at this entry point.
			local retaddr = mem.u4[d.esp]
			d.esp = d.esp + 4
			d:push(retaddr)
			return true  -- suppress autohook's jump into the original body
		end)
	end

	TownPortalControls.Sets = TPSets
	TownPortalControls.SwitchTo = SwitchTo
	TownPortalControls.GetCurrentSwitch = GetCurrentSwitch

	function events.BeforeLoadMap(WasInGame)
	   if not WasInGame then
		  TownPortalControls.SwitchTo(TownPortalControls.GetCurrentSwitch())
	   else
		  TownPortalControls.CheckSwitch()
	   end
	end

end
