
BountyHuntFunctions = {}

local BountyText = ""
local random = math.random

-- Adjectives for bounty monster titles
local BOUNTY_ADJECTIVES = { "Dire", "Feral", "Massive", "Ancient", "Vicious", "Savage", "Rampant", "Shadow" }

-- PlaceMonTxt dimensions (MM7/MM8)
-- Start scan at a safe offset to avoid overwriting PlaceMon.txt entries.
local PLACEMON_ADDR
local PLACEMON_COUNT
local PLACEMON_START
if mmver == 8 then
	PLACEMON_ADDR = 0x5EF9B0
	PLACEMON_COUNT = 131
	PLACEMON_START = 100
elseif mmver == 7 then
	PLACEMON_ADDR = 0x5D27D8
	PLACEMON_COUNT = 31
	PLACEMON_START = 1
else
	PLACEMON_ADDR = 0
	PLACEMON_COUNT = 0
	PLACEMON_START = 0
end

-- =============================================================================
-- EXISTING FUNCTIONS (preserved)
-- =============================================================================

local function RewardByMon(MonId)
	return Game.MonstersTxt[MonId].Level * 100
end

local function HuntText(MonId)
	local text = Game.NPCText[133]:replace("%lu", tostring(RewardByMon(MonId)))
	return text:format(StrColor(255,255,150, Game.MonstersTxt[MonId].Name))
end
BountyHuntFunctions.HuntText = HuntText

local function RewardText(MonId)
	local Reward = RewardByMon(MonId)
	local text = Game.NPCText[134]:replace("%lu", Reward)
	return text:format(Game.MonstersTxt[MonId].Name, Reward)
end
BountyHuntFunctions.RewardText = RewardText

local function ClaimedText()
	return Game.NPCText[135]
end
BountyHuntFunctions.ClaimedText = ClaimedText

local function NewEntry(Month, MonId, Done, Claimed)
	return {
		Month = Month or 0,
		MonId = MonId or 0,
		Done = Done or false,
		Claimed = Claimed or false
	}
end
BountyHuntFunctions.NewEntry = NewEntry

local function BountyExpired(Entry)
	return not (Entry and Game.Month == Entry.Month)
end
BountyHuntFunctions.BountyExpired = BountyExpired

local function AddBountyHuntReward(Gold, NoGold)
	evt.ForPlayer("Current")

	if not NoGold then
		evt.Add{"Gold", Gold}
	end
	evt.Add{"MontersHunted", Gold}
	evt.Subtract{"Reputation", math.ceil(Gold/2000)}
end
BountyHuntFunctions.AddBountyHuntReward = AddBountyHuntReward

-- =============================================================================
-- NEW: Region-appropriate monster selection
-- Scans the current map's actual monster spawns for eligible types, then falls
-- back to the global MonstersTxt filter if the map has no eligible matches.
-- =============================================================================

