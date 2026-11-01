-- The jar as glyphs (#97): the classic jar by day and by night in ascii (the
-- frame set at once) and ascii-each (each thing set by what it is), as a
-- 1080p screen and as the Pi frame shows it, at the cell sizes [ and ] step
-- through, and as a plate of the creatures under the lamp. Saved as
-- <style>_<when>_<w>x<h>_<cell>.png and <style>_plate_<cell>.png, with the
-- same moment with no style beside each as ascii_<when>_<w>x<h>_none.png.
--
--   lovec . --script scripts/ascii.lua
--   ASCII_STYLES=ascii-each ASCII_CELLS=8x12 lovec . --script scripts/ascii.lua

local Ascii = require('jar.ascii')
local Screen = require('core.screen')
local C = require('jar.config')

local function list(env, default)
    local out = {}
    for item in (os.getenv(env) or default):gmatch('[^,]+') do out[#out + 1] = item end
    return out
end

local STYLES = list('ASCII_STYLES', 'ascii,ascii-each')
local CELLS = {}
for _, c in ipairs(list('ASCII_CELLS', '6x9,8x12,12x18')) do
    local w, h = c:match('(%d+)x(%d+)')
    CELLS[#CELLS + 1] = { tonumber(w), tonumber(h) }
end
-- a 1080p screen, as a window shows it; and the Pi frame, as the frame does
local SCREENS = {
    { 1920, 1080, function(w, h) return { fit = Screen.fit(w, h, C.W, C.H) } end },
    { 1280, 720, function() return { frame = true } end },
}

return {run = function(api)
    for _, at in ipairs({ { 'day', 'midday' }, { 'night', 23 } }) do
        api.open(20261018, at[2], nil, nil, api.World.CLASSIC)
        api.step(20)
        for _, size in ipairs(SCREENS) do
            local w, h, opts = size[1], size[2], size[3]
            api.style('none')
            api.save(api.render(w, h, opts(w, h)), ('ascii_%s_%dx%d_none.png'):format(at[1], w, h))
            for _, style in ipairs(STYLES) do
                api.style(style)
                for _, cell in ipairs(CELLS) do
                    Ascii.size(cell[1], cell[2])
                    api.save(api.render(w, h, opts(w, h)),
                        ('%s_%s_%dx%d_%dx%d.png'):format(style, at[1], w, h, cell[1], cell[2]))
                    api.yield()
                end
            end
        end
        if at[1] == 'day' then
            for _, style in ipairs(STYLES) do
                api.style(style)
                for _, cell in ipairs(CELLS) do
                    Ascii.size(cell[1], cell[2])
                    api.save(api.render(1600, 900, { view = { 700, 650, 1300, 650 + 600 * 9 / 16 } }),
                        ('%s_plate_%dx%d.png'):format(style, cell[1], cell[2]))
                end
            end
        end
    end
    Ascii.size(Ascii.CELL[1], Ascii.CELL[2])
end}
