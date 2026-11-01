-- #98's probes: what a style can do once it's told what it's looking at. One
-- moment of the classic jar in each probe (and none, to compare), by day and
-- by night, as the whole frame and as a plate under the lamp, saved as
-- probe_<style>_<day|night|plate>.png. Copy them to renders/.
--
--   lovec . --probes --script scripts/probes.lua

return {run = function(api)
    local names = { 'none', 'probe-matte', 'probe-ink', 'probe-cut' }
    for _, at in ipairs({ { 'day', 'midday' }, { 'night', 23 } }) do
        api.open(20261018, at[2], nil, nil, api.World.CLASSIC)
        api.step(20)
        for _, name in ipairs(names) do
            api.style(name)
            api.save(api.render(1600, 1000), 'probe_' .. name .. '_' .. at[1] .. '.png')
            if at[1] == 'day' then
                api.save(api.render(1600, 900, { view = { 700, 650, 1300, 650 + 600 * 9 / 16 } }),
                    'probe_' .. name .. '_plate.png')
            end
            api.yield()
        end
    end
end}
