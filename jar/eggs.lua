-- Eggs: a clutch in the moss, and the shells it leaves (#23).
--
-- Each plan lays its own kind, and each egg wears its child's colours, pale,
-- the way it will hatch:
--   worm    a cocoon, lemon-shaped and pointed at both ends, as an earthworm's is
--   blob    a bead of clear jelly, like frogspawn, with the child curled inside
--           and growing as the day goes by
--   spider  a sac of silk, with the spiderlings a faint stipple through it
--   springtail  a little heap of glossy beads, each with a dark eye-spot
--           showing as it ripens (#76)
-- They sit pressed into the cushion of moss, and breathe a soft light that
-- shows most at night and most of all in the eggs whose child will glow. In
-- the last hours they tremble, and then there's an empty shell for a while.
--
-- Drawing only: it reads World.eggs and World.shells and keeps nothing but
-- a skin per egg, worked out once (statehash skips `skin`).

local Skin = require('bodies.skin')
local Render = require('jar.render')

local Eggs = {}

local sin, cos, pi, max, min = math.sin, math.cos, math.pi, math.max, math.min

local SIZE = {worm = {7.5, 5}, blob = {6.5, 6.5}, spider = {7.5, 6.5}, springtail = {6.5, 4.5}} -- half width, half height
local STIR = 0.85 -- of the way to hatching, it starts to tremble

local function skin_of(e)
    e.skin = e.skin or Skin.of(e.key, e.genome, 1)
    return e.skin
end

local function set(c, a) love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

-- How far along an egg is (0 laid, 1 due), and how much it shakes now
local function progress(e, time)
    local p = e.due > e.laid and (time - e.laid) / (e.due - e.laid) or 1
    p = max(0, min(1, p))
    local stir = max(0, (p - STIR) / (1 - STIR))
    local phase = e.x * 0.37
    -- (a shiver now and then, coming closer together)
    local shiver = stir * max(0, sin(time * (0.6 + 1.6 * stir) + phase)) ^ 6
    return p, sin(time * 23 + phase) * 0.22 * shiver, phase
end

-- Where an egg sits: pressed into the moss at x on top of the solid
local function seat(world, e)
    local s = world.level.by_id[e.solid]
    local y = s and s.y or e.y
    local h = world.moss and world.moss:height_at(e.x, y) or 0
    local ry = SIZE[e.key][2]
    return e.x, y - ry + (1.5 + 5 * (h or 0) ^ 1.2) * 0.6
end

local function lemon(rx, ry)
    local pts = {}
    for k = 0, 23 do
        local t = k / 24 * 2 * pi
        local c = cos(t)
        -- pointed at both ends: the sides pinch in toward the tips
        local x = rx * c * (1 + 0.22 * c ^ 8)
        local y = ry * sin(t) * (1 - 0.25 * c * c)
        pts[#pts + 1], pts[#pts + 2] = x, y
    end
    return pts
end

local LEMON = {}

local function draw_worm(e, skin, p)
    local rx, ry = SIZE.worm[1], SIZE.worm[2]
    LEMON[1] = LEMON[1] or lemon(rx, ry)
    set(skin.band, 0.95)
    love.graphics.polygon('fill', LEMON[1])
    -- the child, a darker coil showing through the wall as it grows
    set(skin.mark, 0.25 + 0.35 * p)
    love.graphics.ellipse('fill', 0, 0.3, rx * (0.35 + 0.35 * p), ry * (0.3 + 0.3 * p))
    set(skin.belly, 0.7)
    love.graphics.ellipse('fill', -rx * 0.25, -ry * 0.45, rx * 0.35, ry * 0.18)
    set(skin.outline, 0.7)
    love.graphics.setLineWidth(0.6)
    love.graphics.polygon('line', LEMON[1])
end

local function draw_blob(e, skin, p, time, phase)
    local r = SIZE.blob[1]
    set(skin.core, 0.55)
    love.graphics.circle('fill', 0, 0, r)
    -- the child curled inside, turning slowly
    local a = time * 0.3 + phase
    local k = 0.35 + 0.65 * p
    set(skin.mark, 0.55)
    love.graphics.circle('fill', cos(a) * 0.9, sin(a) * 0.9, 1.3 * k + 0.4)
    love.graphics.circle('fill', cos(a + 1.4) * 1.9 * k, sin(a + 1.4) * 1.9 * k, 0.8 * k + 0.2)
    set(skin.rim, 0.7)
    love.graphics.setLineWidth(0.5)
    love.graphics.circle('line', 0, 0, r)
    set(skin.bubble, 0.9)
    love.graphics.circle('fill', -r * 0.38, -r * 0.42, 0.9)
end

local SILK = Skin.families.spider.shell

local function draw_spider(e, skin, p, time, phase)
    local rx, ry = SIZE.spider[1], SIZE.spider[2]
    -- a loose ball of silk: a few overlapping puffs, fuzzy at the edge, and
    -- faintly the colour of the markings it'll have
    local silk = skin.silk
    if not silk then
        local m = skin.mark
        silk = {SILK[1] * 0.8 + m[1] * 0.2, SILK[2] * 0.8 + m[2] * 0.2, SILK[3] * 0.8 + m[3] * 0.2, 1}
        skin.silk = silk
    end
    set(silk, 0.3)
    for k = 0, 7 do
        local a = k / 8 * 2 * pi + phase
        love.graphics.ellipse('fill', cos(a) * 1.1, sin(a) * 0.9, rx * 0.95, ry * 0.95)
    end
    set(silk, 0.85)
    love.graphics.ellipse('fill', 0, 0, rx * 0.88, ry * 0.86)
    -- the windings of the silk
    set(SILK, 0.5)
    love.graphics.setLineWidth(0.4)
    for k = 1, 3 do
        love.graphics.arc('line', 'open', 0, 0, rx * (0.35 + 0.17 * k), phase + k * 1.9, phase + k * 1.9 + 2.2)
    end
    -- the spiderlings, a stipple that darkens toward hatching
    set(skin.body, 0.15 + 0.4 * p)
    for k = 1, 7 do
        local u, v = Skin.hash(phase, k), Skin.hash(k, phase)
        local a, d = u * 2 * pi, 0.25 + 0.6 * v
        love.graphics.circle('fill', cos(a) * rx * d * 0.8, sin(a) * ry * d * 0.8, 0.55)
    end
    -- and a thread or two tying it to the moss
    set(SILK, 0.5)
    love.graphics.setLineWidth(0.35)
    love.graphics.line(-rx * 0.8, ry * 0.4, -rx * 1.5, ry * 1.1)
    love.graphics.line(rx * 0.7, ry * 0.5, rx * 1.4, ry * 1.2)
end

-- (where each bead of a springtail's heap sits, and how big it is)
local BEADS = {{-3.6, 1.6, 2.1}, {0, 1.9, 2.3}, {3.7, 1.5, 2.0}, {-1.9, -1.4, 2.0}, {1.9, -1.5, 2.1}, {0.1, -3.9, 1.7}}

local function draw_springtail(e, skin, p, time, phase)
    for k, b in ipairs(BEADS) do
        local x, y, r = b[1], b[2], b[3] * (0.92 + 0.16 * Skin.hash(phase, k))
        set(skin.outline, 0.45)
        love.graphics.circle('fill', x, y, r + 0.4)
        set(skin.belly, 0.9)
        love.graphics.circle('fill', x, y, r)
        -- the young one's eye-spot, darkening as it ripens
        set(skin.body, 0.15 + 0.6 * p)
        love.graphics.circle('fill', x + r * 0.2, y + r * 0.15, r * (0.18 + 0.12 * p))
        -- each one glossy
        love.graphics.setColor(1, 1, 1, 0.75)
        love.graphics.circle('fill', x - r * 0.38, y - r * 0.4, r * 0.28)
    end
end

local DRAW = {worm = draw_worm, blob = draw_blob, spider = draw_spider, springtail = draw_springtail}

-- The clutches, under the creatures' lighting (in level units)
function Eggs.draw(world, light)
    local time = world.time
    for _, e in ipairs(world.eggs) do
        if e.young then
            local x, y = seat(world, e)
            local p, tilt, phase = progress(e, time)
            -- (no two eggs quite alike: a little bigger or smaller, leaning a little)
            local k = 0.88 + 0.24 * Skin.hash(phase, 3)
            love.graphics.push()
            love.graphics.translate(x, y + SIZE[e.key][2])
            love.graphics.rotate(tilt + (Skin.hash(phase, 5) - 0.5) * 0.3)
            love.graphics.scale(k)
            love.graphics.translate(0, -SIZE[e.key][2])
            DRAW[e.key](e, skin_of(e), p, time, phase)
            love.graphics.pop()
        end
    end
    -- Empty shells: two halves fallen open either side of where the egg lay,
    -- fading back into the moss
    for _, s in ipairs(world.shells) do
        local a = 1 - (time - s.at) / world.SHELL
        if a > 0 then
            local skin = skin_of(s)
            local rx = SIZE[s.key][1]
            local x, y = s.x, s.y - 1 - rx * 0.7
            local shell = Skin.families[s.key].shell -- (a colour of its skin, by name, or a colour)
            local c = type(shell) == 'string' and skin[shell] or shell or skin[skin.main]
            set(c, 0.6 * a)
            love.graphics.arc('fill', x - rx * 2.6, y, rx * 0.75, pi * 0.1, pi * 1.0)
            love.graphics.arc('fill', x + rx * 2.4, y + 0.5, rx * 0.65, 0, pi * 0.85)
        end
    end
end

-- Their light, added after the jar's lighting: a slow breath, brighter in the
-- dark and in the eggs of glowing children, quickening as they stir
function Eggs.draw_emissive(world, light)
    local time = world.time
    local night = light and light.glow or 0
    for _, e in ipairs(world.eggs) do
        if e.young then
            local x, y = seat(world, e)
            local p, tilt, phase = progress(e, time)
            local stir = max(0, (p - STIR) / (1 - STIR))
            local breath = 0.7 + 0.3 * sin(time * (1.1 + 2.5 * stir) + phase)
            local k = (0.25 + 0.75 * night) * (0.45 + 0.55 * e.genome.glow) * breath
            local skin = skin_of(e)
            Skin.paint_glow({{'halo', x, y, 11 + 4 * p}, {'disc', x, y, 1.2 + 0.8 * p}}, skin, k)
        end
    end
end

return Eggs
