-- zzMerchantParty.lua
-- Vendor buy/sell prices use the party's highest Merchant skill,
-- not each individual character's. One merchant negotiates for everyone.
-- Toggle: Game.PartyMerchantEnabled via MenuExtraSettings.

Game.PartyMerchantEnabled = (Game.PartyMerchantEnabled == nil) and true or Game.PartyMerchantEnabled

function events.GetMerchantTotalSkill(t)
    if not Game.PartyMerchantEnabled then return end
    local best = 0
    for i = 0, Party.High do
        local pl = Party[i]
        if pl and pl:IsConscious() then
            local raw = pl.Skills[const.Skills.Merchant]
            if raw and raw > best then
                best = raw
            end
        end
    end
    if best > 0 then
        t.Result = best
    end
end
