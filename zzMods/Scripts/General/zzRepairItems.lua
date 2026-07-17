-- =============================================================================
-- zzRepairItems – Console-callable item-system repair utilities
-- =============================================================================
-- Run from console after a game is loaded:
--   RepairItems()       — clears orphaned charges, prints status
--   RepairItems(true)   — also forces PruneCuratedItems (removes entries for
--                         items the party no longer has)
--   RecurateItems()     — re-curates orphaned items (creates new CuratedItems
--                         entries for items that lost their data)
-- =============================================================================

local random = math.random

-- Replicates ItemSystem.lua's internal RollQuality (README_ItemSystem.md
-- "Stat Variance — Quality": quality in [0.35, 1.00] over 124 levels; pool
-- values are maximums).
-- NOTE: local on purpose -- these are copies of ItemSystem.lua internals and
-- must not leak into the global namespace (and if ItemSystem's tuning changes,
-- update these copies to match).
local function RollQuality()
    local avgLevel = 1
    if Party and Party.Players then
        local total, n = 0, 0
        for _, p in Party.Players do
            -- LevelBase is the real Player field (ExpForLevel never existed).
            if p and p.LevelBase then
                total = total + p.LevelBase
                n = n + 1
            end
        end
        if n > 0 then avgLevel = math.max(1, total / n) end
    end
    local progress = math.min(1, (avgLevel - 1) / 124)
    local minQ = 0.35 + progress * 0.40
    local maxQ = 0.55 + progress * 0.45
    return minQ + random() * (maxQ - minQ)
end

-- Replicates ItemSystem.lua's internal IsExcludedItem.
-- Returns true for spell scrolls (handled elsewhere, never targetable).
local function IsExcludedItem(num)
    return (num > 299  and num < 400)   -- MM7 spell scrolls
        or (num > 1101 and num < 1202)  -- MM6 spell scrolls
        or (num > 1801 and num < 1902)  -- MM8 spell scrolls
end

-- Recurate orphaned items that lost their CuratedItems entries.
-- Each orphan gets a fresh prefix/suffix selected based on the current party.
-- Compute a safe starting id: the persisted counter, raised above the highest
-- existing entry id. Guard against a stale/low persisted counter (observed:
-- counter 70 with entries up to ~172 in the same save): allocating below the
-- max existing id would silently OVERWRITE live entries, cross-linking items.
local function SafeNextId(curated)
    local nextId = ItemSystemInternal.GetNextCuratedId()
    for id in pairs(curated) do
        if type(id) == "number" and id >= nextId then
            nextId = id + 1
        end
    end
    return nextId
end

-- Push the id counter back into ItemSystem + the current save data so
-- ItemSystem's own generation doesn't overwrite entries we created.
local function SyncCounter(nextId)
    if internal and internal.SaveGameData then
        internal.SaveGameData.NextCuratedId = nextId
    end
    local upvOk, upvErr = pcall(function()
        debug.setupvalue(ItemSystemInternal.GetNextCuratedId, 1, nextId)
    end)
    if not upvOk then
        print(string.format("  WARNING: NextCuratedId sync failed: %s", upvErr))
    end
end

