-- CombatLogWindow.lua - Toggleable, moveable, resizable combat log using CustomUI
Game.CombatLogEnabled = (Game.CombatLogEnabled == nil) and true or Game.CombatLogEnabled

local MAX_ENTRIES = 500
Game.CombatLog = Game.CombatLog or {}
Game.CombatLog.entries = Game.CombatLog.entries or {}
local entries = Game.CombatLog.entries

local logWindow = nil
local isOpen = false

local function AddEntry(action, source, target, detail)
    table.insert(entries, 1, {
        time = os.time(), -- or Game.Time
        act = action or "?",
        src = source or "?",
        tgt = target or "?",
        det = detail or ""
    })
    if #entries > MAX_ENTRIES then table.remove(entries) end
end

-- Create the window
local function CreateLogWindow()
    if logWindow then return end

    logWindow = CustomUI.NewWindow("Combat Log", 400, 300, 100, 100)  -- width, height, x, y
    logWindow:SetTitle("Combat Log (L to toggle)")
    logWindow:SetResizable(true)
    logWindow:SetMoveable(true)

    local list = logWindow:AddListBox(10, 30, 380, 250)
    list:SetMultiSelect(false)

    -- Update list content
    local function RefreshList()
        list:Clear()
        for i = 1, math.min(20, #entries) do  -- show last 20
            local e = entries[i]
            list:AddItem(string.format("%s %s → %s | %s", e.act, e.src, e.tgt, e.det))
        end
    end

    logWindow.OnUpdate = RefreshList  -- refresh when visible
    logWindow:Hide()  -- start hidden
end

-- Toggle with L key
function events.KeyDown(t)
    if t.Key == 76 and Game.CombatLogEnabled then  -- L key
        if not logWindow then CreateLogWindow() end
        isOpen = not isOpen
        if isOpen then
            logWindow:Show()
        else
            logWindow:Hide()
        end
        t.Handled = true
    end
end

-- Event logging (same as before)
function events.CalcDamageToMonster(t)
    if not Game.CombatLogEnabled then return end
    if t.Result and t.Result > 0 then
        local src = t.PlayerIndex and ("P"..(t.PlayerIndex+1)) or "Party"
        AddEntry("DMG", src, "Monster", math.floor(t.Result))
    end
end

-- Add other events similarly (CalcDamageToPlayer, MonsterKilled, etc.)

print("CombatLogWindow: Press L to toggle moveable/resizable log window")
