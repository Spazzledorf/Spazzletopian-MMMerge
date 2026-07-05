-- Learning related hooks
--
-- The Learning skill slot (38) is repurposed for Retaliation (see
-- Retaliation.lua) -- training time is normalized to what GM Learning
-- mastery used to give, for everyone, unconditionally, instead of scaling
-- with a skill that no longer means "Learning". The event-XP-boost patch is
-- left disabled entirely so XP stays uniform/vanilla regardless of build.
local LogId = "Learning"
Log(Merge.Log.Info, "Init started: %s", LogId)

local asmpatch, hook, u4 = mem.asmpatch, mem.hook, mem.u4
local max = math.max

-- Fixed at GM (4): days = levels * (7 - mastery) = levels * 3, the shortest
-- training time the native formula supports, for every character.
local FIXED_MASTERY = 4

-- Reduce training time to the fixed best-case value for everyone
local function ReduceTrainingTime()
	-- Ignore MM8 check for maximal amount of level-ups this session
	-- Get training hours to be added in according to Learning mastery
	local NewCode = asmpatch(0x4B3606, [[
	inc dword ptr [eax]
	mov eax, dword ptr [eax]
	nop
	nop
	nop
	nop
	nop
	test edi, edi
	je absolute 0x4B3640
	push eax
	]])

	hook(NewCode + 4, function(d)
		local cur_pl = Game.CurrentPlayer
		local cur_levels = d.eax
		local days, total_levels = 0, 0
		-- Get already spent days during this session for other players
		for k, pl in Party do
			if k ~= cur_pl then
				local levels = u4[0xFFD3AC + k * 4]
				if levels > 0 then
					local pl_days = levels * (7 - FIXED_MASTERY)
					if pl_days > days then
						days = pl_days
					end
					total_levels = total_levels + levels
				end
			end
		end
		local mastery = FIXED_MASTERY
		local cur_days = cur_levels * (7 - mastery)
		if cur_days > days then
			if cur_levels > 1 then
				-- Check if current player already spent more days than others
				local prev_days = (cur_levels - 1) * (7 - mastery)
				days = max(days, prev_days)
			end
			d.edi = (cur_days - days) * 24
		else
			d.edi = 0
		end
		total_levels = total_levels + cur_levels
		d.eax = total_levels
	end)

	-- Ignore extra hours for non first level-up.
	-- Check for next 9 AM to be in 24 hours for first level-up.
	-- ecx - level-ups this sesssion
	-- eax - hours till next dawn
	-- edi - training hours to be added
	asmpatch(0x4B3617, [[
	pop ecx
	cmp ecx, 1
	jle @first
	xor eax, eax
	jmp @std
	@first:
	add eax, 4
	cmp eax, 0x18
	jle @std
	sub eax, 0x18
	@std:
	add eax, edi
	]])
end

function events.GameInitialized2()
	ReduceTrainingTime()
end

Log(Merge.Log.Info, "Init finished: %s", LogId)
