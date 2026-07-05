-- =============================================================================
-- MMMerge Curated Item System — Runtime Logic
-- Scripts/General/ItemSystem.lua
-- =============================================================================
-- Hooks into events.ItemGenerated to REPLACE vanilla random enchantments with
-- curated prefix/suffix pairs from ItemPools.lua (not additive — see below).
--
-- WHAT THIS FILE DOES:
--   1. When a magic item drops, select a prefix (role) and suffix (class)
--      from ItemPools.lua based on a random party member's class.
--   2. Suppress the vanilla enchantment on that specific item instance
--      (item.Bonus/BonusStrength AND item.Bonus2 are all zeroed — these are
--      two INDEPENDENT vanilla enchantment slots, STDITEMS.TXT and
--      SPCITEMS.TXT respectively; an item can roll either one alone or both
--      at once — the engine now treats it as a common item for both stat
--      calc and name display) and tag the item with a per-instance curated
--      id stored in item.Charges.
--   3. Apply the curated stat/skill bonuses via events.CalcStatBonusByItems
--      and events.GetSkill when the player has the item equipped — this is
--      now the ONLY source of bonus for that item, not stacked on vanilla.
--
--   Name display in tooltips/inventory is handled by ItemSystemDisplay.lua
--   (Phase 1), which patches the GetName native call site to inject the
--   curated prefix/suffix onto the displayed item name. An earlier draft of
--   this file called Game.ShowStatusText() here to announce the name at
--   "drop" time, but events.ItemGenerated also fires for items generated into
--   UNOPENED chests during map refill (confirmed via MMExtension.htm's note
--   on "artifacts generated in unopened chests... upon map refill", and
--   ExtraArtifacts.lua hooking this same event for chest-refill logic) — so
--   that call would have fired misleading "Found: X" popups for chest
--   contents nobody had touched yet, possibly in bursts on map load/refill.
--   It was removed for that reason.
--
-- WHY item.Charges AND NOT item.Bonus2:
--   A prior version of this system encoded ids into item.Bonus2 and it
--   crashed the game when the engine read stray values there as SpcItemsTxt
--   indices. item.Charges/MaxCharges is normally only meaningful for
--   charge-based items (wands). We only ever tag an item when
--   item.MaxCharges == 0 at generation time — i.e. the vanilla roll itself
--   proved this item type never uses charges — so repurposing Charges as our
--   id field cannot collide with real charge state. Items that DO use
--   charges (MaxCharges > 0) are left completely untouched by this system.
--   Bonus2 IS zeroed as part of suppression (see SuppressAndTag) — that's
--   safe because it's always either 0 or the item's own original vanilla
--   value (see RestoreVanilla). The crash-prone thing was writing an
--   ENCODED ID into Bonus2, which never happens — the id only ever lives
--   in Charges.
--
-- WHAT THIS FILE DOES NOT TOUCH:
--   - Common items (both Bonus and Bonus2 are 0 at generation time)
--   - Spell scrolls (item numbers handled by ItemsModifiers.lua)
--   - Charge-based items (MaxCharges > 0 at generation time — wands, etc.)
--   - Base item type, material, damage dice — untouched
--
-- KNOWN LIMITATIONS (read before relying on this in a real playthrough):
--   - Curated names ARE shown in tooltips/inventory (ItemSystemDisplay.lua
--     patches the GetName call site to inject the curated prefix/suffix). The
--     engine's name construction routine can't be hooked directly (short jump
--     at the call site), but ItemSystemDisplay.lua works around this via an
--     asmpatch that makes GetName a plain hookfunction target. See that file
--     for the full mechanism (ported from Malekitsu/Maw-Mod-MMMerge).
--   - Vendor price: structs.Item:GetValue returns only base price (item.Bonus
--     is 0). A mem.hookfunction approach caused EAccessViolation crashes.
--     Disabled for now — curated items sell at common-item base price.
--     ItemsModifiers.lua bonus-keyed logic is unaffected (curated items never
--     carry vanilla Bonuses, so those code paths simply don't trigger).
--   - Pruning (see PruneCuratedItems below) only sees items currently in
--     the party's inventory. An item sitting in an unvisited chest or on
--     the ground can have its CuratedItems entry pruned while it's away;
--     if that happens, picking it back up later just makes it a plain item
--     again (no crash — GetCuratedEntry returns nil and no bonus applies).
--
-- FILE LOCATIONS:
--   This file: Scripts/General/ItemSystem.lua   (auto-loaded by RunFiles)
--   Pool data: Scripts/Items/ItemPools.lua      (loaded via dofile below)
--
-- TOGGLE:
--   Game.ItemSystemEnabled (default true). Follows the same Game.<X>Enabled
--   convention as Cleave.lua / ManaShield.lua / Retaliation.lua / Guardian.lua.
--   - New drops: generated as curated (suppressed+tagged) while true, left
--     100% vanilla while false.
--   - Existing items: reconciled by SyncItemSystemToggle(), which runs
--     automatically after the menu toggle state is restored on game load
--     (events.AfterLoadMap) and can also be called manually right after
--     flipping the flag for an immediate effect
--     mid-session (e.g. from the debug console: `Game.ItemSystemEnabled =
--     false; SyncItemSystemToggle()`). Toggling off restores every tagged
--     item's original vanilla Bonus/BonusStrength; toggling back on re-tags
--     any item whose current (Number, Bonus, BonusStrength, Bonus2) still
--     matches a previously recorded curated entry.
-- =============================================================================

local LogId = "ItemSystem"
Log(Merge.Log.Info, "Init started: %s", LogId)

Game.ItemSystemEnabled = (Game.ItemSystemEnabled == nil) and true or Game.ItemSystemEnabled

-- Pool data lives in Items/ to keep it separate from logic.
-- AppPath is set by main.lua before General/*.lua runs.
local Pools = dofile(AppPath.."Scripts/Items/ItemPools.lua")
local random = math.random

-- =============================================================================
-- POOL INDICES
-- Flat lookup tables built once from ItemPools.lua so a persisted small int
-- id (prefixId / suffixId) can be resolved back to a pool entry at runtime.
-- ORDER MUST NEVER CHANGE — changing bucket/line order, or entry order within
-- a pool, reassigns ids and desyncs existing saves' CuratedItems entries.
-- =============================================================================
local BUCKET_ORDER = {
    "Tank", "Warrior", "HybridIntellect", "HybridPersonality",
    "Intellect", "Personality", "Druid", "Ranger",
}
local LINE_ORDER = {
    "KnightLine", "BarbarianLine", "ArcherLine", "DeerslayerLine",
    "ThiefLine", "PaladinLine", "MonkLine", "VampireLine",
    "MinotaurLine", "SorcererLine", "NecromancerLine", "ClericLine",
    "DragonLine", "DruidLine", "RangerLine",
}

-- Runtime lookup tables populated during GameInitialized2
local IdToPrefix = {}   -- [prefixId] = prefix entry table
local IdToSuffix = {}   -- [suffixId] = suffix entry table

local function BuildIndices()
    local pid = 0
    for _, bucket in ipairs(BUCKET_ORDER) do
        local pool = Pools.Prefixes[bucket]
        if pool then
            for _, entry in ipairs(pool) do
                pid = pid + 1
                IdToPrefix[pid] = entry
                entry._prefixId = pid
            end
        end
    end
    local sid = 0
    for _, line in ipairs(LINE_ORDER) do
        local pool = Pools.Suffixes[line]
        if pool then
            for _, entry in ipairs(pool) do
                sid = sid + 1
                IdToSuffix[sid] = entry
                entry._suffixId = sid
            end
        end
    end
    Log(Merge.Log.Info, "%s: Indexed %d prefixes, %d suffixes", LogId, pid, sid)
end

-- =============================================================================
-- CLASS METADATA TABLES
-- Derived from Scripts/Structs/20_MergeConsts.lua const.Class entries.
-- Comment format: ClassKind/PromotionLevel/Alignment (N=Neutral, G=Good/Light, E=Evil/Dark)
-- All *3 suffix variants are MM7/MM8 dual-path versions of the same promotion tier.
-- =============================================================================

local ClassToLine = {
    -- =========================================================================
    -- ARCHER LINE  (HybridIntellect bucket)
    -- ClassKind 1: Archer → WarriorMage → BattleMage/MasterArcher/Sniper
    -- =========================================================================
    [const.Class.Archer]            = "ArcherLine",  -- 1/0
    [const.Class.WarriorMage]       = "ArcherLine",  -- 1/1
    [const.Class.BattleMage]        = "ArcherLine",  -- 1/2/N
    [const.Class.BattleMage3]       = "ArcherLine",  -- 1/3/N
    [const.Class.MasterArcher]      = "ArcherLine",  -- 1/2/G
    [const.Class.MasterArcher3]     = "ArcherLine",  -- 1/3/G
    [const.Class.Sniper]            = "ArcherLine",  -- 1/2/E
    [const.Class.Sniper3]           = "ArcherLine",  -- 1/3/E

    -- =========================================================================
    -- CLERIC LINE  (Personality bucket)
    -- ClassKind 2: Cleric/AcolyteLight/AcolyteDark → Priest/ClericLight/ClericDark
    --           → HighPriest/PriestLight/PriestDark
    -- NOTE: Cleric (tier 0) and Priest (tier 1) are distinct class IDs in MMMerge.
    -- AcolyteLight/AcolyteDark are the light/dark-aligned Cleric base classes.
    -- ClericLight/ClericDark are their first promotions (tier 1, NOT tier 0).
    -- =========================================================================
    [const.Class.Cleric]            = "ClericLine",  -- 2/0/N
    [const.Class.AcolyteLight]      = "ClericLine",  -- 2/0/G
    [const.Class.AcolyteDark]       = "ClericLine",  -- 2/0/E
    [const.Class.Priest]            = "ClericLine",  -- 2/1/N
    [const.Class.ClericLight]       = "ClericLine",  -- 2/1/G
    [const.Class.ClericDark]        = "ClericLine",  -- 2/1/E
    [const.Class.HighPriest]        = "ClericLine",  -- 2/2/N
    [const.Class.HighPriest3]       = "ClericLine",  -- 2/3/N
    [const.Class.PriestLight]       = "ClericLine",  -- 2/2/G
    [const.Class.PriestLight3]      = "ClericLine",  -- 2/3/G
    [const.Class.PriestDark]        = "ClericLine",  -- 2/2/E
    [const.Class.PriestDark3]       = "ClericLine",  -- 2/3/E

    -- =========================================================================
    -- DEERSLAYER LINE  (HybridIntellect bucket)
    -- ClassKind 3: Deerslayer (MM8 Dark Elf renamed) → Pioneer → Pathfinder/Light/Dark
    -- NOTE: const.Class.Pioneer is spelled correctly (2 e's) in MergeConsts.lua.
    --   Previous code incorrectly used const.Class.Pioneeer (3 e's — only a typo
    --   in Promotions.lua's internal reference, not in the const definition itself).
    -- =========================================================================
    [const.Class.Deerslayer]        = "DeerslayerLine",  -- 3/0
    [const.Class.Pioneer]           = "DeerslayerLine",  -- 3/1
    [const.Class.Pathfinder]        = "DeerslayerLine",  -- 3/2/N
    [const.Class.Pathfinder3]       = "DeerslayerLine",  -- 3/3/N
    [const.Class.PathfinderLight]   = "DeerslayerLine",  -- 3/2/G
    [const.Class.PathfinderLight3]  = "DeerslayerLine",  -- 3/3/G
    [const.Class.PathfinderDark]    = "DeerslayerLine",  -- 3/2/E
    [const.Class.PathfinderDark3]   = "DeerslayerLine",  -- 3/3/E

    -- =========================================================================
    -- DRAGON LINE  (Personality bucket)
    -- ClassKind 4: Dragon → FlightLeader → GreatWyrm/DragonLight/DragonDark
    -- =========================================================================
    [const.Class.Dragon]            = "DragonLine",  -- 4/0
    [const.Class.FlightLeader]      = "DragonLine",  -- 4/1
    [const.Class.GreatWyrm]         = "DragonLine",  -- 4/2/N
    [const.Class.GreatWyrm3]        = "DragonLine",  -- 4/3/N
    [const.Class.DragonLight2]      = "DragonLine",  -- 4/2/G
    [const.Class.DragonLight3]      = "DragonLine",  -- 4/3/G
    [const.Class.DragonDark2]       = "DragonLine",  -- 4/2/E
    [const.Class.DragonDark3]       = "DragonLine",  -- 4/3/E

    -- =========================================================================
    -- DRUID LINE  (Druid bucket)
    -- ClassKind 5: Druid → GreatDruid → MasterDruid/ArchDruid/Warlock
    -- =========================================================================
    [const.Class.Druid]             = "DruidLine",  -- 5/0
    [const.Class.GreatDruid]        = "DruidLine",  -- 5/1
    [const.Class.MasterDruid]       = "DruidLine",  -- 5/2/N
    [const.Class.MasterDruid3]      = "DruidLine",  -- 5/3/N
    [const.Class.ArchDruid]         = "DruidLine",  -- 5/2/G
    [const.Class.ArchDruid3]        = "DruidLine",  -- 5/3/G
    [const.Class.Warlock]           = "DruidLine",  -- 5/2/E
    [const.Class.Warlock3]          = "DruidLine",  -- 5/3/E

    -- =========================================================================
    -- KNIGHT LINE  (Tank bucket)
    -- ClassKind 6: Knight → Cavalier → Champion/Templar/BlackKnight
    -- NOTE: Champion (46) is NEUTRAL (6/2/N). Templar (48) is the light Knight.
    --   The old code wrongly put Champion in ClassAlignment as "light".
    --   Templar exists in the const table but is not reachable in normal gameplay;
    --   mapping it here so it works in debug/testing contexts.
    -- =========================================================================
    [const.Class.Knight]            = "KnightLine",  -- 6/0
    [const.Class.Cavalier]          = "KnightLine",  -- 6/1
    [const.Class.Champion]          = "KnightLine",  -- 6/2/N  (neutral — NOT light!)
    [const.Class.Champion3]         = "KnightLine",  -- 6/3/N
    [const.Class.Templar]           = "KnightLine",  -- 6/2/G  (inaccessible in gameplay)
    [const.Class.Templar3]          = "KnightLine",  -- 6/3/G
    [const.Class.BlackKnight]       = "KnightLine",  -- 6/2/E
    [const.Class.BlackKnight3]      = "KnightLine",  -- 6/3/E

    -- =========================================================================
    -- MINOTAUR LINE  (HybridPersonality bucket)
    -- ClassKind 7: Minotaur → MinotaurHeadsman → MinotaurLord/Light/Dark
    -- =========================================================================
    [const.Class.Minotaur]          = "MinotaurLine",  -- 7/0
    [const.Class.MinotaurHeadsman]  = "MinotaurLine",  -- 7/1
    [const.Class.MinotaurLord]      = "MinotaurLine",  -- 7/2/N
    [const.Class.MinotaurLord3]     = "MinotaurLine",  -- 7/3/N
    [const.Class.MinotaurLight2]    = "MinotaurLine",  -- 7/2/G
    [const.Class.MinotaurLight3]    = "MinotaurLine",  -- 7/3/G
    [const.Class.MinotaurDark2]     = "MinotaurLine",  -- 7/2/E
    [const.Class.MinotaurDark3]     = "MinotaurLine",  -- 7/3/E

    -- =========================================================================
    -- MONK LINE  (HybridPersonality bucket)
    -- ClassKind 8: Monk → InitiateMonk → Monk2/MasterMonk/Ninja
    -- NOTE: const.Class.InitiateMonk (not Initiate) and const.Class.MasterMonk
    --   (not Master). The old code used nonexistent const names, silently mapping nil.
    -- =========================================================================
    [const.Class.Monk]              = "MonkLine",  -- 8/0
    [const.Class.InitiateMonk]      = "MonkLine",  -- 8/1
    [const.Class.Monk2]             = "MonkLine",  -- 8/2/N
    [const.Class.Monk3]             = "MonkLine",  -- 8/3/N
    [const.Class.MasterMonk]        = "MonkLine",  -- 8/2/G
    [const.Class.MasterMonk3]       = "MonkLine",  -- 8/3/G
    [const.Class.Ninja]             = "MonkLine",  -- 8/2/E
    [const.Class.Ninja3]            = "MonkLine",  -- 8/3/E

    -- =========================================================================
    -- PALADIN LINE  (HybridPersonality bucket)
    -- ClassKind 9: Paladin → Crusader → Justiciar/Hero/Villain
    -- =========================================================================
    [const.Class.Paladin]           = "PaladinLine",  -- 9/0
    [const.Class.Crusader]          = "PaladinLine",  -- 9/1
    [const.Class.Justiciar]         = "PaladinLine",  -- 9/2/N
    [const.Class.Paladin3]          = "PaladinLine",  -- 9/3/N
    [const.Class.Hero]              = "PaladinLine",  -- 9/2/G
    [const.Class.Hero3]             = "PaladinLine",  -- 9/3/G
    [const.Class.Villain]           = "PaladinLine",  -- 9/2/E
    [const.Class.Villain3]          = "PaladinLine",  -- 9/3/E

    -- =========================================================================
    -- RANGER LINE  (Ranger bucket)
    -- ClassKind 10: Ranger → Hunter → Ranger2/RangerLord/BountyHunter
    -- =========================================================================
    [const.Class.Ranger]            = "RangerLine",  -- 10/0
    [const.Class.Hunter]            = "RangerLine",  -- 10/1
    [const.Class.Ranger2]           = "RangerLine",  -- 10/2/N
    [const.Class.Ranger3]           = "RangerLine",  -- 10/3/N
    [const.Class.RangerLord]        = "RangerLine",  -- 10/2/G
    [const.Class.RangerLord3]       = "RangerLine",  -- 10/3/G
    [const.Class.BountyHunter]      = "RangerLine",  -- 10/2/E
    [const.Class.BountyHunter3]     = "RangerLine",  -- 10/3/E

    -- =========================================================================
    -- THIEF LINE  (HybridIntellect bucket)
    -- ClassKind 11: Thief → Rogue → Robber/Spy/Assassin
    -- =========================================================================
    [const.Class.Thief]             = "ThiefLine",  -- 11/0
    [const.Class.Rogue]             = "ThiefLine",  -- 11/1
    [const.Class.Robber]            = "ThiefLine",  -- 11/2/N
    [const.Class.Robber3]           = "ThiefLine",  -- 11/3/N
    [const.Class.Spy]               = "ThiefLine",  -- 11/2/G
    [const.Class.Spy3]              = "ThiefLine",  -- 11/3/G
    [const.Class.Assassin]          = "ThiefLine",  -- 11/2/E
    [const.Class.Assassin3]         = "ThiefLine",  -- 11/3/E

    -- =========================================================================
    -- BARBARIAN LINE  (Warrior bucket)
    -- ClassKind 12: Barbarian (MM8 Troll renamed) → Berserker → Warmonger/Light/Dark
    -- NOTE: const.Class.Barbarian = 92. Previous code had wrong name const.Class.Troll
    --   and was commented out. Fully mapped here.
    -- =========================================================================
    [const.Class.Barbarian]         = "BarbarianLine",  -- 12/0
    [const.Class.Berserker]         = "BarbarianLine",  -- 12/1
    [const.Class.Warmonger]         = "BarbarianLine",  -- 12/2/N
    [const.Class.Barbarian3]        = "BarbarianLine",  -- 12/3/N
    [const.Class.BarbarianLight2]   = "BarbarianLine",  -- 12/2/G
    [const.Class.BarbarianLight3]   = "BarbarianLine",  -- 12/3/G
    [const.Class.BarbarianDark]     = "BarbarianLine",  -- 12/2/E
    [const.Class.BarbarianDark3]    = "BarbarianLine",  -- 12/3/E

    -- =========================================================================
    -- VAMPIRE LINE  (HybridPersonality bucket)
    -- ClassKind 13: Vampire → ElderVampire → Nosferatu/NosferatuLight/NosferatuDark
    -- =========================================================================
    [const.Class.Vampire]           = "VampireLine",  -- 13/0
    [const.Class.ElderVampire]      = "VampireLine",  -- 13/1
    [const.Class.Nosferatu]         = "VampireLine",  -- 13/2/N
    [const.Class.Nosferatu3]        = "VampireLine",  -- 13/3/N
    [const.Class.NosferatuLight]    = "VampireLine",  -- 13/2/G
    [const.Class.NosferatuLight3]   = "VampireLine",  -- 13/3/G
    [const.Class.NosferatuDark]     = "VampireLine",  -- 13/2/E
    [const.Class.NosferatuDark3]    = "VampireLine",  -- 13/3/E

    -- =========================================================================
    -- SORCERER LINE  (Intellect bucket)
    -- ClassKind 14, neutral + light paths:
    --   Sorcerer/ApprenticeMage (tier 0) → Wizard/Mage (tier 1) → MasterWizard/ArchMage (tier 2)
    -- ApprenticeMage (110) and Mage (111) are the MM7 light-aligned Sorcerer path.
    -- =========================================================================
    [const.Class.Sorcerer]          = "SorcererLine",  -- 14/0/N
    [const.Class.Wizard]            = "SorcererLine",  -- 14/1/N
    [const.Class.ApprenticeMage]    = "SorcererLine",  -- 14/0/G
    [const.Class.Mage]              = "SorcererLine",  -- 14/1/G
    [const.Class.MasterWizard]      = "SorcererLine",  -- 14/2/N
    [const.Class.MasterWizard3]     = "SorcererLine",  -- 14/3/N
    [const.Class.ArchMage]          = "SorcererLine",  -- 14/2/G
    [const.Class.ArchMage3]         = "SorcererLine",  -- 14/3/G

    -- =========================================================================
    -- NECROMANCER LINE  (Intellect bucket)
    -- ClassKind 14, dark path (MM8 Lich class + MM7 Sorcerer dark path):
    --   DarkAdept/Necromancer (evil-aligned tier 0/1) → MasterNecromancer (tier 2)
    -- MasterNecromancer is reachable from both MM7 Wizard dark path and MM8 Necromancer.
    -- NOTE: "the Lich" suffix name appears in both SorcererLine (dark tier 2) and
    --   NecromancerLine (tier 0) — this is a design collision; stats differ significantly.
    -- =========================================================================
    [const.Class.DarkAdept]         = "NecromancerLine",  -- 14/0/E
    [const.Class.Necromancer]       = "NecromancerLine",  -- 14/1/E
    [const.Class.MasterNecromancer] = "NecromancerLine",  -- 14/2/E
    [const.Class.MasterNecromancer3]= "NecromancerLine",  -- 14/3/E
}

-- =============================================================================
-- CLASS TIER TABLE
-- =============================================================================
local ClassTier = {
    -- Archer line
    [const.Class.Archer]            = 0,
    [const.Class.WarriorMage]       = 1,
    [const.Class.BattleMage]        = 2,
    [const.Class.BattleMage3]       = 2,
    [const.Class.MasterArcher]      = 2,
    [const.Class.MasterArcher3]     = 2,
    [const.Class.Sniper]            = 2,
    [const.Class.Sniper3]           = 2,
    -- Cleric line
    [const.Class.Cleric]            = 0,
    [const.Class.AcolyteLight]      = 0,
    [const.Class.AcolyteDark]       = 0,
    [const.Class.Priest]            = 1,  -- tier 1, not 0 (2/1/N)
    [const.Class.ClericLight]       = 1,  -- tier 1, not 0 (2/1/G)
    [const.Class.ClericDark]        = 1,  -- tier 1, not 0 (2/1/E)
    [const.Class.HighPriest]        = 2,
    [const.Class.HighPriest3]       = 2,
    [const.Class.PriestLight]       = 2,
    [const.Class.PriestLight3]      = 2,
    [const.Class.PriestDark]        = 2,
    [const.Class.PriestDark3]       = 2,
    -- Deerslayer line
    [const.Class.Deerslayer]        = 0,
    [const.Class.Pioneer]           = 1,
    [const.Class.Pathfinder]        = 2,
    [const.Class.Pathfinder3]       = 2,
    [const.Class.PathfinderLight]   = 2,
    [const.Class.PathfinderLight3]  = 2,
    [const.Class.PathfinderDark]    = 2,
    [const.Class.PathfinderDark3]   = 2,
    -- Dragon line
    [const.Class.Dragon]            = 0,
    [const.Class.FlightLeader]      = 1,
    [const.Class.GreatWyrm]         = 2,
    [const.Class.GreatWyrm3]        = 2,
    [const.Class.DragonLight2]      = 2,
    [const.Class.DragonLight3]      = 2,
    [const.Class.DragonDark2]       = 2,
    [const.Class.DragonDark3]       = 2,
    -- Druid line
    [const.Class.Druid]             = 0,
    [const.Class.GreatDruid]        = 1,
    [const.Class.MasterDruid]       = 2,
    [const.Class.MasterDruid3]      = 2,
    [const.Class.ArchDruid]         = 2,
    [const.Class.ArchDruid3]        = 2,
    [const.Class.Warlock]           = 2,
    [const.Class.Warlock3]          = 2,
    -- Knight line
    [const.Class.Knight]            = 0,
    [const.Class.Cavalier]          = 1,
    [const.Class.Champion]          = 2,
    [const.Class.Champion3]         = 2,
    [const.Class.Templar]           = 2,
    [const.Class.Templar3]          = 2,
    [const.Class.BlackKnight]       = 2,
    [const.Class.BlackKnight3]      = 2,
    -- Minotaur line
    [const.Class.Minotaur]          = 0,
    [const.Class.MinotaurHeadsman]  = 1,
    [const.Class.MinotaurLord]      = 2,
    [const.Class.MinotaurLord3]     = 2,
    [const.Class.MinotaurLight2]    = 2,
    [const.Class.MinotaurLight3]    = 2,
    [const.Class.MinotaurDark2]     = 2,
    [const.Class.MinotaurDark3]     = 2,
    -- Monk line
    [const.Class.Monk]              = 0,
    [const.Class.InitiateMonk]      = 1,
    [const.Class.Monk2]             = 2,
    [const.Class.Monk3]             = 2,
    [const.Class.MasterMonk]        = 2,
    [const.Class.MasterMonk3]       = 2,
    [const.Class.Ninja]             = 2,
    [const.Class.Ninja3]            = 2,
    -- Paladin line
    [const.Class.Paladin]           = 0,
    [const.Class.Crusader]          = 1,
    [const.Class.Justiciar]         = 2,
    [const.Class.Paladin3]          = 2,
    [const.Class.Hero]              = 2,
    [const.Class.Hero3]             = 2,
    [const.Class.Villain]           = 2,
    [const.Class.Villain3]          = 2,
    -- Ranger line
    [const.Class.Ranger]            = 0,
    [const.Class.Hunter]            = 1,
    [const.Class.Ranger2]           = 2,
    [const.Class.Ranger3]           = 2,
    [const.Class.RangerLord]        = 2,
    [const.Class.RangerLord3]       = 2,
    [const.Class.BountyHunter]      = 2,
    [const.Class.BountyHunter3]     = 2,
    -- Thief line
    [const.Class.Thief]             = 0,
    [const.Class.Rogue]             = 1,
    [const.Class.Robber]            = 2,
    [const.Class.Robber3]           = 2,
    [const.Class.Spy]               = 2,
    [const.Class.Spy3]              = 2,
    [const.Class.Assassin]          = 2,
    [const.Class.Assassin3]         = 2,
    -- Barbarian line
    [const.Class.Barbarian]         = 0,
    [const.Class.Berserker]         = 1,
    [const.Class.Warmonger]         = 2,
    [const.Class.Barbarian3]        = 2,
    [const.Class.BarbarianLight2]   = 2,
    [const.Class.BarbarianLight3]   = 2,
    [const.Class.BarbarianDark]     = 2,
    [const.Class.BarbarianDark3]    = 2,
    -- Vampire line
    [const.Class.Vampire]           = 0,
    [const.Class.ElderVampire]      = 1,
    [const.Class.Nosferatu]         = 2,
    [const.Class.Nosferatu3]        = 2,
    [const.Class.NosferatuLight]    = 2,
    [const.Class.NosferatuLight3]   = 2,
    [const.Class.NosferatuDark]     = 2,
    [const.Class.NosferatuDark3]    = 2,
    -- Sorcerer line
    [const.Class.Sorcerer]          = 0,
    [const.Class.Wizard]            = 1,
    [const.Class.ApprenticeMage]    = 0,
    [const.Class.Mage]              = 1,
    [const.Class.MasterWizard]      = 2,
    [const.Class.MasterWizard3]     = 2,
    [const.Class.ArchMage]          = 2,
    [const.Class.ArchMage3]         = 2,
    -- Necromancer line
    [const.Class.DarkAdept]         = 0,
    [const.Class.Necromancer]       = 1,
    [const.Class.MasterNecromancer] = 2,
    [const.Class.MasterNecromancer3]= 2,
}

-- =============================================================================
-- CLASS ALIGNMENT TABLE
-- Only explicitly aligned classes listed; everything else defaults to "any".
-- =============================================================================
local ClassAlignment = {
    -- Archer line
    [const.Class.MasterArcher]      = "light",
    [const.Class.MasterArcher3]     = "light",
    [const.Class.Sniper]            = "dark",
    [const.Class.Sniper3]           = "dark",
    -- Cleric line (AcolyteLight/AcolyteDark carry alignment from tier 0)
    [const.Class.AcolyteLight]      = "light",
    [const.Class.AcolyteDark]       = "dark",
    [const.Class.ClericLight]       = "light",
    [const.Class.ClericDark]        = "dark",
    [const.Class.PriestLight]       = "light",
    [const.Class.PriestLight3]      = "light",
    [const.Class.PriestDark]        = "dark",
    [const.Class.PriestDark3]       = "dark",
    -- Deerslayer line (Pathfinder alignment variants; mapped even if rarely reachable)
    [const.Class.PathfinderLight]   = "light",
    [const.Class.PathfinderLight3]  = "light",
    [const.Class.PathfinderDark]    = "dark",
    [const.Class.PathfinderDark3]   = "dark",
    -- Dragon line
    [const.Class.DragonLight2]      = "light",
    [const.Class.DragonLight3]      = "light",
    [const.Class.DragonDark2]       = "dark",
    [const.Class.DragonDark3]       = "dark",
    -- Druid line
    [const.Class.ArchDruid]         = "light",
    [const.Class.ArchDruid3]        = "light",
    [const.Class.Warlock]           = "dark",
    [const.Class.Warlock3]          = "dark",
    -- Knight line  (Champion is NEUTRAL; Templar = light, BlackKnight = dark)
    [const.Class.Templar]           = "light",
    [const.Class.Templar3]          = "light",
    [const.Class.BlackKnight]       = "dark",
    [const.Class.BlackKnight3]      = "dark",
    -- Minotaur line
    [const.Class.MinotaurLight2]    = "light",
    [const.Class.MinotaurLight3]    = "light",
    [const.Class.MinotaurDark2]     = "dark",
    [const.Class.MinotaurDark3]     = "dark",
    -- Monk line
    [const.Class.MasterMonk]        = "light",
    [const.Class.MasterMonk3]       = "light",
    [const.Class.Ninja]             = "dark",
    [const.Class.Ninja3]            = "dark",
    -- Paladin line
    [const.Class.Hero]              = "light",
    [const.Class.Hero3]             = "light",
    [const.Class.Villain]           = "dark",
    [const.Class.Villain3]          = "dark",
    -- Ranger line
    [const.Class.RangerLord]        = "light",
    [const.Class.RangerLord3]       = "light",
    [const.Class.BountyHunter]      = "dark",
    [const.Class.BountyHunter3]     = "dark",
    -- Thief line
    [const.Class.Spy]               = "light",
    [const.Class.Spy3]              = "light",
    [const.Class.Assassin]          = "dark",
    [const.Class.Assassin3]         = "dark",
    -- Barbarian line
    [const.Class.BarbarianLight2]   = "light",
    [const.Class.BarbarianLight3]   = "light",
    [const.Class.BarbarianDark]     = "dark",
    [const.Class.BarbarianDark3]    = "dark",
    -- Vampire line
    [const.Class.NosferatuLight]    = "light",
    [const.Class.NosferatuLight3]   = "light",
    [const.Class.NosferatuDark]     = "dark",
    [const.Class.NosferatuDark3]    = "dark",
    -- Sorcerer line (ApprenticeMage/Mage are MM7 light-aligned Sorcerer path)
    [const.Class.ApprenticeMage]    = "light",
    [const.Class.Mage]              = "light",
    [const.Class.ArchMage]          = "light",
    [const.Class.ArchMage3]         = "light",
    -- Necromancer line (entire line is dark by class definition)
    [const.Class.DarkAdept]         = "dark",
    [const.Class.Necromancer]       = "dark",
    [const.Class.MasterNecromancer] = "dark",
    [const.Class.MasterNecromancer3]= "dark",
}

local LineToBucket = {
    KnightLine      = "Tank",
    BarbarianLine   = "Warrior",
    ArcherLine      = "HybridIntellect",
    DeerslayerLine  = "HybridIntellect",
    ThiefLine       = "HybridIntellect",
    PaladinLine     = "HybridPersonality",
    MonkLine        = "HybridPersonality",
    VampireLine     = "HybridPersonality",
    MinotaurLine    = "HybridPersonality",
    SorcererLine    = "Intellect",
    NecromancerLine = "Intellect",
    ClericLine      = "Personality",
    DragonLine      = "Personality",
    DruidLine       = "Druid",
    RangerLine      = "Ranger",
}

-- =============================================================================
-- SELECTION HELPERS
-- =============================================================================

-- Select a random prefix from pool filtered by alignment.
-- gen/spec tags are always eligible. light/dark tags are only eligible
-- when the character's alignment matches exactly.
local function SelectPrefix(pool, alignment)
    local c = {}
    for _, e in ipairs(pool) do
        if not (e.tag == "light" and alignment ~= "light")
        and not (e.tag == "dark"  and alignment ~= "dark") then
            c[#c + 1] = e
        end
    end
    return #c > 0 and c[random(#c)] or nil
end

-- Select a random suffix from pool filtered by tier and alignment.
-- Falls back to tier 0 if no tier match (should not happen with complete pool data).
-- Alignment filter is applied in both the primary pass and the fallback.
local function SelectSuffix(pool, tier, alignment)
    local c = {}
    for _, e in ipairs(pool) do
        if e.tier == tier
        and not (e.alignment == "light" and alignment ~= "light")
        and not (e.alignment == "dark"  and alignment ~= "dark") then
            c[#c + 1] = e
        end
    end
    if #c == 0 then
        -- Fallback: use tier 0 entries, still filtering by alignment
        for _, e in ipairs(pool) do
            if e.tier == 0
            and not (e.alignment == "light" and alignment ~= "light")
            and not (e.alignment == "dark"  and alignment ~= "dark") then
                c[#c + 1] = e
            end
        end
    end
    return #c > 0 and c[random(#c)] or nil
end

-- Pick a random active party member (0-indexed in MM8 engine, up to 4 members).
-- Guard: ItemGenerated can fire during world load before the Party struct
-- is mapped into memory (Party[i] throws "array index out of bounds").
-- Check Party.count before iterating to avoid spamming the error log.
local function RandomPartyMember()
    if not Party or not Party.count or Party.count < 1 then return nil end
    local active = {}
    for i = 0, Party.count - 1 do
        local ok, p = pcall(function() return Party[i] end)
        if ok and p and p.Class and p.Class >= 0 then
            active[#active + 1] = p
        end
    end
    return #active > 0 and active[random(#active)] or nil
end

-- Item number ranges to leave alone (handled elsewhere or not targetable).
-- Ranges confirmed from Scripts/General/ItemsModifiers.lua.
local function IsExcludedItem(num)
    return (num > 299  and num < 400)   -- MM7 spell scrolls
        or (num > 1101 and num < 1202)  -- MM6 spell scrolls
        or (num > 1801 and num < 1902)  -- MM8 spell scrolls
end

-- True if it is safe to store our curated id in item.Charges: only when the
-- vanilla roll itself left MaxCharges at 0, i.e. this item type never uses
-- charges for anything (see header comment for why this matters).
local function CanTagItem(item)
    return item.MaxCharges == 0
end

-- =============================================================================
-- QUALITY — stat variance tied to party level
-- =============================================================================

-- Average level of all party members (ceil). Returns 1 if no valid data.
local function AveragePartyLevel()
    local total, count = 0, 0
    for i = 0, Party.count - 1 do
        local ok, p = pcall(function() return Party[i] end)
        if ok and p and p.LevelBase and p.LevelBase > 0 then
            total = total + p.LevelBase
            count = count + 1
        end
    end
    return count > 0 and math.ceil(total / count) or 1
end

-- Roll a quality multiplier for a newly generated item. Scales with party
-- level so early-game items are noticeably weaker than endgame ones.
-- At level 1:   [0.35, 0.55]
-- At level 125: [0.75, 1.00]
local function RollQuality(avgLevel)
    local progress = math.min(1, (avgLevel - 1) / 124)
    local minQ = 0.35 + progress * 0.40
    local maxQ = 0.55 + progress * 0.45
    return minQ + random() * (maxQ - minQ)
end

-- =============================================================================
-- PERSISTENT CURATED ITEM STORAGE
-- Selections survive save/load via internal.SaveGameData.CuratedItems[],
-- keyed by a small sequential id that is ALSO written into item.Charges on
-- the specific item instance — that makes the id → item link per-instance
-- instead of "shared by any item with the same rolled stats" like the old
-- structural-key approach.
--   entry = {
--     prefixId, suffixId,        -- resolve via IdToPrefix/IdToSuffix
--     itemNumber,                 -- item.Number at generation time (for revert matching)
--     origBonus, origBonusStrength, origBonus2,  -- vanilla roll, for full revert
--     quality,                    -- stat multiplier [0.35-1.00], scales with party level
--   }
-- =============================================================================

local CuratedItems  -- table: { [id] = entry }
local NextCuratedId

local function NewCuratedId()
    local id = NextCuratedId
    NextCuratedId = NextCuratedId + 1
    if internal and internal.SaveGameData then
        internal.SaveGameData.NextCuratedId = NextCuratedId
    end
    return id
end

-- Suppress the vanilla enchantment on `item` and tag it with `id`. Zeroes
-- BOTH enchantment slots (Bonus/BonusStrength from STDITEMS.TXT, and Bonus2
-- from SPCITEMS.TXT — an item can carry either or both independently; a
-- weapon can roll a Bonus2-only "special" enchant with Bonus left at 0).
-- Setting Bonus2 to 0 is a proven-safe operation already used elsewhere in
-- this codebase (Quest_CrossContinents.lua's SetupScroll,
-- RemoveItemsLimits.lua's native cleanup hook both do it) — the crash this
-- file avoids is WRITING AN ENCODED ID into Bonus2, not zeroing it. The id
-- lives exclusively in item.Charges; Bonus2 only ever holds 0 or the item's
-- own original vanilla-rolled value (see RestoreVanilla).
local function SuppressAndTag(item, id)
    item.Bonus = 0
    item.BonusStrength = 0
    item.Bonus2 = 0
    item.Charges = id
end

-- Restore `item`'s original vanilla enchantment from its curated entry and
-- remove the tag. Does not delete the CuratedItems entry (kept so re-enabling
-- the system can re-associate this exact item — see SyncItemSystemToggle).
local function RestoreVanilla(item, entry)
    item.Bonus = entry.origBonus
    item.BonusStrength = entry.origBonusStrength
    item.Bonus2 = entry.origBonus2
    item.Charges = 0
end

local function GetCuratedEntry(item)
    if not item or not CuratedItems then return nil end
    if not CanTagItem(item) then return nil end
    local id = item.Charges
    if not id or id <= 0 then return nil end
    return CuratedItems[id], id
end

-- =============================================================================
-- MAIN HOOK
-- Appends to events.ItemGenerated — does not replace existing handlers.
-- =============================================================================
function events.ItemGenerated(t)
    if not Game.ItemSystemEnabled then return end
    local ok, err = pcall(function()
        if not CuratedItems then return end

        local item = t.Item

        -- Skip common items: vanilla assigns no enchantment in either slot.
        -- Bonus (STDITEMS.TXT) and Bonus2 (SPCITEMS.TXT) roll independently —
        -- an item can have only Bonus2 set with Bonus at 0 (confirmed via
        -- ItemTest.Inspect during testing: "Exquisite Long Dagger", Bonus=0,
        -- Bonus2=64, Material=0 — a real magic item this check used to miss).
        local hasBonus  = item.Bonus  and item.Bonus  > 0
        local hasBonus2 = item.Bonus2 and item.Bonus2 > 0
        if not hasBonus and not hasBonus2 then return end

        -- Skip scroll ranges handled by ItemsModifiers.lua
        if IsExcludedItem(item.Number) then return end

        -- Skip charge-based items (wands, etc.) — see CanTagItem / header comment
        if not CanTagItem(item) then return end

        -- Pick a random party member to target this item toward
        local player = RandomPartyMember()
        if not player then return end

        local class = player.Class
        local line  = ClassToLine[class]
        if not line then return end

        local bucket    = LineToBucket[line]
        local tier      = ClassTier[class]      or 0
        local alignment = ClassAlignment[class] or "any"

        local prefixPool = Pools.Prefixes[bucket]
        local suffixPool = Pools.Suffixes[line]
        if not prefixPool or not suffixPool then return end

        local prefix = SelectPrefix(prefixPool, alignment)
        local suffix = SelectSuffix(suffixPool, tier, alignment)
        if not prefix or not suffix then return end

        local quality = RollQuality(AveragePartyLevel())
        local id = NewCuratedId()
        CuratedItems[id] = {
            prefixId          = prefix._prefixId,
            suffixId          = suffix._suffixId,
            itemNumber        = item.Number,
            origBonus         = item.Bonus,
            origBonusStrength = item.BonusStrength,
            origBonus2        = item.Bonus2,
            quality           = quality,
        }
        SuppressAndTag(item, id)

        Log(Merge.Log.Info,
            "%s: Item #%d → \"%s\" + \"%s\" [class=%d tier=%d %s] (q=%.2f id=%d)",
            LogId, item.Number, prefix.name, suffix.name,
            class, tier, alignment, quality, id)
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: ItemGenerated error: %s", LogId, err)
    end
end

-- =============================================================================
-- PUBLIC API
-- Other scripts can inspect what enchantment is on any item.
-- =============================================================================

-- Returns the prefix entry table for a curated item (or nil)
function GetItemPrefix(item)
    local entry = GetCuratedEntry(item)
    return entry and IdToPrefix[entry.prefixId]
end

-- Returns the suffix entry table for a curated item (or nil)
function GetItemSuffix(item)
    local entry = GetCuratedEntry(item)
    return entry and IdToSuffix[entry.suffixId]
end

-- Returns true if this item was enchanted by the curated system
function IsCuratedItem(item)
    return GetCuratedEntry(item) ~= nil
end

-- =============================================================================
-- STAT & SKILL APPLICATION
-- Two hooks apply curated stat and skill bonuses from equipped items.
--   CalcStatBonusByItems — primary stats, HP, SP, AC, magic schools
--   GetSkill             — weapon skills, armor skills, utility skills
-- Both hooks share a per-player cache (BonusCache) invalidated automatically
-- when that player's equipped-item indices change — see GetCachedBonuses.
-- =============================================================================

-- Pool stat name → const.Stats mapping.
-- Repair/Bodybuilding/Perception are NOT included here: this engine version's
-- const.Stats has no such entries (only const.Skills does), so they belong in
-- SkillMap only — listing them here would just resolve to nil and do nothing.
local StatMap = {
    Might       = const.Stats.Might,
    Intellect   = const.Stats.Intellect,
    Personality = const.Stats.Personality,
    Endurance   = const.Stats.Endurance,
    Accuracy    = const.Stats.Accuracy,
    Speed       = const.Stats.Speed,
    Luck        = const.Stats.Luck,
    HP          = const.Stats.HP,
    SP          = const.Stats.SP,
    AC          = const.Stats.ArmorClass,
    Fire        = const.Stats.FireMagic,
    Air         = const.Stats.AirMagic,
    Water       = const.Stats.WaterMagic,
    Earth       = const.Stats.EarthMagic,
    Spirit      = const.Stats.SpiritMagic,
    Mind        = const.Stats.MindMagic,
    Body        = const.Stats.BodyMagic,
    Light       = const.Stats.LightMagic,
    Dark        = const.Stats.DarkMagic,
    Bow         = const.Stats.Bow,
    Shield      = const.Stats.Shield,
    Meditation  = const.Stats.Meditation,
    Unarmed     = const.Stats.Unarmed,
    Dodge       = const.Stats.Dodging,
    Armsmaster  = const.Stats.Armsmaster,
    Alchemy     = const.Stats.Alchemy,
    Stealing    = const.Stats.Stealing,
    DisarmTrap  = const.Stats.DisarmTraps,
    IdentifyItem= const.Stats.IdentifyItem,
    IdentifyMonster = const.Stats.IdentifyMonster,
    Learning    = const.Stats.Learning,
}

-- Pool skill name → const.Skills mapping (for skills not in StatMap)
local SkillMap = {
    Sword          = const.Skills.Sword,
    Axe            = const.Skills.Axe,
    Mace           = const.Skills.Mace,
    Dagger         = const.Skills.Dagger,
    Staff          = const.Skills.Staff,
    Spear          = const.Skills.Spear,
    Plate          = const.Skills.Plate,
    Chain          = const.Skills.Chain,
    Leather        = const.Skills.Leather,
    Merchant       = const.Skills.Merchant,
    Repair         = const.Skills.Repair,
    Bodybuilding   = const.Skills.Bodybuilding,
    Perception     = const.Skills.Perception,
    Regeneration   = const.Skills.Regeneration,
    DragonMagic    = const.Skills.DragonAbility,
}

-- =============================================================================
-- WEAPON SKILL FILTER
-- A weapon can only ever benefit from ITS OWN weapon skill -- a Mace boosting
-- Sword skill is nonsensical, since equipping the Mace never uses Sword skill
-- at all. Suffix/prefix SELECTION stays independent of base item type (a
-- Mace can still roll "the Knight" for flavor -- Knights plausibly use maces
-- too), but any of the 8 weapon-skill stats that doesn't match the actual
-- equipped item's own weapon skill is dropped before it's applied. This is
-- deliberately narrow: only weapon-skill-vs-weapon-skill mismatches are
-- filtered. Non-weapon items (rings, armor, amulets) are never restricted --
-- a Ring granting a weapon-skill bonus isn't the problem this solves.
-- Also used by ItemSystemTooltip.lua (via ItemSystemInternal) so the
-- tooltip's displayed stat list never shows a bonus that isn't really
-- applying.
-- =============================================================================

-- const.Skills ids for the 8 weapon skills, used as a fast membership set.
local WeaponSkillIds = {
    [const.Skills.Sword]   = true,
    [const.Skills.Axe]     = true,
    [const.Skills.Mace]    = true,
    [const.Skills.Dagger]  = true,
    [const.Skills.Staff]   = true,
    [const.Skills.Spear]   = true,
    [const.Skills.Bow]     = true,
    [const.Skills.Unarmed] = true,
}

-- Pool stat name -> const.Skills id, ONLY for the 8 weapon-skill names.
-- Separate from StatMap/SkillMap (which route Bow/Unarmed through
-- const.Stats, not const.Skills) -- this table exists purely to compare
-- against an item's own item:T().Skill value.
local StatNameToWeaponSkillId = {
    Sword   = const.Skills.Sword,
    Axe     = const.Skills.Axe,
    Mace    = const.Skills.Mace,
    Dagger  = const.Skills.Dagger,
    Staff   = const.Skills.Staff,
    Spear   = const.Skills.Spear,
    Bow     = const.Skills.Bow,
    Unarmed = const.Skills.Unarmed,
}

-- Item categories that are actually weapons (melee 1H, melee 2H, ranged).
-- Everything else (Armor, Shield, Ring, Amulet, Belt, Gauntlets, Boots,
-- Wand, etc.) is never restricted by this filter, regardless of what its
-- .Skill field happens to contain -- checking EquipStat too (not just
-- .Skill) means that's a guarantee, not an assumption about unverifiable
-- ItemsTxt data (LOD-extracted, not available to read outside the running
-- game). This is specifically what lets Unarmed appear freely on gloves,
-- rings, necklaces, belts, etc. while still being excluded from actual
-- weapons (a Sword's own skill is Sword, never Unarmed, so an Unarmed
-- stat on a Sword gets filtered same as any other mismatched weapon skill).
local WeaponEquipTypes = {
    [const.ItemType.Weapon]   = true,
    [const.ItemType.Weapon2H] = true,
    [const.ItemType.Missile]  = true,
}

-- Returns the item's own weapon-skill const.Skills id if it's one of the 8
-- recognized weapon types AND actually equips as a weapon, or nil otherwise
-- (non-weapon equip category, or a weapon type whose Skill isn't one of the
-- 8 -- e.g. Blaster).
local function ItemWeaponSkillId(item)
    local ok, def = pcall(function() return item:T() end)
    if not ok or not def then return nil end
    if not WeaponEquipTypes[def.EquipStat + 1] then return nil end  -- EquipStat = const.ItemType value - 1
    if WeaponSkillIds[def.Skill] then
        return def.Skill
    end
    return nil
end

-- Some weapon types have a real thematic/mechanical secondary skill beyond
-- their own -- Staff-wielders (Monks) also train Unarmed combat, unlike the
-- arbitrary pairings (e.g. a Mace boosting Sword) this filter otherwise
-- removes. Both skills survive together only for pairings listed here;
-- everything else still requires an exact match.
local CompatibleWeaponSkills = {
    [const.Skills.Staff] = { [const.Skills.Unarmed] = true },
}

local function IsWeaponSkillAllowed(weaponSkillId, statSkillId)
    if statSkillId == weaponSkillId then return true end
    local compatible = CompatibleWeaponSkills[weaponSkillId]
    return compatible ~= nil and compatible[statSkillId] == true
end

-- Returns `stats` unchanged if no filtering is needed (the common case --
-- avoids allocating a new table on every call), or a filtered copy with any
-- mismatched weapon-skill entries removed.
local function FilterStatsForItem(item, stats)
    if not stats then return nil end
    local weaponSkillId = ItemWeaponSkillId(item)
    if not weaponSkillId then return stats end
    local needsFilter = false
    for k in pairs(stats) do
        local statSkillId = StatNameToWeaponSkillId[k]
        if statSkillId and not IsWeaponSkillAllowed(weaponSkillId, statSkillId) then
            needsFilter = true
            break
        end
    end
    if not needsFilter then return stats end
    local result = {}
    for k, v in pairs(stats) do
        local statSkillId = StatNameToWeaponSkillId[k]
        if not statSkillId or IsWeaponSkillAllowed(weaponSkillId, statSkillId) then
            result[k] = v
        end
    end
    return result
end

-- Accumulate one pool entry's stats into the given stat/skill accumulators,
-- after filtering out any weapon skill that doesn't match `item`'s own.
-- `quality` (0.0–1.0) scales each stat value so items vary in strength.
local function ApplyStats(item, poolEntry, statAcc, skillAcc, quality)
    if not poolEntry or not poolEntry.stats then return end
    local stats = FilterStatsForItem(item, poolEntry.stats)
    for k, v in pairs(stats) do
        local adjusted = math.max(1, math.floor(v * quality))
        if StatMap[k] then
            statAcc[StatMap[k]] = (statAcc[StatMap[k]] or 0) + adjusted
        elseif SkillMap[k] then
            skillAcc[SkillMap[k]] = (skillAcc[SkillMap[k]] or 0) + adjusted
        end
    end
end

-- Keep only the top N combined stat+skill entries by value, dropping the rest.
-- This prevents curated items from accumulating too many bonuses.
local MAX_ITEM_STATS = 4

local function TrimStats(statAcc, skillAcc, maxCount)
    local combined = {}
    for id, val in pairs(statAcc) do
        combined[#combined + 1] = { id = id, val = val, kind = "stat" }
    end
    for id, val in pairs(skillAcc) do
        combined[#combined + 1] = { id = id, val = val, kind = "skill" }
    end
    if #combined <= maxCount then return end
    table.sort(combined, function(a, b) return a.val > b.val end)
    local keep = {}
    for i = 1, maxCount do
        local entry = combined[i]
        keep[entry.kind .. ":" .. entry.id] = true
    end
    for _, entry in ipairs(combined) do
        if not keep[entry.kind .. ":" .. entry.id] then
            if entry.kind == "stat" then
                statAcc[entry.id] = nil
            else
                skillAcc[entry.id] = nil
            end
        end
    end
end

-- Iterate equipped items and accumulate stat/skill contributions from both
-- prefix and suffix into the given accumulator tables. Quality is read from
-- each curated entry (default 0.60 for backward-compat entries). The merged
-- result is trimmed to at most MAX_ITEM_STATS total bonuses.
local function SumCuratedBonuses(player, statAcc, skillAcc)
    if not player or not player["?ptr"] or player["?ptr"] <= 0 then return end
    for i = 0, 15 do
        local itemIdx = player.EquippedItems[i]
        if itemIdx and itemIdx > 0 and itemIdx <= 138 then
            local itemObj = player.Items[itemIdx]
            if itemObj and itemObj["?ptr"] and itemObj["?ptr"] > 0 then
                local entry = GetCuratedEntry(itemObj)
                if entry then
                    local quality = entry.quality or 0.60
                    local localStat, localSkill = {}, {}
                    ApplyStats(itemObj, IdToPrefix[entry.prefixId], localStat, localSkill, quality)
                    ApplyStats(itemObj, IdToSuffix[entry.suffixId], localStat, localSkill, quality)
                    TrimStats(localStat, localSkill, MAX_ITEM_STATS)
                    for id, val in pairs(localStat) do
                        statAcc[id] = (statAcc[id] or 0) + val
                    end
                    for id, val in pairs(localSkill) do
                        skillAcc[id] = (skillAcc[id] or 0) + val
                    end
                end
            end
        end
    end
end

-- Per-player cache of accumulated curated stat/skill bonuses. Both
-- CalcStatBonusByItems and GetSkill fire once per stat/skill for each player
-- every recalculation pass (dozens of calls per player) — recomputing the
-- full 16-slot equipment scan on every single call was the "make it smooth"
-- problem. Instead we scan once per (player, equipment state) and reuse the
-- result for every stat/skill query in that pass; a cheap signature of the
-- player's equipped-item indices tells us when a real re-scan is needed.
local BonusCache = {}  -- [PlayerIndex] = { sig = "...", stat = {...}, skill = {...} }

local function EquipSignature(player)
    local parts = {}
    for i = 0, 15 do
        parts[i + 1] = player.EquippedItems[i] or 0
    end
    return table.concat(parts, ",")
end

local function GetCachedBonuses(player, playerIndex)
    local sig = EquipSignature(player)
    local cached = BonusCache[playerIndex]
    if cached and cached.sig == sig then
        return cached.stat, cached.skill
    end
    local statAcc, skillAcc = {}, {}
    SumCuratedBonuses(player, statAcc, skillAcc)
    BonusCache[playerIndex] = { sig = sig, stat = statAcc, skill = skillAcc }
    return statAcc, skillAcc
end

-- Hook 1: stat bonuses (fires per-stat for each player)
function events.CalcStatBonusByItems(t)
    if not Game.ItemSystemEnabled then return end
    local ok, err = pcall(function()
        if not t.Player then return end
        local statAcc = GetCachedBonuses(t.Player, t.PlayerIndex)
        local bonus = statAcc[t.Stat]
        if bonus then
            t.Result = t.Result + bonus
        end
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: CalcStatBonusByItems error: %s", LogId, err)
    end
end

-- Hook 2: skill bonuses (fires per-skill for each player, MM7+)
function events.GetSkill(t)
    if not Game.ItemSystemEnabled then return end
    local ok, err = pcall(function()
        if not t.Player then return end
        local base = t.Result
        local _, skillAcc = GetCachedBonuses(t.Player, t.PlayerIndex)
        local bonus = skillAcc[t.Skill]
        if bonus and bonus > 0 then
            t.Result = t.Result + math.min(bonus, math.max(base, 1))
        end
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: GetSkill error: %s", LogId, err)
    end
end

-- Hook 3: sell price adjustment for curated items (DISABLED)
-- Native GetValue at 0x453CE7 returns only the base price because
-- item.Bonus/Bonus2 are zeroed. A mem.hookfunction was attempted but
-- caused EAccessViolation crashes (stack corruption from mismatched
-- calling convention). Disabled until a safer approach is found.
-- Curated items currently sell for their base (common) price.
-- Sorted by priority; this is cosmetic, not gameplay-breaking.

-- =============================================================================
-- TOGGLE SYNC — suppress/revert existing items to match Game.ItemSystemEnabled
-- =============================================================================

-- Reconciles every party item's suppressed/vanilla state with the current
-- Game.ItemSystemEnabled value. Runs automatically on AfterLoadMap (after
-- LoadMapScripts has restored the menu toggle state from ExSet); call it
-- manually right after flipping the flag for an immediate mid-session effect.
local function RecoverOrphanedItem(item)
    local player = RandomPartyMember()
    if not player then return end
    local class = player.Class
    local line  = ClassToLine[class]
    if not line then return end
    local bucket    = LineToBucket[line]
    local tier      = ClassTier[class] or 0
    local alignment = ClassAlignment[class] or "any"
    local prefixPool = Pools.Prefixes[bucket]
    local suffixPool = Pools.Suffixes[line]
    if not prefixPool or not suffixPool then return end
    local prefix = SelectPrefix(prefixPool, alignment)
    local suffix = SelectSuffix(suffixPool, tier, alignment)
    if not prefix or not suffix then return end
    local quality = RollQuality(AveragePartyLevel())
    local id = NewCuratedId()
    CuratedItems[id] = {
        prefixId          = prefix._prefixId,
        suffixId          = suffix._suffixId,
        itemNumber        = item.Number,
        origBonus         = 0,
        origBonusStrength = 0,
        origBonus2        = 0,
        quality           = quality,
    }
    item.Charges = id
    Log(Merge.Log.Info, "%s: Recovered orphaned item #%d → \"%s\" + \"%s\" (q=%.2f id=%d)",
        LogId, item.Number, prefix.name, suffix.name, quality, id)
end

function SyncItemSystemToggle()
    if not Party or not Party.Players or not CuratedItems then return end

    if Game.ItemSystemEnabled then
        -- Re-tag any currently-vanilla item whose (Number, Bonus, BonusStrength,
        -- Bonus2) still matches a previously recorded curated entry (i.e. it was
        -- suppressed before, then reverted by a prior toggle-off).
        local revIndex = {}
        for id, entry in pairs(CuratedItems) do
            local key = entry.itemNumber .. "|" .. entry.origBonus .. "|"
                .. entry.origBonusStrength .. "|" .. (entry.origBonus2 or 0)
            if not revIndex[key] then
                revIndex[key] = id
            end
        end
        for _, pl in Party.Players do
            for slot = 1, 138 do
                local item = pl.Items[slot]
                if item and item.Number and item.Number > 0 and CanTagItem(item)
                and (not item.Charges or item.Charges == 0)
                and ((item.Bonus and item.Bonus > 0) or (item.Bonus2 and item.Bonus2 > 0)) then
                    local key = item.Number .. "|" .. item.Bonus .. "|"
                        .. item.BonusStrength .. "|" .. (item.Bonus2 or 0)
                    local id = revIndex[key]
                    if id then
                        SuppressAndTag(item, id)
                    end
                end
            end
        end
        -- Recover orphaned items that have Charges set but no CuratedItems entry
        -- (e.g. from a prior session whose save data didn't persist the table).
        for _, pl in Party.Players do
            for slot = 1, 138 do
                local item = pl.Items[slot]
                if item and item.Charges and item.Charges > 0 and CanTagItem(item)
                and not CuratedItems[item.Charges] then
                    RecoverOrphanedItem(item)
                end
            end
        end
    else
        for _, pl in Party.Players do
            for slot = 1, 138 do
                local item = pl.Items[slot]
                if item and item.Charges and item.Charges > 0 and CanTagItem(item) then
                    local entry = CuratedItems[item.Charges]
                    if entry then
                        RestoreVanilla(item, entry)
                    else
                        -- Orphaned: no entry to restore from, just clear Charges
                        -- so it doesn't show "Charges: N" with the system disabled.
                        item.Charges = 0
                    end
                end
            end
        end
    end
    BonusCache = {}
    Log(Merge.Log.Info, "%s: Synced toggle state (enabled=%s).", LogId, tostring(Game.ItemSystemEnabled))
end

-- =============================================================================
-- PRUNING
-- Removes CuratedItems entries that no longer correspond to any item the
-- party is carrying, keeping the persisted table from growing forever.
-- Only entries older than PRUNE_GRACE ids (i.e. not from the current batch
-- of recent drops) are eligible, so a freshly generated id can't be swept
-- before it's even had a chance to reach the party's tracked inventory.
-- Items sitting in an unvisited chest/on the ground are NOT seen by this
-- scan and so can be pruned while away — see header "KNOWN LIMITATIONS".
--
-- Only runs while Game.ItemSystemEnabled is true. While disabled,
-- SyncItemSystemToggle has reverted every item and zeroed item.Charges on
-- all of them, so "in use" can't be determined from Charges at all — running
-- this while disabled would see nothing in use and delete every entry,
-- permanently losing the ability to re-associate items when re-enabled.
-- =============================================================================
local PRUNE_GRACE = 50

local function PruneCuratedItems()
    if not Game.ItemSystemEnabled then return end
    if not Party or not Party.Players or not CuratedItems then return end

    local inUse = {}
    for _, pl in Party.Players do
        for slot = 1, 138 do
            local item = pl.Items[slot]
            if item and item.Charges and item.Charges > 0 and CanTagItem(item) then
                inUse[item.Charges] = true
            end
        end
    end

    local cutoff = NextCuratedId - PRUNE_GRACE
    local pruned = 0
    for id in pairs(CuratedItems) do
        if id < cutoff and not inUse[id] then
            CuratedItems[id] = nil
            pruned = pruned + 1
        end
    end
    if pruned > 0 then
        Log(Merge.Log.Info, "%s: Pruned %d stale curated entries.", LogId, pruned)
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function events.GameInitialized2()
    BuildIndices()
    local sgd = internal and internal.SaveGameData
    if sgd and sgd.CuratedItems then
        CuratedItems  = sgd.CuratedItems
        NextCuratedId = sgd.NextCuratedId
    else
        CuratedItems  = {}
        NextCuratedId = 1
        if sgd then
            sgd.CuratedItems  = CuratedItems
            sgd.NextCuratedId = NextCuratedId
        end
    end
    Log(Merge.Log.Info, "%s: Ready. %d curated entries tracked.", LogId, NextCuratedId - 1)
end

-- Deferred sync: runs AFTER LoadMapScripts has set Game.ItemSystemEnabled from
-- saved ExSet (menu toggle state). GameInitialized2 fires before ExSet is
-- loaded — syncing there would use the wrong toggle value on save reload.
function events.AfterLoadMap(WasInGame)
    if not WasInGame then
        SyncItemSystemToggle()  -- also clears BonusCache
    end
    PruneCuratedItems()
end

-- =============================================================================
-- INTERNAL API (shared with other item system files)
-- =============================================================================

-- Apply quality multiplier and trim to a name→value stats table (e.g. from
-- prefix/suffix pool entries). Public API for external code that needs to
-- display or inspect quality-adjusted values (tooltip does its own inline
-- version to match SumCuratedBonuses' per-entry quality application).
local function ApplyQualityAndTrim(item, nameValueTable)
    local entry = GetCuratedEntry(item)
    local quality = (entry and entry.quality) or 0.60
    local adjusted = {}
    for name, value in pairs(nameValueTable) do
        local adj = math.max(1, math.floor(value * quality))
        adjusted[name] = adj
    end
    local names = {}
    for name, value in pairs(adjusted) do
        names[#names + 1] = { name = name, value = value }
    end
    table.sort(names, function(a, b) return a.value > b.value end)
    local result = {}
    for i = 1, math.min(MAX_ITEM_STATS, #names) do
        result[names[i].name] = names[i].value
    end
    return result
end

-- =============================================================================
-- DEBUG HOOKS
-- Minimal read-only access to this file's locals for
-- Scripts/General/ItemSystemDebug.lua to build test/inspection tools on top
-- of. Not meant to be called during normal play. GetCuratedItems() returns
-- the LIVE table — read it, don't mutate it from outside this file.
-- =============================================================================
ItemSystemInternal = {
    Pools               = Pools,
    ClassToLine         = ClassToLine,
    ClassTier           = ClassTier,
    ClassAlignment      = ClassAlignment,
    LineToBucket        = LineToBucket,
    StatMap             = StatMap,
    SkillMap            = SkillMap,
    SelectPrefix        = SelectPrefix,
    SelectSuffix        = SelectSuffix,
    SumCuratedBonuses   = SumCuratedBonuses,
    PruneCuratedItems   = PruneCuratedItems,
    GetCuratedEntry     = GetCuratedEntry,
    GetCuratedItems     = function() return CuratedItems end,
    GetNextCuratedId    = function() return NextCuratedId end,
    FilterStatsForItem  = FilterStatsForItem,
    ItemWeaponSkillId   = ItemWeaponSkillId,
    ApplyQualityAndTrim = ApplyQualityAndTrim,
    MAX_ITEM_STATS      = MAX_ITEM_STATS,
}

Log(Merge.Log.Info, "Init finished: %s", LogId)
