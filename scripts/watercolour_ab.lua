-- #96's A/B, after #95's (scripts/pencil_ab.lua): the same moments painted by
-- watercolour (A, the whole finished frame at once) and watercolour-each (B,
-- each thing painted on its own first), side by side, A on the left, each a
-- plate held still on whoever goes furthest in the next few seconds, so you
-- can watch whether its paint travels with it (B) or it walks through washes
-- laid on the page (A). Once by day, once in the evening, the lamp on and the
-- room dark.
--
--   lovec . --script scripts/watercolour_ab.lua
--
-- Saves wab_<scene>_<nnn>.png (1600 x 450, every frame at 30 fps) to the save
-- directory. To make films of them:
--   ffmpeg -framerate 30 -i wab_day_%03d.png -pix_fmt yuv420p wab_day.mp4

local FRAMES = tonumber(os.getenv('AB_FRAMES') or '') or 120
local W, H = 800, 450
local SEED = 20261018
local A, B = 'watercolour', 'watercolour-each'

local function middle(c)
    local x, y, n = 0, 0, 0
    for _, p in ipairs(c:interp_points()) do x, y, n = x + p.x, y + p.y, n + 1 end
    return x / n, y / n
end

-- The jar at `hour`, twenty seconds in, and which of them goes furthest in
-- the FRAMES after (the jar replays the same, so it can be asked first)
local function open(api, hour)
    local world = api.open(SEED, hour, nil, nil, api.World.CLASSIC)
    api.step(20)
    return world
end
local function busiest(api, hour)
    local world = open(api, hour)
    local from = {}
    for i, c in ipairs(world.creatures) do from[i] = { middle(c) } end
    api.step(FRAMES / 30)
    local best, far, to = 1, -1, nil
    for i, c in ipairs(world.creatures) do
        local x, y = middle(c)
        local dx, dy = x - from[i][1], y - from[i][2]
        local d = dx * dx + dy * dy
        if d > far then best, far, to = i, d, { x, y } end
    end
    return best, from[best], to
end

-- A plate held still over the whole of the busiest one's way, so it crosses
-- the frame under the camera rather than the camera following it
local function film(api, scene, hour)
    local who, from, to = busiest(api, hour)
    local world = open(api, hour)
    print(string.format('[ab] %s: watching the %s go from %.0f, %.0f to %.0f, %.0f',
        scene, world.creatures[who].key, from[1], from[2], to[1], to[2]))
    local x, y = (from[1] + to[1]) / 2, (from[2] + to[2]) / 2
    local span = math.max(300, math.abs(to[1] - from[1]) + 160, (math.abs(to[2] - from[2]) + 120) * W / H)
    local view = { x - span / 2, y - span * H / W * 0.55, x + span / 2, y + span * H / W * 0.45 }
    local side = love.graphics.newCanvas(W * 2, H)
    local font = love.graphics.newFont(14)
    for f = 1, FRAMES do
        for k, name in ipairs({ A, B }) do
            api.style(name)
            local plate = api.render(W, H, { view = view })
            love.graphics.setCanvas(side)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(plate, (k - 1) * W, 0)
            love.graphics.setFont(font)
            love.graphics.setColor(0.17, 0.175, 0.195, 0.8)
            love.graphics.print(k == 1 and 'A  whole frame' or 'B  each thing', (k - 1) * W + 14, 12)
            love.graphics.setCanvas()
        end
        api.save(side, string.format('wab_%s_%03d.png', scene, f))
        api.step(1 / 30)
        api.yield()
    end
end

return {run = function(api)
    film(api, 'day', 'morning')
    film(api, 'evening', 20.5)
end}