-- Curate ONE item in place: pick a class-appropriate prefix/suffix, create a
-- named-field entry (array-format entries lose their numeric keys in the save
-- round-trip -- see ItemSystem.lua's entry accessors), tag the item, and
-- suppress its vanilla enchant (originals preserved in the entry). Shared by
-- RecurateItems (tagged orphans) and SalvageLegacyItems (tagless legacy).
-- Returns the new nextId on success, nil on skip.
local function CurateOneItem(item, curated, nextId)
    local requiredSkill = ItemSystemInternal.GetItemRequiredSkill(item)
    local p = ItemSystemInternal.RandomPartyMember(requiredSkill)
    if not p then return nil end

    local class = p.Class
    local line = ItemSystemInternal.ClassToLine[class]
    if not line then return nil end

    local bucket = ItemSystemInternal.LineToBucket[line]
    local tier = ItemSystemInternal.ClassTier[class] or 0
    local alignment = ItemSystemInternal.ClassAlignment[class] or "any"

    local prefixPool = ItemSystemInternal.Pools.Prefixes[bucket]
    local suffixPool = ItemSystemInternal.Pools.Suffixes[line]
    if not prefixPool or not suffixPool then return nil end

    local prefix = ItemSystemInternal.SelectPrefix(prefixPool, alignment, requiredSkill)
    if not prefix then return nil end
    local suffix = ItemSystemInternal.SelectSuffix(suffixPool, tier, alignment, requiredSkill)
    if not suffix then return nil end

    curated[nextId] = {
        prefixId = prefix._prefixId,
        suffixId = suffix._suffixId,
        num      = item.Number or 0,
        bonus    = item.Bonus or 0,
        bonusStr = item.BonusStrength or 0,
        bonus2   = item.Bonus2 or 0,
        quality  = RollQuality(),
    }
    item.Charges = nextId
    -- Suppress the vanilla enchant so only the curated bonuses apply (the
    -- helper must be self-contained -- do not rely on a later sweep).
    item.Bonus = 0
    item.BonusStrength = 0
    item.Bonus2 = 0
    return nextId + 1
end

function RecurateItems()
    if not ItemSystemInternal then
        print("RecurateItems: ItemSystem not loaded — cannot re-curate")
        return
    end
    if not Party or not Party.Players then
        print("RecurateItems: Party not available (load a game first)")
        return
    end

    local curated = ItemSystemInternal.GetCuratedItems()
    if not curated then
        print("RecurateItems: CuratedItems table is nil")
        return
    end

    local nextId = SafeNextId(curated)
    local recurated = 0
    local total = 0
    local errors = 0

    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0 then
                total = total + 1
                if item.Charges and item.Charges > 0 and not (item.MaxCharges and item.MaxCharges > 0) then
                    if not IsCuratedItem(item) and not IsExcludedItem(item.Number)
                            and ItemSystemInternal.IsCuratableType(item) then
                        local ok, err = pcall(function()
                            local newId = CurateOneItem(item, curated, nextId)
                            if newId then
                                nextId = newId
                                recurated = recurated + 1
                            end
                        end)
                        if not ok then
                            errors = errors + 1
                            print(string.format("  ERROR re-curating item #%d slot %d: %s", item.Number or 0, slot, err))
                            Log(Merge.Log.Error, "zzRepairItems: RecurateItems error item #%d slot %d: %s", item.Number or 0, slot, tostring(err))
                        end
                    end
                end
            end
        end
    end

    if recurated > 0 or errors > 0 then
        SyncCounter(nextId)
    end
    if recurated > 0 then
        Game.NeedRedraw = true
        if ItemSystemInternal.InvalidateBonusCache then
            ItemSystemInternal.InvalidateBonusCache()  -- may have tagged EQUIPPED items
        end
    end
    print(string.format("RecurateItems: scanned %d items, re-curated %d, errors %d", total, recurated, errors))
    Log(Merge.Log.Info, "zzRepairItems: RecurateItems scanned %d, re-curated %d, errors %d", total, recurated, errors)
    if recurated > 0 then
        print(string.format("  New NextCuratedId: %d. Open inventory to see stat/tooltip changes.", nextId))
    end
end

-- =============================================================================
-- SalvageLegacyItems — restore items that lost BOTH their tag and bonuses
-- =============================================================================
-- Earlier buggy sessions stripped some curated items of their Charges tags
-- (entries pruned, then dangling tags cleared, then saved) AND their vanilla
-- bonuses (suppressed at curation). Such items are invisible to tag-based
-- recuration and look identical to ordinary common items -- EXCEPT the save
-- still carries the old legacy-format entries (itemNumber/origBonus* fields,
-- unresolvable old prefix/suffix id space) recording which item Numbers were
-- once curated. Use those as the salvage discriminator: any completely-plain,
-- untagged party item whose Number appears among the legacy entries gets a
-- fresh curation.
--
-- Deliberate behaviors:
--  * Legacy entries are NOT deleted afterwards: curated items still sitting in
--    chests can only be salvaged when later picked up, so the markers must
--    persist (they're tiny).
--  * Known accepted quirk: a genuinely-common item whose Number matches a
--    legacy marker also gets curated. Benign -- it would be curated as a
--    fresh drop anyway.
function SalvageLegacyItems()
    if not ItemSystemInternal or not ItemSystemInternal.EntryNumber then return end
    if not Party or not Party.Players then return end
    local curated = ItemSystemInternal.GetCuratedItems()
    if not curated then return end

    -- One-shot convergence: once salvage has found nothing to do on several
    -- consecutive loads, mark this SAVE as done and stop scanning. Without
    -- this, the persistent legacy markers made salvage PERPETUAL: every
    -- plain common item whose Number matched a marker got curated on every
    -- load, forever -- over-curating fresh shop purchases and inflating the
    -- id counter (2026-07-16 hostile-QA finding). Per-save flag: an old save
    -- that never converged still salvages normally when loaded.
    local sgd = internal and internal.SaveGameData
    if sgd and sgd.LegacySalvageDone then return end

    -- Collect item Numbers referenced by legacy (unresolvable) entries.
    local legacyNumbers = {}
    local legacyCount = 0
    for _, entry in pairs(curated) do
        local num = ItemSystemInternal.EntryNumber(entry)
        if num and not ItemSystemInternal.IsEntryResolvable(entry) then
            legacyNumbers[num] = true
            legacyCount = legacyCount + 1
        end
    end
    if legacyCount == 0 then
        if sgd then sgd.LegacySalvageDone = true end
        Log(Merge.Log.Info, "zzRepairItems: SalvageLegacyItems -- no legacy markers, marking save done")
        return
    end

    local nextId = SafeNextId(curated)
    local salvaged = 0
    local errors = 0

    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0
                    and (not item.Charges or item.Charges == 0)
                    and not (item.MaxCharges and item.MaxCharges > 0)
                    and (item.Bonus or 0) == 0
                    and (item.BonusStrength or 0) == 0
                    and (item.Bonus2 or 0) == 0
                    and not IsExcludedItem(item.Number)
                    and ItemSystemInternal.IsCuratableType(item)
                    and legacyNumbers[item.Number] then
                local ok, err = pcall(function()
                    local newId = CurateOneItem(item, curated, nextId)
                    if newId then
                        nextId = newId
                        salvaged = salvaged + 1
                    end
                end)
                if not ok then
                    errors = errors + 1
                    Log(Merge.Log.Error, "zzRepairItems: SalvageLegacyItems error item #%d slot %d: %s", item.Number or 0, slot, tostring(err))
                end
            end
        end
    end

    if salvaged > 0 or errors > 0 then
        SyncCounter(nextId)
    end
    if salvaged > 0 then
        Game.NeedRedraw = true
        if ItemSystemInternal.InvalidateBonusCache then
            ItemSystemInternal.InvalidateBonusCache()  -- may have tagged EQUIPPED items
        end
    end

    -- Convergence accounting: after 3 consecutive loads with nothing salvaged
    -- (and no errors), finalize -- delete the now-consumed legacy markers and
    -- flag the save so this pass never runs again. Items still in unvisited
    -- chests after that window come back plain (documented limitation).
    if sgd then
        if salvaged == 0 and errors == 0 then
            sgd.LegacySalvageIdle = (tonumber(sgd.LegacySalvageIdle) or 0) + 1
            if sgd.LegacySalvageIdle >= 3 then
                local removed = 0
                for id, entry in pairs(curated) do
                    local num = ItemSystemInternal.EntryNumber(entry)
                    if num and not ItemSystemInternal.IsEntryResolvable(entry) then
                        curated[id] = nil
                        removed = removed + 1
                    end
                end
                sgd.LegacySalvageDone = true
                Log(Merge.Log.Info, "zzRepairItems: SalvageLegacyItems finalized -- removed %d legacy marker(s), save flagged done", removed)
            end
        else
            sgd.LegacySalvageIdle = 0
        end
    end

    print(string.format("SalvageLegacyItems: %d legacy markers, salvaged %d item(s), errors %d", legacyCount, salvaged, errors))
    Log(Merge.Log.Info, "zzRepairItems: SalvageLegacyItems markers %d, salvaged %d, errors %d", legacyCount, salvaged, errors)
end

function RepairItems(full)
    local fixed = 0
    local total = 0

    if not Party or not Party.Players then
        print("RepairItems: Party not available (load a game first)")
        return
    end

    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0 then
                total = total + 1
                if item.Charges and item.Charges > 0 and not (item.MaxCharges and item.MaxCharges > 0) then
                    local isCurated = false
                    if ItemSystemInternal then
                        isCurated = IsCuratedItem(item)
                    end
                    if not isCurated then
                        item.Charges = 0
                        fixed = fixed + 1
                    end
                end
            end
        end
    end

    print(string.format("RepairItems: scanned %d items, cleared %d orphaned Charges", total, fixed))
    Log(Merge.Log.Info, "zzRepairItems: RepairItems scanned %d, cleared %d orphaned Charges", total, fixed)
    if fixed > 0 then
        Game.NeedRedraw = true
        print("  A redraw has been queued. Open/reopen the inventory to see changes.")
    end

    if full then
        if ItemSystemInternal then
            ItemSystemInternal.PruneCuratedItems()
            print("  PruneCuratedItems() done.")
        else
            print("  ItemSystem not loaded — cannot prune.")
        end
    end

    if ItemSystemInternal then
        print(string.format("  ItemSystem: %d entries", (ItemSystemInternal.GetNextCuratedId() or 1) - 1))
    else
        print("  WARNING: ItemSystemInternal is nil — ItemSystem.lua may not be loaded!")
        print("  Check that Scripts/General/ItemSystem.lua exists and can be loaded.")
    end
end

-- One-time migration sweep: items curated by the interim "hybrid" build kept
-- their vanilla Bonus fields live, so the native engine applied the vanilla
-- enchant invisibly ON TOP of the curated bonuses (double-dipping, reported
-- in play-testing 2026-07-16). Curation now zeroes those fields at generation
-- (originals preserved in the CuratedItems entry); this sweep applies the
-- same suppression to already-existing curated items carried in saves.
-- Un-curate consumables that older versions wrongly tagged (potions/reagents
-- store their POWER in item.Bonus, so curation's vanilla-suppression zeroed
-- it -- found in playtesting 2026-07-17). Restores the original Bonus fields
-- from the curated entry (which preserved them), clears the tag, and deletes
-- the entry. Runs on every load, not one-shot: damaged consumables still in
-- chests can only be repaired when picked up later. A tagged consumable whose
-- entry is gone (pruned earlier) can only be untagged -- its power is
-- unrecoverable; it becomes a plain zero-power potion rather than a fake
-- curated one.
function RestoreConsumables()
    if not ItemSystemInternal or not ItemSystemInternal.IsCuratableType then return end
    if not Party or not Party.Players then return end
    local curated = ItemSystemInternal.GetCuratedItems()
    local restored, untagged = 0, 0

    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0
                    and item.Charges and item.Charges > 0
                    and not (item.MaxCharges and item.MaxCharges > 0)
                    and not ItemSystemInternal.IsCuratableType(item) then
                local ok, err = pcall(function()
                    local entry = curated and curated[item.Charges]
                    if entry and ItemSystemInternal.EntryNumber(entry) == item.Number then
                        item.Bonus         = ItemSystemInternal.EntryBonus(entry) or 0
                        item.BonusStrength = ItemSystemInternal.EntryBonusStr(entry) or 0
                        item.Bonus2        = ItemSystemInternal.EntryBonus2(entry) or 0
                        curated[item.Charges] = nil
                        restored = restored + 1
                    else
                        untagged = untagged + 1
                    end
                    item.Charges = 0
                end)
                if not ok then
                    Log(Merge.Log.Error, "zzRepairItems: RestoreConsumables error item #%d slot %d: %s", item.Number or 0, slot, tostring(err))
                end
            end
        end
    end

    if restored > 0 or untagged > 0 then
        if ItemSystemInternal.InvalidateBonusCache then
            ItemSystemInternal.InvalidateBonusCache()
        end
        Game.NeedRedraw = true
        Log(Merge.Log.Info, "zzRepairItems: RestoreConsumables restored %d (power recovered), untagged %d (power lost)", restored, untagged)
        print(string.format("RestoreConsumables: restored %d consumable(s), untagged %d with no recoverable data", restored, untagged))
    end
end

function SuppressVanillaOnCurated()
    if not ItemSystemInternal or not Party or not Party.Players then return end
    local suppressed = 0
    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0
                    and item.Charges and item.Charges > 0
                    and not (item.MaxCharges and item.MaxCharges > 0)
                    and IsCuratedItem(item) then
                if (item.Bonus or 0) > 0 or (item.BonusStrength or 0) > 0 or (item.Bonus2 or 0) > 0 then
                    item.Bonus = 0
                    item.BonusStrength = 0
                    item.Bonus2 = 0
                    suppressed = suppressed + 1
                end
            end
        end
    end
    if suppressed > 0 then
        Game.NeedRedraw = true
        print(string.format("SuppressVanillaOnCurated: suppressed vanilla enchants on %d curated item(s)", suppressed))
    end
end

-- Final cleanup: any item still carrying a tag that resolves to no entry
-- after recuration (excluded types, pool misses, errors) would leak the raw
-- id as a native "Charges: N" tooltip line forever -- clear those tags.
-- Runs LAST, after recuration has had its chance (ItemSystem.lua's own
-- save-load handler intentionally leaves stale tags alone for this reason).
local function ClearLeftoverOrphans()
    if not ItemSystemInternal or not Party or not Party.Players then return end
    local cleared = 0
    for _, player in Party.Players do
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0
                    and item.Charges and item.Charges > 0
                    and not (item.MaxCharges and item.MaxCharges > 0)
                    and not IsCuratedItem(item) then
                item.Charges = 0
                cleared = cleared + 1
            end
        end
    end
    if cleared > 0 then
        if ItemSystemInternal.InvalidateBonusCache then
            ItemSystemInternal.InvalidateBonusCache()  -- may have untagged EQUIPPED items
        end
        Log(Merge.Log.Info, "zzRepairItems: cleared %d leftover orphaned tag(s)", cleared)
    end
end

-- Auto-run on save load (WasInGame=false means fresh load, not combat return).
-- Order matters: ItemSystem.lua's LoadMapScripts (runs first, file-load order)
-- re-binds CuratedItems from the loaded save; then we re-curate orphans,
-- suppress any lingering vanilla double-dips, and clear unfixable tags.
function events.LoadMapScripts(WasInGame)
    if not WasInGame then
        RecurateItems()          -- tagged orphans -> fresh curation
        SalvageLegacyItems()     -- tagless legacy items -> fresh curation
        RestoreConsumables()     -- un-curate wrongly-tagged potions/reagents
        SuppressVanillaOnCurated()
        ClearLeftoverOrphans()
    end
end

print("zzRepairItems.lua loaded — RecurateItems() runs automatically on save load. Manual: RecurateItems() or RepairItems() from console.")
