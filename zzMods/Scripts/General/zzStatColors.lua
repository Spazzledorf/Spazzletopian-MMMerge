-- zzStatColors.lua
-- Colors stat text on the character Stats tab via GlobalTxt \f injection.
-- Toggle: Game.StatColorsEnabled via MenuExtraSettings.

local STAT_COLORS = {
    {144, 0xF800, "Might"},       -- Red
    {116, 0xFD20, "Intellect"},   -- Orange
    {163, 0x001F, "Personality"}, -- Blue
    {75,  0x07E0, "Endurance"},   -- Green
    {211, 0xFFE0, "Accuracy"},    -- Yellow
    {1,   0x8010, "Speed"},       -- Dark Purple
    {136, 0xFFFF, "Luck"},        -- White
    {108, 0x07E0, "HP"},          -- Green
    {212, 0x001F, "SP"},          -- Blue
}

local originals = {}
local onStatsTab = false

function events.GameInitialized2()
    function events.L2InterfaceUpd()
        if not Game.StatColorsEnabled then
            if #originals > 0 then
                for idx, txt in pairs(originals) do
                    Game.GlobalTxt[idx] = txt
                end
                originals = {}
                onStatsTab = false
            end
            return
        end

        if Game.CurrentScreen == const.Screens.Inventory and Game.CurrentCharScreen == const.CharScreens.Stats then
            if #originals == 0 then
                for _, v in ipairs(STAT_COLORS) do
                    originals[v[1]] = Game.GlobalTxt[v[1]]
                end
            end
            onStatsTab = true

            for _, v in ipairs(STAT_COLORS) do
                Game.GlobalTxt[v[1]] = string.format("\f%.5d%s", v[2], v[3])
            end
        elseif onStatsTab then
            onStatsTab = false
            for idx, txt in pairs(originals) do
                Game.GlobalTxt[idx] = txt
            end
            originals = {}
        end
    end
end
