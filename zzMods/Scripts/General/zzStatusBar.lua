-- zzStatusBar.lua
-- Shows recent combat events via ShowStatusText (same as CombatLog).

Game.StatusBarEnabled = (Game.StatusBarEnabled == nil) and true or Game.StatusBarEnabled

local lastEvents = ""
local timer = 0

function events.L2InterfaceUpd()
    if not Game.StatusBarEnabled then return end
    if Game.CurrentScreen ~= 0 then return end

    timer = timer + 1
    if timer < 30 then return end
    timer = 0

    local cl = Game.CombatLog and Game.CombatLog.entries
    if cl and #cl > 0 then
        local e = cl[1]
        local txt = string.format("[%s] %s > %s | %s", e.act, e.src, e.tgt, e.det)
        if txt ~= lastEvents then
            lastEvents = txt
            Game.ShowStatusText(txt, 3)
        end
    end
end

print("StatusBar: shows latest combat event")
