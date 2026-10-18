-- From chrischaps/Fishbowl @ b0624e4 (env/glass.lua)
-- The glass: the panes you see through to the back of the jar, the lid, and the
-- front glass with its film of dust, its edges and a soft glare.
-- Terrarium: no water, so no algae, snail or tap ripple. The film is dust and
-- the dried rings of old condensation (live condensation is #5). The jar's
-- glass edges and its cork-knobbed lid are new, and so is the lamp's cone of
-- light through the lid. Everything on the glass takes the day cycle's light.

local C = require("jar.config")
local Tank = require("jar.tank")
local Render = require("jar.render")

local Glass = {}

local film
local L, R = C.GLASS_L - C.GLASS_THICK, C.GLASS_R + C.GLASS_THICK
local T, B = C.GLASS_T - 12, C.GLASS_B   -- lid top, jar base (level y)

-- The front pane on screen (the front glass has k = 1, so screen = world)
function Glass.frontRect()
    return C.OX + L, C.OY + T, C.OX + R, C.OY + B
end

local function bakeFilm(gen)
    local x0, y0, x1, y1 = Glass.frontRect()
    film = love.graphics.newCanvas(C.W, C.H)
    love.graphics.push("all")
    love.graphics.setCanvas(film)
    love.graphics.clear(0, 0, 0, 0)
    -- Dust settles everywhere, a little more toward the bottom
    for _ = 1, 900 do
        local x = x0 + gen:random() * (x1 - x0)
        local y = y0 + gen:random() ^ 0.7 * (y1 - y0)
        love.graphics.setColor(0.85, 0.82, 0.75, 0.04 + gen:random() * 0.07)
        love.graphics.circle("fill", x, y, 0.5 + gen:random() ^ 3 * 1.6)
    end
    -- Rings left by old condensation, mostly high on the glass
    love.graphics.setLineWidth(0.8)
    for _ = 1, 70 do
        local x = x0 + 12 + gen:random() * (x1 - x0 - 24)
        local y = y0 + 20 + gen:random() ^ 2.2 * (y1 - y0) * 0.6
        local r = 1.5 + gen:random() ^ 2 * 5
        love.graphics.setColor(0.90, 0.92, 0.88, 0.05 + gen:random() * 0.06)
        love.graphics.ellipse("line", x, y, r, r * (0.85 + gen:random() * 0.3))
    end
    love.graphics.pop()
end

function Glass.init(gen)
    bakeFilm(gen)
end

local function at(x, y, d)
    local sx, sy = Tank.level(x, y, d)
    return sx, sy
end

local function quad(ax, ay, ad, bx, by, bd, cx, cy, cd, dx, dy, dd)
    local p = {}
    for _, v in ipairs({ { ax, ay, ad }, { bx, by, bd }, { cx, cy, cd }, { dx, dy, dd } }) do
        local sx, sy = at(v[1], v[2], v[3])
        p[#p + 1] = sx
        p[#p + 1] = sy
    end
    return p
end

-- Terrarium: the lamp's cone, as a fan of strips that fade toward the soil and
-- the cone's edges (rebuilt each frame; it's a handful of vertices)
local coneMesh
local function cone(l)
    local cw = C.LAMP_CONE
    local x, d = C.LAMP_X, 0.5
    local top, bottom = C.GLASS_T, C.SOIL_Y
    local verts = {}
    local cols = { 0, 0.5, 1, 0.5, 0 }
    local rows = 6
    for j = 0, rows - 1 do
        for i = 1, #cols - 1 do
            local function v(ii, jj)
                local t = jj / rows
                local hw = Tank.lerp(cw.top, cw.bottom, t)
                local sx, sy = at(x - hw + 2 * hw * (ii - 1) / (#cols - 1), Tank.lerp(top, bottom, t), d)
                local a = cols[ii] * (1 - t * 0.85) ^ 1.6 * 0.10
                return { sx, sy, 0, 0, l[1] * a, l[2] * a, l[3] * a, 1 }
            end
            local a, b, c, e = v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1)
            for _, q in ipairs({ a, b, c, a, c, e }) do verts[#verts + 1] = q end
        end
    end
    if coneMesh then coneMesh:setVertices(verts)
    else coneMesh = love.graphics.newMesh(verts, "triangles", "stream") end
    return coneMesh
end

--- The far panes: the back glass, the side glass and the underside of the lid,
-- seen from inside. Drawn before anything in the jar.
function Glass.drawBack(light)
    local gl, gr, gt, gb = C.GLASS_L, C.GLASS_R, C.GLASS_T, C.GLASS_B
    love.graphics.push("all")

    -- The jar's air: a little darker and greener than the room behind it
    love.graphics.setColor(0.04, 0.07, 0.065, 0.16)
    love.graphics.polygon("fill", quad(gl, gt, 0, gr, gt, 0, gr, gb, 0, gl, gb, 0))
    for _, side in ipairs({ gl, gr }) do
        love.graphics.setColor(0.05, 0.08, 0.075, 0.24)
        love.graphics.polygon("fill", quad(side, gt, 1, side, gt, 0, side, gb, 0, side, gb, 1))
    end
    love.graphics.setColor(0.06, 0.08, 0.075, 0.30)
    love.graphics.polygon("fill", quad(gl, gt, 1, gr, gt, 1, gr, gt, 0, gl, gt, 0))

    -- The lamp shines down through the lid
    local l = light.lamp
    love.graphics.setBlendMode("add")
    local cx, cy = at((gl + gr) / 2, gt, 0.5)
    love.graphics.setColor(l[1] * 0.10, l[2] * 0.10, l[3] * 0.10, 1)
    Render.drawBlob(cx, cy + 30, 360, 90)

    -- Terrarium: and falls in a soft cone to the moss, brightest under the lid
    if light.lamp_i > 0.01 then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(cone(l), 0, 0)
    end
    love.graphics.setBlendMode("alpha")

    -- Edges where the panes meet
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.70, 0.86, 0.82, 0.10)
    love.graphics.polygon("line", quad(gl, gt, 0, gr, gt, 0, gr, gb, 0, gl, gb, 0))
    love.graphics.setColor(0.70, 0.86, 0.82, 0.16)
    for _, c in ipairs({ { gl, gt }, { gr, gt }, { gl, gb }, { gr, gb } }) do
        local ax, ay = at(c[1], c[2], 1)
        local bx, by = at(c[1], c[2], 0)
        love.graphics.line(ax, ay, bx, by)
    end
    love.graphics.pop()
end

--- Everything on the front glass, drawn over the jar
function Glass.drawFront(light, mouseX)
    local x0, y0, x1, y1 = Glass.frontRect()
    local w, h = x1 - x0, y1 - y0
    love.graphics.push("all")
    -- Terrarium: the glass is only as bright as the light that's on it
    local amb = light.ambient
    local function tint(r, g, b, a)
        love.graphics.setColor(r * amb[1], g * amb[2], b * amb[3], a)
    end

    -- A faint green cast, the way thick glass tints what's behind it
    tint(0.55, 0.78, 0.74, 0.035)
    love.graphics.rectangle("fill", x0, y0, w, h)
    tint(1, 1, 1, 1)
    love.graphics.draw(film)

    -- Glare: a soft diagonal sheen that shifts a little as you move
    local par = ((mouseX or C.W / 2) - C.W / 2) * 0.04
    love.graphics.setScissor(x0, y0, w, h)
    love.graphics.setBlendMode("add")
    local glare = 0.015 + 0.03 * light.lamp_i
    for i, g in ipairs({ { x = 0.12, w = 70, a = 1 }, { x = 0.24, w = 20, a = 0.7 }, { x = 0.83, w = 40, a = 0.45 } }) do
        love.graphics.setColor(1, 1, 1, glare * g.a)
        love.graphics.push()
        love.graphics.translate(x0 + g.x * w + par * (1 + i * 0.3), y0 + h / 2)
        love.graphics.shear(-0.55, 0)
        Render.drawBlob(0, 0, g.w, h * 0.75)
        love.graphics.pop()
    end
    -- The lamp, caught in the glass near the top
    local l = light.lamp
    love.graphics.setColor(l[1] * 0.10, l[2] * 0.10, l[3] * 0.10, 1)
    Render.drawBlob(C.CX - par * 2, y0 + 26, 150, 22)
    love.graphics.setScissor()

    -- The glass edges: thick glass seen edge-on goes green and bright
    local edge = { 0.62, 0.84, 0.78 }
    local inL, inR = C.OX + C.GLASS_L, C.OX + C.GLASS_R
    local lidB, baseT = C.OY + C.GLASS_T, C.OY + B - C.GLASS_THICK
    love.graphics.setBlendMode("alpha")
    tint(edge[1], edge[2], edge[3], 0.22)
    love.graphics.rectangle("fill", x0, lidB, inL - x0, baseT - lidB)
    love.graphics.rectangle("fill", inR, lidB, x1 - inR, baseT - lidB)
    tint(edge[1], edge[2], edge[3], 0.30)
    love.graphics.rectangle("fill", x0, baseT, w, y1 - baseT)
    tint(1, 1, 1, 0.30)
    love.graphics.setLineWidth(1)
    love.graphics.line(x0 + 0.5, lidB, x0 + 0.5, y1)
    love.graphics.line(x1 - 0.5, lidB, x1 - 0.5, y1)
    love.graphics.line(x0, baseT + 0.5, x1, baseT + 0.5)
    tint(1, 1, 1, 0.12)
    love.graphics.line(inL - 0.5, lidB, inL - 0.5, baseT)
    love.graphics.line(inR + 0.5, lidB, inR + 0.5, baseT)

    -- The lid: a slab of glass, a little wider than the jar, with a cork knob
    local lx0, lx1 = x0 - 5, x1 + 5
    tint(edge[1] * 0.55, edge[2] * 0.55, edge[3] * 0.55, 0.85)
    love.graphics.rectangle("fill", lx0, y0, lx1 - lx0, lidB - y0, 2, 2)
    tint(edge[1], edge[2], edge[3], 0.55)
    love.graphics.rectangle("fill", lx0, y0, lx1 - lx0, 2)
    tint(1, 0.95, 0.85, 0.20)
    love.graphics.rectangle("fill", lx0 + 2, lidB - 3, lx1 - lx0 - 4, 1.5)

    local kw, kh = 58, 18
    local kx, ky = C.CX - kw / 2, y0 - kh + 2
    tint(0.52, 0.38, 0.24, 1)
    love.graphics.rectangle("fill", kx, ky, kw, kh, 5, 5)
    tint(0.66, 0.50, 0.33, 1)
    love.graphics.rectangle("fill", kx + 3, ky + 2, kw - 6, 6, 3, 3)
    tint(0.30, 0.20, 0.12, 0.6)
    for i = 0, 26 do
        -- Cork's pores, in a fixed scatter so the knob never shimmers
        local px = kx + 4 + (i * 37 % 56)
        local py = ky + 8 + (i * 23 % 14)
        love.graphics.circle("fill", px, py, 0.8 + (i % 3) * 0.4)
    end
    love.graphics.pop()
end

return Glass
