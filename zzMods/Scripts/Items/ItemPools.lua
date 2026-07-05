-- =============================================================================
-- MMMerge Curated Item System — Pool Definitions
-- Scripts/Items/ItemPools.lua
-- =============================================================================
--
-- PHILOSOPHY:
--   Every magic item has a clear identity. A player should be able to read
--   "Blessed Iron Mace of the Crusader" and immediately know who it's for
--   (divine melee fighter, first promotion). No more junk drops.
--
--   Prefixes = ROLE oriented  (which bucket/playstyle benefits)
--   Suffixes = CLASS oriented (which specific class/promotion this is tailored for)
--
-- EDITING GUIDE:
--   Prefixes and suffixes are plain Lua table entries. Freely change values,
--   add new entries by copying an existing one, or remove by deleting/commenting.
--
--   PREFIX ENTRY FORMAT:
--     { name = "DisplayName", stats = { StatName = Value, ... }, tag = "gen|spec|light|dark" }
--
--   SUFFIX ENTRY FORMAT:
--     { name = "DisplayName", stats = { StatName = Value, ... },
--       tier = 0|1|2, alignment = "any|light|dark" }
--
--   Tags:
--     gen   = generalist (all schools for bucket, minor bonus each — drops for any tier)
--     spec  = specialist (1-2 schools + primary stat — drops for any tier)
--     light = light-path only (only pairs with a light-aligned suffix)
--     dark  = dark-path only  (only pairs with a dark-aligned suffix)
--
--   Tiers:
--     0 = base class    (modest bonuses)
--     1 = 1st promotion (medium bonuses)
--     2 = 2nd promotion (strongest bonuses; may be light/dark/any aligned)
--
-- STAT VALUE SCALE (approximate tuning guide):
--   Primary stats (Might, Intellect, etc.):   +3–7 (tier 0), +5–10 (tier 1), +8–15 (tier 2)
--   Spell school skills (Fire, Spirit, etc.):  +1 (tier 0), +1–2 (tier 1), +2–3 (tier 2)
--     — Spell school bonuses are powerful. Keep values low.
--   Weapon/armor skills (Sword, Plate, etc.): +1–2 (tier 0), +2–3 (tier 1), +3–4 (tier 2)
--   Utility skills (Meditation, Repair, etc.): +1 (tier 0), +1–2 (tier 1), +2–3 (tier 2)
--
-- CAPPED SKILLS [CAP]:
--   These skills reach 100% effectiveness at Grandmaster with no benefit beyond that.
--   Include only as minor bonuses (+1) if at all — more is wasted item budget.
--     Merchant        — GM = 100% price discount, cannot improve further
--     Perception      — GM = 100% bonus on item find, cannot improve further
--     IdentifyMonster — GM = full monster info, cannot improve further
-- =============================================================================

-- STAT NAME REFERENCE:
-- Primary stats:  Might · Endurance · Intellect · Personality · Accuracy · Speed · Luck
-- Derived stats:  HP · SP · AC
-- Elemental:      Fire · Air · Water · Earth
-- Divine:         Spirit · Mind · Body
-- Moral:          Light · Dark
-- Weapon skills:  Sword · Axe · Mace · Dagger · Staff · Bow · Unarmed
-- Defense skills: Plate · Chain · Leather · Shield · Dodge
-- Support skills: Meditation · Bodybuilding · Alchemy · Repair · DisarmTrap · Stealing
-- Capped [CAP]:   Perception · Merchant · IdentifyMonster
-- Unique:         Regeneration · DragonMagic (Dragon class spell power, maps to Dragon skill)
-- =============================================================================

local M = {}


-- =============================================================================
-- PREFIX POOLS — Role / Bucket Oriented
-- =============================================================================

