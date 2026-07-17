-- zzPartyBuffs.lua
-- Makes Regeneration, Fire Aura, and Vampiric Weapon affect the whole
-- party at Expert+ mastery.
-- Regeneration: SpellBuff copied from caster to all party members via Tick.
-- Fire Aura / Vampiric Weapon: damage added at attack time via
-- events.CalcDamageToMonster. Damage is the caster's skill level at
-- cast time (e.g. caster with Fire 20 gives +20 fire damage per hit,
-- regardless of who is attacking). Mastery only gates whether the
-- spell can be cast (Expert+) and affects duration.
-- Toggle: Game.AutoHealEnabled via MenuExtraSettings.
print("zzPartyBuffs: loaded (Regen + FireAura + Vampiric party-wide at Expert+)")

local u2 = mem.u2
local bit = bit
local MT = Merge.Tables

local PARTY_BUFF_SPELLS = {4, 71, 91}

local SPELL_SKILL = {
    [4]  = const.Skills.Fire,
    [71] = const.Skills.Body,
    [91] = const.Skills.Dark,
}

-- Per-player buff tracking.
-- Regen: handled via SpellBuff copy (pending_idx/pending_caster in Tick).
-- Fire Aura / Vampiric Weapon: handled via global party buffs (we
-- don't track per-player; the damage is added at attack time for any
-- active attacker based on the original caster's stored skill level).

-- Global active Fire Aura / Vampiric Weapon buffs. Each entry:
--   { damage = skill_level, mastery = 2|3|4, expire = Game.Time }
-- Only one Fire Aura / one Vampiric active at a time (cast overwrites).
Game._pb_fireaura_active = Game._pb_fireaura_active or nil
Game._pb_vampiric_active = Game._pb_vampiric_active or nil

-- Pending Tick copy for SpellBuff-based spells (Regeneration only).
local pending_idx
local pending_caster

local function spell_var(extra, varNum, mastery, default)
    local names = {"Normal", "Expert", "Master", "GM"}
    local key = "Var" .. varNum .. names[mastery]
    local val = extra[key]
    if val == nil then
        local arr = extra["Var" .. varNum]
        if type(arr) == "table" then
            val = arr[mastery]
        end
    end
    return val or default
end

local function calc_duration(t, caster, extra)
    local _, mastery = SplitSkill(caster:GetSkill(SPELL_SKILL[t]))
    if mastery < 2 then return nil end
    local var1 = spell_var(extra, 1, mastery, 3600)
    local var2 = spell_var(extra, 2, mastery, 0)
    local level = (caster.LevelBase or 0) + (caster.LevelBonus or 0)
    if level < 1 then level = 1 end
    local dur = var1 * level + var2
    if dur < 3600 then dur = 3600 end
    return dur
end

-- Tooltip descriptions for SpellsTxt ----------------------------------------

local function update_tooltips()
    local pnote = "\n\nParty-wide effect at Expert+."
    for _, sid in ipairs(PARTY_BUFF_SPELLS) do
        local txt = Game.SpellsTxt[sid]
        if txt then
            local val = txt.Expert
            if val and val ~= "" and not val:find("Party%-wide") then
                txt.Expert = val .. pnote
            end
            val = txt.Normal
            if val and val ~= "" and not val:find("Party%-wide") then
                txt.Normal = val .. "\n\nSingle target only at Normal."
            end
        end
    end
end

-- SpellTargetType: auto-target caster for party buffs -----------------------

function events.SpellTargetType(t)
    if not Game.AutoHealEnabled then return end
    if not table.find(PARTY_BUFF_SPELLS, t.Spell) then return end
    if bit.band(t.Flags, 0xE021) > 0 then return end
    u2[0x51d824] = t.CasterSlot
    u2[0x51d82c] = bit.lshift(t.CasterSlot, 3) + 4
    t.Flags = 0x1000
end

-- PlayerSpellProc: set up Regen copy / FireAura / Vampiric tracking -------

function events.PlayerSpellProc(t)
    if not Game.AutoHealEnabled then return end
    if not table.find(PARTY_BUFF_SPELLS, t.Spell) then return end

    pending_idx = nil
    pending_caster = nil

    if bit.band(t.Flags, 0xE021) > 0 then return end

    local caster = Party.PlayersArray[t.Caster]
    if not caster then return end

    local skillId = SPELL_SKILL[t.Spell]
    if not skillId then return end

    local skillLevel, mastery = SplitSkill(caster:GetSkill(skillId))
    if mastery < 2 then return end

    if t.Spell == 71 then
        -- Regeneration: SpellBuff copy
        pending_idx = const.PlayerBuff.Regeneration
        pending_caster = t.Caster
        return
    end

    -- Fire Aura / Vampiric Weapon: track globally, add damage at attack time.
    -- Damage scales with the CASTER's skill level (per the user's design:
    -- a caster with 20 Fire gives +20 fire damage per hit, regardless of
    -- who is attacking). Mastery only gates whether the spell can be cast
    -- at all (Expert+) and affects duration, not damage.
    local extra = MT and MT.SpellsExtra and MT.SpellsExtra[t.Spell]
    if not extra then return end
    local dur = calc_duration(t.Spell, caster, extra)
    if not dur then return end
    local expire = Game.Time + dur
    if t.Spell == 4 then
        Game._pb_fireaura_active = {
            damage = skillLevel,
            mastery = mastery,
            expire = expire,
        }
    elseif t.Spell == 91 then
        Game._pb_vampiric_active = {
            damage = skillLevel,
            mastery = mastery,
            expire = expire,
        }
    end
