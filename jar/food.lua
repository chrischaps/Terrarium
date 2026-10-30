-- Food: a pinch of crumbs dropped into the jar (#25).
--
-- Watching, following with the lantern, naming, and this: the only thing you
-- can give the jar. Right-click and a pinch falls from under the lid where you
-- clicked, a few crumbs of dried petal and pollen turning over as they come
-- down through the lamp's light, until each settles on whatever is below it.
-- Whoever is awake and near enough notices and comes over to nibble it
-- (mind.lua). A crumb nobody eats softens into the moss after a while.
--
-- It stays a small treat. The jar keeps PINCHES of them a day, and one
-- comes back every 1/PINCHES of a day, so a crumb is a mouthful beside a
-- morning's grazing and can't stand in for the moss that does the selecting.
--
-- The crumbs are simulation: they fall on the fixed step, the minds read them,
-- and the state hash walks them. A pinch is an input like the seed, and
-- `given` keeps when and where each one fell, the jar's history. Food.draw only
-- reads them.

local C = require('jar.config')
local Skin = require('bodies.skin')
local Render = require('jar.render')
local rng = require('core.rng')

local Food = {}
Food.__index = Food

Food.PINCHES = 3        -- pinches the jar keeps, and how many come back in a day
local CRUMBS = {5, 8}   -- in a pinch
local SPREAD = 16       -- how far either side of the click they fall from
local FALL = {55, 85}   -- the speed each settles to as it falls, units a second
local SWAY = {4, 10}    -- how far it slips sideways as it turns over
Food.KEEP = 240         -- seconds a crumb lies uneaten before it's gone into the moss
local SOFTEN = 40       -- the last of those, it fades

local fmath = require('core.fmath') -- Terrarium: the same sines compiled or not (#94)
local sin, cos, abs, min, max, floor, exp = fmath.sin, fmath.cos, math.abs, math.min, math.max, math.floor, fmath.exp

function Food.new(level)
    return setmetatable({
        level = level,
        crumbs = {},          -- falling and lying, in the order they fell
        count = 0,            -- crumbs ever dropped, so each has its own id
        pantry = Food.PINCHES,
        given = {},           -- each pinch: {at, x}
    }, Food)
end

-- A pinch at x, if there's one left. Returns its crumbs, or nil.
function Food:pinch(x, time)
    if self.pantry < 1 then return nil end
    self.pantry = self.pantry - 1
    x = max(C.GLASS_L + SPREAD, min(C.GLASS_R - SPREAD, x))
    self.given[#self.given + 1] = {at = time, x = x}
    local out = {}
    for k = 1, rng.sim:random(CRUMBS[1], CRUMBS[2]) do
        self.count = self.count + 1
        local cx = x + rng.range(rng.sim, -SPREAD, SPREAD)
        local y = C.GLASS_T + 2 + rng.range(rng.sim, 0, 6)
        local f = {
            id = self.count, x = cx, y = y, px = cx, py = y, vy = rng.range(rng.sim, 0, 10),
            fall = rng.range(rng.sim, FALL[1], FALL[2]), sway = rng.range(rng.sim, SWAY[1], SWAY[2]),
            rot = rng.range(rng.sim, 0, 6.28), spin = rng.range(rng.sim, -3, 3),
            size = rng.range(rng.sim, 2.2, 3.4), tint = rng.sim:random(1, 6),
        }
        self.crumbs[#self.crumbs + 1] = f
        out[k] = f
    end
    return out
end

-- How many pinches are left now (a fraction while the next comes back)
function Food:left()
    return floor(self.pantry)
end

function Food:get(id)
    for _, f in ipairs(self.crumbs) do
        if f.id == id then return f end
    end
end

-- The crumb `id` is eaten: it's gone
function Food:eat(id)
    for k, f in ipairs(self.crumbs) do
        if f.id == id then return table.remove(self.crumbs, k) end
    end
end

-- One fixed step: the pantry fills back over the day, falling crumbs come down,
-- and the ones left too long go into the moss
function Food:update(dt, time, day)
    self.pantry = min(Food.PINCHES, self.pantry + dt * Food.PINCHES / day)
    local level, keep = self.level, {}
    for _, f in ipairs(self.crumbs) do
        f.px, f.py = f.x, f.y
        if not f.down then
            f.vy = f.vy + (f.fall - f.vy) * min(1, dt * 2)
            f.rot = f.rot + f.spin * dt
            -- A turning crumb slips sideways, and falls slower while it's flat on
            local nx = f.x + sin(f.rot) * f.sway * dt
            local ny = f.y + f.vy * dt * (0.6 + 0.4 * abs(cos(f.rot)))
            if nx < C.GLASS_L + 2 or nx > C.GLASS_R - 2 or level:solid_at(nx, f.y) then nx = f.x end
            local sy, s = level:surface_below(nx, f.y, ny - f.y + 1)
            if sy and ny >= sy then
                f.x, f.y, f.down, f.solid, f.at = nx, sy, true, s, time
            else
                f.x, f.y = nx, ny
            end
        end
        if not f.down or time - f.at < Food.KEEP then keep[#keep + 1] = f end
    end
    self.crumbs = keep
end

--------------------------------------------------------------------------------
-- Drawing: each crumb a little flake of petal or pollen, its own shape from its
-- id, tilting as it turns over and lying flat in the moss once it's down. In
-- the lamp's pool a falling one catches the light as it turns.
--------------------------------------------------------------------------------

local TINTS = {
    {0.86, 0.52, 0.24}, -- marigold
    {0.93, 0.78, 0.36}, -- pollen
    {0.72, 0.36, 0.26}, -- rosehip
    {0.90, 0.84, 0.66}, -- chaff
    {0.58, 0.64, 0.30}, -- dried leaf
    {0.80, 0.44, 0.40}, -- petal
}

local shapes = {} -- id -> polygon, worked out once

local function shape(f)
    local pts = shapes[f.id]
    if pts then return pts end
    pts = {}
    local n = 4 + floor(Skin.hash(f.id, 1) * 3)
    for i = 1, n do
        local a = (i / n) * math.pi * 2 + (Skin.hash(f.id, i + 2) - 0.5) * 0.7
        local r = f.size * (0.6 + 0.5 * Skin.hash(f.id, i + 11))
        pts[#pts + 1], pts[#pts + 2] = cos(a) * r, sin(a) * r
    end
    shapes[f.id] = pts
    return pts
end

-- Where a crumb is drawn: between its last two steps, and once down, resting
-- on the cushion of moss under it
local function place(food, f, alpha, moss)
    local x, y = f.px + (f.x - f.px) * alpha, f.py + (f.y - f.py) * alpha
    if f.down then
        local h = moss and moss:height_at(f.x, f.y) or 0
        y = y - (0.5 + 7.5 * (h or 0) ^ 1.2) - f.size * 0.3
    end
    return x, y
end

local function fade(f, time)
    return f.down and min(1, max(0, (Food.KEEP - (time - f.at)) / SOFTEN)) or 1
end

--- The crumbs under the creatures' lighting (in level units, Tank.pushPlane)
function Food.draw(food, time, alpha, moss)
    for _, f in ipairs(food.crumbs) do
        local x, y = place(food, f, alpha, moss)
        local c, a = TINTS[f.tint], fade(f, time)
        local tilt = f.down and 0.45 or (0.2 + 0.8 * abs(cos(f.rot)))
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.rotate(f.down and (Skin.hash(f.id, 9) - 0.5) * 0.6 or f.rot * 0.3)
        love.graphics.scale(1, tilt)
        love.graphics.setColor(c[1], c[2], c[3], 0.95 * a)
        love.graphics.polygon('fill', shape(f))
        love.graphics.setColor(1, 0.95, 0.85, 0.3 * a)
        love.graphics.circle('fill', -f.size * 0.2, -f.size * 0.2, f.size * 0.35)
        love.graphics.pop()
    end
end

--- Their light, added after the jar's: a glint off a falling crumb in the
-- lamp's pool each time it turns its face up to the lamp
function Food.draw_emissive(food, light, time, alpha)
    local lamp = light and light.lamp_i or 0
    if lamp < 0.02 then return end
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, f in ipairs(food.crumbs) do
        if not f.down then
            local x, y = place(food, f, alpha)
            local t = (y - C.GLASS_T) / (C.SOIL_Y - C.GLASS_T)
            local u = (x - C.LAMP_X) / (C.LAMP_CONE.top + (C.LAMP_CONE.bottom - C.LAMP_CONE.top) * t)
            local k = lamp * exp(-u * u * 1.6) * abs(cos(f.rot)) ^ 12
            if k > 0.02 then
                local c = TINTS[f.tint]
                love.graphics.setColor(k * 0.3, k * 0.27, k * 0.2, 1)
                Render.drawBlob(x, y, f.size * 5)
                love.graphics.setColor(k * (0.6 + 0.4 * c[1]), k * (0.55 + 0.4 * c[2]), k * (0.45 + 0.4 * c[3]), 1)
                love.graphics.circle('fill', x, y, f.size * 0.9)
            end
        end
    end
    love.graphics.pop()
end

return Food
