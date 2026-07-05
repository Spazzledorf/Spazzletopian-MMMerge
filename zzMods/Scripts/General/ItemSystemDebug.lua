-- =============================================================================
-- MMMerge Curated Item System — Test / Debug Tool
-- Scripts/General/ItemSystemDebug.lua
-- =============================================================================
-- Console-callable helpers for verifying Scripts/General/ItemSystem.lua one
-- piece at a time, without grinding for real drops. Open the debug console
-- (Ctrl+F1 — see DebugConsoleKey.lua) and call these directly, e.g.:
--
--   ItemTest.DumpAllClasses()                          -- stage 1
--   ItemTest.DumpSelectionsForClass(const.Class.Monk)  -- stage 1
--   ItemTest.DumpInventory(0)                          -- stage 2/3 (see what's in
--                                                          player 0's backpack, pick
--                                                          a slot you don't mind losing)
--   local item = ItemTest.GenerateItem(3, const.ItemType.Weapon)  -- stage 2/3
--                                       -- (re-rolls slot 3 IN PLACE -- see the
--                                       -- function's own comment for why this
--                                       -- signature requires a slot; OVERWRITES it)
--   ItemTest.Inspect(item)                             -- stage 3
--   ItemTest.DumpPlayerBonuses(0)                      -- stage 4 (equip the
--                                                          item on player 0 first)
--   ItemTest.TestToggleRoundTrip(item)                  -- stage 5
--   ItemTest.TestPrune()                                -- stage 6
--   ItemTest.RunAll(3)                                  -- 1,2,3,5,6 in one go,
--                                                          also overwrites slot 3
--
-- Everything here is opt-in and console-only — nothing in this file runs on
-- its own or hooks any event. GenerateItem returns (item, report); everything
-- else returns a report string. Both are also logged to the mod log file.
--
-- Requires Scripts/General/ItemSystem.lua to have already loaded (it exposes
-- ItemSystemInternal — see that file's "DEBUG HOOKS" section). RunFiles loads
-- General/*.lua alphabetically, and "ItemSystem.lua" sorts before
-- "ItemSystemDebug.lua", so this is guaranteed on normal startup.
-- =============================================================================

ItemTest = {}
local LogId = "ItemSystemDebug"

local function Internal()
    if not ItemSystemInternal then
        error("ItemSystemInternal not found -- is Scripts/General/ItemSystem.lua loaded?")
    end
    return ItemSystemInternal
end

local function DumpStats(t)
    if not t then return "{}" end
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- =============================================================================
-- STAGE 1: pool data & class mapping — pure logic, no item generation, no RNG
-- =============================================================================

-- Enumerates every known const.Class value and reports which ones the item
-- system can/can't resolve to a line/bucket/tier/alignment. Anything printed
-- as UNMAPPED means ClassToLine in ItemSystem.lua is missing that class --
-- usually because Scripts/Structs/20_MergeConsts.lua added or renamed one.
-- Run this any time MergeConsts.lua changes, before touching real items.
function ItemTest.DumpAllClasses()
    local I = Internal()
    local lines = {}
    for name, classId in pairs(const.Class) do
        local line = I.ClassToLine[classId]
        if line then
            local bucket = I.LineToBucket[line]
            local tier = I.ClassTier[classId]
            local alignment = I.ClassAlignment[classId] or "any"
            lines[#lines + 1] = string.format("  OK       %-20s (id=%3d) -> %-16s tier=%-4s align=%-5s bucket=%s",
                name, classId, line, tostring(tier), alignment, tostring(bucket))
        else
            lines[#lines + 1] = string.format("  UNMAPPED %-20s (id=%3d)", name, classId)
        end
    end
    table.sort(lines)
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: DumpAllClasses:\n%s", LogId, report)
    return report
end

-- Calls SelectPrefix/SelectSuffix directly for one class, `count` times,
-- bypassing item generation and RandomPartyMember entirely -- use this to
-- check a class's pool coverage/weighting without needing that class in
-- your current party. Pass a const.Class value.
function ItemTest.DumpSelectionsForClass(classId, count)
    local I = Internal()
    count = count or 20
    local line = I.ClassToLine[classId]
    if not line then
        Log(Merge.Log.Error, "%s: DumpSelectionsForClass: class %s has no line mapping", LogId, tostring(classId))
        return nil
    end
    local bucket = I.LineToBucket[line]
    local tier = I.ClassTier[classId] or 0
    local alignment = I.ClassAlignment[classId] or "any"
    local prefixPool = I.Pools.Prefixes[bucket]
    local suffixPool = I.Pools.Suffixes[line]

    local lines = {
        string.format("class=%s line=%s bucket=%s tier=%d align=%s",
            tostring(classId), line, bucket, tier, alignment)
    }
    for i = 1, count do
        local prefix = I.SelectPrefix(prefixPool, alignment)
        local suffix = I.SelectSuffix(suffixPool, tier, alignment)
        lines[#lines + 1] = string.format("  #%02d: %-14s + %s", i,
            prefix and prefix.name or "<none>", suffix and suffix.name or "<none>")
    end
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: %s", LogId, report)
    return report
end

-- =============================================================================
-- STAGE 2/3: real item generation + suppression/tag inspection
-- Exercises the full native pipeline: structs.Item.Randomize ->
-- events.GenerateItem -> (native roll) -> events.ItemGeneratedM ->
-- events.ItemGenerated (our hook).
-- =============================================================================

-- Lists every non-empty inventory slot for one player, with the same raw
-- fields as Inspect(). Useful for seeing exactly what landed where after
-- GenerateItem, or for spotting an item FindItemByChargeId should have found.
function ItemTest.DumpInventory(playerIndex)
    local player = Party[playerIndex or 0]
    if not player then
        Log(Merge.Log.Error, "%s: DumpInventory: no player at index %s", LogId, tostring(playerIndex))
        return nil
    end
    local lines = { "Player " .. tostring(playerIndex or 0) .. " inventory:" }
    for slot = 1, 138 do
        local it = player.Items[slot]
        if it and it.Number and it.Number > 0 then
            lines[#lines + 1] = string.format("  slot %3d: Number=%-4d Bonus=%d BonusStrength=%d Bonus2=%d Charges=%d MaxCharges=%d",
                slot, it.Number, it.Bonus, it.BonusStrength, it.Bonus2, it.Charges, it.MaxCharges)
        end
    end
    if #lines == 1 then
        lines[#lines + 1] = "  (empty)"
    end
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: %s", LogId, report)
    return report
end

-- Searches party inventory for an item tagged with the given curated id.
-- Handy for finding a real (non-test-generated) curated item, e.g. one
-- found by ItemTest.Inspect() while playing normally.
function ItemTest.FindItemByChargeId(id)
    for _, pl in Party.Players do
        for slot = 1, 138 do
            local it = pl.Items[slot]
            if it and it.Charges == id then
                return it
            end
        end
    end
    return nil
end

-- Re-rolls an EXISTING item already sitting in playerIndex's inventory, IN
-- PLACE, by calling :Randomize() directly on it -- the same pattern
-- MAW-Mod-MMMerge uses to enchant items the engine already owns (see
-- zzMaw-Items.lua's events.AfterLoadMap: `it:Randomize(...)` called directly
-- on Map.Chests[k].Items[i] / Map.Objects[i].Item -- never a manually
-- copied-in item; https://github.com/Malekitsu/Maw-Mod-MMMerge).
--
-- A previous version of this function generated the item on Mouse.Item and
-- either called Mouse:ReleaseItem() (silently failed to land it in
-- inventory when called from the debug console) or manually copied its
-- fields into a slot found via "first Number==0" (crashed the game inside
-- Mouse:RemoveItem() -- EAccessViolation reading 0x000000F5, see
-- ErrorLog.txt). Both tried to CREATE a new inventory entry from Lua, which
-- apparently needs bookkeeping (e.g. the separate Inventory[] grid-mapping
-- array, see 00 structs.lua) that neither approach performed. Re-rolling an
-- item that's already validly placed sidesteps all of that -- nothing is
-- being inserted, only the contents of an existing, already-tracked slot
-- change, exactly like MAW's chest/object re-enchant pattern.
--
-- REQUIRES an explicit slot number -- this OVERWRITES whatever is currently
-- in that slot. Use ItemTest.DumpInventory(playerIndex) first to see what's
-- there and pick something you don't mind losing (a spare/junk item, not
-- your starting gear). Returns (item, report), or (nil, nil) if the roll
-- wasn't curated (no Bonus/Bonus2 rolled) or the slot/player is invalid.
function ItemTest.GenerateItem(slot, itemType, strength, playerIndex)
    if not slot then
        Log(Merge.Log.Error, "%s: GenerateItem: slot is required (this OVERWRITES that slot) -- run ItemTest.DumpInventory(playerIndex) first and pick one", LogId)
        return nil, nil
    end
    itemType = itemType or const.ItemType.Any
    strength = strength or 5
    local player = Party[playerIndex or 0]
    if not player then
        Log(Merge.Log.Error, "%s: GenerateItem: no player at index %s", LogId, tostring(playerIndex))
        return nil, nil
    end
    local item = player.Items[slot]
    if not item or not item["?ptr"] or item["?ptr"] <= 0 then
        Log(Merge.Log.Error, "%s: GenerateItem: slot %s is not a valid item slot", LogId, tostring(slot))
        return nil, nil
    end

    item:Randomize(strength, itemType, true)

    if not IsCuratedItem(item) then
        Log(Merge.Log.Info, "%s: GenerateItem: re-rolled slot %d, not curated (roll had no Bonus/Bonus2)", LogId, slot)
    end
    return item, ItemTest.Inspect(item)
end

-- Prints an item's raw fields plus, if curated, its resolved prefix/suffix
-- and the stats they carry. Pass any structs.Item, e.g. Mouse.Item or
-- Party[0].Items[slot].
function ItemTest.Inspect(item)
    if not item or not item["?ptr"] or item["?ptr"] <= 0 then
        Log(Merge.Log.Error, "%s: Inspect: not a valid item", LogId)
        return nil
    end
    local prefix = GetItemPrefix(item)
    local suffix = GetItemSuffix(item)
    local lines = {
        string.format("Number=%d Bonus=%d BonusStrength=%d Bonus2=%d Charges=%d MaxCharges=%d",
            item.Number, item.Bonus, item.BonusStrength, item.Bonus2, item.Charges, item.MaxCharges),
        "Curated: " .. tostring(IsCuratedItem(item)),
    }
    if prefix then
        lines[#lines + 1] = "  Prefix: " .. prefix.name .. " " .. DumpStats(prefix.stats)
    end
    if suffix then
        lines[#lines + 1] = "  Suffix: " .. suffix.name .. " " .. DumpStats(suffix.stats)
    end
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: Inspect:\n%s", LogId, report)
    return report
end

-- =============================================================================
-- STAGE 4: stat/skill application on an equipped player
-- =============================================================================

-- Recomputes curated stat/skill totals for a real party member directly
-- (bypassing the CalcStatBonusByItems/GetSkill event dance) and prints them
-- with human-readable names, so you can cross-check against the character
-- screen without hunting through 40+ stats by hand. Equip a curated item on
-- this player first, or the result will just be empty.
function ItemTest.DumpPlayerBonuses(playerIndex)
    local I = Internal()
    local player = Party[playerIndex or 0]
    if not player then
        Log(Merge.Log.Error, "%s: DumpPlayerBonuses: no player at index %s", LogId, tostring(playerIndex))
        return nil
    end
    local statAcc, skillAcc = {}, {}
    I.SumCuratedBonuses(player, statAcc, skillAcc)

    local statNames, skillNames = {}, {}
    for name, id in pairs(I.StatMap) do
        statNames[id] = statNames[id] and (statNames[id] .. "/" .. name) or name
    end
    for name, id in pairs(I.SkillMap) do
        skillNames[id] = skillNames[id] and (skillNames[id] .. "/" .. name) or name
    end

    local lines = { "Player " .. tostring(playerIndex or 0) .. " curated bonuses:" }
    for statId, bonus in pairs(statAcc) do
        lines[#lines + 1] = string.format("  stat  %-16s +%d", statNames[statId] or ("#" .. statId), bonus)
    end
    for skillId, bonus in pairs(skillAcc) do
        lines[#lines + 1] = string.format("  skill %-16s +%d", skillNames[skillId] or ("#" .. skillId), bonus)
    end
    if #lines == 1 then
        lines[#lines + 1] = "  (none -- is a curated item actually equipped on this player?)"
    end
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: %s", LogId, report)
    return report
end

-- =============================================================================
-- STAGE 5: toggle revert/reapply round-trip
-- =============================================================================

local function ItemStateStr(item)
    return string.format("Bonus=%d BonusStrength=%d Bonus2=%d Charges=%d",
        item.Bonus, item.BonusStrength, item.Bonus2, item.Charges)
end

-- Takes a curated item (defaults to Mouse.Item) and exercises: revert
-- (toggle off + sync) -> verify vanilla restored -> reapply (toggle on +
-- sync) -> verify re-tagged with the SAME id it had before. Restores
-- Game.ItemSystemEnabled to whatever it was before the test either way.
--
-- Ground truth for "did revert restore the real vanilla values" comes from
-- the item's own CuratedItems entry (origBonus/origBonusStrength/
-- origBonus2), NOT from a state snapshot taken when this function starts --
-- the item is usually ALREADY suppressed at that point (Bonus/Bonus2 both
-- 0), so comparing against that snapshot instead of the recorded original
-- would flag a correct revert as a false failure whenever the item's real
-- vanilla roll had a nonzero Bonus2 (confirmed happening in testing: item
-- correctly reverted to Bonus2=67, but was compared against the
-- already-suppressed Bonus2=0 snapshot and wrongly reported FAIL).
--
-- Returns (report, pass) -- report is a full string so calling this bare at
-- the console shows the detail directly, without needing the log file.
function ItemTest.TestToggleRoundTrip(item)
    local I = Internal()
    item = item or Mouse.Item
    if not IsCuratedItem(item) then
        local msg = "TestToggleRoundTrip: item is not curated -- generate/pick one first"
        Log(Merge.Log.Error, "%s: %s", LogId, msg)
        return msg, false
    end
    local id = item.Charges
    local entry = I.GetCuratedItems()[id]
    if not entry then
        local msg = "TestToggleRoundTrip: item.Charges (" .. tostring(id) .. ") has no CuratedItems entry -- data inconsistency"
        Log(Merge.Log.Error, "%s: %s", LogId, msg)
        return msg, false
    end
    local wasEnabled = Game.ItemSystemEnabled
    local lines = { "before:  " .. ItemStateStr(item),
        string.format("recorded original: Bonus=%d BonusStrength=%d Bonus2=%d",
            entry.origBonus, entry.origBonusStrength, entry.origBonus2) }

    Game.ItemSystemEnabled = false
    SyncItemSystemToggle()
    lines[#lines + 1] = "reverted:" .. ItemStateStr(item)
    local revertedOk = item.Charges == 0
        and item.Bonus == entry.origBonus
        and item.BonusStrength == entry.origBonusStrength
        and item.Bonus2 == entry.origBonus2

    Game.ItemSystemEnabled = true
    SyncItemSystemToggle()
    lines[#lines + 1] = "reapplied:" .. ItemStateStr(item)
    local reappliedOk = item.Charges == id and item.Bonus == 0 and item.Bonus2 == 0

    Game.ItemSystemEnabled = wasEnabled
    SyncItemSystemToggle()

    local pass = revertedOk and reappliedOk
    lines[#lines + 1] = string.format("result: %s (reverted=%s reapplied=%s)",
        pass and "PASS" or "FAIL", tostring(revertedOk), tostring(reappliedOk))
    local report = table.concat(lines, "\n")
    Log(Merge.Log.Info, "%s: TestToggleRoundTrip:\n%s", LogId, report)
    return report, pass
end

-- =============================================================================
-- STAGE 6: pruning
-- =============================================================================

-- Reports the CuratedItems count before/after one prune pass. A no-op while
-- Game.ItemSystemEnabled is false (PruneCuratedItems skips itself then --
-- see ItemSystem.lua header for why).
function ItemTest.TestPrune()
    local I = Internal()
    local before = I.GetCuratedItems()
    local beforeCount = 0
    for _ in pairs(before) do beforeCount = beforeCount + 1 end

    I.PruneCuratedItems()

    local after = I.GetCuratedItems()
    local afterCount = 0
    for _ in pairs(after) do afterCount = afterCount + 1 end

    local report = string.format("CuratedItems: %d -> %d (pruned %d), nextId=%d, enabled=%s",
        beforeCount, afterCount, beforeCount - afterCount, I.GetNextCuratedId(), tostring(Game.ItemSystemEnabled))
    Log(Merge.Log.Info, "%s: TestPrune: %s", LogId, report)
    return report
end

-- =============================================================================
-- Convenience: run stages 1, 2/3, 5, 6 in one call and log a summary.
-- Stage 4 needs manual equipping so it's not included -- run
-- ItemTest.DumpPlayerBonuses(playerIndex) yourself after equipping the item
-- this generates.
--
-- REQUIRES an explicit slot -- see ItemTest.GenerateItem, this OVERWRITES
-- whatever is in that slot. Run ItemTest.DumpInventory(playerIndex) first.
-- =============================================================================
function ItemTest.RunAll(slot, playerIndex)
    if not slot then
        Log(Merge.Log.Error, "%s: RunAll: slot is required (this OVERWRITES that slot) -- run ItemTest.DumpInventory(playerIndex) first and pick one", LogId)
        return nil, false
    end
    Log(Merge.Log.Info, "%s: ==== RunAll starting ====", LogId)
    ItemTest.DumpAllClasses()
    local item = ItemTest.GenerateItem(slot, const.ItemType.Weapon, 5, playerIndex)
    if not item then
        local msg = "RunAll: GenerateItem did not produce a curated item -- see log above, try again"
        Log(Merge.Log.Error, "%s: %s", LogId, msg)
        return msg, false
    end
    local toggleReport, togglePass = ItemTest.TestToggleRoundTrip(item)
    ItemTest.TestPrune()
    Log(Merge.Log.Info, "%s: ==== RunAll finished: toggle round-trip %s ====",
        LogId, togglePass and "PASS" or "FAIL")
    return toggleReport, togglePass
end

Log(Merge.Log.Info, "%s: loaded, call ItemTest.DumpInventory(0) then ItemTest.RunAll(slot) or see file header for individual stages", LogId)
