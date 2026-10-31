-- The jar's moments, close up (#33): a jar from its seed left to live on
-- 900 s days, and a plate of each of its first courtships, clutches,
-- hatchings, moults and returns to the moss, framed on where it happened a
-- few seconds after. Like the time-lapse, nothing is staged: the moments are
-- the jar's own, wherever and whenever they fall.
--
--   lovec . --script scripts/moments.lua [--seed <n>] [--day <sec>] [--cast a,b,c]
--
-- Saves moment_<seed>_<n>_<kind>.png to the save directory (copy them to
-- renders/, which git ignores) and prints what each one shows.

local DayCycle = require('jar.daycycle')

local DAYS = 8
local DAY = 900
local EACH = 3 -- plates of each kind of moment
local W, H = 1920, 1080
local WIDE = 420 -- level units across a plate

-- How long after the event a plate is taken, and how high above the place
-- its middle sits (a courtship stands off the moss; the spores rise)
local AFTER = {
    court = { 6, 30 },
    laid = { 4, 20 },
    hatched = { 4, 20 },
    moulted = { 2, 25 },
    dying = { 45, 20 },
    returned = { 6, 40 },
}

return {
    run = function(api)
        local seed = api.args.seed or 20261018
        local day = api.args.day or DAY
        local w = api.open(seed, 'dawn', nil, day, api.args.cast or api.World.CLASSIC)
        local due, taken, n = {}, {}, 0
        w.events:on(function(ev)
            local a = AFTER[ev.kind]
            if not a or (taken[ev.kind] or 0) >= EACH then return end
            taken[ev.kind] = (taken[ev.kind] or 0) + 1
            local who = ev.who and (ev.who.key .. (ev.who.name and (' ' .. ev.who.name) or '')) or '?'
            due[#due + 1] = { at = w.time + a[1], x = ev.x, y = ev.y - a[2], kind = ev.kind, who = who }
        end)
        while w.time < DAYS * day do
            api.step(0.5)
            for k = #due, 1, -1 do
                local d = due[k]
                if w.time >= d.at then
                    table.remove(due, k)
                    n = n + 1
                    local h = WIDE * H / W
                    local x0 = math.max(40, math.min(2000 - 40 - WIDE, d.x - WIDE / 2))
                    local y0 = math.max(60, math.min(940 - h, d.y - h / 2))
                    local file = string.format('moment_%d_%02d_%s.png', seed, n, d.kind)
                    api.save(api.render(W, H, { view = { x0, y0, x0 + WIDE, y0 + h } }), file)
                    local hour = DayCycle.hourAt(DayCycle.presets.dawn, w.time, day)
                    print(string.format('[moments] %s: day %d %02d:%02d, %s %s at %.0f, %.0f', file,
                        math.floor(w.time / day) + 1, math.floor(hour), math.floor(hour % 1 * 60), d.who, d.kind,
                        d.x, d.y))
                    api.yield()
                end
            end
        end
    end,
}
