-- SkillDebug: discovers GlobalTxt indices for skill display on character sheet
-- Toggle: /e Game.SkillDebug = true   (F11 console) - scans GlobalTxt live
-- Dump:   /e DumpSkillGxt()           - writes all skill-related GlobalTxt to file

local LogId = "[SkillDebug]"
local dumped = false

local function Log(...)
    print(LogId, ...)
end

-- Global function to dump all skill-related GlobalTxt entries to a file
-- Call from F11 console:  /e Game.DumpSkillGxt()
function Game.DumpSkillGxt()
    local path = "E:\\Games\\GOG Galaxy\\Games\\Might and Magic 8 - MMMerge TEST\\Data\\Tables\\GlobalTxtSkillDump.txt"
    local f = io.open(path, "w")
    if not f then
        Log("Failed to open " .. path)
        return
    end
    local count = 0
    local MASTERIES = {"Normal", "Expert", "Master", "Grandmaster"}
    f:write("=== GlobalTxt Skill-Related Entries ===\n\n")

    for i = 1, 600 do
        local v = Game.GlobalTxt[i]
        if v and v ~= "" then
            local txt = tostring(v)
            local matched = false

            -- Check skill names
            for si = 0, 38 do
                local sname = Game.SkillNames[si]
                if sname and sname ~= "" and txt:find(sname, 1, true) then
                    f:write(string.format("GlobalTxt[%d] = \"%s\"  [skill %d: %s]\n", i, txt:sub(1, 80), si, sname))
                    count = count + 1
                    matched = true
                    break
                end
            end

            if not matched then
                -- Check mastery text
                for _, mstr in ipairs(MASTERIES) do
                    if txt:find(mstr, 1, true) then
                        f:write(string.format("GlobalTxt[%d] = \"%s\"  [mastery: %s]\n", i, txt:sub(1, 80), mstr))
                        count = count + 1
                        matched = true
                        break
                    end
                end
            end

            if not matched then
                -- Check short numbers (skill levels)
                if txt:match("^%d+$") then
                    local n = tonumber(txt)
                    if n and n >= 1 and n <= 65 then
                        f:write(string.format("GlobalTxt[%d] = \"%s\"  [level number]\n", i, txt))
                        count = count + 1
                    end
                end
            end
        end
    end

    f:write(string.format("\nTotal entries: %d\n", count))
    f:close()
    Log("Dumped " .. count .. " entries to Data/Tables/GlobalTxtSkillDump.txt")
end

function events.GameInitialized2()
    Game.SkillDebug = false
    Log("Loaded. Use: DumpSkillGxt() or Game.SkillDebug = true")
end

function events.L2InterfaceUpd()
    -- Test refresh: modify a GlobalTxt entry to see if display changes
    if Game.TestRefresh then
        local idx = Game.TestRefresh
        if type(idx) == "number" then
            local old = Game.GlobalTxt[idx]
            local newval = "*** MODIFIED ***"
            Game.GlobalTxt[idx] = newval
            Log("Modified GlobalTxt[" .. idx .. "] from '" .. tostring(old) .. "' to '" .. newval .. "'")
        end
        Game.TestRefresh = nil
        return
    end

    if not Game.SkillDebug then return end
    if Game.CurrentScreen ~= const.Screens.Inventory then return end
    if dumped then return end
    dumped = true

    Log("=== GlobalTxt scan on Skills tab ===")

    local MASTERIES = {"Normal", "Expert", "Master", "Grandmaster"}

    for i = 1, 500 do
        local v = Game.GlobalTxt[i]
        if v and v ~= "" then
            local txt = tostring(v)

            for si = 0, 38 do
                local sname = Game.SkillNames[si]
                if sname and sname ~= "" and txt:find(sname, 1, true) then
                    Log("GlobalTxt[" .. i .. "] \"" .. txt:sub(1, 60) .. "\" <- skill " .. si .. " \"" .. sname .. "\"")
                    break
                end
            end

            for _, mstr in ipairs(MASTERIES) do
                if txt:find(mstr, 1, true) then
                    Log("GlobalTxt[" .. i .. "] \"" .. txt:sub(1, 60) .. "\" <- mastery \"" .. mstr .. "\"")
                    break
                end
            end

            if txt:match("^%d+$") then
                local n = tonumber(txt)
                if n and n >= 1 and n <= 60 then
                    Log("GlobalTxt[" .. i .. "] \"" .. n .. "\" <- possible skill level")
                end
            end
        end
    end

    Log("Scan complete. Set Game.SkillDebug = false to re-scan.")
    Game.SkillDebug = false
end
