-- zzLootAll.lua
-- Press V to loot all nearby ground items, gold piles, and monster corpses.
-- Toggle: Game.LootAllEnabled via MenuExtraSettings.

if Game.LootAllEnabled == nil then Game.LootAllEnabled = true end
local GoldEquipStat = const.ItemType.Gold - 1
local isMM7plus = false
pcall(function() isMM7plus = Game.Version and Game.Version > 6 end)

local errors = 0
local goldBefore = 0
local itemsLooted = 0
local lootedThisPress = {}

if Game.LootAllRange == nil then Game.LootAllRange = 2000 end

local pickCorpseAddr = 0
pcall(function()
    if Game.Version == 8 then pickCorpseAddr = 0x424E3D
    elseif Game.Version == 7 then pickCorpseAddr = 0x426A03
    elseif Game.Version == 6 then pickCorpseAddr = 0x421670 end
end)

function events.KeyDown(t)
    if t.Key ~= 86 then return end
    if not Game.LootAllEnabled then return end
    if Game.Paused or Game.CurrentScreen ~= 0 then return end

    errors = 0
    goldBefore = Party.Gold
    itemsLooted = 0
    local toRemove = {}

    local mouseItemPtr = Game.Mouse.Item["?ptr"]
    local itemSize = isMM7plus and 0x24 or 0x1C

    pcall(function()
        if Game.Mouse.Item.Number ~= 0 then
            Game.Mouse:ReleaseItem()
        end
    end)

    local px, py, pz = Party.X or 0, Party.Y or 0, Party.Z or 0
    local a = (Party.Direction or 0) * math.pi / 1024
    local fx, fy = math.cos(a), math.sin(a)
    local rangeSq = Game.LootAllRange * Game.LootAllRange

    -- === Phase 1: Ground items and gold piles (Map.Objects) ===
    for i, obj in Map.Objects do
        local removed, missile
        local ok0 = pcall(function()
            removed = obj.Removed
            missile = obj.Missile
        end)
        if not ok0 or removed or missile then
            -- skip non-item objects
        else
            local filterOk = false
            pcall(function()
                local dx = obj.X - px; local dy = obj.Y - py; local dz = obj.Z - pz
                if dx*dx + dy*dy + dz*dz <= rangeSq then
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= 0 or (dx*fx + dy*fy) / dist >= 0.707 then
                        if dist <= 500 then
                            filterOk = true
                        elseif not PathfinderDll or PathfinderDll.TraceLine(Party, obj, 80) then
                            filterOk = true
                        end
                    end
                end
            end)
            if filterOk then
            local num
            pcall(function() num = obj.Item.Number end)
            if num and num > 0 then
                local entry
                pcall(function() entry = Game.ItemsTxt[num] end)
                if entry and entry.EquipStat == GoldEquipStat then
                    local goldValue = obj.Item.Bonus2 or 0
                    if goldValue > 0 then
                        Party.Gold = Party.Gold + goldValue
                        obj.Item.Number = 0
                        pcall(function() obj.Visible = false end)
                        pcall(function() obj.Removed = true end)
                        toRemove[#toRemove + 1] = i
                    end
                elseif entry then
                    local srcPtr = obj.Item["?ptr"]
                    if srcPtr then
                        local ok = pcall(function()
                            mem.copy(mouseItemPtr, srcPtr, itemSize)
                        end)
                        if ok then
                            local ok2 = pcall(function()
                                Game.Mouse:ReleaseItem()
                            end)
                            if ok2 then
                                obj.Item.Number = 0
                                pcall(function() obj.Visible = false end)
                                pcall(function() obj.Removed = true end)
                                itemsLooted = itemsLooted + 1
                                toRemove[#toRemove + 1] = i
                            else
                                errors = errors + 1
                            end
                        else
                            errors = errors + 1
                        end
                    end
                end
            end
            end
        end
    end

    -- === Removal: swap-with-last (data) + SpritesToDraw buffer cleanup (visual) ===
    if #toRemove > 0 then
        local mapObjSize = isMM7plus and 0x70 or 0x64
        pcall(function()
            -- Step 1: Remove from Map.Objects array
            for k = #toRemove, 1, -1 do
                local idx = toRemove[k]
                local count = Map.Objects.Count
                if idx < count then
                    local last = count - 1
                    if idx < last then
                        local src = Map.Objects[last]["?ptr"]
                        local dst = Map.Objects[idx]["?ptr"]
                        mem.copy(dst, src, mapObjSize)
                    end
                    Map.Objects.Count = last
                end
            end
            -- Step 2: Clear stale entries from the SpritesToDraw render buffer
            if Game.Version == 8 then
                local drawPtr = u4[0x43CBEF + 2]
                local drawCount = i4[0x529F40]
                if drawPtr and drawCount > 0 then
                    local entrySize = 0x34
                    local objRefOff = 0x10
                    for ki = #toRemove, 1, -1 do
                        local objRef = toRemove[ki] * 8
                        for j = 0, drawCount - 1 do
                            local entryRef = u2[drawPtr + j * entrySize + objRefOff]
                            if entryRef == objRef then
                                if j < drawCount - 1 then
                                    mem.copy(
                                        drawPtr + j * entrySize,
                                        drawPtr + (drawCount - 1) * entrySize,
                                        entrySize
                                    )
                                end
                                drawCount = drawCount - 1
                                break
                            end
                        end
                    end
                    i4[0x529F40] = drawCount
                end
            end
        end)
        pcall(function() Game.NeedRender = true end)
    end

end

function events.KeyUp(t)
    if t.Key ~= 86 then return end
    if not Game.LootAllEnabled then return end
    if Game.Paused or Game.CurrentScreen ~= 0 then return end

    local corpseCount = 0
    local goldCollected = Party.Gold - goldBefore

    local px, py, pz = Party.X or 0, Party.Y or 0, Party.Z or 0
    local a = (Party.Direction or 0) * math.pi / 1024
    local fx, fy = math.cos(a), math.sin(a)
    local rangeSq = Game.LootAllRange * Game.LootAllRange

    if isMM7plus and pickCorpseAddr ~= 0 then
        pcall(function()
            if Game.Mouse.Item.Number ~= 0 then
                Game.Mouse:ReleaseItem()
            end
        end)

        local high = 499
        pcall(function() high = Map.Monsters.High end)
        if not high or high < 0 then high = 499 end
        for i = 0, high do
            local mon
            pcall(function() mon = Map.Monsters[i] end)
            if mon then
                local hp, aiState
                pcall(function() hp = mon.HP end)
                pcall(function() aiState = mon.AIState end)
                if hp and hp <= 0 and aiState and aiState > 0 then
                    if not lootedThisPress[i] then
                        local filterOk = false
                        pcall(function()
                            local dx = mon.X - px; local dy = mon.Y - py; local dz = mon.Z - pz
                            if dx*dx + dy*dy + dz*dz <= rangeSq then
                                local dist = math.sqrt(dx*dx + dy*dy)
                                if dist <= 0 or (dx*fx + dy*fy) / dist >= 0.707 then
                                    if dist <= 500 then
                                        filterOk = true
                                    elseif not PathfinderDll or PathfinderDll.TraceLine(Party, mon, 80) then
                                        filterOk = true
                                    end
                                end
                            end
                        end)
                        if filterOk then
                        local monPtr
                        pcall(function() monPtr = mon["?ptr"] end)
                        if monPtr then
                            pcall(function()
                                mem.call(pickCorpseAddr, 0, monPtr)
                            end)
                            pcall(function()
                                if Game.Mouse.Item.Number ~= 0 then
                                    Game.Mouse:ReleaseItem()
                                end
                            end)
                            corpseCount = corpseCount + 1
                            lootedThisPress[i] = true
                        end
                        end
                    end
                end
            end
        end
    end

    goldCollected = Party.Gold - goldBefore
    local parts = {}
    if itemsLooted > 0 then table.insert(parts, string.format("%d items", itemsLooted)) end
    if corpseCount > 0 then table.insert(parts, string.format("%d corpses", corpseCount)) end
    if goldCollected > 0 then table.insert(parts, string.format("%d gold", goldCollected)) end
    if errors > 0 then table.insert(parts, string.format("%d errors", errors)) end
    if #parts > 0 then Game.ShowStatusText("LootAll: " .. table.concat(parts, ", ")) end
end
