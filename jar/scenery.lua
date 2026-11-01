-- Scenery: the solids the creatures stand on, drawn.
-- The cork-bark arch, the standing stone and the cairn, the twig between them,
-- the basalt stair, the stump with its branch and its bracket of fungus, the
-- slate shelf and the water dish under the twig. Each is baked once from
-- rng.scape at load (raw colours; the light goes on at draw time through the
-- object shader, like the scape) and drawn on the creatures' plane in level
-- coordinates.
--
-- The body never lies: every silhouette fills its solids and stays inside
-- them, except a few strands of moss and a fringe at the edges, so a foot
-- lands on what you see.

local Render = require("jar.render")
local C = require("jar.config")
local Matte = require("jar.matte")

local Scenery = {}

local SCALE = 2 -- bakes are drawn at twice the level's resolution
local PAD = 14  -- room around a piece for moss, fringe and its shadow

local gen
local pieces = {}
local water

local sin, cos, pi, min, max, floor = math.sin, math.cos, math.pi, math.min, math.max, math.floor

local function random(a, b)
    if a then return gen:random(a, b) end
    return gen:random()
end

local function jitter(c, j)
    local k = (random() - 0.5) * j
    return { c[1] + k, c[2] + k, c[3] + k * 0.8 }
end

local tones = {
    cork  = { base = { 0.33, 0.22, 0.14 }, ridge = { 0.50, 0.36, 0.23 }, crack = { 0.13, 0.08, 0.05 } },
    twig  = { base = { 0.38, 0.31, 0.25 }, ridge = { 0.55, 0.47, 0.38 }, crack = { 0.18, 0.14, 0.11 } },
    stone = { base = { 0.47, 0.45, 0.42 }, ridge = { 0.66, 0.63, 0.57 }, crack = { 0.26, 0.25, 0.24 } },
    slate = { base = { 0.29, 0.31, 0.34 }, ridge = { 0.45, 0.48, 0.51 }, crack = { 0.14, 0.15, 0.17 } },
    basalt = { base = { 0.25, 0.25, 0.26 }, ridge = { 0.40, 0.40, 0.41 }, crack = { 0.10, 0.10, 0.11 } },
    fungus = { base = { 0.52, 0.36, 0.20 }, ridge = { 0.72, 0.56, 0.36 }, crack = { 0.30, 0.18, 0.10 },
        pale = { 0.93, 0.89, 0.78 } },
}
local mossTones = {
    { 0.30, 0.46, 0.20 }, { 0.36, 0.52, 0.24 }, { 0.24, 0.38, 0.17 }, { 0.42, 0.56, 0.26 },
}
local lichen = { { 0.62, 0.68, 0.52 }, { 0.70, 0.72, 0.60 }, { 0.55, 0.63, 0.47 } }

--------------------------------------------------------------------------------
-- Shapes: outlines in a piece's own (unscaled) coordinates
--------------------------------------------------------------------------------

