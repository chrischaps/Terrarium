-- The jar as glyphs (#97): the classic jar by day and by night in the ascii
-- style, as a 1080p screen and as the Pi frame's 1280 x 720 show it (fitted
-- and cropped as they are), at the cell sizes [ and ] step through, and as a
-- plate of the creatures under the lamp. Saved as ascii_<when>_<w>x<h>_<cell>.png
-- and ascii_plate_<cell>.png; the same moment with no style beside each, as
-- ascii_<when>_<w>x<h>_none.png, to hold them up against.
--
--   lovec . --script scripts/ascii.lua

local Ascii = require('jar.ascii')

local CELLS = { { 6, 9 }, { 8, 12 }, { 12, 18 } }
local SCREENS = { { 1920, 1080 }, { 1280, 720 } }

return {run = function(api)
    for _, at in ipairs({ { 'day', 'midday' }, { 'night', 23 } }) do
        api.open(20261018, at[2], nil, nil, api.World.CLASSIC)
        api.step(20)
        for _, size in ipairs(SCREENS) do
            local w, h = size[1], size[2]
            api.style('none')
            api.save(api.render(w, h, { screen = true }), ('ascii_%s_%dx%d_none.png'):format(at[1], w, h))
            api.style('ascii')
            for _, cell in ipairs(CELLS) do
                Ascii.size(cell[1], cell[2])
                api.save(api.render(w, h, { screen = true }),
                    ('ascii_%s_%dx%d_%dx%d.png'):format(at[1], w, h, cell[1], cell[2]))
                api.yield()
            end
        end
        if at[1] == 'day' then
            for _, cell in ipairs(CELLS) do
                Ascii.size(cell[1], cell[2])
                api.save(api.render(1600, 900, { view = { 700, 650, 1300, 650 + 600 * 9 / 16 } }),
                    ('ascii_plate_%dx%d.png'):format(cell[1], cell[2]))
            end
        end
    end
    Ascii.size(Ascii.CELL[1], Ascii.CELL[2])
end}
