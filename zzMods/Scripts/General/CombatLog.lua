-- CombatLog.lua
-- Captures combat events, displays via status bar and optional overlay text.
-- L toggles log mode. L scrolls entries. Esc exits.

Game.CombatLogEnabled = (Game.CombatLogEnabled == nil) and true or Game.CombatLogEnabled

local MAX_ENTRIES = 500
Game.CombatLog = Game.CombatLog or {}
Game.CombatLog.entries = Game.CombatLog.entries or {}
local entries = Game.CombatLog.entries
local logMode = false
local scrollPos = 0
local wasL = false
local wasEsc = false

local function AddEntry(act, src, tgt, det)
    table.insert(entries, 1, {act=act, src=src, tgt=tgt, det=det})
    if #entries > MAX_ENTRIES then table.remove(entries) end
end

local function ShowEntry(idx)
    if #entries == 0 then Game.ShowStatusText("(no combat events)", 2); return end
    if idx < 1 then idx = 1 end
    if idx > #entries then idx = #entries end
    local e = entries[idx]
    Game.ShowStatusText(string.format("[%d/%d] %s %s > %s | %s", idx, #entries, e.act, e.src, e.tgt, e.det), 3)
end

function events.CalcDamageToMonster(t)
    if not Game.CombatLogEnabled then return end
    if t.Result and t.Result > 0 then
        local src = "Player"
        if t.PlayerIndex then src = string.format("P%d", t.PlayerIndex + 1) end
        AddEntry("DMG", src, string.format("Mon[%d]", t.MonsterIndex or 0), math.floor(t.Result) .. (t.DamageKind and (" " .. tostring(t.DamageKind)) or ""))
        if logMode then scrollPos = 1; ShowEntry(1) end
    end
end

function events.CalcDamageToPlayer(t)
    if not Game.CombatLogEnabled then return end
    if t.Result and t.Result > 0 then
        AddEntry("DMG", "Monster", string.format("P%d", (t.PlayerIndex or 0) + 1), math.floor(t.Result))
        if logMode then scrollPos = 1; ShowEntry(1) end
    end
end

function events.MonsterKilled(mon, monIndex)
    if not Game.CombatLogEnabled then return end
    AddEntry("KILL", "Party", string.format("Mon[%d]", monIndex or 0), "slain")
end

function events.MonsterKillExp(t)
    if not Game.CombatLogEnabled then return end
    if t.Exp and t.Exp > 0 then
        AddEntry("EXP", "Party", string.format("Mon[%d]", t.MonsterIndex or 0), "+" .. t.Exp .. " XP")
    end
end

function events.Tick()
    if not Game.CombatLogEnabled then
        if wasL then wasL = false; wasEsc = false end
        return end
    local isL = Keys.IsPressed(76)
    local isEsc = Keys.IsPressed(27)
    if isL and not wasL then
        if not logMode then
            logMode = true
            scrollPos = 1
            ShowEntry(1)
        else
            scrollPos = scrollPos + 1
            if scrollPos > #entries then scrollPos = 1 end
            ShowEntry(scrollPos)
        end
    end
    wasL = isL
    if logMode and isEsc and not wasEsc then
        logMode = false
        Game.ShowStatusText("Combat log closed", 1)
    end
    wasEsc = isEsc
end

print("CombatLog: L enters log mode, L scrolls, Esc exits")