-- A rectangle with rounded corners whose sides wander by up to `wobble`
-- inward. The top stays flat between its corners: creatures walk on it.
local function outline(x, y, w, h, r, wobble, flatTop)
    r = min(r, w / 2, h / 2)
    local pts = {}
    local function add(px, py) pts[#pts + 1] = px; pts[#pts + 1] = py end
    local function corner(cx, cy, a0)
        for i = 0, 4 do
            local a = a0 + (pi / 2) * i / 4
            add(cx + cos(a) * r, cy + sin(a) * r)
        end
    end
    local function side(x0, y0, x1, y1, nx, ny, flat)
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local n = max(1, floor(len / 7))
        for i = 1, n - 1 do
            local t = i / n
            local inset = flat and 0 or random() * wobble
            add(x0 + (x1 - x0) * t - nx * inset, y0 + (y1 - y0) * t - ny * inset)
        end
    end
    corner(x + r, y + r, pi)                                   -- top left
    side(x + r, y, x + w - r, y, 0, -1, flatTop)
    corner(x + w - r, y + r, -pi / 2)                          -- top right
    side(x + w, y + r, x + w, y + h - r, 1, 0)
    corner(x + w - r, y + h - r, 0)                            -- bottom right
    side(x + w - r, y + h, x + r, y + h, 0, 1)
    corner(x + r, y + h - r, pi / 2)                           -- bottom left
    side(x, y + h - r, x, y + r, -1, 0)
    return pts
end

local function fillOutline(pts)
    local ok, tris = pcall(love.math.triangulate, pts)
    if ok then
        for _, t in ipairs(tris) do love.graphics.polygon("fill", t) end
    else
        love.graphics.polygon("fill", pts)
    end
end

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------

-- Bark, stone or slate grain across a rectangle. `along` is the grain's
-- direction: "x" runs it lengthways, "y" up and down, "o" is no direction.
local function grain(t, x, y, w, h, along, density)
    local n = floor(w * h / (density or 14))
    for _ = 1, n do
        local px, py = x + random() * w, y + random() * h
        local long, short = 2 + random() * 7, 0.8 + random() * 1.6
        local rx, ry = long, short
        if along == "y" then rx, ry = short, long
        elseif along == "o" then rx, ry = short * 1.4, short end -- stone: blotches, no grain
        local c = random() < 0.55 and t.ridge or t.crack
        local k = (random() - 0.5) * 0.08
        love.graphics.setColor(c[1] + k, c[2] + k, c[3] + k, 0.35 + random() * 0.4)
        love.graphics.ellipse("fill", px, py, rx, ry)
    end
end

-- Top-lit: brighter along the top, darker toward the underside
local function shade(x, y, w, h, topLight, underDark)
    for i = 0, 11 do
        local t = i / 11
        love.graphics.setColor(0, 0, 0, (t ^ 1.6) * (underDark or 0.45))
        love.graphics.rectangle("fill", x, y + h * t, w, h / 11 + 1)
    end
    love.graphics.setColor(1, 1, 1, topLight or 0.12)
    love.graphics.rectangle("fill", x, y, w, min(3, h * 0.2))
end

-- A few strands of moss spilling over the front of a top at its ends. The moss
-- on the top itself is alive (jar/moss.lua), so it isn't baked in.
local function mossTop(x, y, w, ends)
    -- Strands over the ends, short enough not to be mistaken for anything to hold
    for _, ex in ipairs(ends or {}) do
        for _ = 1, random(2, 4) do
            local px = ex + (random() - 0.5) * 6
            local len = 3 + random() * 6
            local c = mossTones[random(#mossTones)]
            love.graphics.setColor(c[1] * 0.9, c[2] * 0.9, c[3] * 0.9, 0.85)
            love.graphics.setLineWidth(0.9)
            love.graphics.line(px, y + 1, px + (random() - 0.5) * 2, y + 1 + len)
        end
    end
end

local function lichenSpots(x, y, w, h, count)
    for _ = 1, count do
        local cx, cy = x + random() * w, y + random() * h
        local c = lichen[random(#lichen)]
        for _ = 1, random(3, 7) do
            love.graphics.setColor(c[1], c[2], c[3], 0.55 + random() * 0.3)
            love.graphics.circle("fill", cx + (random() - 0.5) * 5, cy + (random() - 0.5) * 3, 0.5 + random() * 1.1)
        end
    end
end

--------------------------------------------------------------------------------
-- Materials. Each draws a piece in its own coordinates: (0, 0) is the top left
-- of its bounding box, and `rects` are its solids relative to that.
--------------------------------------------------------------------------------
local paint = {}

-- Cork bark: a curl of it standing on one foot. Deep knobbly furrows, a pale
-- lichen here and there, moss along the top. Its grain runs along it, so up and
-- down a foot, or a stump stood on end.
local function lengthways(r) return r.main and r.h <= r.w * 2 end

function paint.cork(piece)
    local t = tones.cork
    local shapes = {}
    for _, r in ipairs(piece.rects) do
        local radius = r.main and 7 or 5
        shapes[#shapes + 1] = { r = r, pts = outline(r.x, r.y, r.w, r.h, radius, 2, r.main) }
    end
    -- Fillets where the foot and the lip meet the slab, so it reads as one curl
    local main = piece.rects[1]
    local fillets = {}
    for _, r in ipairs(piece.rects) do
        if not r.main then
            local fy = main.y + main.h
            fillets[#fillets + 1] = { r.x - 6, fy, r.x, fy, r.x, fy + 7 }
            fillets[#fillets + 1] = { r.x + r.w, fy, r.x + r.w + 6, fy, r.x + r.w, fy + 7 }
        end
    end
    local function silhouette()
        for _, s in ipairs(shapes) do fillOutline(s.pts) end
        for _, f in ipairs(fillets) do love.graphics.polygon("fill", f) end
    end

    love.graphics.stencil(silhouette, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(t.base)
    love.graphics.rectangle("fill", 0, 0, piece.w, piece.h)
    for _, s in ipairs(shapes) do
        local r = s.r
        grain(t, r.x, r.y, r.w, r.h, lengthways(r) and "x" or "y", 9)
    end
    -- Cork's deep crevices wander along the grain, a warm ridge lit above each
    for _, s in ipairs(shapes) do
        local r = s.r
        local along = lengthways(r)
        local across = along and r.h or r.w
        for k = 1, max(2, floor(across / 4)) do
            local off = across * (k - 0.5 + (random() - 0.5) * 0.5) / max(2, floor(across / 4))
            local f, ph, amp = 0.05 + random() * 0.08, random() * 6, 0.8 + random() * 1.4
            local line, ridge = {}, {}
            local len = along and r.w or r.h
            for u = 0, len, 3 do
                local v = off + sin(u * f + ph) * amp
                if along then
                    line[#line + 1], line[#line + 2] = r.x + u, r.y + v
                    ridge[#ridge + 1], ridge[#ridge + 2] = r.x + u, r.y + v - 1.2
                else
                    line[#line + 1], line[#line + 2] = r.x + v, r.y + u
                    ridge[#ridge + 1], ridge[#ridge + 2] = r.x + v - 1.2, r.y + u
                end
            end
            if #line >= 4 then
                love.graphics.setLineWidth(1)
                love.graphics.setColor(t.ridge[1] * 1.1, t.ridge[2] * 1.05, t.ridge[3], 0.45)
                love.graphics.line(ridge)
                love.graphics.setLineWidth(1.3)
                love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.8)
                love.graphics.line(line)
            end
        end
    end
    -- The slab's underside is the curl's hollow: darker, with fine fibres
    if lengthways(main) then
        love.graphics.setColor(0.08, 0.05, 0.03, 0.55)
        love.graphics.rectangle("fill", main.x, main.y + main.h - 5, main.w, 6)
    end
    for _, r in ipairs(piece.rects) do shade(r.x, r.y, r.w, r.h, 0.10, r.main and 0.35 or 0.55) end
    lichenSpots(main.x + 10, main.y + 4, main.w - 20, main.h - 8, random(2, 4))
    love.graphics.setStencilTest()
    mossTop(main.x + 3, main.y, main.w - 6, { main.x + 8, main.x + main.w - 8 })
end

-- Stone: the standing stone is one upright, the cairn three flat stones stacked
function paint.stone(piece)
    local t = tones.stone
    local r = piece.rects[1]
    local layers = {}
    if r.h > 60 and r.w > 50 then
        -- A cairn: heights from the bottom up, each stone a little different
        local hs = { 0.36, 0.30, 0.34 }
        local y = r.y + r.h
        for i = 1, 3 do
            local h = r.h * hs[i]
            y = y - h
            layers[#layers + 1] = { x = r.x + random() * 2, y = y, w = r.w - random() * 4, h = h, top = (i == 3) }
        end
        layers[3].y, layers[3].h = r.y, layers[3].h + (layers[3].y - r.y)
    else
        layers[1] = { x = r.x, y = r.y, w = r.w, h = r.h, top = true, upright = true }
    end

    for _, l in ipairs(layers) do
        local radius = l.upright and 10 or min(12, l.h * 0.45)
        local pts = outline(l.x, l.y, l.w, l.h, radius, l.upright and 1.5 or 2.5, l.top)
        local base = jitter(t.base, 0.08)
        love.graphics.stencil(function() fillOutline(pts) end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(base)
        love.graphics.rectangle("fill", l.x, l.y, l.w, l.h)
        grain(t, l.x, l.y, l.w, l.h, "o", 10)
        -- A vein or two of quartz
        for _ = 1, random(1, 2) do
            local vy = l.y + l.h * (0.25 + random() * 0.5)
            local slope = (random() - 0.5) * 0.4
            love.graphics.setColor(0.80, 0.79, 0.74, 0.25 + random() * 0.2)
            love.graphics.setLineWidth(0.6 + random() * 0.8)
            love.graphics.line(l.x, vy, l.x + l.w, vy + slope * l.w)
        end
        shade(l.x, l.y, l.w, l.h, 0.14, 0.5)
        -- Where one stone sits on the next
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", l.x, l.y + l.h - 2, l.w, 2)
        love.graphics.setStencilTest()
    end
    -- Moss in the seams and over the top
    for i = 1, #layers - 1 do
        local l = layers[i]
        for _ = 1, floor(l.w / 4) do
            local c = mossTones[random(#mossTones)]
            love.graphics.setColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 0.8)
            love.graphics.circle("fill", l.x + random() * l.w, l.y + random() * 2, 0.7 + random() * 1.1)
        end
    end
    mossTop(r.x + 2, r.y, r.w - 4, { r.x + 5 })
end

-- Slate: thin dark layers, a chipped free end, wedged into the glass
function paint.slate(piece)
    local t = tones.slate
    local r = piece.rects[1]
    local w = min(r.w, C.GLASS_R - piece.x0 - r.x + 3) -- the rest is in the glass
    local pts = outline(r.x, r.y, w, r.h, 4, 3, true)
    love.graphics.stencil(function() fillOutline(pts) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(t.base)
    love.graphics.rectangle("fill", r.x, r.y, w, r.h)
    -- Strata
    local y = r.y + 2
    while y < r.y + r.h do
        local c = random() < 0.5 and t.ridge or t.crack
        love.graphics.setColor(c[1], c[2], c[3], 0.35 + random() * 0.3)
        love.graphics.setLineWidth(0.6 + random() * 0.9)
        local line = {}
        for x = r.x, r.x + w, 6 do
            line[#line + 1] = x
            line[#line + 1] = y + sin(x * 0.05 + y) * 0.6
        end
        love.graphics.line(line)
        y = y + 2 + random() * 3
    end
    grain(t, r.x, r.y, w, r.h, "x", 30)
    shade(r.x, r.y, w, r.h, 0.16, 0.55)
    -- A chipped face at the free end
    love.graphics.setColor(t.ridge[1], t.ridge[2], t.ridge[3], 0.35)
    love.graphics.polygon("fill", r.x, r.y + 4, r.x + 6, r.y + 3, r.x + 4, r.y + r.h - 3, r.x, r.y + r.h - 5)
    lichenSpots(r.x + 6, r.y + 5, w * 0.6, r.h - 9, random(1, 3))
    love.graphics.setStencilTest()
    mossTop(r.x + 2, r.y, w - 2, { r.x + 6, r.x + w * 0.45 })
end

-- Basalt: a column of it, as it cooled. Seen side-on, a six-sided column shows
-- three faces, the one toward the lamp lit and the one by the glass in shadow;
-- it's fine-grained and nearly black, streaked by weather, and broken across
-- every hand's breadth or so by a joint that cups a little.
function paint.basalt(piece)
    local t = tones.basalt
    local r = piece.rects[1]
    local pts = outline(r.x, r.y, r.w, r.h, 4, 1, true)
    love.graphics.stencil(function() fillOutline(pts) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(jitter(t.base, 0.04))
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    -- Fine grain, and streaks where water has run down it
    for _ = 1, floor(r.w * r.h / 5) do
        local c = random() < 0.5 and t.ridge or t.crack
        love.graphics.setColor(c[1], c[2], c[3], 0.12 + random() * 0.2)
        love.graphics.circle("fill", r.x + random() * r.w, r.y + random() * r.h, 0.3 + random() * 0.5)
    end
    love.graphics.setLineWidth(0.7)
    for _ = 1, floor(r.w / 6) do
        local sx, sy = r.x + random() * r.w, r.y + random() * r.h * 0.6
        local c = random() < 0.5 and t.ridge or t.crack
        love.graphics.setColor(c[1], c[2], c[3], 0.12)
        love.graphics.line(sx, sy, sx + (random() - 0.5) * 2, sy + 30 + random() * 90)
    end
    -- The faces
    local fa, fb = r.w * (0.2 + random() * 0.1), r.w * (0.68 + random() * 0.1)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", r.x, r.y, fa, r.h)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", r.x + fb, r.y, r.w - fb, r.h)
    love.graphics.setLineWidth(0.8)
    love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.5)
    love.graphics.line(r.x + fa, r.y + 2, r.x + fa, r.y + r.h)
    love.graphics.setColor(t.ridge[1], t.ridge[2], t.ridge[3], 0.45)
    love.graphics.line(r.x + fb, r.y + 2, r.x + fb, r.y + r.h)
    -- The joints: each cups a little, some only part of the way across, a lit
    -- lip over the crack
    local y = r.y + 30 + random() * 30
    local joints = {}
    while y < r.y + r.h - 16 do
        local cup, x0, x1 = 0.6 + random() * 1.2, 0, r.w
        if random() < 0.3 then
            if random() < 0.5 then x1 = fb else x0 = fa end
        end
        local line, lip = {}, {}
        for u = x0, x1, 2.5 do
            local v = y - cup * sin(pi * u / r.w) + (random() - 0.5) * 0.8
            line[#line + 1], line[#line + 2] = r.x + u, v
            lip[#lip + 1], lip[#lip + 2] = r.x + u, v - 1.1
        end
        if #line >= 4 then
            love.graphics.setLineWidth(0.9)
            love.graphics.setColor(t.ridge[1], t.ridge[2], t.ridge[3], 0.45)
            love.graphics.line(lip)
            love.graphics.setLineWidth(1.3)
            love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.9)
            love.graphics.line(line)
            joints[#joints + 1] = y
        end
        y = y + 40 + random() * 44
    end
    shade(r.x, r.y, r.w, r.h, 0.14, 0.45)
    lichenSpots(r.x + 4, r.y + 6, r.w - 8, min(r.h - 12, 120), random(1, 3))
    love.graphics.setStencilTest()
    -- Moss caught in a joint here and there
    for _, jy in ipairs(joints) do
        if random() < 0.4 then
            for _ = 1, floor(r.w / 5) do
                local c = mossTones[random(#mossTones)]
                love.graphics.setColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 0.75)
                love.graphics.circle("fill", r.x + random() * r.w, jy - random() * 2, 0.6 + random())
            end
        end
    end
    mossTop(r.x + 2, r.y, r.w - 4, { r.x + 4, r.x + r.w - 4 })
end

-- Fungus: a bracket growing out of the wood it's `on`. Its cap is flat on top
-- and thins toward the rim. Seen edge-on, the years it has grown show as rings
-- round the rim, each a ridge, and the newest is the margin, white where it's
-- still growing; under the cap's brown crust, its pores are a cream face.
function paint.fungus(piece)
    local t = tones.fungus
    local r = piece.rects[1]
    local root = piece.from_left and r.x or r.x + r.w -- where it grows out of the wood
    local dir = piece.from_left and 1 or -1
    local N = 16
    -- How thick it is at u, from the wood (0) to the rim (1), and the point k
    -- of the way down through it there
    local function thick(u) return r.h * (1 - 0.3 * u ^ 2) end
    local tip = thick(1) / 2
    local function at(u, k) return root + dir * (r.w - tip) * u, r.y + thick(u) * k end
    -- Its outline from k0 down to k1, closed round the rim
    local function band(k0, k1)
        local pts = {}
        for i = 0, N do
            local x, y = at(i / N, k0)
            pts[#pts + 1], pts[#pts + 2] = x, y
        end
        local cx, cy = at(1, 0.5)
        for i = 1, 11 do
            local a = -pi / 2 + pi * i / 12
            local k = 0.5 + sin(a) * 0.5
            if k > k0 and k < k1 then pts[#pts + 1], pts[#pts + 2] = cx + dir * cos(a) * tip, cy + sin(a) * tip end
        end
        for i = N, 0, -1 do
            local x, y = at(i / N, k1)
            pts[#pts + 1], pts[#pts + 2] = x, y
        end
        return pts
    end
    -- A ring about the point u along it, a ridge seen edge-on
    local function ring(u, squash)
        local cx, cy = at(u, 0.5)
        local rr = thick(u) / 2
        local pts = {}
        for i = 0, 10 do
            local a = -pi / 2 + pi * i / 10
            pts[#pts + 1], pts[#pts + 2] = cx + dir * cos(a) * rr * squash, cy + sin(a) * rr
        end
        return pts
    end
    love.graphics.stencil(function() fillOutline(band(0, 1)) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(jitter(t.base, 0.05))
    love.graphics.rectangle("fill", r.x - 2, r.y, r.w + 4, r.h)
    grain(t, r.x, r.y, r.w, r.h, "x", 10)
    -- The pores underneath, and the crust darkening toward the wood
    love.graphics.setColor(t.pale[1] * 0.92, t.pale[2] * 0.9, t.pale[3] * 0.84, 1)
    fillOutline(band(0.8, 1.01))
    for i = 0, 5 do
        local w = r.w * (1 - i / 8)
        love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.12)
        love.graphics.rectangle("fill", piece.from_left and r.x or r.x + r.w - w, r.y, w, r.h * 0.8)
    end
    -- The years, a ridge each, closer together toward the rim
    love.graphics.setLineWidth(1.1)
    local u = 0.3 + random() * 0.1
    while u < 0.93 do
        love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.75)
        love.graphics.line(ring(u, 0.5))
        love.graphics.setColor(t.ridge[1], t.ridge[2], t.ridge[3], 0.55)
        love.graphics.line(ring(u + 0.02, 0.5))
        u = u + (1 - u) * (0.28 + random() * 0.12)
    end
    love.graphics.setColor(1, 1, 1, 0.14)
    love.graphics.rectangle("fill", r.x, r.y, r.w, 1.2)
    love.graphics.setStencilTest()
    -- The margin, white where it's growing
    love.graphics.setLineWidth(1.8)
    love.graphics.setColor(t.pale[1], t.pale[2], t.pale[3], 0.95)
    love.graphics.line(ring(1, 1))
    -- Where it meets the wood, a dark seam
    love.graphics.setColor(0.08, 0.05, 0.03, 0.6)
    love.graphics.setLineWidth(1.2)
    love.graphics.line(root, r.y + 1, root, r.y + r.h - 1)
end

-- Twig: a length of fallen branch, a knot or two, lichen, moss in the crook
function paint.twig(piece)
    local t = tones.twig
    local r = piece.rects[1]
    local pts = outline(r.x, r.y, r.w, r.h, 2.5, 0.6, true)
    love.graphics.stencil(function() fillOutline(pts) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(t.base)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    grain(t, r.x, r.y, r.w, r.h, "x", 4)
    -- Round: a lit top, a dark underside
    love.graphics.setColor(1, 1, 1, 0.16)
    love.graphics.rectangle("fill", r.x, r.y + 0.5, r.w, 1.4)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", r.x, r.y + r.h - 2, r.w, 2)
    for _ = 1, random(1, 2) do
        local kx = r.x + 12 + random() * (r.w - 24)
        love.graphics.setColor(t.crack[1], t.crack[2], t.crack[3], 0.9)
        love.graphics.ellipse("fill", kx, r.y + r.h * 0.5, 2.2, 1.6)
        love.graphics.setColor(t.ridge[1], t.ridge[2], t.ridge[3], 0.7)
        love.graphics.ellipse("line", kx, r.y + r.h * 0.5, 2.6, 1.9)
    end
    lichenSpots(r.x + 4, r.y + 1, r.w - 8, r.h - 2, random(2, 3))
    love.graphics.setStencilTest()
    -- A twiglet broken off short, angled down toward the water
    local bx = r.x + r.w * (0.3 + random() * 0.4)
    love.graphics.setColor(t.base[1] * 0.9, t.base[2] * 0.9, t.base[3] * 0.9, 1)
    love.graphics.setLineWidth(1.6)
    love.graphics.line(bx, r.y + r.h - 1, bx + 5, r.y + r.h + 4)
end

--------------------------------------------------------------------------------
-- Baking
--------------------------------------------------------------------------------

local function bake(piece)
    local cw, ch = math.ceil((piece.w + PAD * 2) * SCALE), math.ceil((piece.h + PAD * 2) * SCALE)
    piece.canvas = love.graphics.newCanvas(cw, ch)
    love.graphics.push("all")
    love.graphics.setCanvas({ piece.canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.scale(SCALE)
    love.graphics.translate(PAD, PAD)
    paint[piece.material](piece)
    love.graphics.pop()
end

-- Group solids by part_of into pieces, each with its bounding box
local function collect(level)
    local byId, out = {}, {}
    for _, s in ipairs(level.solids) do
        if s.material and not s.part_of then
            local p = { id = s.id, material = s.material, solids = { s } }
            byId[s.id] = p
            out[#out + 1] = p
        end
    end
    for _, s in ipairs(level.solids) do
        if s.part_of and byId[s.part_of] then table.insert(byId[s.part_of].solids, s) end
    end
    for _, p in ipairs(out) do
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for _, s in ipairs(p.solids) do
            x0, y0 = min(x0, s.x), min(y0, s.y)
            x1, y1 = max(x1, s.x + s.w), max(y1, s.y + s.h)
        end
        -- Nothing below the soil shows; keep bakes to what does
        y1 = min(y1, C.SOIL_Y + 2)
        p.x0, p.y0, p.w, p.h = x0, y0, x1 - x0, y1 - y0
        p.rects = {}
        for i, s in ipairs(p.solids) do
            p.rects[i] = { x = s.x - x0, y = s.y - y0, w = s.w, h = min(s.h, y1 - s.y), main = (i == 1) }
        end
        p.grounded = y1 >= C.SOIL_Y
        -- (a bracket grows out of the side of what it's on)
        local on = p.solids[1].on and level.by_id[p.solids[1].on]
        p.from_left = on and p.solids[1].x >= on.x + on.w - 1
    end
    return out
end

--- Compose and bake the scenery for this level. Draws from `generator` only here.
function Scenery.init(generator, level)
    gen = generator
    pieces = collect(level)
    for _, p in ipairs(pieces) do bake(p) end
    local wd = level.data.water
    if wd then
        water = { x0 = wd.x0, x1 = wd.x1, y = wd.y, glints = {} }
        for i = 1, random(3, 5) do
            water.glints[i] = { x = random(), w = 0.08 + random() * 0.18, phase = random() * 6 }
        end
    end
end

-- The dish sunk into the soil, and the water in it catching the lamp
local function drawWater(light, time)
    local w = water
    local cx, cy = (w.x0 + w.x1) / 2, w.y - 1
    local rx = (w.x1 - w.x0) / 2 + 4
    love.graphics.setColor(0.42, 0.40, 0.37, 1)
    love.graphics.ellipse("fill", cx, cy, rx, 6.5)
    love.graphics.setColor(0.58, 0.56, 0.52, 0.8)
    love.graphics.ellipse("line", cx, cy - 0.5, rx - 0.5, 6)
    love.graphics.setColor(0.05, 0.08, 0.09, 1)
    love.graphics.ellipse("fill", cx, cy + 0.6, rx - 4, 4.6)
    -- What the water shows: the glass and the lamp above, a little darker
    local l = light.lamp
    love.graphics.setColor(0.14 + l[1] * 0.16, 0.18 + l[2] * 0.16, 0.20 + l[3] * 0.15, 1)
    love.graphics.ellipse("fill", cx, cy - 0.4, rx - 6, 3.2)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", cx, cy - 1.6, rx - 12, 1.2) -- the twig's shadow on the water
    for _, g in ipairs(w.glints) do
        local a = 0.10 + 0.08 * sin(time * 0.7 + g.phase)
        local gx = w.x0 + 8 + g.x * (w.x1 - w.x0 - 16)
        love.graphics.setColor(1, 0.97, 0.88, a)
        love.graphics.rectangle("fill", gx, cy - 0.5, g.w * (w.x1 - w.x0) * 0.5, 0.9)
    end
end

--- Draw the scenery on the creatures' plane (call inside Tank.pushPlane()).
-- `time` only animates the water's glints; it's the jar's clock, read not moved.
function Scenery.draw(light, time)
    Render.useObject(C.PLANE_D)
    -- Contact shadows where things stand on the soil (light, not a layer, so
    -- not in the matte, #98)
    Matte.mark()
    for _, p in ipairs(pieces) do
        if p.grounded then
            love.graphics.setColor(0, 0, 0, 0.28)
            for _, s in ipairs(p.solids) do
                if s.y + s.h >= C.SOIL_Y then
                    Render.drawBlob(s.x + s.w / 2, C.SOIL_Y + 1, s.w * 0.7, 5)
                end
            end
        end
    end
    Matte.mark('solid', C.PLANE_D)
    if water then drawWater(light, time or 0) end
    love.graphics.setColor(1, 1, 1, 1)
    for _, p in ipairs(pieces) do
        love.graphics.draw(p.canvas, p.x0 - PAD, p.y0 - PAD, 0, 1 / SCALE, 1 / SCALE)
    end
end

--- Pieces, for anything that wants to grow on them
function Scenery.all() return pieces end

return Scenery
