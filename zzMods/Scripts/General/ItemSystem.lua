-- =============================================================================
-- MMMerge Curated Item System — Runtime Logic (zzMods enhanced version)
-- Scripts/General/ItemSystem.lua
-- =============================================================================
-- Hooks into events.ItemGenerated to replace vanilla random enchantments
-- with curated prefix/suffix pairs from ItemPools.lua.
--
-- Items are identified by composite key:
--     Number|Bonus|BonusStrength|Bonus2
-- (stable across inventory moves and save/load).
-- item.Charges is set to the curated ID to trigger the native tooltip
-- Enchantment row; ItemSystemTooltip.lua replaces "Charges: N" with
-- the actual curated prefix/suffix stat text.
-- Bonus/BonusStrength/Bonus2 are NEVER modified.
--
-- QUALITY: each curated item gets a random quality 0.35–0.85 based on
-- average party level.  Stats are multiplied by quality before application.
-- Only the top 4 stats (by adjusted value) are kept per item.
-- Weapon-skill bonuses are filtered to the item's actual weapon type.
-- Skill bonuses are capped at the player's base (unbuffed) skill level.
--
-- Toggle: Game.ItemSystemEnabled gates all event handlers.
-- Visual layer: ItemSystemDisplay.lua (names), ItemSystemTooltip.lua (tooltips).
-- =============================================================================

local LogId = "ItemSystem"
Log(Merge.Log.Info, "Init started: %s", LogId)