M.Prefixes = {

    -- -------------------------------------------------------------------------
    -- TANK — pure survivability, no spell schools
    -- -------------------------------------------------------------------------
    Tank = {
        { name = "Stalwart",    stats = { AC=3, Endurance=5 },              tag = "gen"  },
        { name = "Unyielding",  stats = { AC=5, HP=15 },                    tag = "spec" },
        { name = "Guardian's",  stats = { AC=4, Shield=2 },                 tag = "spec" },
        { name = "Ironhide",    stats = { AC=6, Endurance=4 },              tag = "spec" },
        { name = "Resolute",    stats = { Endurance=7, HP=10 },             tag = "spec" },
        { name = "Fortress",    stats = { AC=5, Endurance=5, HP=10 },       tag = "spec" },
    },

    -- -------------------------------------------------------------------------
    -- WARRIOR — raw physical output, no spell schools
    -- -------------------------------------------------------------------------
    Warrior = {
        { name = "Mighty",      stats = { Might=5 },                        tag = "gen"  },
        { name = "Swift",       stats = { Might=3, Speed=5 },               tag = "spec" },
        { name = "Savage",      stats = { Might=7, Endurance=3 },           tag = "spec" },
        { name = "Brutal",      stats = { Might=6, Endurance=4 },           tag = "spec" },
        { name = "Fierce",      stats = { Might=5, Accuracy=5 },            tag = "spec" },
        { name = "Raging",      stats = { Might=8, Speed=4 },               tag = "spec" },
    },

    -- -------------------------------------------------------------------------
    -- HYBRID INTELLECT — elemental schools (Fire/Air/Water/Earth)
    -- Classes: Archer line · Deerslayer line · Thief line
    -- -------------------------------------------------------------------------
    HybridIntellect = {
        -- Generalist: tiny bonus to all 4 elemental schools
        { name = "Battlemage's",  stats = { Fire=1, Air=1, Water=1, Earth=1, Might=3 }, tag = "gen"   },
        -- School specialists (2 schools max per prefix to stay focused)
        { name = "Pyromancer's",  stats = { Fire=2, Intellect=5 },                      tag = "spec"  },
        { name = "Stormcaller's", stats = { Air=2, Speed=3, Accuracy=3 },               tag = "spec"  },
        { name = "Frostweaver's", stats = { Water=2, Intellect=4 },                     tag = "spec"  },
        { name = "Earthshaper's", stats = { Earth=2, Endurance=4 },                     tag = "spec"  },
        { name = "Runic",         stats = { Fire=1, Earth=1, Might=4 },                 tag = "spec"  },
        -- Moral schools — only paired with a matching suffix alignment
        { name = "Sunforged",     stats = { Light=2, Intellect=4 },                     tag = "light" },
        { name = "Shadowbound",   stats = { Dark=2, Intellect=4 },                      tag = "dark"  },
    },

    -- -------------------------------------------------------------------------
    -- HYBRID PERSONALITY — divine schools (Spirit/Mind/Body)
    -- Classes: Paladin line · Monk line · Vampire line · Minotaur line
    -- -------------------------------------------------------------------------
    HybridPersonality = {
        -- Generalist: tiny bonus to all 3 divine schools
        { name = "Blessed",      stats = { Spirit=1, Mind=1, Body=1, Personality=3 },  tag = "gen"   },
        -- School specialists
        { name = "Zealous",      stats = { Might=4, Personality=4 },                   tag = "spec"  }, -- combat + divine balance
        { name = "Spiritbound",  stats = { Spirit=2, Personality=5 },                  tag = "spec"  },
        { name = "Ironwilled",   stats = { Mind=2, Personality=4, Luck=3 },            tag = "spec"  },
        { name = "Lifeguard's",  stats = { Body=2, Personality=4, HP=8 },              tag = "spec"  },
        -- Moral schools
        { name = "Hallowed",     stats = { Light=2, Personality=4 },                   tag = "light" },
        { name = "Corrupted",    stats = { Dark=2, Personality=4 },                    tag = "dark"  },
    },

    -- -------------------------------------------------------------------------
    -- INTELLECT — elemental schools, pure caster
    -- Classes: Sorcerer → Wizard → Archmage/Lich · Lich → Greater Lich → Power Lich
    -- -------------------------------------------------------------------------
    Intellect = {
        -- Generalist: all 4 elemental schools + Int
        { name = "Brilliant",    stats = { Fire=1, Air=1, Water=1, Earth=1, Intellect=5 }, tag = "gen"   },
        { name = "Channeling",   stats = { SP=15, Meditation=2 },                          tag = "spec"  },
        -- School specialists
        { name = "Infernal",     stats = { Fire=2, Intellect=6 },                          tag = "spec"  },
        { name = "Tempest",      stats = { Air=2, Intellect=5, Speed=3 },                  tag = "spec"  },
        { name = "Glacial",      stats = { Water=2, Intellect=5 },                         tag = "spec"  },
        { name = "Tectonic",     stats = { Earth=2, Intellect=5, Endurance=3 },            tag = "spec"  },
        -- Moral schools
        { name = "Luminous",     stats = { Light=2, Intellect=5, SP=10 },                  tag = "light" },
        { name = "Necrotic",     stats = { Dark=2, Intellect=5, SP=10 },                   tag = "dark"  },
    },

    -- -------------------------------------------------------------------------
    -- PERSONALITY — divine schools, pure healer/support caster
    -- Classes: Cleric/Priest line · Dragon line
    -- -------------------------------------------------------------------------
    Personality = {
        -- Generalist: all 3 divine schools + Personality
        { name = "Pious",        stats = { Spirit=1, Mind=1, Body=1, Personality=5 },  tag = "gen"   },
        { name = "Serene",       stats = { Personality=5, SP=12, Meditation=2 },       tag = "spec"  },
        -- School specialists
        { name = "Soul's",       stats = { Spirit=2, Personality=6 },                  tag = "spec"  },
        { name = "Mindful",      stats = { Mind=2, Personality=5, Luck=3 },            tag = "spec"  },
        { name = "Merciful",     stats = { Body=2, Personality=5, HP=8 },              tag = "spec"  },
        -- Moral schools
        { name = "Divine",       stats = { Light=2, Personality=5, HP=8 },             tag = "light" },
        { name = "Shadowed",     stats = { Dark=2, Personality=5, SP=10 },             tag = "dark"  },
    },

    -- -------------------------------------------------------------------------
    -- DRUID — all 7 schools (Fire/Air/Water/Earth + Spirit/Mind/Body)
    -- Classes: Druid → Great Druid → Arch Druid / Warlock
    -- -------------------------------------------------------------------------
    Druid = {
        -- Generalist: tiny bonus to all 7 schools
        { name = "Ancient",      stats = { Fire=1,Air=1,Water=1,Earth=1,Spirit=1,Mind=1,Body=1 }, tag = "gen"  },
        -- Lean toward elemental or divine
        { name = "Primal",       stats = { Fire=2, Air=2, Water=2, Earth=2, Intellect=4 },        tag = "spec" },
        { name = "Verdant",      stats = { Spirit=2, Mind=2, Body=2, Personality=4 },             tag = "spec" },
        -- Nature-flavor elemental combos
        { name = "Wildfire",     stats = { Fire=2, Body=2 },                                      tag = "spec" },
        { name = "Sylvan",       stats = { Earth=2, Spirit=2 },                                   tag = "spec" },
        { name = "Timeless",     stats = { Intellect=5, Personality=5, Alchemy=1 },               tag = "spec" },
    },

    -- -------------------------------------------------------------------------
    -- RANGER — minor access to both school groups + physical
    -- Classes: Ranger → Hunter → Ranger Lord / Bounty Hunter
    -- -------------------------------------------------------------------------
    Ranger = {
        -- Generalist: one elemental + one divine + accuracy
        { name = "Wilderness",   stats = { Fire=1, Spirit=1, Accuracy=4 },            tag = "gen"  },
        { name = "Keen",         stats = { Accuracy=6, Perception=1 },                tag = "spec" }, -- Perception [CAP], stays minor
        { name = "Outrider's",   stats = { Might=5, Speed=4 },                        tag = "spec" },
        { name = "Vigilant",     stats = { Spirit=2, Mind=2, Accuracy=3 },            tag = "spec" },
        { name = "Scout's",      stats = { Fire=2, Earth=2, Accuracy=3 },             tag = "spec" },
    },

} -- end M.Prefixes


