-- =============================================================================
-- MMMerge Curated Item System — Tooltip/Info-Box Hooks
-- Scripts/General/ItemSystemTooltip.lua
-- =============================================================================
-- PHASE 2: replaces the native "Charges: N" line (which leaks our per-instance
-- curated id -- see ItemSystem.lua's WHY item.Charges header note) with a
-- readable description of the curated item's actual stat/skill bonuses, in
-- the item info box shown when examining an item.
--
-- Mechanism ported directly from Malekitsu/Maw-Mod-MMMerge
-- (Scripts/Structs/extraEditableDescriptions.lua; same file Phase 1's name
-- hook and this project's own StatTooltips.lua both derive from --
-- https://github.com/Malekitsu/Maw-Mod-MMMerge).
--
-- The item info box is built from FIVE independent text rows -- Type,
-- BasicStat, Enchantment ("Charges: N" lives here), Description, Name --
-- populated by three separate native call sites (Type/BasicStat/Enchantment
-- together at 0x41D40E, Description at a patched 0x41D441, Name at
-- 0x41D4BD), then rendered by two later passes (0x41D405-0x41D438 to
-- calculate text height, 0x41D591-0x41D5D1 to actually draw) that iterate
-- ALL FIVE rows through one shared indexed-address lookup table regardless
-- of which row you actually care about.
--
-- IMPORTANT: this file installs hooks for all five rows even though it only
-- actively changes Enchantment. The height/draw passes dereference every
-- row's slot in that lookup table unconditionally -- if a row's hook were
-- skipped, its slot would stay null (mem.StaticAlloc zero-initializes), and
-- the native loop would dereference a null pointer trying to read it. That
-- is the same crash class documented in ItemSystem.lua's/ItemSystemDebug.lua's
-- earlier incident (EAccessViolation from an under-populated data
-- structure), so all five rows are wired up as one unit; the other four
-- just pass their text through unchanged via processNewTexts.
--
-- Name is NOT overridden here -- ItemSystemDisplay.lua's Phase 1 hook
-- (structs.Item.GetName/GetIdentifiedName) already runs underneath this and
-- has already set the curated name by the time this file's Name-row hook
-- sees it; this file's Name row exists purely so its lookup slot is
-- populated (see IMPORTANT above), not to change anything.
--
-- Only item rows are ported (ROW_COUNT=5); MAW's monster-tooltip rows and
-- BuildMonsterInformationBox machinery use entirely separate addresses and
-- aren't needed here, so they're left out.
--
-- Toggle: gated by Game.ItemSystemEnabled (same flag as ItemSystem.lua).
-- =============================================================================

local LogId = "ItemSystemTooltip"
Log(Merge.Log.Info, "Init started: %s", LogId)

local u4 = mem.u4
local alloc, free = mem.allocMM, mem.freeMM
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch

-- =============================================================================
-- Curated stat/skill description text (what replaces "Charges: N")
-- =============================================================================

-- Single-line, no redundant prefix/suffix name headers (the item's title
-- already shows those, via ItemSystemDisplay.lua). Uses
-- ItemSystemInternal.FilterStatsForItem so this can never display a
-- weapon-skill bonus that SumCuratedBonuses (ItemSystem.lua) wouldn't
-- actually apply -- e.g. a Mace with "the Knight" suffix shows only its
-- Shield/Endurance stats, not the Sword bonus that suffix also carries.
--
-- Mirrors SumCuratedBonuses exactly (see ItemSystem.lua, per
-- README_ItemSystem.md "Stat Count Cap"): quality-scale, sum SAME-NAME
-- bonuses across prefix+suffix FIRST, then rank by value and keep only the
-- top MAX_ITEM_STATS -- attributes and skills compete together. (Skill
-- bonuses may additionally be capped at the viewing character's base skill
-- when applied -- that cap is per-character at query time, so the tooltip
-- shows the item's own values.)
local function CuratedEnchantmentText(item)
    local prefix, suffix = GetItemPrefix(item), GetItemSuffix(item)
    if not prefix and not suffix then return nil end

    local entry = ItemSystemInternal.GetCuratedEntry(item)
    local quality = (entry and entry.quality) or 0.60

    -- Sum same-name bonuses first...
    local totals = {}
    local function collectStats(stats)
        if not stats then return end
        local filtered = ItemSystemInternal.FilterStatsForItem(item, stats)
        for name, value in pairs(filtered) do
            if ItemSystemInternal.StatMap[name] or ItemSystemInternal.SkillMap[name] then
                local adj = math.max(1, math.floor(value * quality))
                totals[name] = (totals[name] or 0) + adj
            end
        end
    end
    collectStats(prefix and prefix.stats)
    collectStats(suffix and suffix.stats)

    -- ...then rank and keep only the top MAX_ITEM_STATS.
    local ranked = {}
    for name, value in pairs(totals) do
        ranked[#ranked + 1] = { name = name, value = value }
    end
    table.sort(ranked, function(a, b) return a.value > b.value end)

    local parts = {}
    for i = 1, math.min(ItemSystemInternal.MAX_ITEM_STATS, #ranked) do
        parts[#parts + 1] = ranked[i].name .. " +" .. ranked[i].value
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function events.BuildItemInformationBox(t)
    if not Game.ItemSystemEnabled then return end
    if t.Enchantment == nil then return end  -- only fires when native engine populated the row (Charges > 0)

    local ok, err = pcall(function()
        local text = CuratedEnchantmentText(t.Item)
        if text then
            t.Enchantment = text
        end
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: BuildItemInformationBox error: %s", LogId, err)
    end
end

-- =============================================================================
-- Row-text infrastructure (ported from extraEditableDescriptions.lua,
-- items-only subset -- ROW_COUNT=5, no monster rows)
-- =============================================================================

local ROW_COUNT = 5  -- Type, BasicStat, Enchantment, Description, Name
local INDEX_DESCRIPTION, INDEX_NAME = 3, 4
local dynamicTextRowAddresses = mem.StaticAlloc(ROW_COUNT * 4)
local dynamicTextRowContentsByIndex = {}

local function getAddrByIndex(index)
    return u4[dynamicTextRowAddresses + index * 4]
end

local function prepareTableItem(d, rows)
    local t = {}
    for _, row in pairs(rows) do
        t[row.name] = mem.string(row.addr)
        row.text = t[row.name]
    end
    t.Item = structs.Item:new(u4[d.ebp - 4])
    return t
end

local reallocAndCopyIfNeeded
do
    local allocatedSizes = {}
    -- returns address of buffer where text is stored and length of that buffer in bytes
    function reallocAndCopyIfNeeded(addr, oldStr, newStr)
        if addr and oldStr == newStr then
            assert(allocatedSizes[addr] >= #newStr + 1,
                string.format("[realloc text] assertion failed! Text %q (length %d) is same as before, but allocated size is smaller (%d)",
                    newStr, #newStr + 1, allocatedSizes[addr]))
            mem.copy(addr, newStr .. string.char(0))
            return addr, #newStr + 1
        end
        local newLen = #newStr + 1
        local allocatedSize = allocatedSizes[addr] or 0
        if not addr or allocatedSize < newLen then
            if addr then
                free(addr)
                allocatedSizes[addr] = nil
            end
            addr = alloc(newLen)
            allocatedSizes[addr] = newLen
        end
        mem.copy(addr, newStr .. string.char(0))
        return addr, allocatedSize
    end
end

-- content data has fields: buf, len (full buffer length)
local function processNewTexts(t, rows)
    for _, rowData in pairs(rows) do
        assert(rowData.index < ROW_COUNT)
        local contentData = tget(dynamicTextRowContentsByIndex, rowData.index)
        local buf, name = contentData.buf, rowData.name
        local current = (buf and mem.string(buf, contentData.len or nil, contentData.len and true or nil) or "")
        local bufNew, newLen = reallocAndCopyIfNeeded(buf, current, t[name])
        contentData.buf, rowData.addr, contentData.len = bufNew, bufNew, newLen
        u4[dynamicTextRowAddresses + rowData.index * 4] = bufNew
    end
end

local function itemTooltipEvent(t)
    events.cocall("BuildItemInformationBox", t)
end

-- Type/BasicStat/Enchantment, populated together
--[[
    0x270 - item type str
    0x20C - basic stat (like "Armor: +50")
    0x1A8 - enchantment/charges/power
    0x74  - full item name (assigned later, see ItemSystemDisplay.lua instead)
]]
autohook2(0x41D40E, function(d)
    local rows = {
        Type = { addr = d.ebp - 0x270, index = 0, name = "Type" },
        BasicStat = { addr = d.ebp - 0x20C, index = 1, name = "BasicStat" },
        Enchantment = { addr = d.ebp - 0x1A8, index = 2, name = "Enchantment" },
    }
    local t = prepareTableItem(d, rows)
    itemTooltipEvent(t)
    processNewTexts(t, rows)
end)

local hooks = HookManager{addresses = dynamicTextRowAddresses}

-- calc text height: change address ptr to index
asmpatch(0x41D405, [[
    and dword ptr [ebp-8],0
]], 9)

hooks.asmpatch(0x41D415, [[
    mov eax, dword [ebp - 8]
    mov eax, dword [%addresses% + eax * 4]
    cmp [eax], bl
]])

asmpatch(0x41D41C, "mov edx, eax")

asmpatch(0x41D438, "inc dword [ebp - 8]")

-- write text: change address ptr to index
asmpatch(0x41D591, [[
    and dword [ebp - 0x14], 0
]], 9)

hooks.asmpatch(0x41D5A1, [[
    mov eax, dword [ebp - 0x14]
    mov eax, dword [%addresses% + eax * 4]
    cmp [eax], bl
]])

hooks.asmpatch(0x41D5BB, [[
    mov edx, [ebp - 0x14]
    mov edx, [%addresses% + edx * 4]
    mov ecx,dword ptr [ebp-0x10]
]])

asmpatch(0x41D5D1, "inc dword [ebp - 0x14]")

-- Description row
local descCode = asmpatch(0x41D441, [[
    nop
    nop
    nop
    nop
    nop
    cmp [edi], bl
]])

hook(descCode, function(d)
    local rows = {
        Description = { addr = u4[d.edi + 0xC], index = INDEX_DESCRIPTION, name = "Description" },
    }
    local t = prepareTableItem(d, rows)
    itemTooltipEvent(t)
    processNewTexts(t, rows)
    d.edi = getAddrByIndex(INDEX_DESCRIPTION)
end)

-- Name row (pass-through only -- see header note; ItemSystemDisplay.lua
-- already set the curated name before this fires)
autohook(0x41D4BD, function(d)
    local rows = {
        Name = { addr = d.eax, index = INDEX_NAME, name = "Name" },
    }
    local t = prepareTableItem(d, rows)
    itemTooltipEvent(t)
    processNewTexts(t, rows)
    d.eax = getAddrByIndex(INDEX_NAME)
end)

hook(0x41D5DA, function(d)
    d.eax = getAddrByIndex(INDEX_DESCRIPTION)
end)

autohook(0x41D60C, function(d)
    d.eax = getAddrByIndex(INDEX_NAME)
end)

Log(Merge.Log.Info, "Init finished: %s", LogId)