-- Pool data lives in Items/ to keep it separate from logic.
-- AppPath is set by main.lua before General/*.lua runs.
local Pools = dofile(AppPath.."Scripts/Items/ItemPools.lua")
local random = math.random
local mmv = function(...) return select((offsets.MMVersion or 8) - 5, ...) end

Game.ItemSystemEnabled = (Game.ItemSystemEnabled == nil) and true or Game.ItemSystemEnabled

-- =============================================================================
-- ID ENCODING
-- We encode our selection ID into item.Bonus2 using a non-overlapping offset
-- (vanilla Bonus2 uses values roughly 0–80). The ID indexes into the
-- CuratedItems table persisted via internal.SaveGameData.
-- IDs are assigned in DETERMINISTIC ORDER so they survive save/load.
-- =============================================================================
local PREFIX_OFFSET = 2000   -- internal IDs for IdToPrefix (never written to items)
local SUFFIX_OFFSET = 4000   -- internal IDs for IdToSuffix (never written to items)
-- Ceiling for per-item entry ids stored in item.Charges. This used to be
-- PREFIX_OFFSET (2000), which a long playthrough can genuinely exhaust --
-- the id counter only ever grows (salvage/recuration included), and once a
-- tag reached 2000 it was silently rejected as invalid: items curated but
-- displayed/applied nothing (2026-07-16 hostile-QA finding). 1e6 is beyond
-- any realistic playthrough. NOTE: entry ids share no id space with the
-- PREFIX/SUFFIX index ids above -- those live in separate tables and are
-- never written to item.Charges, so overlap between the ranges is harmless.
local MAX_ENTRY_ID = 1000000

-- ORDER MUST NEVER CHANGE — changing order breaks existing saves.
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
local IdToPrefix = {}   -- [encodedId] = prefix entry table
local IdToSuffix = {}   -- [encodedId] = suffix entry table

local function BuildIndices()
    local pid = PREFIX_OFFSET
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
    local sid = SUFFIX_OFFSET
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
    Log(Merge.Log.Info, "%s: Indexed %d prefixes, %d suffixes",
        LogId, pid - PREFIX_OFFSET, sid - SUFFIX_OFFSET)
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
-- HELPERS
-- =============================================================================

-- Armor body skills that share the same equip slot — mutually exclusive.
local ARMOR_BODY_SKILLS = {
    [const.Skills.Leather] = true,  -- 9
    [const.Skills.Chain]   = true,  -- 10
    [const.Skills.Plate]   = true,  -- 11
}
local ARMOR_BODY_SKILL_IDS = {
    Leather = const.Skills.Leather,
    Chain   = const.Skills.Chain,
    Plate   = const.Skills.Plate,
}

local function HasArmorConflict(stats, requiredSkill)
    if not stats or not requiredSkill or not ARMOR_BODY_SKILLS[requiredSkill] then
        return false
    end
    for name in pairs(stats) do
        local skillId = ARMOR_BODY_SKILL_IDS[name]
        if skillId and skillId ~= requiredSkill then
            return true
        end
    end
    return false
end

-- Select a random prefix from pool filtered by alignment.
-- gen/spec tags are always eligible. light/dark tags are only eligible
-- when the character's alignment matches exactly.
local function SelectPrefix(pool, alignment, requiredSkill)
    local c = {}
    for _, e in ipairs(pool) do
        if not (e.tag == "light" and alignment ~= "light")
        and not (e.tag == "dark"  and alignment ~= "dark")
        and not HasArmorConflict(e.stats, requiredSkill) then
            c[#c + 1] = e
        end
    end
    return #c > 0 and c[random(#c)] or nil
end

-- Select a random suffix from pool filtered by tier and alignment.
-- Falls back to tier 0 if no tier match (should not happen with complete pool data).
-- Alignment filter is applied in both the primary pass and the fallback.
local function SelectSuffix(pool, tier, alignment, requiredSkill)
    local c = {}
    for _, e in ipairs(pool) do
        if e.tier == tier
        and not (e.alignment == "light" and alignment ~= "light")
        and not (e.alignment == "dark"  and alignment ~= "dark")
        and not HasArmorConflict(e.stats, requiredSkill) then
            c[#c + 1] = e
        end
    end
    if #c == 0 then
        -- Fallback: use tier 0 entries, still filtering by alignment
        for _, e in ipairs(pool) do
            if e.tier == 0
            and not (e.alignment == "light" and alignment ~= "light")
            and not (e.alignment == "dark"  and alignment ~= "dark")
            and not HasArmorConflict(e.stats, requiredSkill) then
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
-- When requiredSkill is set, only members whose class can reach Master+ are eligible.
local function RandomPartyMember(requiredSkill)
    if not Party or not Party.count or Party.count < 1 then return nil end
    local active = {}
    for i = 0, Party.count - 1 do
        local ok, p = pcall(function() return Party[i] end)
        if ok and p and p.Class and p.Class >= 0 then
            if not requiredSkill then
                active[#active + 1] = p
            else
                local mastery = Game.Classes.Skills
                    and Game.Classes.Skills[p.Class]
                    and Game.Classes.Skills[p.Class][requiredSkill]
                if mastery and mastery >= 3 then
                    active[#active + 1] = p
                end
            end
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

-- Only EQUIPPABLE item types may be curated. Curated bonuses apply solely
-- through the equipped-item scan, so curating a consumable is at best inert
-- -- and for potions/reagents it is DESTRUCTIVE: they store their power in
-- item.Bonus, so the "suppress vanilla enchant" step (Bonus = 0) erased
-- potion strength (found in playtesting 2026-07-17: potions showing curated
-- stats). EquipStat is const.ItemType - 1 (see zzLootAll.lua's Gold check),
-- so 12..18 = wand, reagent, potion, scroll, book, mscroll, gold. Everything
-- else (0..11 wearables, 19+ Merge-extended categories) is fair game.
local function IsCuratableType(item)
    local t = item and item["T"] and item:T()
    if not t then return false end
    local es = t.EquipStat
    return not (es >= 12 and es <= 18)
end

-- Roll item quality based on average party experience level.
-- Per the design doc (README_ItemSystem.md "Stat Variance — Quality"):
-- pool values are MAXIMUM possible values; quality is in [0.35, 1.00],
-- scaling with party level over 124 levels. (An interim version used
-- [0.5, 1.5], letting items roll 150% of pool maximums -- overpowered,
-- reported in play-testing 2026-07-16.)
local function RollQuality()
    local avgLevel = 1
    if Party and Party.Players then
        local total, n = 0, 0
        for _, p in Party.Players do
            -- LevelBase is a real, documented Player field. A previous
            -- version read the nonexistent `p.ExpForLevel`, so quality never
            -- scaled with party level (caught in the 2026-07-16 QA pass).
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

-- =============================================================================
-- PERSISTENT CURATED ITEM STORAGE
-- Selections survive save/load via internal.SaveGameData.CuratedItems[].
-- Items are identified by their 4-field composite key:
--   (Number, Bonus, BonusStrength, Bonus2)
-- Entry format (hybrid): { prefixId, suffixId, num, bonus, bonusStr, bonus2, quality = quality }
-- item fields are NEVER modified.
-- =============================================================================

local CuratedItems       -- table: { [id] = { prefixId=, suffixId=, num=, bonus=, bonusStr=, bonus2=, quality= } }
local CuratedItemLookup  -- reverse-index: key = "num|bonus|bonusStr|bonus2" → id
local NextCuratedId

-- Entry field accessors, reading every format this project has ever saved
-- (all confirmed present in real saves via the 2026-07-16 [DIAG ENTRY] dump):
--   current:   { prefixId=, suffixId=, num=,        bonus=,     bonusStr=,          bonus2= }
--   legacy:    { prefixId=, suffixId=, itemNumber=, origBonus=, origBonusStrength=, origBonus2= }
--   array-era: { [1]=pid, [2]=sid, [3]=num, [4]=bonus, [5]=bonusStr, [6]=bonus2 }
-- New entries MUST use the current named form. NOTE: legacy prefixId/suffixId
-- values use the old sequential index space and will NOT resolve in the
-- current PREFIX_OFFSET-based IdToPrefix/IdToSuffix -- GetCuratedIdAndEntry
-- treats unresolvable entries as "not curated" so recuration replaces them.
local function EntryPrefixId(e) return e.prefixId or e[1] end
local function EntrySuffixId(e) return e.suffixId or e[2] end
local function EntryNumber(e)   return e.num      or e.itemNumber        or e[3] end
local function EntryBonus(e)    return e.bonus    or e.origBonus         or e[4] end
local function EntryBonusStr(e) return e.bonusStr or e.origBonusStrength or e[5] end
local function EntryBonus2(e)   return e.bonus2   or e.origBonus2        or e[6] end

-- O(1) lookup with linear-scan fallback (handles edge cases).
local function LookupCuratedId(key)
    local id = CuratedItemLookup and CuratedItemLookup[key]
    if id then return id end
    if not CuratedItems then return nil end
    for eid, entry in pairs(CuratedItems) do
        if EntryNumber(entry) then
            local ek = EntryNumber(entry) .. "|" .. (EntryBonus(entry) or 0) .. "|" .. (EntryBonusStr(entry) or 0) .. "|" .. (EntryBonus2(entry) or 0)
            if ek == key then
                CuratedItemLookup[key] = eid
                return eid
            end
        end
    end
    return nil
end

-- Forward declaration: GetItemRequiredSkill is defined further down (with the
-- equip-slot tables it needs) but called inside events.ItemGenerated below.
-- Without this, the call compiled as a GLOBAL lookup (nil) and EVERY item
-- generation errored out ("attempt to call global 'GetItemRequiredSkill'"),
-- silently leaving all items vanilla -- caught in the 2026-07-14 pre-ship
-- audit from the session log. Locals must be declared before any closure
-- that references them is compiled.
local GetItemRequiredSkill

-- =============================================================================
-- MAIN HOOK
-- Appends to events.ItemGenerated — does not replace existing handlers.
-- =============================================================================
function events.ItemGenerated(t)
    if not Game.ItemSystemEnabled then return end
    local ok, err = pcall(function()
        if not CuratedItems then return end
        local item = t.Item
        if not item.Bonus or item.Bonus == 0 then return end
        if IsExcludedItem(item.Number) then return end
        if item.MaxCharges and item.MaxCharges > 0 then return end
        if not IsCuratableType(item) then return end

        local requiredSkill = GetItemRequiredSkill(item)
        local player = RandomPartyMember(requiredSkill)
        local class
        if player then
            class = player.Class
        else
            -- No eligible party member: either the party isn't loaded yet
            -- (startup / initial shop+chest stocking fires before the save's
            -- party exists -- confirmed via [DIAG] logging, see AGENTS.md
            -- ItemSystem recovery incident) or no member's class can reach
            -- Master+ in requiredSkill. Fall back to a random mapped class so
            -- these items still get curated instead of silently staying
            -- vanilla -- this exact regression shipped once ("first shop all
            -- vanilla"). Respect the skill gate when one applies; if nothing
            -- satisfies it, any mapped class beats no curation at all.
            local candidates = {}
            for cls in pairs(ClassToLine) do
                if not requiredSkill then
                    candidates[#candidates + 1] = cls
                else
                    local m = Game.Classes and Game.Classes.Skills
                        and Game.Classes.Skills[cls]
                        and Game.Classes.Skills[cls][requiredSkill]
                    if m and m >= 3 then candidates[#candidates + 1] = cls end
                end
            end
            if #candidates == 0 then
                for cls in pairs(ClassToLine) do candidates[#candidates + 1] = cls end
            end
            if #candidates == 0 then return end
            class = candidates[random(#candidates)]
        end

        local line  = ClassToLine[class]
        if not line then
            Log(Merge.Log.Error, "%s: ItemGenerated #%d — class %d not in ClassToLine", LogId, item.Number, class)
            return
        end

        local bucket    = LineToBucket[line]
        local tier      = ClassTier[class]      or 0
        local alignment = ClassAlignment[class] or "any"

        local prefixPool = Pools.Prefixes[bucket]
        local suffixPool = Pools.Suffixes[line]
        if not prefixPool or not suffixPool then
            Log(Merge.Log.Error, "%s: ItemGenerated #%d — pool missing bucket=%s line=%s", LogId, item.Number, bucket, line)
            return
        end

        local prefix = SelectPrefix(prefixPool, alignment, requiredSkill)
        if not prefix then
            Log(Merge.Log.Error, "%s: ItemGenerated #%d — no prefix for bucket=%s align=%s", LogId, item.Number, bucket, alignment)
            return
        end
        local suffix = SelectSuffix(suffixPool, tier, alignment, requiredSkill)
        if not suffix then
            Log(Merge.Log.Error, "%s: ItemGenerated #%d — no suffix for line=%s tier=%d align=%s", LogId, item.Number, line, tier, alignment)
            return
        end

        local quality = RollQuality()

        local id = NextCuratedId
        NextCuratedId = NextCuratedId + 1
        if internal and internal.SaveGameData then
            internal.SaveGameData.NextCuratedId = NextCuratedId
        end
        CuratedItems[id] = {
            prefixId = prefix._prefixId,
            suffixId = suffix._suffixId,
            num      = item.Number or 0,
            bonus    = item.Bonus or 0,
            bonusStr = item.BonusStrength or 0,
            bonus2   = item.Bonus2 or 0,
            quality  = quality,
        }
        local key = (item.Number or 0) .. "|" .. (item.Bonus or 0) .. "|" .. (item.BonusStrength or 0) .. "|" .. (item.Bonus2 or 0)
        if not CuratedItemLookup[key] then CuratedItemLookup[key] = id end
        item.Charges = id   -- primary identity tag; also triggers the native Enchantment row the tooltip replaces
        -- Suppress the vanilla enchantment so ONLY the curated bonuses apply.
        -- Without this, the native engine kept applying the vanilla roll
        -- invisibly alongside the curated stats (double-dipping, with only
        -- the curated half displayed) -- reported in play-testing 2026-07-16.
        -- The original roll is preserved in the entry above for revert.
        item.Bonus = 0
        item.BonusStrength = 0
        item.Bonus2 = 0

        Log(Merge.Log.Info,
            "%s: Item #%d → \"%s\" + \"%s\" [class=%d tier=%d %s] (id=%d qual=%.2f)",
            LogId, item.Number, prefix.name, suffix.name,
            class, tier, alignment, id, quality)
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: ItemGenerated error: %s", LogId, err)
    end
end

-- =============================================================================
-- PUBLIC API
-- Other scripts can inspect what enchantment is on any item.
-- =============================================================================

-- Identity is the item.Charges tag (primary), NOT the composite key: since
-- curation zeroes the vanilla Bonus fields (see ItemGenerated), every curated
-- item of the same Number reads "num|0|0|0" and composite keys can no longer
-- distinguish them. The composite key of the ORIGINAL roll is still stored in
-- each entry (fields 3-6) for revert and for the recuration tool. The entry's
-- stored Number (entry.num) is sanity-checked against the item so a stale tag
-- from an older id scheme can never match the wrong entry.
local function GetCuratedIdAndEntry(item)
    if not item then return nil, nil end
    local id = item.Charges
    if not id or id <= 0 or id >= MAX_ENTRY_ID then return nil, nil end
    local entry = CuratedItems and CuratedItems[id]
    if not entry then return nil, nil end
    local eNum = EntryNumber(entry)
    if eNum and item.Number and eNum ~= item.Number then return nil, nil end
    -- An entry only counts if it actually resolves to a live prefix+suffix.
    -- Legacy entries (old sequential id space) and content-damaged entries
    -- would otherwise be "present but unusable": items looked curated to
    -- IsCuratedItem (blocking recuration forever) while displaying and
    -- applying NOTHING -- the recuration deadlock observed 2026-07-16.
    if not IdToPrefix[EntryPrefixId(entry) or -1]
            or not IdToSuffix[EntrySuffixId(entry) or -1] then
        return nil, nil
    end
    return id, entry
end

local function GetCuratedIds(item)
    local _, entry = GetCuratedIdAndEntry(item)
    if entry then
        return IdToPrefix[EntryPrefixId(entry)], IdToSuffix[EntrySuffixId(entry)]
    end
    return nil, nil
end

function GetItemPrefix(item)
    local p = GetCuratedIds(item)
    return p
end

function GetItemSuffix(item)
    local _, s = GetCuratedIds(item)
    return s
end

function IsCuratedItem(item)
    local _, entry = GetCuratedIdAndEntry(item)
    return entry ~= nil
end

function GetCuratedEntry(item)
    local _, entry = GetCuratedIdAndEntry(item)
    return entry
end

-- =============================================================================
-- WEAPON-SKILL FILTER
-- A weapon item can only apply bonuses for its OWN weapon skill.
-- Staff and Unarmed are treated as compatible (Monk exception).
-- =============================================================================
local WeaponSkillStats = {
    Sword = true, Axe = true, Mace = true, Dagger = true,
    Staff = true, Spear = true, Bow = true, Unarmed = true,
}

-- Item types that require a specific skill to use effectively.
-- Weapons (0/1/2, 22-29) → weapon skill ID.
-- Body armor (3, 30-32) → Leather/Chain/Plate skill ID.
-- Shield (4, 33) → Shield skill ID.
local EQUIP_SKILL_SLOTS = {
    [0] = true, [1] = true, [2] = true,       -- Weapon(1H), Weapon2H, Missile (old)
    [3] = true,                                 -- Armor (old)
    [4] = true,                                 -- Shield (old)
    [22] = true, [23] = true, [24] = true,     -- Sword, Dagger, Axe (extended)
    [25] = true, [26] = true, [27] = true,     -- Spear, Bow, Mace (extended)
    [28] = true, [29] = true,                   -- Club, Staff (extended)
    [30] = true, [31] = true, [32] = true,      -- Leather, Chain, Plate (extended)
    [33] = true,                                 -- Shield_ (extended)
}

-- (assigns the forward-declared local above -- do NOT re-declare with `local`,
-- or ItemGenerated's captured upvalue would stay nil)
function GetItemRequiredSkill(item)
    local t = item and item["T"] and item:T()
    if not t or not EQUIP_SKILL_SLOTS[t.EquipStat] then return nil end
    return t.Skill
end

local function GetItemWeaponSkill(item)
    local t = item and item["T"] and item:T()
    if not t then return nil end
    local equipStat = t.EquipStat
    if equipStat ~= 22 and equipStat ~= 23 and equipStat ~= 24 then return nil end
    return t.Skill
end

function FilterStatsForItem(item, stats)
    if not stats then return stats end
    local weaponSkill = GetItemWeaponSkill(item)
    local requiredSkill = GetItemRequiredSkill(item)
    local isArmorSlot = requiredSkill and ARMOR_BODY_SKILLS[requiredSkill]
    if not weaponSkill and not isArmorSlot then return stats end
    local result = {}
    for name, value in pairs(stats) do
        local armorSkillId = ARMOR_BODY_SKILL_IDS[name]
        if armorSkillId then
            -- Armor skill bonus: keep only if it matches the item's slot
            if isArmorSlot and armorSkillId == requiredSkill then
                result[name] = value
            end
        elseif weaponSkill and WeaponSkillStats[name] then
            -- Weapon skill bonus: keep only if it matches the item's weapon skill
            if name == weaponSkill then
                result[name] = value
            elseif weaponSkill == const.Skills.Staff and name == "Unarmed" then
                result[name] = value
            elseif name == "Staff" and weaponSkill == const.Skills.Unarmed then
                result[name] = value
            end
        else
            result[name] = value
        end
    end
    return result
end

-- =============================================================================
-- STAT COUNT CAP & SKILL BONUS CAP
-- After quality adjustment, keep only the top N stat/skill values per item.
-- Skill bonuses are capped at the player's base (unbuffed) skill level.
-- =============================================================================
local MAX_ITEM_STATS = 4

-- Returns (level, mastery) -- SAME ORDER as the global SplitSkill in
-- Scripts/Structs/After/Functions.lua (level = bits 0-5, mastery = bits 6+).
-- A previous version returned them REVERSED, which made the skill cap in
-- events.GetSkill cap by mastery code (0/1/2/4) instead of skill level --
-- a level-10 Normal-mastery skill capped item bonuses at 1 (caught in the
-- 2026-07-16 hostile-QA pass).
local function SplitSkill(skillAndMastery)
    if not skillAndMastery then return 0, 0 end
    return skillAndMastery % 64, math.floor(skillAndMastery / 64)
end

-- (skill cap is applied inside events.GetSkill on the cross-item total --
-- see the "Skill Bonus Cap" comment there)

-- =============================================================================
-- PHASE 2: STAT & SKILL APPLICATION
-- Two hooks apply curated stat and skill bonuses from equipped items.
--   CalcStatBonusByItems — primary stats, HP, SP, AC, magic schools
--   GetSkill             — weapon skills, armor skills, utility skills
-- Quality, weapon-skill filter, top-N trim, and skill cap are applied.
-- =============================================================================

-- Pool stat name → const.Stats mapping. CORE ATTRIBUTES ONLY (applied via
-- events.CalcStatBonusByItems, uncapped per the design doc). All skill-type
-- bonuses -- including magic schools -- live in SkillMap below so they flow
-- through events.GetSkill and the skill cap ("Skill Bonus Cap" section of
-- README_ItemSystem.md). An interim version routed schools and utility
-- skills through this uncapped stat channel, bypassing the cap entirely
-- (reported as overpowered in play-testing 2026-07-16).
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
}

-- Pool skill name → const.Skills mapping. Everything skill-shaped lives here
-- (weapon, armor, utility, AND magic schools) so it all flows through
-- events.GetSkill and the skill cap, per the design doc. Earlier the schools
-- appeared starved out of the top-4 trim ("of the Lich" gave no skills) --
-- that was actually the inflated [0.5,1.5] quality range bloating attribute
-- values past them, not a flaw in the trim; with the spec's [0.35,1.0] range
-- the ranking behaves as the doc's own worked example shows.
local SkillMap = {
    Sword          = const.Skills.Sword,
    Axe            = const.Skills.Axe,
    Mace           = const.Skills.Mace,
    Dagger         = const.Skills.Dagger,
    Staff          = const.Skills.Staff,
    Spear          = const.Skills.Spear,
    Bow            = const.Skills.Bow,
    Shield         = const.Skills.Shield,
    Plate          = const.Skills.Plate,
    Chain          = const.Skills.Chain,
    Leather        = const.Skills.Leather,
    Fire           = const.Skills.Fire,
    Air            = const.Skills.Air,
    Water          = const.Skills.Water,
    Earth          = const.Skills.Earth,
    Spirit         = const.Skills.Spirit,
    Mind           = const.Skills.Mind,
    Body           = const.Skills.Body,
    Light          = const.Skills.Light,
    Dark           = const.Skills.Dark,
    Meditation     = const.Skills.Meditation,
    Unarmed        = const.Skills.Unarmed,
    Dodge          = const.Skills.Dodging,
    Armsmaster     = const.Skills.Armsmaster,
    Alchemy        = const.Skills.Alchemy,
    Stealing       = const.Skills.Stealing,
    -- This pack FREES the DisarmTraps slot (31) and merges disarming into
    -- Perception (see zzMods/AGENTS.md "Skill Slot Reuse") -- a bonus routed
    -- to slot 31 would be dead weight ("the Deerslayer" grants DisarmTrap=2).
    -- Map the pool name to Perception, the skill that actually disarms now.
    DisarmTrap     = const.Skills.Perception,
    IdentifyItem   = const.Skills.IdentifyItem,
    IdentifyMonster= const.Skills.IdentifyMonster,
    Learning       = const.Skills.Learning,
    Merchant       = const.Skills.Merchant,
    Repair         = const.Skills.Repair,
    Bodybuilding   = const.Skills.Bodybuilding,
    Perception     = const.Skills.Perception,
    Regeneration   = const.Skills.Regeneration,
    DragonMagic    = const.Skills.DragonAbility,
}

-- Iterate equipped items and accumulate stat/skill contributions.
-- Per README_ItemSystem.md "Stat Count Cap": for each item, prefix+suffix
-- stats are quality-scaled, SAME-NAME bonuses are summed FIRST, then ranked
-- by value, and only the top MAX_ITEM_STATS survive -- attributes and skills
-- compete together, exactly as the doc's worked example shows. The skill cap
-- is NOT applied here; it caps the cross-item TOTAL at query time in
-- events.GetSkill (see "Skill Bonus Cap" section).
local function SumCuratedBonuses(player, statAcc, skillAcc)
    if not player or not player["?ptr"] or player["?ptr"] <= 0 then return end
    for i = 0, 15 do
        local itemIdx = player.EquippedItems[i]
        if itemIdx and itemIdx > 0 and itemIdx <= 138 then
            local itemObj = player.Items[itemIdx]
            if itemObj and itemObj["?ptr"] and itemObj["?ptr"] > 0 then
                local prefix, suffix = GetCuratedIds(itemObj)
                local entry = GetCuratedEntry(itemObj)
                local quality = (entry and entry.quality) or 0.60
                -- Sum same-name bonuses across prefix+suffix first...
                local totals = {}
                local function collectStats(stats)
                    if not stats then return end
                    local filtered = FilterStatsForItem(itemObj, stats)
                    for k, v in pairs(filtered) do
                        if StatMap[k] or SkillMap[k] then
                            local adj = math.max(1, math.floor(v * quality))
                            totals[k] = (totals[k] or 0) + adj
                        end
                    end
                end
                collectStats(prefix and prefix.stats)
                collectStats(suffix and suffix.stats)
                -- ...then rank and keep only the top MAX_ITEM_STATS.
                local ranked = {}
                for k, v in pairs(totals) do
                    ranked[#ranked + 1] = { name = k, value = v }
                end
                table.sort(ranked, function(a, b) return a.value > b.value end)
                for idx = 1, math.min(MAX_ITEM_STATS, #ranked) do
                    local k = ranked[idx].name
                    local adj = ranked[idx].value
                    if StatMap[k] then
                        statAcc[StatMap[k]] = (statAcc[StatMap[k]] or 0) + adj
                    elseif SkillMap[k] then
                        skillAcc[SkillMap[k]] = (skillAcc[SkillMap[k]] or 0) + adj
                    end
                end
            end
        end
    end
end

-- Per-player cache of accumulated curated bonuses. CalcStatBonusByItems and
-- GetSkill fire once per stat/skill for each player on every recalculation
-- pass (dozens of calls per player); recomputing the full 16-slot equipment
-- scan + sort on every single call is the known "character screen stutter"
-- problem an earlier version solved the same way. A cheap signature of the
-- equipped-item indexes (+ a global epoch) detects when a real re-scan is
-- needed. The cache stores UNCAPPED skill totals -- the skill cap depends on
-- the player's current training and is applied at query time in GetSkill, so
-- training a skill never serves stale capped values.
local BonusCache = {}   -- [playerIndex] = { sig = "...", stat = {...}, skill = {...} }
local CacheEpoch = 0

-- Bump whenever entry data changes outside of an equip change (recuration,
-- salvage, suppression, save load, toggle) -- equipping/unequipping already
-- changes the signature by itself.
local function InvalidateBonusCache()
    CacheEpoch = CacheEpoch + 1
    BonusCache = {}
end

local function GetCachedBonuses(player, playerIndex)
    if playerIndex == nil then
        -- No stable cache key: fall back to a direct scan.
        local statAcc, skillAcc = {}, {}
        SumCuratedBonuses(player, statAcc, skillAcc)
        return statAcc, skillAcc
    end
    -- Signature must capture item IDENTITY, not just which Items-array slots
    -- are equipped: swapping an item in place reuses the same slot index, so
    -- an index-only signature stayed identical and served the OLD item's
    -- bonuses until gear moved again (playtest report 2026-07-17: "swap
    -- keeps the previous item's stats until re-equipped"). Number + Charges
    -- distinguish the occupant (Charges = curated id, unique per item).
    local parts = { CacheEpoch }
    for i = 0, 15 do
        local idx = player.EquippedItems[i] or 0
        parts[#parts + 1] = idx
        if idx > 0 and idx <= 138 then
            local it = player.Items[idx]
            if it and it["?ptr"] and it["?ptr"] > 0 then
                parts[#parts + 1] = it.Number or 0
                parts[#parts + 1] = it.Charges or 0
            end
        end
    end
    local sig = table.concat(parts, ",")
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

-- Hook 2: skill bonuses (fires per-skill for each player, MM7+).
-- Skill Bonus Cap (README_ItemSystem.md): the summed curated bonus for a
-- skill can never exceed the player's BASE skill level, with a floor of 1 so
-- even untrained skills get a tiny nudge:
--   finalBonus = min(curatedTotal, max(playerBaseSkill, 1))
-- Applied to the cross-item TOTAL here at query time (capping per item, as an
-- interim version did, lets several items stack past the cap). Applies to ALL
-- skills routed through SkillMap -- weapon, armor, utility, and magic schools.
function events.GetSkill(t)
    if not Game.ItemSystemEnabled then return end
    local ok, err = pcall(function()
        if not t.Player then return end
        local _, skillAcc = GetCachedBonuses(t.Player, t.PlayerIndex)
        local bonus = skillAcc[t.Skill]
        if bonus then
            local baseRank = SplitSkill(t.Player.Skills[t.Skill] or 0)
            t.Result = t.Result + math.min(bonus, math.max(baseRank, 1))
        end
    end)
    if not ok then
        Log(Merge.Log.Error, "%s: GetSkill error: %s", LogId, err)
    end
end

-- =============================================================================
-- ITEM VALUE (sell/buy price)
-- Curated items suppress the vanilla Bonus (=0), so native GetValue prices
-- them at bare base cost -- reported 2026-07-16. Add a premium reflecting the
-- item's ACTUAL curated bonuses (works for freshly-generated AND salvaged
-- items alike, unlike restoring the suppressed vanilla roll -- salvaged items
-- had no vanilla roll to restore).
-- =============================================================================
local GOLD_PER_BONUS_POINT = 100

-- Sum of an item's applied curated bonus values (post-quality, top-N trimmed
-- -- the SAME set the tooltip shows and SumCuratedBonuses applies).
local function CuratedBonusSum(item)
    local entry = GetCuratedEntry(item)
    if not entry then return 0 end
    local prefix, suffix = GetItemPrefix(item), GetItemSuffix(item)
    if not prefix and not suffix then return 0 end
    local quality = entry.quality or 0.60
    local totals = {}
    local function collect(stats)
        if not stats then return end
        local filtered = FilterStatsForItem(item, stats)
        for k, v in pairs(filtered) do
            if StatMap[k] or SkillMap[k] then
                totals[k] = (totals[k] or 0) + math.max(1, math.floor(v * quality))
            end
        end
    end
    collect(prefix and prefix.stats)
    collect(suffix and suffix.stats)
    local ranked = {}
    for _, v in pairs(totals) do ranked[#ranked + 1] = v end
    table.sort(ranked, function(a, b) return a > b end)
    local sum = 0
    for i = 1, math.min(MAX_ITEM_STATS, #ranked) do sum = sum + ranked[i] end
    return sum
end

if Game.Version == 8 then
    -- structs.Item.GetValue @ 0x453CE7: thiscall (ecx=this), no stack args,
    -- returns eax -> hookfunction convention (1, 0). Disassembly confirms a
    -- clean hookable entry; the README's note about an earlier crash was a
    -- technique error -- if this callback throws, the hook trampoline's
    -- d:ret() is skipped and the stack corrupts (the Town Portal 0x425B1A
    -- lesson), so EVERY path here is pcall-isolated and always returns a
    -- number. Additive only: never mutates item fields (no double-apply risk).
    mem.hookfunction(0x453CE7, 1, 0, function(d, def, this)
        local vok, base = pcall(def, this)
        if not vok or type(base) ~= "number" then
            return type(base) == "number" and base or 0
        end
        if not Game.ItemSystemEnabled then return base end
        local pok, sum = pcall(function()
            return CuratedBonusSum(structs.Item:new(this))
        end)
        if pok and type(sum) == "number" and sum > 0 then
            return base + sum * GOLD_PER_BONUS_POINT
        end
        return base
    end)
end

-- =============================================================================
-- TOGGLE & SYNC
-- Game.ItemSystemEnabled gates all event handlers.
-- No item-level changes are needed — toggle just enables/disables
-- stat/skill application and visual hooks.
-- =============================================================================
function SyncItemSystemToggle()
    InvalidateBonusCache()
    Log(Merge.Log.Info, "%s: Toggle %s", LogId, Game.ItemSystemEnabled and "ON" or "OFF")
end

-- =============================================================================
-- PRUNING
-- Removes CuratedItems entries for items no longer in party possession.
-- =============================================================================
local function PruneCuratedItems()
    if not Game.ItemSystemEnabled then return end
    if not CuratedItems then return end
    -- HARD GUARD: never prune when the party isn't iterable (startup / main
    -- menu). An empty scan marks nothing as active, and the loop below would
    -- then delete EVERY entry -- total curated-data wipe. This exact landmine
    -- was latent in the composite-key version (caught in the 2026-07-16
    -- pre-ship audit); only safe to prune with a live party in hand.
    if not Party or not Party.Players then return end
    local active = {}
    local playersSeen = 0
    for _, player in Party.Players do
        playersSeen = playersSeen + 1
        for slot = 1, 138 do
            local item = player.Items[slot]
            if item and item.Number and item.Number > 0 then
                -- tag-based match (see GetCuratedIdAndEntry): the composite
                -- key can't identify curated items once bonuses are zeroed
                local id = item.Charges
                if id and id > 0 and id < MAX_ENTRY_ID then
                    active[id] = true
                end
            end
        end
    end
    if playersSeen == 0 then return end  -- party empty: same wipe risk as above
    local pruned = 0
    for id, _ in pairs(CuratedItems) do
        if not active[id] then
            CuratedItems[id] = nil
            pruned = pruned + 1
        end
    end
    if pruned > 0 then
        Log(Merge.Log.Info, "%s: Pruned %d stale entries", LogId, pruned)
    end
end

-- =============================================================================
-- ITEMSYSTEM INTERNAL — public API for other files
-- =============================================================================
ItemSystemInternal = {
    ClassToLine = ClassToLine,
    LineToBucket = LineToBucket,
    ClassTier = ClassTier,
    ClassAlignment = ClassAlignment,
    Pools = Pools,
    SelectPrefix = SelectPrefix,
    SelectSuffix = SelectSuffix,
    GetCuratedItems = function() return CuratedItems end,
    GetCuratedEntry = GetCuratedEntry,
    InvalidateBonusCache = InvalidateBonusCache,
    -- Entry-format helpers for zzRepairItems.lua's salvage pass:
    EntryNumber = EntryNumber,
    IsEntryResolvable = function(e)
        return IdToPrefix[EntryPrefixId(e) or -1] ~= nil
           and IdToSuffix[EntrySuffixId(e) or -1] ~= nil
    end,
    -- For the consumable-restore pass (un-curating wrongly-tagged potions):
    IsCuratableType = IsCuratableType,
    EntryBonus = EntryBonus,
    EntryBonusStr = EntryBonusStr,
    EntryBonus2 = EntryBonus2,
    GetNextCuratedId = function() return NextCuratedId end,
    PruneCuratedItems = PruneCuratedItems,
    FilterStatsForItem = FilterStatsForItem,
    GetItemRequiredSkill = GetItemRequiredSkill,
    RandomPartyMember = function(rs) return RandomPartyMember(rs) end,
    MAX_ITEM_STATS = MAX_ITEM_STATS,
    StatMap = StatMap,
    SkillMap = SkillMap,
    SumCuratedBonuses = SumCuratedBonuses,
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Bind CuratedItems/NextCuratedId to the CURRENT internal.SaveGameData and
-- rebuild the reverse index. Called from GameInitialized2 (app startup) AND
-- from LoadMapScripts on every fresh save load -- the latter is what makes
-- persistence actually work (see the persistence-bug note below).
local function BindSaveDataAndRebuild(context)
    local sgd = internal and internal.SaveGameData
    -- Type guard: a corrupt/foreign save could carry a non-table under this
    -- key; pairs() over it below would throw inside an event handler.
    if sgd and type(sgd.CuratedItems) == "table" then
        CuratedItems  = sgd.CuratedItems
        NextCuratedId = tonumber(sgd.NextCuratedId) or 1
    else
        CuratedItems  = {}
        NextCuratedId = 1
        if sgd then
            sgd.CuratedItems  = CuratedItems
            sgd.NextCuratedId = NextCuratedId
        end
    end
    -- Build reverse-index lookup. Entries without a readable item Number
    -- (broken/legacy formats) are skipped; recuration replaces them.
    -- Entries without explicit .quality default to 0.60.
    CuratedItemLookup = {}
    local total, count = 0, 0
    for id, entry in pairs(CuratedItems) do
        total = total + 1
        -- Repair a stale/low persisted counter (observed: counter 70 with
        -- entries up to ~172): allocating ids below the existing max would
        -- silently overwrite live entries, cross-linking items.
        if type(id) == "number" and id >= NextCuratedId then
            NextCuratedId = id + 1
        end
        if EntryNumber(entry) then
            if entry.quality == nil then entry.quality = 0.60 end
            local key = EntryNumber(entry) .. "|" .. (EntryBonus(entry) or 0) .. "|" .. (EntryBonusStr(entry) or 0) .. "|" .. (EntryBonus2(entry) or 0)
            if not CuratedItemLookup[key] then
                CuratedItemLookup[key] = id
            end
            count = count + 1
        end
    end
    -- TEMPORARY DIAGNOSTIC (2026-07-16): entries round-trip through the save
    -- as tables but their inner numeric keys read nil afterwards (172 loaded,
    -- 0 indexable). Dump one failing entry's actual keys/types to pin down
    -- what the serializer did to them. REMOVE once root-caused.
    if total > 0 and count == 0 then
        for id, entry in pairs(CuratedItems) do
            local parts = {}
            for k, v in pairs(entry) do
                parts[#parts + 1] = string.format("[%s %s]=%s %s",
                    type(k), tostring(k), type(v), tostring(v))
                if #parts >= 8 then break end
            end
            Log(Merge.Log.Info, "%s: [DIAG ENTRY] id(%s)=%s keys: %s",
                LogId, type(id), tostring(id),
                #parts > 0 and table.concat(parts, " ") or "<EMPTY TABLE>")
            break
        end
    end
    InvalidateBonusCache()  -- entry data just changed wholesale
    Log(Merge.Log.Info, "%s: Ready (%s). %d/%d entries indexable (counter %d).",
        LogId, context, count, total, NextCuratedId - 1)
end

function events.GameInitialized2()
    BuildIndices()
    BindSaveDataAndRebuild("startup")
end

-- =============================================================================
-- PERSISTENCE (the actual fix for "items wiped on every reload")
-- GameInitialized2 fires ONCE at app startup, BEFORE any save is loaded; the
-- internal.SaveGameData it sees is then replaced when a save loads. Binding
-- only there meant reads never saw the real save's entries and writes went
-- into a discarded table -- every session ever logged "Ready. 0 entries",
-- items got curated in-memory, and the data evaporated on exit (root cause
-- of every "curated items wiped" incident; found in the 2026-07-16 audit).
-- Fix = the same proven pattern MenuExtraSettings/RemoveQBitsAndABitsLimits
-- use: re-bind from the CURRENT sgd after each fresh save load, and write
-- into the CURRENT sgd at save time.
-- NOTE: this handler must run before zzRepairItems.lua's LoadMapScripts
-- recuration pass; it does, because handlers run in file-load order and
-- "ItemSystem" sorts before "zzRepairItems".
-- =============================================================================
function events.LoadMapScripts(WasInGame)
    if WasInGame then return end
    BindSaveDataAndRebuild("save load")
    -- NO auto-prune here: prune only counts PARTY-carried tags as "in use",
    -- so every entry belonging to curated items sitting in SHOP STOCK or
    -- chests got deleted on each load (150 of 172 entries destroyed in one
    -- observed load, 2026-07-16). Entries are tiny; leaks are preferable to
    -- data loss. Prune remains available manually via RepairItems(true).
    -- Deliberately NO orphan-clearing here either: zzRepairItems.lua's
    -- LoadMapScripts pass runs AFTER this (file-load order) and needs stale
    -- tags intact to re-curate those items; it clears whatever it couldn't
    -- re-curate at the end of its own pass.
end

function events.BeforeSaveGame()
    local sgd = internal and internal.SaveGameData
    if sgd then
        sgd.CuratedItems  = CuratedItems
        sgd.NextCuratedId = NextCuratedId
    end
end

Log(Merge.Log.Info, "Init finished: %s", LogId)
