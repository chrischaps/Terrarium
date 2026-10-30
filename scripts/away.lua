-- Time away (#31): a jar left in the evening and opened again three days
-- later, the next morning but two. The glass has fogged over; through it the
-- days go by as light, each creature a long exposure of where it went, and a
-- tally of the days is drawn in the mist. Then the bodies come back and the
-- glass clears. Saves away_00.png and on, a frame every so often, to the save
-- directory; `every` is how many frames apart (1 for a film of it).
--
--   lovec . --script scripts/away.lua

local every = tonumber(os.getenv('AWAY_EVERY') or '') or 12
local W, H = 1280, 800
local FPS = 30
local STEPS = 900 -- coarse steps of catch-up a frame: about what a desktop lives in one

return {run = function(api)
    api.open(20261018, 19.5, nil, nil, api.World.CLASSIC)
    api.step(3)
    -- (back three days and twelve hours later, half past seven in the morning)
    local moment = assert(api.away(3.5 * 24 * 3600), 'away: that was short enough to live at once')
    local frame, saved = 0, 0
    local function shoot()
        api.save(api.render(W, H), string.format('away_%03d.png', saved))
        saved = saved + 1
    end
    shoot()
    while api.pass(1 / FPS, STEPS) do
        frame = frame + 1
        if frame % every == 0 then shoot() end
    end
    -- (and the jar a few seconds on, its glass clear)
    api.step(3)
    shoot()
    print(string.format('[away] %d frames, %d saved; %d marks', frame, saved, #moment.marks))
end}
