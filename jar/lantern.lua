-- Terrarium: the lantern (#6). Click a creature and you hold a lantern up to
-- the glass beside it, and a warm pool of light follows it about; click empty
-- space and the light goes. You only watch: the lantern lives outside the
-- World, never selects or steers anyone, and only reads where bodies are.
-- Its easing and flicker run on the frame clock, which is fine for something
-- the simulation never sees.

local C = require("jar.config")
local Tank = require("jar.tank")
local Render = require("jar.render")

local Lantern = {}
Lantern.__index = Lantern

local PICK = 26           -- how close a click must land to a body (level px)
local EASE = 7            -- how quickly the pool catches up (per second)
local FADE = 2.5          -- how quickly it comes up or goes out (per second)
local WARM = { 1.00, 0.70, 0.38 }

function Lantern.new()
    return setmetatable({ who = nil, x = nil, y = nil, feet = nil, glow = 0 }, Lantern)
end

-- Where a body is: the middle of its points, and its lowest one
local function locate(c)
    local sx, sy, n, low = 0, 0, 0, -math.huge
    for _, p in ipairs(c:interp_points()) do
        sx, sy, n = sx + p.x, sy + p.y, n + 1
        if p.y > low then low = p.y end
    end
    return sx / n, sy / n, low
end

--- The creature nearest a point in level coordinates, if one is close enough
function Lantern.creatureAt(world, lx, ly)
    local best, bestD = nil, PICK * PICK
    for i, c in ipairs(world.creatures) do
        for _, p in ipairs(c:interp_points()) do
            local d = (p.x - lx) ^ 2 + (p.y - ly) ^ 2
            if d < bestD then best, bestD = i, d end
        end
    end
    return best
end

--- Follow whoever is under the click, or let go
function Lantern:pick(world, lx, ly)
    self.who = Lantern.creatureAt(world, lx, ly)
    return self.who
end

function Lantern:following(world)
    return self.who and world.creatures[self.who]
end

--- Ease the pool toward whoever it follows (frame dt, render only)
function Lantern:update(dt, world)
    local c = self:following(world)
    if c then
        local x, y, feet = locate(c)
        if not self.x or self.glow < 0.02 then
            self.x, self.y, self.feet = x, y, feet
        else
            local k = 1 - math.exp(-EASE * dt)
            self.x = self.x + (x - self.x) * k
            self.y = self.y + (y - self.y) * k
            self.feet = self.feet + (feet - self.feet) * k
        end
    end
    local target = c and 1 or 0
    self.glow = self.glow + (target - self.glow) * (1 - math.exp(-FADE * dt))
end

-- The lantern matters most in the dark; under the lamp it's a gentle warmth
local function strength(self, light)
    local t = love.timer.getTime()
    local flicker = 1 + 0.05 * math.sin(t * 7.3) + 0.03 * math.sin(t * 13.1 + 1.7)
    return self.glow * (0.55 + 0.45 * (1 - light.lamp_i)) * flicker
end

--- The pool of light on the creatures' plane: drawn in level coordinates,
-- over the creatures, so it lights them and the ground they're standing on
function Lantern:draw(light)
    if self.glow < 0.01 or not self.x then return end
    local s = strength(self, light)
    love.graphics.push("all")
    love.graphics.setBlendMode("add")
    local r, g, b = WARM[1], WARM[2], WARM[3]
    love.graphics.setColor(r * 0.10 * s, g * 0.10 * s, b * 0.10 * s, 1)
    Render.drawBlob(self.x, self.y - 8, 130, 110)
    love.graphics.setColor(r * 0.13 * s, g * 0.13 * s, b * 0.13 * s, 1)
    Render.drawBlob(self.x, self.y - 4, 48, 42)
    -- Where the light lands at its feet
    love.graphics.setColor(r * 0.16 * s, g * 0.16 * s, b * 0.16 * s, 1)
    Render.drawBlob(self.x, self.feet + 2, 84, 11)
    love.graphics.pop()
end

--- The lantern itself, held to the outside of the glass: its flame caught in
-- the pane, and a warm bloom in whatever mist is on the inside
function Lantern:drawGlass(light)
    if self.glow < 0.01 or not self.x then return end
    local s = strength(self, light)
    local sx, sy = Tank.level(self.x, self.y)
    local x0, y0 = C.OX + C.GLASS_L, C.OY + C.GLASS_T
    local x1, y1 = C.OX + C.GLASS_R, C.OY + C.GLASS_B - C.GLASS_THICK
    local fx, fy = sx + 22, sy - 46     -- held a little above and to one side
    love.graphics.push("all")
    love.graphics.setScissor(x0, y0, x1 - x0, y1 - y0)
    love.graphics.setBlendMode("add")
    local r, g, b = WARM[1], WARM[2], WARM[3]
    local mist = 0.04 + 0.10 * (light.damp or 0)
    love.graphics.setColor(r * mist * s, g * mist * s, b * mist * s, 1)
    Render.drawBlob(fx, fy, 150)
    love.graphics.setColor(r * 0.22 * s, g * 0.22 * s, b * 0.22 * s, 1)
    Render.drawBlob(fx, fy, 16, 22)
    love.graphics.setColor(0.9 * s, 0.8 * s, 0.6 * s, 1)
    Render.drawBlob(fx, fy + 1, 3, 5)
    love.graphics.pop()
end

return Lantern
