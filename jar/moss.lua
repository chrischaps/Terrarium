-- Moss: a coarse grid of moss height over every mossy top (#20).
--
-- Each mossed solid's exposed top (Level:top_spans) is cut into cells about
-- CELL units wide, and each cell holds a height from 0 (bare) to 1 (lush).
-- While the lamp is on, moss grows toward its cell's own ceiling, faster and
-- taller where the lamp's cone falls on it unshaded. A grazing mouth crops it
-- to the ground and passing feet wear it short. It's the creatures' food, and
-- it's the jar's record of where life has been: the ways they go are worn,
-- the places they eat are bare, and by the next afternoon it's grown back.
--
-- Where a creature has returned to the moss (#24), the patch it lay on is
-- pressed flat, then grows back faster, taller and greener than the moss
-- around it: each cell keeps a richness that the lamp's hours slowly use up.
--
-- The heights are simulation: the World steps them on the fixed step and the
-- state hash reads them. Moss.draw only reads them.

local C = require('jar.config')
local Render = require('jar.render')

local Moss = {}
Moss.__index = Moss

local CELL = 6        -- level units per cell, about
local GROW = 1 / 240  -- growth rate under the full lamp, per second (see Moss:update)
local EAT = 0.12      -- height a mouth crops from the cell under it, per second
local BITE = {1, 0.4}  -- how much of that it takes from the cells either side
local TREAD = 0.03    -- height passing feet wear away, per second
local WORN = 0.15     -- feet wear moss down to this; only eating leaves it bare
Moss.WORN = WORN
local RICH_CAP = 0.35   -- how much higher a rich cell's ceiling stands
local RICH_GROW = 3     -- and how much faster it grows
local RICH_FOR = 150000 -- seconds of full lamp it takes to use up (about three days of lamp)
local REACH = {18, 4} -- a body this far above a top (or this far into it) is on it

local sqrt, exp, sin, min, max, floor, abs = math.sqrt, math.exp, math.sin, math.min, math.max, math.floor, math.abs

-- A fixed pseudo-random number in [0, 1) for cell i: the moss's own variety,
-- the same every run, without drawing from any stream
local function noise(i, salt)
    local v = sin(i * 12.9898 + (salt or 0) * 78.233) * 43758.5453
    return v - floor(v)
end

-- How much of the lamp reaches (x, y), 0..1. The cone's pool falls off the way
-- the object shader's does, and three rays to the lid under the lamp say how
-- much of it gets past the solids above.
local function exposure(level, x, y)
    local t = (y - C.GLASS_T) / (C.SOIL_Y - C.GLASS_T)
    local hw = C.LAMP_CONE.top + (C.LAMP_CONE.bottom - C.LAMP_CONE.top) * t
    local u = (x - C.LAMP_X) / hw
    local pool = exp(-u * u * 1.6)
    local open = 0
    for _, off in ipairs({-120, 0, 120}) do
        local dx, dy = C.LAMP_X + off - x, C.GLASS_T - (y - 1)
        local d = sqrt(dx * dx + dy * dy)
        if not level:raycast(x, y - 1, dx / d, dy / d, d - 1) then open = open + 1 / 3 end
    end
    return (0.2 + 0.8 * pool) * (0.25 + 0.75 * open)
end

function Moss.new(level)
    local self = setmetatable({spans = {}, h = {}, cap = {}, sun = {}, x = {}, rich = {}}, Moss)
    local n = 0
    for _, s in ipairs(level:top_spans()) do
        if s.solid.moss then
            local cells = max(1, floor((s.x1 - s.x0) / CELL + 0.5))
            local span = {x0 = s.x0, x1 = s.x1, y = s.y, solid = s.solid.id, first = n + 1, n = cells,
                w = (s.x1 - s.x0) / cells}
            self.spans[#self.spans + 1] = span
            for k = 1, cells do
                n = n + 1
                local x = s.x0 + (k - 0.5) * span.w
                local sun = exposure(level, x, s.y)
                self.x[n], self.sun[n] = x, sun
                -- Shaded moss stays short; in the lamp's pool it grows deep
                self.cap[n] = 0.4 + 0.6 * sun
                self.h[n] = self.cap[n] * (0.8 + 0.2 * noise(n))
                self.rich[n] = 0
            end
        end
    end
    self.count = n
    return self
end

-- The span and cell a body at (x, y) stands on, if it stands on moss
function Moss:cell_at(x, y)
    for _, s in ipairs(self.spans) do
        if x >= s.x0 and x <= s.x1 and y >= s.y - REACH[1] and y <= s.y + REACH[2] then
            return s, s.first + min(s.n - 1, floor((x - s.x0) / s.w))
        end
    end
end

-- The moss's height where a body at (x, y) would stand (nil off the moss)
function Moss:height_at(x, y)
    local _, i = self:cell_at(x, y)
    return i and self.h[i]
end

-- One fixed step of growth. `lamp` is the lamp's brightness (DayCycle.lampAt).
-- Growth is slow from bare ground and quickens as the moss thickens, then
-- slows again near its ceiling: a cropped patch under the lamp is back to
-- most of its height in a few hours.
function Moss:update(dt, lamp)
    if lamp <= 0 then return end
    local h, cap, sun, rich = self.h, self.cap, self.sun, self.rich
    local k = GROW * lamp * dt
    for i = 1, self.count do
        local v, c, r = h[i], cap[i], rich[i]
        if r > 0 then
            c = c + RICH_CAP * r
            rich[i] = max(0, r - lamp * dt / RICH_FOR)
        end
        if v < c then h[i] = min(c, v + k * (1 + RICH_GROW * r) * sun[i] * (0.15 + v) * (c - v)) end
    end
end

-- The moss a body at (x, y) lies on, or the nearest below it (a spider asleep
-- under a ledge comes down to the moss beneath): its span, or nil
function Moss:beneath(x, y)
    local best
    for _, s in ipairs(self.spans) do
        if x >= s.x0 and x <= s.x1 and s.y >= y - REACH[1] and (not best or s.y < best.y) then best = s end
    end
    return best
end

-- A creature returns to the moss (#24): the cells from x0 to x1 of the moss
-- at or below y are pressed down where it lay, and grow back rich
function Moss:enrich(x0, x1, y)
    local s = self:beneath((x0 + x1) / 2, y)
    if not s then return end
    -- (Terrarium: the smallest body still richens the cell either side of it,
    -- wherever it lies on them, #77)
    local mid, half = (x0 + x1) / 2, max(s.w, (x1 - x0) / 2)
    for i = s.first, s.first + s.n - 1 do
        local d = abs(self.x[i] - mid) / half
        if d < 1.3 then
            self.h[i] = min(self.h[i], WORN)
            self.rich[i] = max(self.rich[i], min(1, 1.3 - d))
        end
    end
    return s
end

-- A mouth at (x, y) grazing for dt. Returns how much it ate, in cells' worth
-- of lush moss, or nil if it isn't standing on moss.
function Moss:graze(x, y, dt)
    local s, i = self:cell_at(x, y)
    if not s then return nil end
    local h, eaten = self.h, 0
    for d = -#BITE + 1, #BITE - 1 do
        local j = i + d
        if j >= s.first and j < s.first + s.n then
            local bite = min(h[j], EAT * BITE[abs(d) + 1] * dt)
            h[j] = h[j] - bite
            eaten = eaten + bite
        end
    end
    return eaten
end

-- Feet passing over (x, y) for dt wear the moss there short, never bare
function Moss:tread(x, y, dt)
    local _, i = self:cell_at(x, y)
    if i and self.h[i] > WORN then self.h[i] = max(WORN, self.h[i] - TREAD * dt) end
end

--------------------------------------------------------------------------------
-- Drawing: a cushion along each top whose surface rolls with the heights, and
-- tufts on it like the little stars of a moss pile. Height is thickness;
-- colour is how much of its own ceiling it has left. Lush is a deep green
-- mound, cropped is a thin gold felt, and bare is the brown of the bark or
-- soil showing through. Anyone standing in it presses it down.
--------------------------------------------------------------------------------

local TUFTS = 3                 -- per cell
local PER_CELL = 12 + TUFTS * 6 -- two quads of cushion, a diamond per tuft
local mesh, verts
local depth = {}

local BARE  = {0.29, 0.21, 0.13}
local SHORT = {0.50, 0.49, 0.21}
local LUSH  = {0.19, 0.39, 0.14}
local RICH  = {0.13, 0.47, 0.13} -- where one returned to it
Moss.LUSH, Moss.RICH = LUSH, RICH -- (Terrarium: for what grows over a snail's shell and its eggs, #77)

local function tone(v)
    local a, b, t
    if v < 0.35 then a, b, t = BARE, SHORT, v / 0.35
    else a, b, t = SHORT, LUSH, (v - 0.35) / 0.65 end
    t = t * t * (3 - 2 * t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function put(k, x, y, r, g, b, a)
    local v = verts[k]
    if not v then v = {0, 0, 0, 0, 0, 0, 0, 1}; verts[k] = v end
    v[1], v[2], v[5], v[6], v[7], v[8] = x, y, r, g, b, a or 1
end

local function quad(k, xa, ya, xb, yb, xc, yc, xd, yd, r, g, b, under)
    local u = under
    put(k + 1, xa, ya, r, g, b); put(k + 2, xb, yb, r, g, b); put(k + 3, xc, yc, r * u, g * u, b * u)
    put(k + 4, xa, ya, r, g, b); put(k + 5, xc, yc, r * u, g * u, b * u); put(k + 6, xd, yd, r * u, g * u, b * u)
    return k + 6
end

--- Draw the moss on the creatures' plane (call inside Tank.pushPlane(), after
-- the scenery). It only reads the grid, the jar's clock and where bodies are.
function Moss.draw(m, light, time, creatures)
    if m.count == 0 then return end
    local need = m.count * PER_CELL
    if not mesh or mesh:getVertexCount() ~= need then
        verts = {}
        mesh = love.graphics.newMesh(need, 'triangles', 'stream')
    end
    local feet = {}
    for _, c in ipairs(creatures or {}) do
        local x, y = c:anchor()
        feet[#feet + 1] = x
        feet[#feet + 1] = y
    end

    local k = 0
    for _, s in ipairs(m.spans) do
        local y, w, first, last = s.y, s.w, s.first, s.first + s.n - 1
        -- How thick the cushion stands in each cell, pressed where a body is
        for i = first, last do
            local t = 0.5 + 7.5 * m.h[i] ^ 1.2 * (0.75 + 0.5 * noise(i, 11))
            for f = 1, #feet, 2 do
                local dx, dy = abs(m.x[i] - feet[f]), y - feet[f + 1]
                if dx < 10 and dy > -REACH[2] and dy < REACH[1] then t = t * (0.55 + 0.45 * dx / 10) end
            end
            depth[i] = t
        end
        for i = first, last do
            local v = m.h[i]
            local x0, cx = s.x0 + (i - first) * w, m.x[i]
            local x1 = x0 + w
            local tl = (depth[i] + (i > first and depth[i - 1] or depth[i] * 0.3)) / 2
            local tr = (depth[i] + (i < last and depth[i + 1] or depth[i] * 0.3)) / 2
            local tc = depth[i]
            -- Its colour is how cropped it is: shaded moss is short but green
            local r, g, b = tone(min(1, v / m.cap[i]))
            -- and where one returned to it, it's greener while it's lush
            local rich = m.rich[i] * min(1, v / m.cap[i])
            if rich > 0 then
                r, g, b = r + (RICH[1] - r) * rich, g + (RICH[2] - g) * rich, b + (RICH[3] - b) * rich
            end
            -- The cushion, rolling through each cell's thickness and tucked a
            -- little over the edge of what it grows on
            k = quad(k, x0, y - tl, cx, y - tc, cx, y + 1.4, x0, y + 1.4, r, g, b, 0.6)
            k = quad(k, cx, y - tc, x1, y - tr, x1, y + 1.4, cx, y + 1.4, r, g, b, 0.6)
            -- Tufts: none on bare ground, a fringe on worn, a pile when lush
            for j = 1, TUFTS do
                local n1, n2 = noise(i, j), noise(i, j + 7)
                local rad = v < 0.15 and 0 or (0.5 + 2.2 * v) * (0.65 + 0.7 * n1)
                local u = (j - 0.5 + (n2 - 0.5) * 0.9) / TUFTS
                local tx = x0 + w * u
                local top = y - (u < 0.5 and (tl + (tc - tl) * u * 2) or (tc + (tr - tc) * (u - 0.5) * 2))
                local ty = top + rad * 0.45
                local lift = 0.05 + 0.12 * n2
                local tr2, tg, tb = r + (n1 - 0.5) * 0.06, g + (n2 - 0.5) * 0.05, b
                put(k + 1, tx, ty - rad, tr2 + lift, tg + lift * 1.2, tb + lift * 0.4)
                put(k + 2, tx - rad * 0.85, ty, tr2 * 0.9, tg * 0.9, tb * 0.9)
                put(k + 3, tx + rad * 0.85, ty, tr2 * 0.9, tg * 0.9, tb * 0.9)
                put(k + 4, tx - rad * 0.85, ty, tr2 * 0.9, tg * 0.9, tb * 0.9)
                put(k + 5, tx + rad * 0.85, ty, tr2 * 0.9, tg * 0.9, tb * 0.9)
                put(k + 6, tx, ty + rad * 0.5, tr2 * 0.7, tg * 0.7, tb * 0.7)
                k = k + 6
            end
        end
    end
    mesh:setVertices(verts)
    Render.useObject(C.PLANE_D)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)

    -- After the lamp goes off, moss nobody has cropped catches what light there
    -- is and gives it back gold-green, like goblin's gold in a cave mouth, and
    -- like goblin's gold it shines most in the shade
    local glow = light.glow or 0
    if glow > 0.02 then
        love.graphics.setShader()
        love.graphics.setBlendMode('add')
        for _, s in ipairs(m.spans) do
            for i = s.first, s.first + s.n - 1 do
                local f = min(1, m.h[i] / m.cap[i])
                if f > 0.7 and noise(i, 3) < 0.6 then
                    local a = glow * ((f - 0.7) / 0.3) ^ 2 * (1.1 - 0.6 * m.sun[i]) * (0.6 + 0.4 * sin(time * 0.4 + i))
                    love.graphics.setColor(0.55 * a, 0.62 * a, 0.14 * a, 1)
                    love.graphics.circle('fill', m.x[i] + (noise(i, 5) - 0.5) * s.w, s.y - depth[i] - 0.6, 1.1)
                end
            end
        end
        love.graphics.setBlendMode('alpha')
    end
end

return Moss
