-- From chrischaps/Fishbowl @ b0624e4 (env/substrate.lua)
-- The scape: the room and the desk the jar stands on, the soil bed receding
-- toward the back glass, its layers seen through the front glass, and stones.
-- Terrarium: composed once from rng.scape, so a jar's seed always gives the same
-- scape. The bakes hold the scape's own colours; the day cycle's light is put
-- on as they're drawn (the bed through floor.glsl). The arch, twig, cairn and
-- shelf that bodies stand on are level geometry (jar/room.lua), drawn by
-- jar/scenery.lua.

local C = require("jar.config")
local Tank = require("jar.tank")
local Render = require("jar.render")

local Scape = {}

local gen
local roomCanvas, bedCanvas, frontCanvas
local stones = {}

local function random(a, b)
    if a then return gen:random(a, b) end
    return gen:random()
end

local sin, cos, pi = math.sin, math.cos, math.pi

-- Terrarium: loam, peat and bark tones in place of aquarium sand
local soilTones = {
    { 0.30, 0.21, 0.15 }, { 0.25, 0.18, 0.13 }, { 0.36, 0.26, 0.18 },
    { 0.20, 0.15, 0.11 }, { 0.42, 0.33, 0.24 }, { 0.16, 0.12, 0.10 },
}
local gravelTones = {
    { 0.62, 0.58, 0.52 }, { 0.52, 0.49, 0.45 }, { 0.70, 0.64, 0.55 },
    { 0.44, 0.42, 0.40 }, { 0.58, 0.50, 0.42 }, { 0.36, 0.35, 0.34 },
}
local mossTones = {
    { 0.30, 0.46, 0.20 }, { 0.36, 0.52, 0.24 }, { 0.24, 0.38, 0.17 }, { 0.42, 0.55, 0.26 },
}

