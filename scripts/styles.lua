-- The jar in every style (#94): one moment of the classic jar, as the whole
-- frame and as a plate of the creatures' plane under the lamp, by day and by
-- night, saved as style_<name>_<day|night>.png and style_<name>_plate.png.
-- Every frame comes through the same seam as the window's, so these are what
-- Tab shows.
--
--   lovec . --script scripts/styles.lua

return {run = function(api)
    local names = {}
    for _, s in ipairs(require('jar.styles').list) do names[#names + 1] = s.name end
    for _, at in ipairs({ { 'day', 'midday' }, { 'night', 23 } }) do
        api.open(20261018, at[2], nil, nil, api.World.CLASSIC)
        api.step(20)
        for _, name in ipairs(names) do
            api.style(name)
            api.save(api.render(1600, 1000), 'style_' .. name .. '_' .. at[1] .. '.png')
            if at[1] == 'day' then
                api.save(api.render(1600, 900, { view = { 700, 650, 1300, 650 + 600 * 9 / 16 } }),
                    'style_' .. name .. '_plate.png')
            end
        end
    end
end}
