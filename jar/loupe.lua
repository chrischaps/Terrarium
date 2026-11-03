-- Terrarium: the loupe (#122), drawn over a finished frame in the screen's own
-- pixels: a small ring on a creature, two lines, and the round lens up in its
-- corner with the plate of what's in that ring. jar/camera.lua says where.
--
-- The plate comes through a style's seams as any plate does, so what's in the
-- lens is right in every look. The rings aren't in the frame (a style would make
-- them a faint line of the ground, in its own grey), so each style names a hand
-- for them (`ring` in jar/styles.lua), always in the lamp's warm colour:
--   brass   a turned ring with a shadow under it, on a photograph
--   pencil  a coloured pencil on the page, gone round twice; the lines ruled, and
--           run a little past where they meet the rings. Boils as pencil's line does
--   wash    a band of thin paint with a wet edge, its width wandering
--   type    set in glyphs: the rings and lines in the grid's own characters, and
--           the lens stepped to its cells
-- It's drawing only, reads no stream, and is the same picture at the same time.

local Render = require('jar.render')
local Tank = require('jar.tank')
local Ascii = require('jar.ascii')
local Camera = require('jar.camera')

local Loupe = {}

local BOILS = 4 -- drawings a second, as pencil_common.glsl's line

-- The lamp's warm colour (Lantern's WARM), and on paper, where a light line
-- wouldn't show, the same hue as a pigment
local WARM = { 1.00, 0.70, 0.38 }
local PENCIL = { 0.74, 0.37, 0.09 }
local WASH = { 0.83, 0.47, 0.14 }

local function colour(c, a) love.graphics.setColor(c[1], c[2], c[3], a) end

-- A small smooth wobble, the same for the same `seed` and `t` (no stream)
local function wander(t, seed)
    local s = seed * 12.9898
    return (math.sin(t * 2 + s) + 0.6 * math.sin(t * 3 + s * 2.1) + 0.35 * math.sin(t * 7 + s * 3.7)) / 1.95
end

