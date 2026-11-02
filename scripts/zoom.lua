-- A closer look (#120): a tap on a creature, the view coming in on it and
-- staying with it as it walks, a tap on another, and a tap on nothing. Each
-- style in ZOOM_STYLES (none, pencil-each and ascii-each to begin with) in a
-- window's 1600 x 1000 and on the frame's 1280 x 720, as
-- zoom_<style>_<window|frame>_<nnn>.png, every ZOOM_EVERY (6) frames of 30 fps.
-- ZOOM_EVERY=1 for a film of it; ZOOM_SHAPES=frame for only the frame's.
--
-- It ends by printing the jar's state hash, so ZOOM=0 runs the same jar with no
-- zoom and no frames, and the two must agree: looking closer changes nothing.
--
--   lovec . --script scripts/zoom.lua
--   ZOOM=0 lovec . --script scripts/zoom.lua

local Hash = require('core.statehash')

local FPS = 30
-- what happens when: who to look at, from that many seconds in, or `nil` for a
-- tap on nothing. The two worms are a pair, side by side, so the tap from one to
-- the other is one you could make in the close view.
local BEATS = {
    { at = 1, who = 'worm' },
    { at = 4, who = 'mate' },
    { at = 7, who = nil },
    { at = 9, who = 'spider' },
    { at = 14, who = nil },
}
local LENGTH = 16

local function words(s)
    local out = {}
    for w in s:gmatch('[^,%s]+') do out[#out + 1] = w end
    return out
end

return { run = function(api)
    local look = os.getenv('ZOOM') ~= '0'
    local every = tonumber(os.getenv('ZOOM_EVERY') or '') or 6
    local styles = words(os.getenv('ZOOM_STYLES') or 'none,pencil-each,ascii-each')
    local shapes = {}
    for _, shape in ipairs({ { 'window', 1600, 1000 }, { 'frame', 1280, 720, { frame = true } } }) do
        if (os.getenv('ZOOM_SHAPES') or 'window,frame'):find(shape[1], 1, true) then shapes[#shapes + 1] = shape end
    end

    for _, name in ipairs(look and styles or { 'none' }) do
        if look then api.style(name) end
        for _, shape in ipairs(look and shapes or { shapes[1] }) do
            -- (the classic cast, opened at the same moment, so each goes the same)
            local w = api.open(20261018, 'midday', nil, nil, api.World.CLASSIC)
            api.step(20)
            local who = { worm = w:first('worm'), spider = w:first('spider') }
            who.mate = who.worm + 1
            assert(w.creatures[who.mate].key == 'worm')
            local beat, frames = 1, 0
            for f = 1, LENGTH * FPS do
                local t = f / FPS
                local b = BEATS[beat]
                if b and t >= b.at then
                    beat = beat + 1
                    if look then api.zoom(who[b.who]) end
                end
                api.step(1 / FPS)
                if look and f % every == 0 then
                    frames = frames + 1
                    api.save(api.render(shape[2], shape[3], shape[4]),
                        ('zoom_%s_%s_%03d.png'):format(name, shape[1], frames))
                    api.yield() -- (let LÖVE present, or the driver queues every frame)
                end
            end
            print('hash ' .. Hash.of(w).total)
        end
    end
end }
