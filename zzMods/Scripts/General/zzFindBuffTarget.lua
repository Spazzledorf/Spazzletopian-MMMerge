-- zzFindBuffTarget.lua (diagnostic -- remove after use)
-- Searches for SpellBuff:Set and target-read patterns.
-- Results show Fire Aura (0x4272E4-0x427534) and Vampiric Weapon
-- (0x42C100-0x42C20F) DON'T use movzx r32, [r+4] -- they handle
-- target via different code paths (likely no per-player loop exists).
-- Solution: use events.ItemAdditionalDamage instead of native asmpatch.

print("zzFindBuffTarget: concluded -- ItemAdditionalDamage approach adopted")
print("  See zzPartyBuffs.lua for implementation.")
