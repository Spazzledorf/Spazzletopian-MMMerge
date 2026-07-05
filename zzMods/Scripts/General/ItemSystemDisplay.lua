-- =============================================================================
-- MMMerge Curated Item System — Display Hooks
-- Scripts/General/ItemSystemDisplay.lua
-- =============================================================================
-- PHASE 1: shows the curated prefix/suffix in an item's displayed name, e.g.
-- "Unyielding Long Dagger of the Crusader" instead of the plain base name
-- that ItemSystem.lua's suppression otherwise leaves showing (curated items
-- have Bonus/Bonus2 zeroed, so the vanilla name-building code has nothing
-- to append on its own).
--
-- Mechanism ported directly from Malekitsu/Maw-Mod-MMMerge
-- (Scripts/Structs/extraEditableDescriptions.lua, "ITEM NAME HOOK" section;
-- https://github.com/Malekitsu/Maw-Mod-MMMerge). structs.Item.GetName
-- (0x453D3E for MM8) has a short jump right at its start, which is why a
-- plain mem.hookfunction can't intercept it directly -- this is the same
-- limitation ItemSystem.lua's header notes as the reason the original
-- Phase 3 name-display attempt was abandoned. MAW's approach: asmpatch the
-- exact 6-byte "test+je" dispatch at the start of GetName so it explicitly
-- jumps to GetIdentifiedName (0x453D58) when the item is identified -- the
-- same branch the original code already took, just written explicitly
-- instead of implicitly -- and the resulting patched address is then a
-- normal, simple hookfunction target. A second, direct hookfunction on
-- GetIdentifiedName covers the "identified" path, with a HookManager
-- toggle to avoid double-firing when GetName's patched jump lands there too
-- (both share getOwnBufferHookFunction, parameterized by whether the
-- caller only wants identified-item names).
--
-- Addresses confirmed matching this project's own structs.Item definition
-- (Scripts/Structs/01 common structs.lua: GetName/GetIdentifiedName use the
-- exact same values for MM8 as MAW's 0x453D3E/0x453D58) -- MAW and this
-- project share the same GOG MM8 + Rodril/MMMerge lineage, confirmed
-- working via HookManager/mem.asmpatch/mem.hookfunction, all of which this
-- project's own Scripts/Core/events.lua already relies on extensively for
-- its own event dispatch (e.g. the exact same mem.hookfunction call that
-- wraps structs.Item.Randomize to fire events.ItemGenerated).
--
-- For names <= 0x63 (99) chars, the native code already uses a shared
-- static buffer at 0x5E4888 and returns a pointer already equal to it --
-- our curated names ("Unyielding Long Dagger of the Crusader" et al.) are
-- always well under that, so we can just overwrite the buffer in place and
-- return the same pointer, no allocation needed. Only names longer than
-- that get their own allocated buffer (kept for fidelity to MAW's proven
-- code, though our name lengths should never actually hit it).
--
-- Toggle: gated by Game.ItemSystemEnabled (same flag as ItemSystem.lua).
--
-- PHASE 2 (see Scripts/General/ItemSystemTooltip.lua): the native item
-- tooltip separately shows "Charges: N" for any item with item.Charges > 0,
-- regardless of item type -- confirmed in testing, this leaks our curated
-- id as a nonsensical line on non-wand items. That's a much larger hook
-- (BuildItemInformationBox's dynamic text-row system), kept in its own
-- file so it can be tested/disabled independently of this one.
-- =============================================================================

local LogId = "ItemSystemDisplay"
Log(Merge.Log.Info, "Init started: %s", LogId)

local alloc, free = mem.allocMM, mem.freeMM

-- Builds the hook function for one of the two GetName/GetIdentifiedName
-- entry points. `identifiedNameOnly` mirrors MAW's own parameter -- it's
-- threaded through for fidelity to the source but this file doesn't
-- currently branch on it (curated items are always shown with their
-- curated name whether identified or not, since suppression already
-- happens at generation time regardless of identification state).
local function GetOwnBufferHookFunction(identifiedNameOnly)
    local itemNameBuf, itemNameBufLen
    return function(d, def, itemPtr)
        local defNamePtr = def(itemPtr)
        if not Game.ItemSystemEnabled then return defNamePtr end

        local ok, result = pcall(function()
            local item = structs.Item:new(itemPtr)
            local prefix, suffix = GetItemPrefix(item), GetItemSuffix(item)
            if not prefix and not suffix then return defNamePtr end

            local name = mem.string(defNamePtr)
            if prefix then name = prefix.name .. " " .. name end
            if suffix then name = name .. " of " .. suffix.name end

            local len = name:len()
            if len <= 0x63 then
                mem.copy(0x5E4888, name .. string.char(0))
                return defNamePtr
            end
            if not itemNameBuf or itemNameBufLen < len + 1 then
                if itemNameBuf then free(itemNameBuf) end
                itemNameBufLen = len + 1
                itemNameBuf = alloc(itemNameBufLen)
            end
            mem.copy(itemNameBuf, name .. string.char(0))
            return itemNameBuf
        end)
        if not ok then
            Log(Merge.Log.Error, "%s: GetOwnBufferHookFunction error: %s", LogId, result)
            return defNamePtr
        end
        return result
    end
end

local identifiedItemNameHooks = HookManager()
identifiedItemNameHooks.hookfunction(0x453D58, 1, 0, GetOwnBufferHookFunction(true))

local addr = mem.asmpatch(0x453D3E, [[
    test byte ptr [ecx+0x14],1
    je absolute 0x453D58
]], 0x6)

local secondHookFunc = GetOwnBufferHookFunction(false)
mem.hookfunction(addr, 1, 0, function(d, def, itemPtr)
    identifiedItemNameHooks.Switch(false)
    local r = secondHookFunc(d, def, itemPtr)
    identifiedItemNameHooks.Switch(true)
    return r
end)

Log(Merge.Log.Info, "Init finished: %s", LogId)
