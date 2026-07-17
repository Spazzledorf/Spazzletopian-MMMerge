-- Save and restore Player.Attrs to/from vars.PlayersAttrs
local LogId = "PlayersAttrs"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MT, MV = Merge.ModSettings, Merge.Tables, Merge.Vars

function events.GameInitialized2()
	MV.PlayersAttrs = MV.PlayersAttrs or {}

	-- Rod:
	-- "Player" is lua table with custom metatable, thus we have
	--     to edit metatable to properly add new field:
	local player = Party.PlayersArray[0]
	local metatable = getmetatable(player)
	if not metatable.offsets.Attrs then
		metatable.offsets.Attrs = 0
		metatable.members.Attrs = function(offset, parent, field, value)
			--local playerId = (parent["?ptr"] - Party.PlayersArray["?ptr"])/parent["?size"]
			local playerId = parent.RosterBitIndex - 400
			if value then
				MV.PlayersAttrs[playerId] = value
			else
				return MV.PlayersAttrs[playerId]
			end
		end
		setmetatable(player, metatable)
	end
	-- Rod.
end

local spc_attack_fields = {
	'Spell', 'Skill', 'DamageType', 'SpellPoints', 'Recovery',
	'NextTime', 'Bits', 'Cooldown', 'Projectile', 'Sound'
}

local function set_race_spc_attack(roster_id, race, ranged, face)
	if tonumber(ranged) then
		ranged = (tonumber(ranged) > 0) and 1 or 0
	else
		ranged = ranged and 1 or 0
	end
	if MT.Races[race] and MT.Races[race].SpcAttack and MT.Races[race].SpcAttack[ranged] then
		for _, k in pairs(spc_attack_fields) do
			Game.PlayersExtra[roster_id].SpcAttack[ranged][k] =
				MT.Races[race].SpcAttack[ranged][k] or 0
		end
	end
	if face then
		if ranged == 0 then
			Game.PlayersExtra[roster_id].SpcAttackMelee.Spell =
				MF.GetPortraitSpcAttack(Party.PlayersArray[roster_id].Face)
		else
			Game.PlayersExtra[roster_id].SpcAttackRanged.Spell =
				MF.GetPortraitSpcAttack(Party.PlayersArray[roster_id].Face, true)
		end
	end
end
MF.SetRaceSpcAttack = set_race_spc_attack

local function before_save_game()
	vars.PlayersAttrs = MV.PlayersAttrs
	vars.PlayersExtra = vars.PlayersExtra or {}
	for i = 0, Party.PlayersArray.count - 1 do
		vars.PlayersExtra[i] = vars.PlayersExtra[i] or {}
		vars.PlayersExtra[i].SpcAttackMelee = vars.PlayersExtra[i].SpcAttackMelee or {}
		vars.PlayersExtra[i].SpcAttackRanged = vars.PlayersExtra[i].SpcAttackRanged or {}
		for _, k in pairs(spc_attack_fields) do
			vars.PlayersExtra[i].SpcAttackMelee[k] = Game.PlayersExtra[i].SpcAttackMelee[k]
			vars.PlayersExtra[i].SpcAttackRanged[k] = Game.PlayersExtra[i].SpcAttackRanged[k]
		end
	end
end

function events.BeforeSaveGame()
	MF.LogVerbose("%s: BeforeSaveGame", LogId)
	before_save_game()
end

function events.BeforeNewGameAutosave()
	MF.LogVerbose("%s: BeforeNewGameAutosave", LogId)
	-- set default race spc attack parameters
	for i = 0, 49 do
		local pl = Party.PlayersArray[i]
		local race = pl.Attrs.Race or Game.CharacterPortraits[pl.Face].Race
		set_race_spc_attack(i, race, false, true)
		--Game.PlayersExtra[i].SpcAttackMelee.Spell =
		--	MF.GetPortraitSpcAttack(pl.Face)
		set_race_spc_attack(i, race, true, true)
		--Game.PlayersExtra[i].SpcAttackRanged.Spell =
		--	MF.GetPortraitSpcAttack(pl.Face, true)
	end
	before_save_game()
end

local function determine_player_maturity(player)
	-- FIXME
	return math.min(Game.ClassesExtra[player.Class].Step, MM.Races.MaxMaturity)
end
MF.DeterminePlayerMaturity = determine_player_maturity

function events.InternalBeforeLoadMap(WasInGame)
	if not WasInGame then
		MF.LogVerbose("%s: InternalBeforeLoadMap", LogId)
		-- Looks like new game start time can be bigger than 138240
		if not vars.PlayersAttrs and Game.Time <= 138245 and not MV.NewGame then
			-- Clear PlayersAttrs on non-initial new game autosave load
			MF.LogWarning("%s: [%d] No vars.PlayersAttrs, reset PlayersAttrs", LogId, Game.Time)
			MF.ResetPlayersAttrs()
		end

		MV.PlayersAttrs = vars.PlayersAttrs or MV.PlayersAttrs
		if MV.PlayersAttrs == nil then
			MF.LogInfo("%s: neither MV.PlayersAttrs nor vars.PlayersAttrs", LogId)
			MV.PlayersAttrs = {}
		end

		for i = 0, Party.PlayersArray.count - 1 do
			local player = Party.PlayersArray[i]
			--Log(Merge.Log.Info, "PlayersAttrs: Player %d", k)
			MV.PlayersAttrs[i] = MV.PlayersAttrs[i] or {}
			if player.Attrs.Race == nil then
				player.Attrs.Race = GetCharRace(player)
				MF.LogInfo("Set default race %d for player %d", player.Attrs.Race, i)
			end
			if player.Attrs.Maturity == nil then
				player.Attrs.Maturity = determine_player_maturity(player)
			end
			if player.Attrs.PromoAwards == nil then
				player.Attrs.PromoAwards = {}
			end
			if player.Attrs.ExtraQuickSpells == nil then
				player.Attrs.ExtraQuickSpells = {}
			end
			if vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].SpcAttackMelee then
				for _, k in pairs(spc_attack_fields) do
					Game.PlayersExtra[i].SpcAttackMelee[k] =
						vars.PlayersExtra[i].SpcAttackMelee[k] or 0
				end
			else
				set_race_spc_attack(i, player.Attrs.Race, false, true)
			end
			if vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].SpcAttackRanged then
				for _, k in pairs(spc_attack_fields) do
					Game.PlayersExtra[i].SpcAttackRanged[k] =
						vars.PlayersExtra[i].SpcAttackRanged[k] or 0
				end
			else
				set_race_spc_attack(i, player.Attrs.Race, true, true)
			end
		end
	end
end

local function player_attrs_clear(roster_id)
	if not roster_id then return end
	--MV.PlayersAttrs[roster_id] = {}
	MV.PlayersAttrs[roster_id] = MV.PlayersAttrs[roster_id] or {}
	local attrs = MV.PlayersAttrs[roster_id]
	attrs.Race = nil
	attrs.Maturity = nil
	attrs.Alignment = nil
	attrs.PromoAwards = {}
	attrs.ExtraQuickSpells = {}
end
MF.PlayerAttrsClear = player_attrs_clear

local function reset_players_attrs()
	for k = 0, Party.PlayersArray.count - 1 do
		player_attrs_clear(k)
	end
end
MF.ResetPlayersAttrs = reset_players_attrs

function events.NewGame(WasInGame, Continent)
	MF.LogInfo("%s: NewGame, was in game: %d", LogId, WasInGame and 1 or 0)
	reset_players_attrs()
end

MF.LogInit2(LogId)

