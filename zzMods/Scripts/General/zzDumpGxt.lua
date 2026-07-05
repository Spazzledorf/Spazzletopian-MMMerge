-- zzDumpGxt.lua
-- Dumps all GlobalTxt entries to a text file.
-- Call from console: DumpGxt() or DumpGxt("Armor")

function DumpGxt(search)
    local f = io.open("Data/Tables/GlobalTxtDump.txt", "w")
    if not f then print("Failed to open file"); return end
    
    local count = 0
    for i = 0, 749 do
        local t = Game.GlobalTxt[i]
        if t and t ~= "" then
            if not search or string.find(t, search, 1, true) then
                f:write(string.format("%d = %s\n", i, t))
                count = count + 1
            end
        end
    end
    f:close()
    print(string.format("Dumped %d entries to Data/Tables/GlobalTxtDump.txt", count))
end

function events.GameInitialized2()
    print("zzDumpGxt loaded. Type: DumpGxt() or DumpGxt(\"Armor\")")
end