-- A circle by hand, as a line's points: from a start set by `seed`, round `turns`
-- times, each point pushed out by up to `by`
local function round(c, by, seed, turns)
    local n = math.floor(math.max(24, c.r * 1.2) * turns + 0.5)
    local start = seed * 2.399
    local pts = {}
    for i = 0, n do
        local t = start + i / n * turns * 2 * math.pi
        local r = c.r + by * wander(t, seed)
        pts[#pts + 1] = c.x + r * math.cos(t)
        pts[#pts + 1] = c.y + r * math.sin(t)
    end
    return pts
end

-- A line by hand, as its points
local function ruled(x0, y0, x1, y1, by, seed)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return nil end
    local n = math.max(2, math.floor(len / 24))
    local nx, ny = -dy / len, dx / len
    local pts = {}
    for i = 0, n do
        local f = i / n
        -- (it wanders in the middle and comes back at its ends)
        local off = by * wander(f * 6, seed) * math.sin(f * math.pi)
        pts[#pts + 1] = x0 + dx * f + nx * off
        pts[#pts + 1] = y0 + dy * f + ny * off
    end
    return pts
end

local function extended(x0, y0, x1, y1, by)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return x0, y0, x1, y1 end
    dx, dy = dx / len * by, dy / len * by
    return x0 - dx, y0 - dy, x1 + dx, y1 + dy
end

-- Glyphs -----------------------------------------------------------------------

local fonts = {}
local function fontFor(px)
    px = math.max(6, math.floor(px + 0.5))
    fonts[px] = fonts[px] or love.graphics.newFont(px)
    return fonts[px]
end

-- The stroke for a way of running, `angle` in radians, as the ascii style's own
-- edges are (| / - \)
local function stroke(angle)
    local a = (angle / math.pi) % 1 -- (a line has no direction)
    if a < 0.125 or a >= 0.875 then return '-' end
    if a < 0.375 then return '\\' end -- (y is down the screen)
    if a < 0.625 then return '|' end
    return '/'
end

-- A run of points as glyphs on the grid of cw x ch cells from (ox, oy), one wide:
-- the cells it goes through, in order, less any it only clips a corner of (one
-- whose neighbours before and after touch each other). `seen` is which cells are
-- taken already; the frame is knocked back behind each, so it reads over anything.
local function set(pts, closed, cw, ch, ox, oy, seen, font, c, a)
    local cells = {}
    local n = #pts / 2
    for i = 1, closed and n or n - 1 do
        local x0, y0 = pts[2 * i - 1], pts[2 * i]
        local j = i % n + 1
        local dx, dy = pts[2 * j - 1] - x0, pts[2 * j] - y0
        local steps = math.max(1, math.ceil(math.max(math.abs(dx) / cw, math.abs(dy) / ch) * 4))
        local way = math.atan2(dy, dx)
        for s = 0, steps do
            local gx = math.floor((x0 + dx * s / steps - ox) / cw)
            local gy = math.floor((y0 + dy * s / steps - oy) / ch)
            local last = cells[#cells]
            if not last or last.x ~= gx or last.y ~= gy then
                local before = cells[#cells - 1]
                if before and math.abs(before.x - gx) <= 1 and math.abs(before.y - gy) <= 1 then
                    cells[#cells] = nil
                end
                cells[#cells + 1] = { x = gx, y = gy, way = way }
            end
        end
    end
    love.graphics.setFont(font)
    for _, g in ipairs(cells) do
        local key = g.x .. ',' .. g.y
        if not seen[key] then
            seen[key] = true
            local px, py = ox + g.x * cw, oy + g.y * ch
            love.graphics.setColor(0, 0, 0, 0.72 * a)
            love.graphics.rectangle('fill', px, py, cw, ch)
            colour(c, a)
            local glyph = stroke(g.way)
            love.graphics.print(glyph, math.floor(px + (cw - font:getWidth(glyph)) / 2 + 0.5),
                math.floor(py + (ch - font:getHeight()) / 2 + 0.5))
        end
    end
end

-- The hands -----------------------------------------------------------------------
-- Each is `under(inset, a, k, time)`, the lines and the small ring, on the frame;
-- `shadow(lens, a, k)`, what the lens casts on it; and `over(inset, a, k, time)`,
-- the lens's own ring, on the lens. `a` is how far they've come up, and `k` the
-- line's scale: 1 on the frame's 720 lines.

local function drawLines(inset, width, c, a, by, seed, past)
    local a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y = Camera.tangents(inset.ring, inset.lens)
    if not a1x then return end
    love.graphics.setLineWidth(width)
    colour(c, a)
    for i, l in ipairs({ { a1x, a1y, a2x, a2y }, { b1x, b1y, b2x, b2y } }) do
        local x0, y0, x1, y1 = l[1], l[2], l[3], l[4]
        if past then x0, y0, x1, y1 = extended(x0, y0, x1, y1, past) end
        local pts = ruled(x0, y0, x1, y1, by, seed + i)
        if pts then love.graphics.line(pts) end
    end
end

local brass = {
    under = function(inset, a, k)
        -- (a dark line under each, so it reads against the lamp's pool too)
        drawLines(inset, 2.2 * k, { 0, 0, 0 }, 0.22 * a, 0, 1)
        drawLines(inset, 1.1 * k, WARM, 0.7 * a, 0, 1)
        local r = inset.ring
        love.graphics.setColor(0, 0, 0, 0.35 * a)
        love.graphics.setLineWidth(3.6 * k)
        love.graphics.circle('line', r.x, r.y, r.r, 72)
        colour(WARM, a)
        love.graphics.setLineWidth(2 * k)
        love.graphics.circle('line', r.x, r.y, r.r, 72)
    end,
    shadow = function(lens, a)
        love.graphics.setColor(0, 0, 0, 0.5 * a)
        Render.drawBlob(lens.x, lens.y + lens.r * 0.05, lens.r * 1.22)
    end,
    over = function(inset, a, k)
        local l = inset.lens
        colour(WARM, a)
        love.graphics.setLineWidth(3.6 * k)
        love.graphics.circle('line', l.x, l.y, l.r, 128)
        -- (the turned ring's lit edge)
        love.graphics.setColor(1, 0.92, 0.76, 0.55 * a)
        love.graphics.setLineWidth(1 * k)
        love.graphics.circle('line', l.x, l.y, l.r - 0.9 * k, 128)
    end,
}

local pencil = {
    under = function(inset, a, k, time)
        local d = math.floor(time * BOILS)
        drawLines(inset, 1.1 * k, PENCIL, 0.9 * a, 0.5 * k, d % 16, 7 * k)
        colour(PENCIL, 0.95 * a)
        love.graphics.setLineWidth(1.5 * k)
        love.graphics.line(round(inset.ring, 0.7 * k, d % 16 + 3, 1.08))
    end,
    shadow = function() end, -- (a drawing casts none)
    over = function(inset, a, k, time)
        local d = math.floor(time * BOILS)
        colour(PENCIL, 0.9 * a)
        love.graphics.setLineWidth(1.8 * k)
        love.graphics.line(round(inset.lens, 0.9 * k, d % 16 + 5, 1.06))
        colour(PENCIL, 0.55 * a)
        love.graphics.setLineWidth(1.3 * k)
        love.graphics.line(round(inset.lens, 1.3 * k, d % 16 + 9, 1.03))
    end,
}

local wash = {
    under = function(inset, a, k)
        drawLines(inset, 3 * k, WASH, 0.22 * a, 1 * k, 2)
        drawLines(inset, 1 * k, WASH, 0.7 * a, 1 * k, 2)
        local r = inset.ring
        colour(WASH, 0.3 * a)
        love.graphics.setLineWidth(5 * k)
        love.graphics.line(round(r, 1.1 * k, 4, 1))
        colour(WASH, 0.8 * a)
        love.graphics.setLineWidth(1.2 * k)
        love.graphics.line(round({ x = r.x, y = r.y, r = r.r + 2 * k }, 1.2 * k, 4, 1))
    end,
    shadow = function() end,
    over = function(inset, a, k)
        local l = inset.lens
        colour(WASH, 0.38 * a)
        love.graphics.setLineWidth(9 * k)
        love.graphics.line(round({ x = l.x, y = l.y, r = l.r + 1.5 * k }, 1.6 * k, 6, 1))
        colour(WASH, 0.85 * a)
        love.graphics.setLineWidth(1.6 * k)
        love.graphics.line(round({ x = l.x, y = l.y, r = l.r + 5.5 * k }, 1.6 * k, 6, 1))
        colour(WASH, 0.4 * a)
        love.graphics.setLineWidth(1 * k)
        love.graphics.line(round({ x = l.x, y = l.y, r = l.r - 2.5 * k }, 1.4 * k, 11, 1))
    end,
}

local type_ = {
    under = function(inset, a, _, _, cw, ch, _)
        local font, seen = fontFor(ch * 0.95), {}
        local a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y = Camera.tangents(inset.ring, inset.lens)
        if a1x then
            set({ a1x, a1y, a2x, a2y }, false, cw, ch, 0, 0, seen, font, WARM, 0.75 * a)
            set({ b1x, b1y, b2x, b2y }, false, cw, ch, 0, 0, seen, font, WARM, 0.75 * a)
        end
        set(round(inset.ring, 0, 1, 1), true, cw, ch, 0, 0, seen, font, WARM, a)
    end,
    shadow = function() end,
    over = function(inset, a, _, _, cw, ch)
        -- (on the lens's own grid, so it goes with it, as its stepped edge does)
        local l = inset.lens
        local s = l.r / inset.R
        cw, ch = cw * s, ch * s
        if cw < 3 then return end
        local font = fontFor(ch * 0.95)
        local grown = { x = l.x, y = l.y, r = l.r }
        set(round(grown, 0, 1, 1), true, cw, ch, l.x - l.r, l.y - l.r, {}, font, WARM, a)
    end,
}

local HANDS = { brass = brass, pencil = pencil, wash = wash, type = type_ }

--- Draw an inset (Camera:inset) in the hand named `kind`, over what's on the
-- target now. `plate` is the canvas of its stretch of the plane, inset.size
-- square; `k` is the base fit's scale, for a cell of the type's grid.
function Loupe.draw(kind, inset, plate, time, k)
    local hand = HANDS[kind] or brass
    local lens = inset.lens
    local a = Tank.smoothstep(0.02, 0.3, inset.amount)
    local lines = inset.R / 120 -- (the frame's lens is 120 in radius)
    -- (a cell of the type's grid: on the frame in the screen's pixels, on the
    -- plate in its own, since a plate's frame is drawn one to one)
    local vw, vh = Ascii.cell()
    local cw, ch = vw * k, vh * k

    love.graphics.push('all')
    love.graphics.setShader()
    love.graphics.setLineStyle('smooth')
    hand.under(inset, a, lines, time, cw, ch)
    hand.shadow(lens, a, lines)

    local scale = lens.r / inset.R
    local sh = Render.shader('loupe')
    if sh then
        love.graphics.setShader(sh)
        sh:send('feather', 1 / math.max(1, lens.r))
        if kind == 'type' then
            sh:send('cell', { vw / inset.size, vh / inset.size })
        else
            sh:send('cell', { 0, 0 })
        end
        sh:send('rim', kind == 'brass' and 0.34 or 0)
    end
    love.graphics.setColor(1, 1, 1, Tank.smoothstep(0, 0.1, inset.amount))
    love.graphics.draw(plate, lens.x - lens.r, lens.y - lens.r, 0, scale, scale)
    love.graphics.setShader()

    hand.over(inset, a, lines, time, vw, vh)
    love.graphics.pop()
end

return Loupe