end

-- Tick: Regen copy + cleanup expired Fire Aura / Vampiric entries --------

function events.Tick()
    -- Copy Regeneration from caster to all
    if pending_idx and pending_caster ~= nil then
        local caster = Party.PlayersArray[pending_caster]
        if caster then
            local src = caster.SpellBuffs[pending_idx]
            for i = 0, Party.High do
                if i ~= pending_caster then
                    local ok = Party.PlayersArray[i]
                    if ok then
                        local dst = Party[i].SpellBuffs[pending_idx]
                        dst.ExpireTime = src.ExpireTime
                        dst.Power = src.Power
                        dst.Skill = src.Skill
                        dst.OverlayId = src.OverlayId
                        dst.Caster = src.Caster
                        dst.Bits = src.Bits
                        Party[i]:ShowFaceAnimation(const.FaceAnimation.TempleHeal)
                    end
                end
            end
        end
        pending_idx = nil
        pending_caster = nil
    end

    -- Clean up expired Fire Aura / Vampiric entries
    local now = Game.Time
    if Game._pb_fireaura_active and Game._pb_fireaura_active.expire <= now then
        Game._pb_fireaura_active = nil
    end
    if Game._pb_vampiric_active and Game._pb_vampiric_active.expire <= now then
        Game._pb_vampiric_active = nil
    end
end

-- CalcDamageToMonster: add Fire Aura / Vampiric damage at attack time ---

function events.CalcDamageToMonster(t)
    if not Game.AutoHealEnabled then return end
    if t.Result <= 0 then return end

    -- Identify the active attacker. Prefer t.PlayerIndex (correct for
    -- spell-based hits); fall back to Game.CurrentPlayer for melee where
    -- t.PlayerIndex is unreliable.
    local pi = t.PlayerIndex
    if type(pi) ~= "number" or pi < 0 or pi > Party.High then
        pi = Game.CurrentPlayer
    end
    if type(pi) ~= "number" or pi < 0 or pi > Party.High then return end

    local attacker = Party.PlayersArray[pi]

    -- Fire Aura: add flat damage = caster's Fire skill level (per hit, for all party members)
    local fa = Game._pb_fireaura_active
    if fa and fa.expire > Game.Time then
        t.Result = t.Result + fa.damage
    end

    -- Vampiric Weapon: add flat damage + heal attacker by same amount
    local vp = Game._pb_vampiric_active
    if vp and vp.expire > Game.Time then
        t.Result = t.Result + vp.damage
        if attacker and attacker.HP and attacker.HP > 0 then
            local maxhp = attacker.HPMax or attacker.HP
            attacker.HP = math.min(maxhp, attacker.HP + vp.damage)
        end
    end
end

-- BuildItemInformationBox: show active buffs on equipped weapon tooltips --

function events.BuildItemInformationBox(t)
    local lines = {}

    local fa = Game._pb_fireaura_active
    if fa and fa.expire > Game.Time then
        table.insert(lines, "Fire Aura: +" .. fa.damage .. " fire damage per hit")
    end

    local vp = Game._pb_vampiric_active
    if vp and vp.expire > Game.Time then
        table.insert(lines, "Vampiric Weapon: +" .. vp.damage .. " damage and lifesteal per hit")
    end

    if #lines > 0 then
        local text = t.Description or ""
        if text ~= "" then
            text = text .. "\n"
        end
        t.Description = text .. "\nActive Enchants: " .. table.concat(lines, ", ")
    end
end

-- Init -----------------------------------------------------------------------

update_tooltips()
function events.GameInitialized2()
    update_tooltips()
end
