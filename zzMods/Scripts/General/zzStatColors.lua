-- zzStatColors.lua
-- Colors label text on the character Stats tab by prefixing a \f color code
-- to the GlobalTxt strings the sheet draws. Toggle: Game.StatColorsEnabled
-- (MenuExtraSettings).
--
-- IMPORTANT: this prefixes the color onto each label's ORIGINAL text; it does
-- NOT substitute a hardcoded name. An earlier version substituted names and
-- had two indices mislabeled (GlobalTxt[1] is "Accuracy", not "Speed"; [211]
-- is "Speed", not "Accuracy"), which swapped those two labels on screen while
-- the values/tooltips stayed correct. Prefixing the real text makes that class
-- of bug impossible -- a wrong index can only mis-COLOR, never mis-label.
--
-- All indices verified against the live game via DumpGxt(). Colors are RGB565
-- as a 5-digit decimal after \f. NOTE: 0x07FF (full cyan) rendered dark in
-- testing for a reason I have not pinned down (it is NOT a leading-zero issue
-- -- 0x07E0 green formats to "02016" and renders fine), so Air uses the
-- lighter 0x7FFF, which reads correctly. If any color looks wrong, that's the
-- first thing to suspect: pick a nearby value and test in-game.

-- {GlobalTxt index, RGB565 color}  (trailing name = documentation only)
local STAT_COLORS = {
    -- Base attributes
    {144, 0xF800, "Might"},        -- Red
    {116, 0xFD20, "Intellect"},    -- Orange
    {163, 0x001F, "Personality"},  -- Blue
    {75,  0x07E0, "Endurance"},    -- Green
    {1,   0xFFE0, "Accuracy"},     -- Yellow   (index 1 IS Accuracy)
    {211, 0x8010, "Speed"},        -- Purple   (index 211 IS Speed)
    {136, 0xFFFF, "Luck"},         -- White
    {108, 0x07E0, "Hit Points"},   -- Green
    {212, 0x001F, "Spell Points"}, -- Blue
    -- Resistances (the six shown on the MM8 stats page)
    {87,  0xF800, "Fire"},         -- Red
    {6,   0x7FFF, "Air"},          -- Light cyan (0x7FFF: no leading zero)
    {240, 0x001F, "Water"},        -- Blue
    {70,  0xA365, "Earth"},        -- Brown
    {142, 0x981F, "Mind"},         -- Purple
    {29,  0xFC18, "Body"},         -- Pink
}

local originals = {}

local function restore()
    for idx, txt in pairs(originals) do
        Game.GlobalTxt[idx] = txt
    end
    originals = {}
end

function events.GameInitialized2()
    function events.L2InterfaceUpd()
        if not Game.StatColorsEnabled then
            if next(originals) ~= nil then restore() end
            return
        end

        if Game.CurrentScreen == const.Screens.Inventory
           and Game.CurrentCharScreen == const.CharScreens.Stats then
            -- Snapshot the clean originals once so re-prefixing each tick
            -- always builds "color + clean text" (never double-prefixes).
            if next(originals) == nil then
                for _, v in ipairs(STAT_COLORS) do
                    originals[v[1]] = Game.GlobalTxt[v[1]]
                end
            end
            for _, v in ipairs(STAT_COLORS) do
                local orig = originals[v[1]] or Game.GlobalTxt[v[1]]
                Game.GlobalTxt[v[1]] = string.format("\f%.5d%s", v[2], orig)
            end
        elseif next(originals) ~= nil then
            restore()
        end
    end
end
