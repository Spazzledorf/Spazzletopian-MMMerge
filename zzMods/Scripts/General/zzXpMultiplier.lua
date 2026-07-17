-- XP Multiplier: scales kill XP and quest/promotion XP independently.
-- Kill multiplier toggles via Game.XpMultiplierEnabled / Game.XpMultiplier.
-- Quest multiplier toggles via Game.XpQuestMultiplierEnabled / Game.XpQuestMultiplier.
-- Both configured in Extra Settings -> XP Multiplier.

Game.XpMultiplierEnabled = (Game.XpMultiplierEnabled == nil) and true or Game.XpMultiplierEnabled
Game.XpMultiplier = Game.XpMultiplier or 2
Game.XpQuestMultiplierEnabled = (Game.XpQuestMultiplierEnabled == nil) and false or Game.XpQuestMultiplierEnabled
Game.XpQuestMultiplier = Game.XpQuestMultiplier or 2

-- Track expected XP per player so Tick can distinguish already-multiplied
-- kills from unmultiplied native events.
local expected_xp = {}
local prev_xp = {}

-- Hook 1: MonsterKillExp (kill XP only)
function events.MonsterKillExp(t)
    if not Game.XpMultiplierEnabled then return end
    local mul = Game.XpMultiplier
    if not mul or mul == 1 then return end
    if t.Exp and t.Exp > 0 then
        local multiplied = math.floor(t.Exp * mul)
        local share = math.floor(multiplied / Party.Count)
        for i = 0, Party.Count - 1 do
            expected_xp[i] = (expected_xp[i] or 0) + share
        end
        t.Exp = multiplied
    end
end

-- Hook 2: Lua-scripted quest/promotion XP
local function install_evt_wrapper()
    if Game._xp_evt_wrapped then return end

    for _, ctx in pairs(evt) do
        if type(ctx) == "table" then
            local orig_add = ctx.Add
            if type(orig_add) == "function" then
                ctx.Add = function(key, value, ...)
                    if Game.XpQuestMultiplierEnabled then
                        local mul = Game.XpQuestMultiplier
                        if mul and mul ~= 1 and (key == "Experience" or key == "Exp") and value then
                            value = math.floor(value * mul)
                        end
                    end
                    return orig_add(key, value, ...)
                end
            end
        end
    end

    local orig_evt_add = evt.Add
    if type(orig_evt_add) == "function" then
        evt.Add = function(key, value, ...)
            if Game.XpQuestMultiplierEnabled then
                local mul = Game.XpQuestMultiplier
                if mul and mul ~= 1 and (key == "Experience" or key == "Exp") and value then
                    value = math.floor(value * mul)
                end
            end
            return orig_evt_add(key, value, ...)
        end
    end

    Game._xp_evt_wrapped = true
end

install_evt_wrapper()
function events.GameInitialized2()
    install_evt_wrapper()
end

-- Hook 3: Tick scanner for native evt XP (vanilla quests, etc.)
function events.Tick()
    if not Game.XpQuestMultiplierEnabled then return end
    local mul = Game.XpQuestMultiplier
    if not mul or mul == 1 then return end

    for i = 0, Party.Count - 1 do
        local current = Party[i].Experience
        local prev = prev_xp[i]
        if prev and current > prev then
            local gain = current - prev
            local expected = expected_xp[i] or 0
            if gain > expected then
                local native = gain - expected
                Party[i].Experience = current + math.floor(native * (mul - 1))
            end
        end
        prev_xp[i] = Party[i].Experience
        expected_xp[i] = 0
    end
end
