-- A pinch of food (#25): one dropped beside the blob on the soil under the
-- lamp, falling through its light, settling in the moss, and the ones near
-- coming over to nibble it. Saves pinch_1.png (falling), pinch_2.png (down)
-- and pinch_3.png (nibbling) to the save directory.
--
--   lovec . --script scripts/pinch.lua

return {run = function(api)
    local w = api.open(20261018, 'midday')
    api.step(5)
    local x = 960
    for i, c in ipairs(w.creatures) do
        if c.name == 'Dew' then x = c:anchor() + 70 end
    end
    w:pinch(x)
    local views = {
        {x - 330, 150, x + 270, 150 + 600 * 9 / 16}, -- coming down through the lamp
        {x - 200, 400, x + 160, 400 + 360 * 9 / 16}, -- down in the moss
        {x - 200, 400, x + 160, 400 + 360 * 9 / 16}, -- nibbled
    }
    for k, t in ipairs({4, 6, 8}) do
        api.step(t)
        api.save(api.render(1600, 900, {view = views[k]}), 'pinch_' .. k .. '.png')
    end
end}