local function MonstersForBountyHunt()
	local avgLevel = (Party[0] and Party[0].LevelBase) or 1

	local seen, mapMons = {}, {}

	-- Collect map-native monsters (no pcall — individual nil guards prevent errors)
	if Map and Map.Monsters then
		for i, mon in Map.Monsters do
			if mon and mon.Id and mon.Id > 0 then
				local id = tonumber(mon.Id)
				if id and not seen[id] then
					seen[id] = true
					local def = Game.MonstersTxt[id]
					if def and def.Level and Game.IsMonsterOfKind
					and Game.IsMonsterOfKind(id, const.MonsterKind.NoArena) ~= 1 then
						mapMons[#mapMons + 1] = { id = id, level = def.Level }
					end
				end
			end
		end
	end

	-- If map has monsters, pick from the upper tier (toughest native species)
	if #mapMons > 0 then
		table.sort(mapMons, function(a, b) return a.level > b.level end)
		local topCount = math.max(1, math.ceil(#mapMons * 0.5))
		local result = {}
		for i = 1, topCount do
			result[#result + 1] = mapMons[i].id
		end
		return result
	end

	-- Fallback: region-agnostic, use tight level cap to avoid cross-region picks
	local maxLevel = avgLevel + 5
	local list = {}
	for i, v in Game.MonstersTxt do
		if type(i) == "number" and v and v.Level and v.Level <= maxLevel
		and Game.IsMonsterOfKind
		and Game.IsMonsterOfKind(i, const.MonsterKind.NoArena) ~= 1 then
			list[#list + 1] = i
		end
	end

	-- If too restrictive, widen search so we never return empty
	if #list == 0 and maxLevel < avgLevel + 20 then
		maxLevel = avgLevel + 20
		for i, v in Game.MonstersTxt do
			if type(i) == "number" and v and v.Level and v.Level <= maxLevel
			and Game.IsMonsterOfKind
			and Game.IsMonsterOfKind(i, const.MonsterKind.NoArena) ~= 1 then
				list[#list + 1] = i
			end
		end
	end

	return list
end
BountyHuntFunctions.MonstersForBountyHunt = MonstersForBountyHunt

-- =============================================================================
-- NEW: Bounty monster title e.g. "Dire Wolf of Harmondale"
-- =============================================================================

local function BountyTitle(MonId)
	local adj = BOUNTY_ADJECTIVES[random(1, #BOUNTY_ADJECTIVES)]
	return adj .. " " .. Game.MonstersTxt[MonId].Name .. " of " .. Map.Name
end

-- =============================================================================
-- NEW: Custom name via PlaceMonTxt (MM7/MM8) or direct Name field (MM6)
-- =============================================================================

local function CleanupBountyName(MapName)
	local slot = vars.BountyNameSlots and vars.BountyNameSlots[MapName]
	if slot ~= nil and PLACEMON_ADDR then
		local ptr = mem.u4[PLACEMON_ADDR + slot * 4]
		if ptr and ptr > 0 then
			mem.freeMM(ptr)
		end
		mem.u4[PLACEMON_ADDR + slot * 4] = 0
		vars.BountyNameSlots[MapName] = nil
	end
end

local function ApplyBountyName(mon, MonId)
	local ok, result = pcall(function()
		local title = BountyTitle(MonId) .. string.char(0)
		local len = #title

		if mmver == 6 then
			mon.Name = title
			return
		end

		-- MM7/MM8: find empty PlaceMonTxt slot
		vars.BountyNameSlots = vars.BountyNameSlots or {}
		CleanupBountyName(Map.Name)

		for slot = PLACEMON_START, PLACEMON_COUNT - 1 do
			local ptr = mem.u4[PLACEMON_ADDR + slot * 4]
			if ptr == 0 then
				local allocPtr = mem.allocMM(len)
				mem.copy(allocPtr, title)
				mem.u4[PLACEMON_ADDR + slot * 4] = allocPtr
				vars.BountyNameSlots[Map.Name] = slot
				mon.NameId = slot
				return
			end
		end
	end)
	if not ok then
		Log(Merge.Log.Warning, "BountyHunt: ApplyBountyName failed: %s", tostring(result))
	end
end

-- =============================================================================
-- NEW: Visual glow effect on summoned bounty monster
-- Uses DayOfProtection buff for a visible golden shimmer.
-- =============================================================================

local function ApplyBountyGlow(mon)
	local ok = pcall(function()
		local buff = mon.SpellBuffs[const.MonsterBuff.DayOfProtection]
		if not buff then
			buff = {}
			mon.SpellBuffs[const.MonsterBuff.DayOfProtection] = buff
		end
		buff.ExpireTime = Game.Time + const.Month
		buff.Power = 4
		buff.Skill = 4
		buff.Caster = 49
	end)
	if not ok then
		Log(Merge.Log.Warning, "BountyHunt: ApplyBountyGlow failed")
	end
end

-- =============================================================================
-- NEW: Autonote + map note
-- =============================================================================

local AUTONOTE_CATEGORY = 1

local function AddBountyNotes(MonId, X, Y, Reward)
	local monName = Game.MonstersTxt[MonId].Name
	local title = BountyTitle(MonId)
	local monthEnd = Game.Month

	local noteText = string.format("Bounty Hunt — %s\nTarget: %s\nReward: %d gold\nActive until end of month %d",
		Map.Name, title, Reward, monthEnd)

	-- Create or update named autonote
	local autoName = "BountyHunt:" .. Map.Name
	pcall(function()
		vars.Autonotes = vars.Autonotes or {}
		if not vars.Autonotes[autoName] then
			Autonote(autoName, AUTONOTE_CATEGORY, noteText)
		else
			local t = FindAutonote(autoName, false)
			if t then
				Game.AutonoteTxt[t.AutonoteIndex] = noteText
			end
		end
		AddAutonote(autoName)
	end)

	-- Add map note
	pcall(function()
		local noteId = 9000
		for i, v in Map.Notes do
			if v.Id == noteId then
				v.Active = true
				v.Text = title
				v.X = X
				v.Y = Y
				return
			end
		end
		for i, v in Map.Notes do
			if not v.Active and v.Id == 0 then
				v.X = X
				v.Y = Y
				v.Text = title
				v.Active = true
				v.Id = noteId
				return
			end
		end
	end)
end

local function ClearBountyNotes(MapName)
	local autoName = "BountyHunt:" .. MapName
	pcall(function()
		if vars.Autonotes then
			vars.Autonotes[autoName] = nil
		end
	end)
	pcall(function()
		for i, v in Map.Notes do
			if v.Id == 9000 and v.Active then
				v.Active = false
				return
			end
		end
	end)
end

-- =============================================================================
-- EXISTING: Spawn point (unchanged)
-- =============================================================================

local function NewBHSpawnPoint()
	local function default_random()
		return random(-15000, 15000), random(-15000, 15000), 1000
	end

	local FacetIds, X, Y, Z
	local append = table.insert
	if Map.IsIndoor() and Map.Facets.count > 0 then
		local Facet, RoomsWFloors, RoomsWWalls = nil, {}, {}
		for i, Room in Map.Rooms do
			if Room.Floors.count > 0 then
				append(RoomsWFloors, Room)
			end
			if Room.Walls.count > 0 then
				append(RoomsWWalls, Room)
			end
		end

		if #RoomsWFloors > 0 then
			FacetIds = RoomsWFloors[random(1, #RoomsWFloors)].Floors
		elseif #RoomsWWalls > 0 then
			FacetIds = RoomsWWalls[random(1, #RoomsWFloors)].Walls
		else
			return default_random()
		end

		Facet = Map.Facets[FacetIds[random(FacetIds.count-1)]]
		return Facet.MinX + (Facet.MaxX - Facet.MinX)/2, Facet.MinY + (Facet.MaxY - Facet.MinY)/2, Facet.MaxZ

	elseif Map.IsOutdoor() then
		X, Y, Z = default_random()

		local Tile = Game.CurrentTileBin[Map.TileMap[(64 - Y / 0x200):floor()][(64 + X / 0x200):floor()]]
		local Cnt = 5
		while Cnt > 0 do
			if not Tile.Water then
				break
			end
			X, Y, Z = default_random()
			Tile = Game.CurrentTileBin[Map.TileMap[(64 - Y / 0x200):floor()][(64 + X / 0x200):floor()]]
			Cnt = Cnt - 1
		end
	else
		X, Y, Z = default_random()
	end
	return X, Y, Z
end
BountyHuntFunctions.NewBHSpawnPoint = NewBHSpawnPoint

-- =============================================================================
-- EXISTING: SetCurrentHunt (modified — new summon + reward flow)
-- =============================================================================

local function SetCurrentHunt()
	local ok, result = pcall(function()
		vars.BountyHunt = vars.BountyHunt or {}

		local BountyText, MonId
		local Entry = vars.BountyHunt[Map.Name]

		if not BountyExpired(Entry) then
			MonId = Entry.MonId
			if not MonId then
				vars.BountyHunt[Map.Name] = nil
				return BountyHuntFunctions.SetCurrentHunt()
			end

			if Entry.Done then
				if Entry.Claimed then
					BountyText = ClaimedText()
				else
					local Reward = RewardByMon(MonId)
					BountyText = RewardText(MonId)

					for i,v in Party do
						v.Awards[44] = true
					end

					AddBountyHuntReward(Reward)
					Entry.Claimed = true

					-- Claim notification
					Game.ShowStatusText(string.format("Bounty complete! +%d gold.", Reward))

					events.Call("BountyHuntRewardClaimed", Map.Name, Reward)
				end
			else
				BountyText = HuntText(MonId)
			end

		else
			local Mons = BountyHuntFunctions.MonstersForBountyHunt()
			if #Mons == 0 then
				return "No suitable bounty targets available in this area."
			end

			local t = {MapName = Map.Name, Handled = false}
			t.Entry = NewEntry(Game.Month, Mons[random(1, #Mons)], false, false)
			events.Call("BountyHuntGeneration", t)

			vars.BountyHunt[Map.Name] = t.Entry
			if t.Handled then
				return t.Text or HuntText(t.Entry.MonId)
			end

			MonId = t.Entry.MonId
			local X, Y, Z = BountyHuntFunctions.NewBHSpawnPoint()
			local mon = SummonMonster(MonId, X, Y, Z)
			mon.Group = 39
			mon.Hostile = true
			mon.ShowAsHostile = true
			mon.HostileType = 4

			-- Apply visual glow
			ApplyBountyGlow(mon)

			-- Apply custom name
			ApplyBountyName(mon, MonId)

			-- Create autonote + map note
			AddBountyNotes(MonId, X, Y, RewardByMon(MonId))

			events.Call("NewBountyHuntCreated", Map.Name, vars.BountyHunt[Map.Name], mon)
			BountyText = HuntText(MonId)
		end

		return BountyText
	end)
	if ok then
		return result
	else
		Log(Merge.Log.Error, "BountyHunt: SetCurrentHunt error: %s", tostring(result))
		return "Bounty hunt is currently unavailable."
	end
end
BountyHuntFunctions.SetCurrentHunt = SetCurrentHunt

-- =============================================================================
-- EXISTING: MonsterKilled (modified — added notification)
-- =============================================================================

function events.MonsterKilled(Monster, MonsterIndex, _, killer)
	if vars.BountyHunt and killer and killer.Player then
		for MapName, Entry in pairs(vars.BountyHunt) do
			if not Entry.Done and Game.Month == Entry.Month and Entry.MonId == Monster.Id then
				Entry.Done = true

				-- Kill notification
				if MapName == Map.Name then
					local ok, title = pcall(function()
						local slot = vars.BountyNameSlots and vars.BountyNameSlots[MapName]
						if slot ~= nil then
							return mem.string(mem.u4[PLACEMON_ADDR + slot * 4])
						end
						return nil
					end)
					if ok and title then
						Game.ShowStatusText(string.format("%s eliminated! Return to town hall to claim your reward.", title))
					else
						Game.ShowStatusText("Bounty target eliminated! Return to town hall to claim your reward.")
					end
				end

				events.Call("BountyHuntEliminated", MapName, Entry, Monster)
			end
		end
	end
end

-- =============================================================================
-- NEW: Cleanup on month change / map unload
-- =============================================================================

function events.LeaveGame()
	if vars.BountyNameSlots then
		for mapName in pairs(vars.BountyNameSlots) do
			CleanupBountyName(mapName)
		end
	end
end

function events.AfterLoadMap()
	if Game.Month ~= (vars._lastBountyMonth or Game.Month) then
		vars._lastBountyMonth = Game.Month
		-- Month changed: clean up expired bounty names
		if vars.BountyHunt then
			for mapName, entry in pairs(vars.BountyHunt) do
				if entry.Month ~= Game.Month then
					CleanupBountyName(mapName)
					vars.BountyHunt[mapName] = nil
				end
			end
		end
	end
end

-- =============================================================================
-- EXISTING: ASM hooks (unchanged)
-- =============================================================================

if mmver == 7 then
	-- Repair town hall topic (MM7 only)
	NewCode = mem.asmproc([[
	nop
	nop
	nop
	nop
	nop
	jmp absolute 0x4bb3f0]])
	mem.asmpatch(0x4bae73, "jmp absolute " .. NewCode)

	mem.hook(NewCode, function(d)
		BountyText = BountyHuntFunctions.SetCurrentHunt()
		mem.u4[0xffd410] = mem.topointer(BountyText)
	end)
end

if mmver == 8 then
	-- Make MM8 bounty hunt same as MM7 and MM6 now
	mem.hook(0x4b080e, function(d)
		BountyText = BountyHuntFunctions.SetCurrentHunt()
		Message(BountyText)
	end)
end