local function pick(tones)
    local c = tones[random(#tones)]
    local j = (random() - 0.5) * 0.06
    return c[1] + j, c[2] + j, c[3] + j * 0.8
end

local function pebble(x, y, rx, ry, r, g, b, light)
    -- Contact shadow, body, then a top-lit highlight: reads as a rounded stone
    love.graphics.setColor(r * 0.35, g * 0.33, b * 0.32, 0.55)
    love.graphics.ellipse("fill", x + rx * 0.12, y + ry * 0.35, rx * 1.05, ry * 0.95)
    love.graphics.setColor(r, g, b, 1)
    love.graphics.ellipse("fill", x, y, rx, ry)
    if rx > 1.2 then
        love.graphics.setColor(math.min(1, r * 1.25 + 0.05), math.min(1, g * 1.25 + 0.05), math.min(1, b * 1.22 + 0.05), 0.55 * light)
        love.graphics.ellipse("fill", x - rx * 0.22, y - ry * 0.32, rx * 0.5, ry * 0.42)
    end
end

--------------------------------------------------------------------------------
-- Terrarium: bake the room, the wall behind and the desk under the jar
--------------------------------------------------------------------------------
local DESK_Y -- world y of the desk top (the jar's base)

local function deskPoint(x, d)
    local sx, sy = Tank.project(x, DESK_Y, d)
    return sx, sy
end

local function bakeRoom()
    roomCanvas = love.graphics.newCanvas(C.W, C.H)
    love.graphics.push("all")
    love.graphics.setCanvas(roomCanvas)
    love.graphics.clear(0, 0, 0, 1)

    -- The wall: plaster, darkening upward away from the desk
    local _, wallFoot = deskPoint(C.CX, C.DESK_BACK_D)
    for i = 0, 31 do
        local t = i / 31
        local y0 = wallFoot * t
        love.graphics.setColor(0.07 + 0.07 * t, 0.062 + 0.055 * t, 0.06 + 0.04 * t, 1)
        love.graphics.rectangle("fill", 0, y0, C.W, wallFoot / 31 + 1)
    end

    -- The desk top: walnut, its grain running left to right
    local wood = { 0.40 + (random() - 0.5) * 0.05, 0.27, 0.18 }
    local x0, x1 = -3000, C.W + 3000
    local verts = {}
    local ds = 18
    local function vert(x, d)
        local sx, sy = deskPoint(x, d)
        local t = (d - C.DESK_BACK_D) / (C.DESK_FRONT_D - C.DESK_BACK_D)
        local s = 0.62 + 0.38 * t
        return { sx, sy, 0, 0, wood[1] * s, wood[2] * s, wood[3] * s, 1 }
    end
    for j = 0, ds - 1 do
        local da = Tank.lerp(C.DESK_BACK_D, C.DESK_FRONT_D, j / ds)
        local db = Tank.lerp(C.DESK_BACK_D, C.DESK_FRONT_D, (j + 1) / ds)
        local a, b, c, d = vert(x0, da), vert(x1, da), vert(x1, db), vert(x0, db)
        for _, v in ipairs({ a, b, c, a, c, d }) do verts[#verts + 1] = v end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(love.graphics.newMesh(verts, "triangles", "static"))

    -- Grain: long wavering lines at fixed depths, a few darker figure lines
    love.graphics.setLineWidth(1)
    for _ = 1, 150 do
        local d = Tank.lerp(C.DESK_BACK_D, C.DESK_FRONT_D, random())
        local phase, freq = random() * 10, 0.002 + random() * 0.004
        local amp = 0.01 + random() * 0.03
        local dark = random() < 0.7
        local line = {}
        for x = -200, C.W + 200, 24 do
            local wx = select(1, Tank.unproject(x, 0, d))
            local sx, sy = deskPoint(wx, d + amp * sin(wx * freq + phase))
            line[#line + 1] = sx
            line[#line + 1] = sy
        end
        if dark then
            love.graphics.setColor(0.10, 0.06, 0.04, 0.10 + random() * 0.18)
        else
            love.graphics.setColor(0.55, 0.40, 0.28, 0.06 + random() * 0.08)
        end
        love.graphics.line(line)
    end

    -- The desk's front edge, catching the lamp
    local _, front = deskPoint(C.CX, C.DESK_FRONT_D)
    love.graphics.setColor(wood[1] * 0.45, wood[2] * 0.45, wood[3] * 0.45, 1)
    love.graphics.rectangle("fill", 0, front, C.W, C.H - front)
    love.graphics.setColor(0.70, 0.52, 0.36, 0.35)
    love.graphics.rectangle("fill", 0, front, C.W, 1.5)

    -- Where the wall meets the desk, a line of shadow
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, wallFoot - 1, C.W, 3)
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- Bake: the soil bed (top of the soil, all depths)
--------------------------------------------------------------------------------
local mossPhase = {}

local function mossiness(x, d)
    -- Patches of sheet moss over bare soil, thickest where the lamp falls
    x = x * C.S -- Terrarium: patches keep their size on screen
    local m = 0.5 + 0.28 * sin(x * 0.011 + mossPhase[1] + d * 4.0)
        + 0.22 * sin(x * 0.029 - d * 9.0 + mossPhase[2])
        + 0.18 * cos(x * 0.004 + mossPhase[3])
    return Tank.clamp(m, 0, 1)
end

local function bakeBed()
    bedCanvas = love.graphics.newCanvas(C.W, C.H)
    love.graphics.push("all")
    love.graphics.setCanvas(bedCanvas)
    love.graphics.clear(0, 0, 0, 0)

    -- Base surface as a mesh over the soil top
    local xs, ds = 72, 14
    local x0, x1 = C.GLASS_L, C.GLASS_R
    local verts = {}
    local function vert(x, d)
        local sx, sy = Tank.project(Tank.wx(x), Tank.floorY(x, d), d)
        local m = mossiness(x, d)
        local n = 0.03 * sin(x * 0.013 + d * 7) + 0.02 * sin(x * 0.041 - d * 13)
        local r = Tank.lerp(0.26, 0.27, m) + n
        local g = Tank.lerp(0.19, 0.38, m) + n
        local b = Tank.lerp(0.14, 0.16, m) + n * 0.8
        return { sx, sy, 0, 0, r, g, b, 1 }
    end
    for i = 0, xs - 1 do
        local xa = x0 + (x1 - x0) * i / xs
        local xb = x0 + (x1 - x0) * (i + 1) / xs
        for j = 0, ds - 1 do
            local da, db = j / ds, (j + 1) / ds
            local a, b, c, d = vert(xa, da), vert(xb, da), vert(xb, db), vert(xa, db)
            for _, v in ipairs({ a, b, c, a, c, d }) do verts[#verts + 1] = v end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(love.graphics.newMesh(verts, "triangles", "static"))

    -- Moss cushions and soil crumbs, back to front
    local bits = {}
    for _ = 1, 6500 do
        local d = random() ^ 0.8
        bits[#bits + 1] = { x = x0 + random() * (x1 - x0), d = d, r = 0.7 + random() ^ 3 * 2.6 }
    end
    table.sort(bits, function(a, b) return a.d < b.d end)
    for _, s in ipairs(bits) do
        local sx, sy, k = Tank.project(Tank.wx(s.x), Tank.floorY(s.x, s.d), s.d)
        local moss = random() < mossiness(s.x, s.d)
        local r, g, b = pick(moss and mossTones or soilTones)
        -- Seen at a grazing angle, cushions squash vertically
        pebble(sx, sy - s.r * k * 0.2, s.r * k, s.r * k * 0.5, r, g, b, moss and 1 or 0.4)
    end
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- Bake: the soil's layers against the front glass
--------------------------------------------------------------------------------
-- Terrarium: in place of aquarium gravel, a terrarium's layers: drainage
-- gravel at the bottom, a seam of charcoal, sphagnum, then loam up to the moss.
local function bakeFront()
    -- Terrarium: the face is drawn in world x, from L to R
    local base = Tank.wy(C.GLASS_B - C.GLASS_THICK)
    local L, R = math.floor(Tank.wx(C.GLASS_L)), math.ceil(Tank.wx(C.GLASS_R))
    local top, lowest = {}, 0
    for x = L, R do
        top[x] = Tank.floorY(Tank.lx(x), 1)
        lowest = math.max(lowest, top[x])
    end

    -- Each boundary wanders on its own
    local function boundary(mean, amp)
        local p1, p2, f = random() * 10, random() * 10, 0.012 + random() * 0.01
        return function(x)
            return mean + amp * (0.6 * sin(x * f + p1) + 0.4 * sin(x * f * 2.7 + p2))
        end
    end
    local gravelTop = boundary(base - 46, 5)
    local charcoalTop = boundary(base - 53, 2.5)
    local sphagnumTop = boundary(base - 63, 3.5)

    frontCanvas = love.graphics.newCanvas(C.W, C.H)
    love.graphics.push("all")
    love.graphics.setCanvas({ frontCanvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    local poly = { L, base }
    for x = L, R, 8 do
        poly[#poly + 1] = x
        poly[#poly + 1] = top[x]
    end
    poly[#poly + 1] = R
    poly[#poly + 1] = top[R]
    poly[#poly + 1] = R
    poly[#poly + 1] = base
    local function shape()
        for _, t in ipairs(love.math.triangulate(poly)) do love.graphics.polygon("fill", t) end
    end
    love.graphics.stencil(shape, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    -- Loam: the whole face, then the lower layers over it
    love.graphics.setColor(0.17, 0.12, 0.09, 1)
    shape()
    local function band(upper, lower, r, g, b)
        local pts = {}
        for x = L, R, 6 do pts[#pts + 1] = x; pts[#pts + 1] = upper(x) end
        for x = R, L, -6 do pts[#pts + 1] = x; pts[#pts + 1] = lower(x) end
        love.graphics.setColor(r, g, b, 1)
        for _, t in ipairs(love.math.triangulate(pts)) do love.graphics.polygon("fill", t) end
    end
    local floor = function() return base + 2 end
    band(sphagnumTop, charcoalTop, 0.46, 0.38, 0.26)
    band(charcoalTop, gravelTop, 0.07, 0.07, 0.075)
    band(gravelTop, floor, 0.24, 0.22, 0.20)

    -- Crumbs through the loam, perlite flecks, fibres in the sphagnum
    for _ = 1, 4000 do
        local x = L + random() * (R - L)
        local y = top[math.floor(x)] + random() * (sphagnumTop(x) - top[math.floor(x)])
        local r, g, b = pick(soilTones)
        love.graphics.setColor(r, g, b, 0.9)
        love.graphics.circle("fill", x, y, 0.6 + random() ^ 2 * 2.2)
    end
    for _ = 1, 170 do
        local x = L + random() * (R - L)
        local y = top[math.floor(x)] + 6 + random() * (sphagnumTop(x) - top[math.floor(x)] - 8)
        love.graphics.setColor(0.86, 0.84, 0.78, 0.8)
        love.graphics.circle("fill", x, y, 0.8 + random() * 1.1)
    end
    love.graphics.setLineWidth(0.8)
    for _ = 1, 400 do
        local x = L + random() * (R - L)
        local y = Tank.lerp(sphagnumTop(x), charcoalTop(x), random())
        local a = (random() - 0.5) * 0.9
        local l = 3 + random() * 7
        love.graphics.setColor(0.62, 0.52, 0.36, 0.5)
        love.graphics.line(x, y, x + cos(a) * l, y + sin(a) * l)
    end
    for _ = 1, 780 do
        local x = L + random() * (R - L)
        local y = Tank.lerp(charcoalTop(x), gravelTop(x), random())
        local g = 0.05 + random() * 0.12
        love.graphics.setColor(g, g, g * 1.05, 1)
        love.graphics.rectangle("fill", x, y, 1 + random() * 3, 1 + random() * 2)
    end
    -- Drainage gravel, packed; deeper stones sit in shadow
    for _ = 1, 2000 do
        local x = L + random() * (R - L)
        local gt = gravelTop(x)
        local y = gt - 1 + random() ^ 0.9 * (base - gt + 6)
        local occl = 1 - (y - gt) / (base - gt + 1) * 0.5
        local r = 1.8 + random() ^ 2 * 4.6
        local cr, cg, cb = pick(gravelTones)
        pebble(x, y, r * (0.9 + random() * 0.3), r * (0.75 + random() * 0.25),
            cr * occl, cg * occl, cb * occl, occl)
    end

    -- Roots: fine pale threads reaching down from the moss
    for _ = 1, 40 do
        local x = L + 10 + random() * (R - L - 20)
        local y = top[math.floor(x)] + 2
        local len = 12 + random() * 40
        local line = { x, y }
        local a = pi / 2 + (random() - 0.5) * 0.5
        for _ = 1, 8 do
            a = a + (random() - 0.5) * 0.5
            x, y = x + cos(a) * len / 8, y + sin(a) * len / 8
            line[#line + 1] = x
            line[#line + 1] = y
        end
        love.graphics.setColor(0.78, 0.70, 0.56, 0.35 + random() * 0.25)
        love.graphics.setLineWidth(0.5 + random() * 0.7)
        love.graphics.line(line)
    end

    -- Darken toward the bottom
    local steps = 20
    local deepest = base
    for i = 0, steps - 1 do
        local t = i / steps
        local y = lowest + (deepest - lowest) * t
        love.graphics.setColor(0.03, 0.02, 0.02, t * t * 0.45)
        love.graphics.rectangle("fill", L, y, R - L, (deepest - lowest) / steps + 1)
    end
    love.graphics.setStencilTest()

    -- The moss's edge where it meets the glass
    for x = L, R, 2 do
        local m = mossiness(Tank.lx(x), 1)
        if random() < 0.35 + m * 0.6 then
            local r, g, b = pick(mossTones)
            love.graphics.setColor(r, g, b, 1)
            love.graphics.ellipse("fill", x, top[x] + 1, 1.5 + random() * 2, 1.2 + m * 2)
        end
    end
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- Stones
--------------------------------------------------------------------------------
local stoneStyles = {
    { base = { 0.44, 0.45, 0.46 }, vein = { 0.78, 0.79, 0.78 } },  -- seiryu grey
    { base = { 0.47, 0.41, 0.36 }, vein = { 0.66, 0.58, 0.50 } },  -- warm river stone
    { base = { 0.36, 0.37, 0.38 }, vein = { 0.62, 0.64, 0.64 } },
}

local function bakeStone(w, h, style)
    local pad = 8
    local cw, ch = math.ceil(w + pad * 2), math.ceil(h + pad * 2)
    local canvas = love.graphics.newCanvas(cw, ch)
    local ox, oy = cw / 2, ch - pad  -- ground contact at bottom center

    -- Outline: an irregular dome with a flat buried base
    local pts = {}
    local n = random(7, 11)
    for i = 0, n do
        local a = math.pi + math.pi * i / n
        local rx = w / 2 * (0.8 + random() * 0.25)
        local ry = h * (0.75 + random() * 0.3)
        pts[#pts + 1] = { ox + math.cos(a) * rx, oy + math.sin(a) * ry }
    end
    pts[1][2], pts[#pts][2] = oy + 2, oy + 2

    local peak = { ox - w * 0.12 + (random() - 0.5) * w * 0.15, oy - h * 0.62 }
    local lx, ly = -0.35, -1
    local ll = math.sqrt(lx * lx + ly * ly)
    lx, ly = lx / ll, ly / ll

    love.graphics.push("all")
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    local flat = {}
    for _, p in ipairs(pts) do flat[#flat + 1] = p[1]; flat[#flat + 1] = p[2] end
    flat[#flat + 1] = ox
    flat[#flat + 1] = oy + 2
    local function outline()
        for _, t in ipairs(love.math.triangulate(flat)) do love.graphics.polygon("fill", t) end
    end
    love.graphics.stencil(outline, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    local b = style.base
    love.graphics.setColor(b[1] * 0.7, b[2] * 0.7, b[3] * 0.7)
    outline()

    -- Facets fanned from the peak, shaded by which way they face
    for i = 1, #pts - 1 do
        local p1, p2 = pts[i], pts[i + 1]
        local mx, my = (p1[1] + p2[1]) / 2 - peak[1], (p1[2] + p2[2]) / 2 - peak[2]
        local ml = math.sqrt(mx * mx + my * my) + 0.001
        local face = (mx / ml) * lx + (my / ml) * ly
        local shade = 0.62 + 0.38 * (-face) + (random() - 0.5) * 0.08
        shade = math.max(0.45, math.min(1.15, shade))
        love.graphics.setColor(b[1] * shade, b[2] * shade, b[3] * shade)
        love.graphics.polygon("fill", peak[1], peak[2], p1[1], p1[2], p2[1], p2[2])
    end

    -- Soft vertical gradient: lit top, dark base
    for i = 0, 10 do
        local t = i / 10
        love.graphics.setColor(0, 0, 0, t * t * 0.35)
        love.graphics.rectangle("fill", 0, oy - h * (1 - t), cw, h / 10 + 1)
    end
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.ellipse("fill", peak[1] - w * 0.05, peak[2] + h * 0.1, w * 0.25, h * 0.18)

    -- Mineral veins
    local v = style.vein
    for _ = 1, random(2, 5) do
        local y = oy - h * (0.15 + random() * 0.7)
        local slope = (random() - 0.5) * 0.5
        love.graphics.setColor(v[1], v[2], v[3], 0.25 + random() * 0.25)
        love.graphics.setLineWidth(0.6 + random() * 1.2)
        local line = {}
        for x = 0, cw, 6 do
            line[#line + 1] = x
            line[#line + 1] = y + (x - ox) * slope + math.sin(x * 0.2 + y) * 1.2
        end
        love.graphics.line(line)
    end

    -- Specks and pits
    for _ = 1, math.floor(w * h / 40) do
        local x, y = ox + (random() - 0.5) * w, oy - random() * h
        local dark = random() < 0.6
        love.graphics.setColor(dark and 0 or 1, dark and 0 or 1, dark and 0 or 1, 0.08 + random() * 0.08)
        love.graphics.circle("fill", x, y, 0.5 + random() * 1.2)
    end

    -- Terrarium: moss creeping over the shaded foot of the stone
    for _ = 1, math.floor(w * 0.9) do
        local x = ox + (random() - 0.5) * w * 0.95
        local y = oy - random() ^ 2.2 * h * 0.55
        local r, g, bb = pick(mossTones)
        love.graphics.setColor(r * 0.9, g * 0.9, bb * 0.9, 0.85)
        love.graphics.circle("fill", x, y, 0.8 + random() * 1.8)
    end

    love.graphics.setStencilTest()

    -- Soil banked against the base
    for _ = 1, math.floor(w / 2) do
        local x = ox + (random() - 0.5) * w * 1.1
        local r, g, bb = pick(soilTones)
        love.graphics.setColor(r, g, bb, 0.9)
        love.graphics.ellipse("fill", x, oy + 1 - random() * 3, 1 + random() * 2.5, 0.8 + random() * 1.2)
    end
    love.graphics.pop()

    return canvas, ox, oy
end

-- Terrarium: x is in level coordinates; small stones are pebbles drawn directly
local function addStone(x, d, w, h)
    local s = { kind = "stone", x = x, d = d, w = w, h = h, y = Tank.floorY(x, d) }
    if w > 14 then
        s.canvas, s.ox, s.oy = bakeStone(w, h, stoneStyles[random(#stoneStyles)])
    else
        s.color = { pick(gravelTones) }
    end
    stones[#stones + 1] = s
end

-- Terrarium: the composition. Big stones stand toward the back, where they
-- fall out of focus; a few pebbles lie between the creatures and the glass.
local function compose()
    stones = {}
    local n = random(8, 11)
    for i = 1, n do
        local x = Tank.lerp(C.GLASS_L + 40, C.GLASS_R - 40, (i - 0.5 + (random() - 0.5) * 0.7) / n)
        local d = 0.04 + random() ^ 1.4 * 0.5
        local w = 70 + random() * 110 * (1 - d)
        addStone(x, d, w, w * (0.42 + random() * 0.3))
    end
    for _ = 1, random(1, 2) do
        local left = random() < 0.5
        local x = left and C.GLASS_L + 30 + random() * 120 or C.GLASS_R - 30 - random() * 120
        addStone(x, 0.78 + random() * 0.14, 22 + random() * 18, 10 + random() * 8)
    end
    for _ = 1, random(26, 44) do
        local x = C.GLASS_L + 8 + random() * (C.GLASS_R - C.GLASS_L - 16)
        local r = 1.5 + random() ^ 2 * 4
        addStone(x, 0.76 + random() * 0.22, r * 2, r)
    end
    table.sort(stones, function(a, b) return a.d < b.d end)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
function Scape.init(generator)
    gen = generator
    DESK_Y = Tank.wy(C.GLASS_B)
    mossPhase = { random() * 10, random() * 10, random() * 10 }
    bakeRoom()
    bakeBed()
    bakeFront()
    compose()
end

function Scape.getStones() return stones end

--- Terrarium: the lamp hangs on its cord to just above the lid, which in a tall
--- jar is near the top of the view. This is its shade's top; its lit rim is 58 below.
function Scape.lampHang() return Tank.wy(C.GLASS_T - C.LID_THICK) - 76 end
Scape.LAMP_RIM = 58

--- The room and desk (drawn into the room layer, which is blurred)
function Scape.drawRoom(light)
    local rm = light.room
    love.graphics.setColor(rm[1], rm[2], rm[3], 1)
    love.graphics.draw(roomCanvas)

    love.graphics.push("all")
    -- Terrarium: after the lamp goes off, the moon through a window to the left
    -- lays its panes across the wall and the desk
    if light.moon > 0.01 then
        local m = light.moon
        love.graphics.setBlendMode("add")
        love.graphics.push()
        love.graphics.translate(150, 120)
        love.graphics.shear(0.42, 0)
        for i = 0, 3 do
            local px, py = (i % 2) * 74, math.floor(i / 2) * 104
            love.graphics.setColor(0.035 * m, 0.045 * m, 0.075 * m, 1)
            love.graphics.rectangle("fill", px, py, 66, 96)
            Render.drawBlob(px + 33, py + 48, 52, 70)
        end
        love.graphics.pop()
        love.graphics.setColor(0.05 * m, 0.07 * m, 0.11 * m, 1)
        Render.drawBlob(260, DESK_Y + 30, 360, 60)
        love.graphics.setBlendMode("alpha")
    end

    -- The jar's shadow on the desk: sharp under the lamp, faint by moonlight
    local sx, sy = Tank.project(C.CX, DESK_Y, 0.55)
    love.graphics.setColor(0, 0, 0, 0.18 + 0.37 * light.lamp_i)
    Render.drawBlob(sx, sy + 6, (C.GLASS_R - C.GLASS_L) * C.S * 0.62, 46)

    -- The lamp's pool of light, on the wall and on the desk around the jar
    local hang = Scape.lampHang()
    local rim = hang + Scape.LAMP_RIM
    local l = light.lamp
    love.graphics.setBlendMode("add")
    love.graphics.setColor(l[1] * 0.10, l[2] * 0.10, l[3] * 0.10, 1)
    Render.drawBlob(C.CX, hang + 170, 900, 420)
    love.graphics.setColor(l[1] * 0.22, l[2] * 0.20, l[3] * 0.18, 1)
    Render.drawBlob(C.CX, sy + 20, 1100, 150)

    -- The lamp itself, hung just above the jar: a dark shade, a lit rim
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(0.05 * rm[1], 0.045 * rm[2], 0.04 * rm[3], 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(C.CX, -10, C.CX, hang)
    love.graphics.polygon("fill", C.CX - 38, hang - 10, C.CX + 38, hang - 10, C.CX + 92, rim, C.CX - 92, rim)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(l[1] * 0.9, l[2] * 0.9, l[3] * 0.9, 1)
    love.graphics.ellipse("fill", C.CX, rim, 88, 6)
    love.graphics.setColor(l[1] * 0.35, l[2] * 0.35, l[3] * 0.35, 1)
    Render.drawBlob(C.CX, hang + 64, 220, 46)
    love.graphics.pop()
end

--- The soil top, lit and hazed per pixel by its depth
function Scape.drawBed(light)
    love.graphics.setColor(1, 1, 1, 1)
    Render.useFloor(light)
    love.graphics.draw(bedCanvas)
    love.graphics.setShader()
end

--- The soil's layers through the front glass (in front of everything in the jar).
-- Terrarium: lit by the room, not the lamp, which is above and behind the glass.
function Scape.drawFront(light)
    local a = light.ambient
    love.graphics.setColor(a[1] * 0.92, a[2] * 0.92, a[3] * 0.92, 1)
    love.graphics.draw(frontCanvas)
end

--- A stone or pebble, lit and hazed by its depth
function Scape.drawStone(s)
    local sx, sy, k = Tank.project(Tank.wx(s.x), s.y, s.d)
    Render.useObject(s.d)
    if s.canvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(s.canvas, sx, sy + 2 * k, 0, k, k, s.ox, s.oy)
    else
        local c = s.color
        pebble(sx, sy - s.h * k * 0.4, s.w * 0.5 * k, s.h * 0.6 * k, c[1], c[2], c[3], 1)
    end
end

return Scape
