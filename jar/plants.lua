-- From chrischaps/Fishbowl @ b0624e4 (env/plants.lua)
-- Living plants. Fronds are chains of angular springs that sway and part
-- around passing creatures.
-- Terrarium: no water and no current, so nothing floats or pearls. Fishbowl's
-- vallisneria and rotala are gone. What's left is what grows in a jar of moss:
--   fern  : small ferns peeking out from behind the stones (Fishbowl's java fern)
--   spore : tufts of moss sporophytes, a thin red-gold stalk with a capsule at
--           its tip (Fishbowl's carpet grass). A few capsules hold goblin's gold
--           and glow faintly once the lamp is off.
-- Composed once from rng.scape and stepped on the fixed step as World's flora,
-- so every frame is the same for the same jar. Positions are in level
-- coordinates (x, y) plus a depth d; they never touch the simulation.

local C = require("jar.config")
local Tank = require("jar.tank")
local Render = require("jar.render")

local Plants = {}

local sin, cos, sqrt, abs, min, max, pi = math.sin, math.cos, math.sqrt, math.abs, math.min, math.max, math.pi

local gen
local list = {}
local time = 0

local function random(a, b)
    if a then return gen:random(a, b) end
    return gen:random()
end

local function soilY(x, d) return Tank.ly(Tank.floorY(x, d)) end

--------------------------------------------------------------------------------
-- Angular spring chains
--------------------------------------------------------------------------------
-- Each node holds an absolute angle from vertical. A springiness pulls every
-- node toward its rest angle, bending stiffness couples neighbours, and
-- passing creatures push them aside.
local function newChain(n, length, lean, stiffness, droop)
    local c = { n = n, seg = length / n, a = {}, w = {}, rest = {}, x = {}, y = {}, stiff = stiffness or 1 }
    local curve = (random() - 0.5) * 0.15
    for i = 1, n do
        local s = i / n
        c.rest[i] = lean + curve * s + (droop or 0) * s * s * (lean >= 0 and 1 or -1)
        c.a[i], c.w[i] = c.rest[i], 0
        c.x[i], c.y[i] = 0, 0
    end
    c.phase = random() * 10
    return c
end

local function layout(c, bx, by)
    local x, y = bx, by
    for i = 1, c.n do
        x = x + sin(c.a[i]) * c.seg
        y = y - cos(c.a[i]) * c.seg
        c.x[i], c.y[i] = x, y
    end
end

-- How hard the creatures nearby push at (x, y), as a sideways torque.
-- Terrarium: only plants close to the creatures' plane are within reach.
local function push(x, y, d, near)
    local dz = abs(d - C.PLANE_D)
    if dz > 0.1 or not near then return 0 end
    local t = 0
    for _, f in ipairs(near) do
        local dx, dy = x - f.x, y - f.y
        local r = f.r + 8
        local d2 = dx * dx + dy * dy
        if d2 < r * r then
            local p = (1 - sqrt(d2) / r) * (1 - dz / 0.1)
            t = t + (f.vx * 0.0012 + (dx >= 0 and 1 or -1) * 0.03) * p
        end
    end
    return t
end

local function simulate(c, dt, bx, by, d, near, flex)
    layout(c, bx, by)
    local n = c.n
    for i = 1, n do
        local s = i / n
        -- A slow sway of its own: the jar's air is still, but never quite
        local torque = (sin(time * 0.35 + c.phase + i * 0.35) * 0.004 + push(c.x[i], c.y[i], d, near)) * flex * (0.4 + s)
        local spring = c.stiff * (1.6 - 0.9 * s)
        local prev = (i == 1) and c.rest[1] or c.a[i - 1]
        local nxt = (i == n) and c.a[i] or c.a[i + 1]
        local bend = (prev + nxt - 2 * c.a[i]) * 6 * c.stiff
        c.w[i] = c.w[i] + (torque * 30 - spring * (c.a[i] - c.rest[i]) + bend - 2.0 * c.w[i]) * dt
    end
    for i = 1, n do
        c.a[i] = max(-1.3, min(1.3, c.a[i] + c.w[i] * dt))
    end
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------
local function addFern(x, y, d, count, size)
    local p = { kind = "plant", type = "fern", x = x, d = d, y = y, leaves = {} }
    for i = 1, count do
        local lean = (i / count - 0.5) * 1.9 + (random() - 0.5) * 0.3
        local c = newChain(6, (30 + random() * 30) * size, lean, 1.6, 0.6)
        c.width = (6 + random() * 4) * size
        c.mesh = love.graphics.newMesh(c.n * 2 + 2, "strip", "stream")
        c.dark = 0.85 + random() * 0.25
        layout(c, x, y) -- so it can be drawn before its first step
        p.leaves[i] = c
    end
    list[#list + 1] = p
end

local function addSpores(x, d, count, y)
    local p = { kind = "plant", type = "spore", x = x, d = d, y = y or (soilY(x, d) + 1), blades = {}, cushion = {} }
    for i = 1, count do
        p.blades[i] = {
            ox = (random() - 0.5) * 16, len = 9 + random() * 16,
            lean = (random() - 0.5) * 0.5, phase = random() * 10,
            a = 0, w = 0, ripe = random(),  -- ripe: green capsule (0) to brown (1)
            glows = random() < 0.18,
        }
    end
    -- The moss cushion the stalks rise from
    for i = 1, 9 do
        p.cushion[i] = { ox = (random() - 0.5) * 22, r = 1.4 + random() * 2.2, g = 0.40 + random() * 0.14 }
    end
    list[#list + 1] = p
end

--- Compose the plants for this jar. Ferns take root behind the larger stones.
-- Terrarium: `ledges` are the level's mossed solids; a few tufts grow on top.
function Plants.init(generator, stones, ledges)
    gen = generator
    list = {}
    time = 0

    -- Terrarium: a stone's size is in world px, and a fern keeps its size on
    -- screen, so it towers over the residents (whose level units are 1/C.S px)
    local big = 1 / C.S
    for _, s in ipairs(stones or {}) do
        if s.canvas and random() < 0.75 then
            local side = random() < 0.5 and -1 or 1
            local x = s.x + side * s.w * big * (0.18 + random() * 0.2)
            addFern(x, soilY(x, s.d) - s.h * big * (0.15 + random() * 0.25), s.d - 0.01, random(4, 6),
                (0.9 + random() * 0.5) * big)
        end
    end
    -- And in the back corners, where the glass meets
    local x = C.GLASS_L + 50 + random() * 50
    addFern(x, soilY(x, 0.03), 0.03, random(5, 7), 1.3 * big)
    x = C.GLASS_R - 50 - random() * 50
    addFern(x, soilY(x, 0.05), 0.05, random(5, 7), 1.2 * big)

    -- Sporophyte tufts: scattered behind, a few where the creatures walk through
    -- them, a few just inside the front glass
    for _ = 1, 24 do
        addSpores(C.GLASS_L + 20 + random() * (C.GLASS_R - C.GLASS_L - 40), 0.10 + random() * 0.5, random(5, 10))
    end
    for _ = 1, 12 do
        addSpores(C.GLASS_L + 30 + random() * (C.GLASS_R - C.GLASS_L - 60), C.PLANE_D + (random() - 0.5) * 0.06, random(6, 11))
    end
    for _ = 1, 8 do
        local x = C.GLASS_L + 16 + random() * (C.GLASS_R - C.GLASS_L - 32)
        if abs(x - C.LAMP_X) > 240 then addSpores(x, 0.86 + random() * 0.1, random(4, 8)) end
    end

    -- Terrarium: on the scenery's tops, just behind the creatures' plane, so
    -- the stalks rise from the far edge and part as something walks past
    for _, s in ipairs(ledges or {}) do
        local tufts = math.floor(s.w / 70 + random())
        for _ = 1, tufts do
            local x = s.x + 10 + random() * (math.min(s.x + s.w, C.GLASS_R) - s.x - 20)
            addSpores(x, C.PLANE_D - 0.004, random(3, 6), s.y + 1)
        end
    end
end

function Plants.all() return list end

--- World's flora hook: step on the fixed step with the creatures' influencers
function Plants:update(dt, near)
    time = time + dt
    for _, p in ipairs(list) do
        if p.leaves then
            for _, c in ipairs(p.leaves) do simulate(c, dt, p.x, p.y, p.d, near, 0.4) end
        else
            for _, b in ipairs(p.blades) do
                local tip = p.y - b.len
                local t = push(p.x + b.ox, tip, p.d, near)
                b.w = b.w + (t * 40 - 9 * b.a - 3 * b.w) * dt
                b.a = max(-1.1, min(1.1, b.a + b.w * dt))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local stripVerts = {}
-- Terrarium: where each capsule was last drawn, on screen, for its glow. Kept
-- here and not on the blade, which is sim state (statehash reads it, #94).
local tips = setmetatable({}, { __mode = 'k' })
for i = 1, 64 do stripVerts[i] = { 0, 0, 0, 0, 1, 1, 1, 1 } end

local function drawRibbon(c, d, bx, by, colorAt, widthAt)
    local n = c.n
    local idx = 0
    local function put(x, y, s, side)
        local sx, sy = Tank.level(x, y, d)
        idx = idx + 1
        local v = stripVerts[idx]
        v[1], v[2] = sx, sy
        local r, g, b, a = colorAt(s, side)
        v[5], v[6], v[7], v[8] = r, g, b, a
    end
    put(bx - 1, by, 0, -1)
    put(bx + 1, by, 0, 1)
    local px, py = bx, by
    for i = 1, n do
        local x, y = c.x[i], c.y[i]
        local nx_, ny_ = c.x[min(n, i + 1)], c.y[min(n, i + 1)]
        local tx, ty = nx_ - px, ny_ - py
        local tl = sqrt(tx * tx + ty * ty) + 1e-6
        local nx, ny = -ty / tl, tx / tl
        local s = i / n
        local w = widthAt(s)
        put(x - nx * w, y - ny * w, s, -1)
        put(x + nx * w, y + ny * w, s, 1)
        px, py = x, y
    end
    c.mesh:setVertices(stripVerts, 1, idx)
    c.mesh:setDrawRange(1, idx)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(c.mesh)
end

local function drawFern(p)
    for _, c in ipairs(p.leaves) do
        drawRibbon(c, p.d, p.x, p.y,
            function(s, side)
                -- The underside of a frond is paler; the tips are new growth
                local k = c.dark * (0.8 + 0.2 * s) * (side > 0 and 1 or 0.86)
                return (0.15 + 0.08 * s ^ 3) * k, (0.33 + 0.10 * s ^ 3) * k, 0.13 * k, 1
            end,
            function(s)
                local blade = sin(pi * min(1, (s - 0.12) / 0.88)) ^ 0.7
                if s < 0.12 then blade = 0.08 end
                -- Pinnae: the frond's edge is a row of small lobes
                return c.width * blade * (1 + 0.22 * abs(sin(s * 34)))
            end)
        local pts = {}
        local sx, sy = Tank.level(p.x, p.y, p.d)
        pts[1], pts[2] = sx, sy
        for i = 1, c.n - 1 do
            local x, y = Tank.level(c.x[i], c.y[i], p.d)
            pts[#pts + 1] = x
            pts[#pts + 1] = y
        end
        love.graphics.setLineWidth(0.8)
        love.graphics.setColor(0.34, 0.50, 0.22, 0.5)
        love.graphics.line(pts)
        love.graphics.setLineWidth(1)
    end
end

-- A stalk's tip, swaying on its own and bent by whatever brushed past
local function sporeTip(p, b)
    local sway = sin(time * 0.6 + b.phase) * 0.05 + b.lean + b.a
    return p.x + b.ox + sin(sway) * b.len, p.y - cos(sway) * b.len, sway
end

local function drawSpores(p)
    local k = Tank.k(p.d)
    for _, m in ipairs(p.cushion) do
        local x, y = Tank.level(p.x + m.ox, p.y, p.d)
        love.graphics.setColor(0.22, m.g, 0.15, 1)
        love.graphics.ellipse("fill", x, y - m.r * k * 0.3, m.r * k * 1.3, m.r * k * 0.8)
    end
    love.graphics.setLineWidth(0.9 * k)
    for _, b in ipairs(p.blades) do
        local bx = p.x + b.ox
        local tx, ty, sway = sporeTip(p, b)
        local x1, y1 = Tank.level(bx, p.y, p.d)
        local mx, my = Tank.level(bx + sin(sway) * b.len * 0.35, p.y - b.len * 0.55, p.d)
        local x2, y2 = Tank.level(tx, ty, p.d)
        -- The seta: red-brown at the foot, gold toward the capsule
        love.graphics.setColor(0.42, 0.20, 0.12, 1)
        love.graphics.line(x1, y1, mx, my)
        love.graphics.setColor(0.66, 0.42, 0.18, 1)
        love.graphics.line(mx, my, x2, y2)
        -- The capsule nods at the tip, green while young, brown when ripe
        local r = Tank.lerp(0.40, 0.46, b.ripe)
        local g = Tank.lerp(0.50, 0.30, b.ripe)
        love.graphics.push()
        love.graphics.translate(x2, y2)
        love.graphics.rotate(sway + 0.5 + b.lean)
        love.graphics.setColor(r, g, 0.16, 1)
        love.graphics.ellipse("fill", 0, -1.2 * k, 1.3 * k, 2.4 * k)
        love.graphics.setColor(0.78, 0.70, 0.50, 0.8)
        love.graphics.ellipse("fill", 0, -3.4 * k, 0.8 * k, 0.9 * k)
        love.graphics.pop()
        local tip = tips[b] or {}
        tip[1], tip[2], tips[b] = x2, y2, tip
    end
    love.graphics.setLineWidth(1)
end

-- Terrarium: where a plant is drawn, in the frame's px (pencil-each, #95,
-- draws each on its own): its fronds as they lie now, or its stalks' reach
function Plants.bounds(p)
    local k = Tank.k(p.d)
    if p.leaves then
        local x0, y0 = Tank.level(p.x, p.y, p.d)
        local x1, y1 = x0, y0
        for _, c in ipairs(p.leaves) do
            for i = 1, c.n do
                local x, y = Tank.level(c.x[i], c.y[i], p.d)
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            end
        end
        local pad = 16 * k
        return x0 - pad, y0 - pad, x1 + pad, y1 + pad
    end
    local x0, y0 = Tank.level(p.x - 24, p.y - 40, p.d)
    local x1, y1 = Tank.level(p.x + 24, p.y + 8, p.d)
    return x0, y0, x1, y1
end

function Plants.draw(p)
    Render.useObject(p.d)
    if p.type == "fern" then drawFern(p)
    else drawSpores(p) end
end

--- Goblin's gold: a few capsules glow once the lamp is off, drawn additively
-- after the scene. Terrarium: in place of Fishbowl's bioluminescent tips.
function Plants.drawGlow(env)
    local g = env.glow
    if g < 0.05 then return end
    love.graphics.push("all")
    love.graphics.setBlendMode("add")
    for _, p in ipairs(list) do
        if p.blades then
            local fade = 1 - Tank.haze(p.d) * 0.6
            for _, b in ipairs(p.blades) do
                local tip = tips[b]
                if b.glows and tip then
                    local pulse = 0.6 + 0.4 * sin(time * 0.5 + b.phase)
                    love.graphics.setColor(0.45, 0.85, 0.40, 0.30 * g * pulse * fade)
                    Render.drawBlob(tip[1], tip[2], 7 * Tank.k(p.d))
                    love.graphics.setColor(0.80, 1.00, 0.70, 0.45 * g * pulse * fade)
                    Render.drawBlob(tip[1], tip[2], 2.2 * Tank.k(p.d))
                end
            end
        end
    end
    love.graphics.pop()
end

return Plants