-- =============================================================================
-- SUFFIX POOLS — Class / Promotion Oriented
--
-- Chips marked UNIQUE below are skills that ONLY this class or line can
-- Grandmaster. These are the anchor stats that make the suffix meaningful.
-- =============================================================================

M.Suffixes = {

    -- -------------------------------------------------------------------------
    -- KNIGHT LINE (Tank bucket)
    -- UNIQUE: Plate GM, Shield GM, Sword GM, Spear GM
    -- -------------------------------------------------------------------------
    KnightLine = {
        { name = "the Knight",       stats = { Sword=2, Shield=2, Endurance=1 },              tier=0, alignment="any"   },
        { name = "the Cavalier",     stats = { Plate=2, Spear=2, Chain=1, Endurance=4 },       tier=1, alignment="any"   },
        { name = "the Champion",     stats = { Plate=3, Shield=3, Might=6, HP=12 },            tier=2, alignment="light" },
        { name = "the Black Knight", stats = { Plate=3, Sword=3, Might=6, Endurance=5 },       tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- BARBARIAN LINE (Warrior bucket)
    -- UNIQUE: Regeneration GM (no other class reaches this)
    -- -------------------------------------------------------------------------
    BarbarianLine = {
        { name = "the Barbarian",    stats = { Axe=2, Regeneration=3, HP=8 },                  tier=0, alignment="any" },
        { name = "the Berserker",    stats = { Axe=3, Regeneration=4, Endurance=5 },           tier=1, alignment="any" },
        { name = "the Warmonger",    stats = { Axe=4, Regeneration=7, Endurance=7 },           tier=2, alignment="any" },
    },

    -- -------------------------------------------------------------------------
    -- ARCHER LINE (Hybrid Intellect bucket)
    -- UNIQUE: Bow GM, Perception GM
    -- NOTE: Perception [CAP] — stays at +1 regardless of tier
    -- -------------------------------------------------------------------------
    ArcherLine = {
        { name = "the Archer",        stats = { Bow=2, Perception=1, Accuracy=2 },             tier=0, alignment="any"   },
        { name = "the Warrior Mage",  stats = { Bow=3, Perception=1, Intellect=5 },            tier=1, alignment="any"   },
        { name = "the Master Archer", stats = { Bow=4, Perception=1, Accuracy=3, Light=1 },    tier=2, alignment="light" },
        { name = "the Sniper",        stats = { Bow=4, Perception=1, Accuracy=4, Dark=1 },     tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- DEERSLAYER LINE (Hybrid Intellect bucket)
    -- UNIQUE: Merchant GM, DisarmTrap GM
    -- NOTE: Merchant [CAP] — stays at +1 regardless of tier
    -- -------------------------------------------------------------------------
    DeerslayerLine = {
        { name = "the Deerslayer",   stats = { Bow=2, DisarmTrap=2, Merchant=1 },              tier=0, alignment="any" },
        { name = "the Pioneer",      stats = { Bow=3, Merchant=1, Fire=1, Earth=1 },           tier=1, alignment="any" },
        { name = "the Pathfinder",   stats = { Bow=4, Merchant=1, Fire=2, Air=1, Water=1, Earth=1 }, tier=2, alignment="any" },
    },

    -- -------------------------------------------------------------------------
    -- THIEF LINE (Hybrid Intellect bucket)
    -- UNIQUE: Dagger GM, DisarmTrap GM
    -- -------------------------------------------------------------------------
    ThiefLine = {
        { name = "the Thief",        stats = { DisarmTrap=2, Perception=2, Dagger=1 },         tier=0, alignment="any"   },
        { name = "the Rogue",        stats = { Dagger=3, DisarmTrap=3, Speed=4 },              tier=1, alignment="any"   },
        { name = "the Spy",          stats = { Dagger=4, DisarmTrap=4, Luck=7 },               tier=2, alignment="light" },
        { name = "the Assassin",     stats = { Dagger=4, Luck=4, Speed=7 },                    tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- PALADIN LINE (Hybrid Personality bucket)
    -- UNIQUE: Mace GM, Shield GM, Repair GM
    -- -------------------------------------------------------------------------
    PaladinLine = {
        { name = "the Paladin",      stats = { Mace=2, Shield=2, Personality=4, Spirit=1 },    tier=0, alignment="any"   },
        { name = "the Crusader",     stats = { Mace=3, Shield=3, Repair=2, Personality=5 },    tier=1, alignment="any"   },
        { name = "the Hero",         stats = { Mace=4, Repair=3, Light=2, Personality=6 },     tier=2, alignment="light" },
        { name = "the Villain",      stats = { Mace=4, Repair=3, Dark=2, Personality=6 },      tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- MONK LINE (Hybrid Personality bucket)
    -- UNIQUE: Unarmed GM, Dodge GM, Bodybuilding GM
    --   No other class can grandmaster any of these three skills.
    -- -------------------------------------------------------------------------
    MonkLine = {
        { name = "the Monk",         stats = { Unarmed=2, Dodge=3 },                                           tier=0, alignment="any"   },
        { name = "the Initiate",     stats = { Unarmed=3, Dodge=3, Spirit=1, Mind=1, Body=1 },                 tier=1, alignment="any"   },
        { name = "the Master",       stats = { Unarmed=4, Dodge=4, Bodybuilding=3, HP=12 },                    tier=2, alignment="light" },
        { name = "the Ninja",        stats = { Unarmed=4, Dodge=4, Speed=8, Dark=1 },                          tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- VAMPIRE LINE (Hybrid Personality bucket)
    -- Uses Body/Mind/Spirit (Personality schools)
    -- -------------------------------------------------------------------------
    VampireLine = {
        { name = "the Vampire",       stats = { Dagger=2, Body=1, Mind=1, Spirit=1, Luck=1 },  tier=0, alignment="any" },
        { name = "the Elder Vampire", stats = { Dagger=3, Body=2, Mind=1, Spirit=1, Luck=5 },  tier=1, alignment="any" },
        { name = "the Nosferatu",     stats = { Dagger=4, Body=3, Mind=2, Spirit=2, Luck=7 },  tier=2, alignment="any" },
        -- "HP drain" effect flag: add as a special_effect entry when implementing
    },

    -- -------------------------------------------------------------------------
    -- MINOTAUR LINE (Hybrid Personality bucket)
    -- Uses Body/Spirit/Mind; UNIQUE: Perception GM at lord tier
    -- NOTE: Perception [CAP] — stays at +1
    -- -------------------------------------------------------------------------
    MinotaurLine = {
        { name = "the Minotaur",          stats = { Axe=2, Endurance=5, Body=1 },                          tier=0, alignment="any" },
        { name = "the Minotaur Headsman", stats = { Axe=3, Endurance=6, Body=2, Spirit=1 },               tier=1, alignment="any" },
        { name = "the Minotaur Lord",     stats = { Axe=4, Endurance=8, Perception=1, Body=2, Spirit=1 }, tier=2, alignment="any" },
    },

    -- -------------------------------------------------------------------------
    -- SORCERER LINE / MM7 PATH (Intellect bucket)
    -- UNIQUE: all 4 elemental schools to GM; Meditation GM
    -- 2nd promo options from Wizard: MasterWizard (neutral), ArchMage (light), Lich (dark)
    -- MasterWizard is also reachable from the MM8 Necromancer (Greater Lich) path.
    -- NOTE: "the Lich" here is the MM7 Sorcerer dark path (tier 2).
    --       The MM8 NecromancerLine also has "the Lich" at tier 0.
    --       Both share a display name but differ in tier and prefix pairing.
    -- -------------------------------------------------------------------------
    SorcererLine = {
        { name = "the Sorcerer",      stats = { Intellect=5, Fire=1, Air=1, Water=1, Earth=1 },                                tier=0, alignment="any"   },
        { name = "the Wizard",        stats = { Intellect=8, Fire=2, Air=2, Meditation=2, SP=12 },                             tier=1, alignment="any"   },
        { name = "the Master Wizard", stats = { Intellect=12, Fire=2, Air=2, Water=2, Earth=2, Meditation=3, SP=18 },          tier=2, alignment="any"   }, -- neutral 2nd promo, no moral school
        { name = "the Archmage",      stats = { Intellect=12, Fire=2, Air=2, Water=2, Earth=2, Light=3, Meditation=3, SP=20 }, tier=2, alignment="light" },
        { name = "the Lich",          stats = { Intellect=12, Fire=2, Air=2, Water=2, Earth=2, Dark=3,  Meditation=3, SP=20 }, tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- NECROMANCER LINE / MM8 PATH (Intellect bucket)
    -- Renamed in CustomRaceClassNames.txt:
    --   DarkAdept (112)          → Lich
    --   Necromancer (113)        → Greater Lich
    --   MasterNecromancer (118)  → Power Lich
    -- -------------------------------------------------------------------------
    NecromancerLine = {
        { name = "the Lich",         stats = { Intellect=5, Dark=2, Earth=1, Water=1 },                                                          tier=0, alignment="any" },
        { name = "the Greater Lich", stats = { Intellect=8, Dark=3, Earth=2, Water=2, Meditation=2 },                                            tier=1, alignment="any" },
        { name = "the Power Lich",   stats = { Intellect=12, Dark=4, Fire=2, Air=2, Water=2, Earth=2, Meditation=3, SP=20 },                     tier=2, alignment="any" },
    },

    -- -------------------------------------------------------------------------
    -- CLERIC / PRIEST LINE (Personality bucket)
    -- MM7:  Cleric (base) → Priest (1st) → High Priest / Priest of Light / Priest of Dark
    -- MM8:  Priest (base, same as MM7 1st tier) → Priest of Light / Priest of Dark
    -- High Priest is treated as a neutral 2nd promo (no moral alignment committed)
    -- UNIQUE: all 3 divine schools to GM; Meditation GM
    -- -------------------------------------------------------------------------
    ClericLine = {
        { name = "the Cleric",          stats = { Mace=2, Personality=4, Spirit=1, Mind=1, Body=1 },                 tier=0, alignment="any"   },
        { name = "the Priest",          stats = { Mace=2, Personality=5, Spirit=1, Mind=1, Body=1, Meditation=1 },   tier=0, alignment="any"   }, -- MM8 base / MM7 1st promo
        { name = "the High Priest",     stats = { Personality=8, Spirit=2, Mind=2, Body=2, Meditation=3, SP=15 },    tier=2, alignment="any"   }, -- neutral 2nd promo
        { name = "the Priest of Light", stats = { Personality=8, Spirit=2, Mind=2, Body=2, Light=3, Meditation=3 },  tier=2, alignment="light" },
        { name = "the Priest of Dark",  stats = { Personality=8, Spirit=2, Mind=2, Body=2, Dark=3,  Meditation=3 },  tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- DRAGON LINE (Personality bucket)
    -- UNIQUE: DragonMagic skill (the Dragon class's exclusive spell power)
    --   Fire breath: ranged attack (powered by DragonMagic + SP)
    --   Claw attack: melee (scales with Might — include for melee builds)
    --   4 spell attack types: all require SP (mana pool) to sustain
    -- NOTE: Personality prefixes supply the Spirit/Mind/Body and Personality stat;
    --       this suffix focuses on what's unique: DragonMagic, SP, Might
    -- -------------------------------------------------------------------------
    DragonLine = {
        { name = "the Dragon",        stats = { DragonMagic=1, Might=4, SP=10, Body=1, Spirit=1 },             tier=0, alignment="any" },
        { name = "the Flight Leader", stats = { DragonMagic=2, Might=5, SP=15, Body=2, Spirit=1 },             tier=1, alignment="any" },
        { name = "the Great Wyrm",    stats = { DragonMagic=3, Might=6, SP=20, Personality=8, Body=2, Spirit=2 }, tier=2, alignment="any" },
        -- DragonMagic maps to the Dragon class's unique spell skill (tune scale per implementation)
    },

    -- -------------------------------------------------------------------------
    -- DRUID LINE (Druid bucket)
    -- UNIQUE: Alchemy GM, Meditation GM; only class to access all 7 spell schools
    -- -------------------------------------------------------------------------
    DruidLine = {
        { name = "the Druid",       stats = { Alchemy=1, Fire=1, Spirit=1, Mind=1 },                              tier=0, alignment="any"   },
        { name = "the Great Druid", stats = { Alchemy=2, Meditation=2, Fire=2, Spirit=2, Body=1 },                tier=1, alignment="any"   },
        { name = "the Arch Druid",  stats = { Alchemy=3, Meditation=3, Fire=2, Air=2, Water=2, Earth=2 },         tier=2, alignment="light" },
        { name = "the Warlock",     stats = { Alchemy=3, Meditation=3, Spirit=2, Mind=2, Body=2, Dark=2 },        tier=2, alignment="dark"  },
    },

    -- -------------------------------------------------------------------------
    -- RANGER LINE (Ranger bucket)
    -- Both school groups at minor levels; UNIQUE: Identify Monster GM, Axe GM
    -- NOTE: IdentifyMonster [CAP] — stays at +1 regardless of tier
    -- -------------------------------------------------------------------------
    RangerLine = {
        { name = "the Ranger",        stats = { Axe=2, IdentifyMonster=1, Fire=1, Spirit=1 },        tier=0, alignment="any"   },
        { name = "the Hunter",        stats = { Axe=3, IdentifyMonster=1, Fire=2, Spirit=2 },        tier=1, alignment="any"   },
        { name = "the Ranger Lord",   stats = { Axe=4, IdentifyMonster=1, Light=2, Accuracy=5 },     tier=2, alignment="light" },
        { name = "the Bounty Hunter", stats = { Axe=4, IdentifyMonster=1, Dark=2, Speed=5 },         tier=2, alignment="dark"  },
    },

} -- end M.Suffixes


return M
