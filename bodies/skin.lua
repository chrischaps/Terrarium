-- Skin: a creature's colours and markings from its genes (#15).
--
-- In the style of Fishbowl's species colours, but drawn from genes. Each body
-- plan owns a stretch of the colour wheel, and `hue` only moves a creature
-- within it, so the families never meet: worms are rose to apricot, blobs mint
-- to sky, spiders indigo to plum. Each family also keeps its own lightness, in
-- OKLCH, where equal lightness looks equally bright: worms are fleshy, blobs
-- pale and glassy, spiders dark. Colour alone tells you whose child it is.
--
-- `pattern` is one of four kinds, and every plan wears all four in its own way:
--   capped   the head end in the mark colour: a worm's dark head, a jelly's
--            bell, a spider's thorax
--   banded   rings round a worm, comb rows down a blob that turn as it rolls,
--            chevrons and banded knees on a spider
--   spotted  dots down the back
--   striped  one line along the back, or a ring inside a blob's skin
--
-- `glow` is how brightly the markings shine in the dark. It shows only as the
-- lamp dims (the day cycle's `glow`, 0 by day and 1 at night), drawn after the
-- jar's lighting so the dark can't touch it.
--
-- Nothing here is simulation: a skin is worked out once from the genome and
-- only ever read by drawing.

local colour = require('core.colour')

local Skin = {}

local oklch = colour.oklch
local sin, floor = math.sin, math.floor

Skin.PATTERNS = {'capped', 'banded', 'spotted', 'striped'}

-- Each family's stretch of hue, in OKLCH degrees, and its colours at hue h.
-- Light falling on a body (a worm's rim, a blob's lit edge) stays the lamp's.
-- Terrarium: a hatchling is pale (#23): `pale` (1 just hatched, 0 grown)
-- lifts every colour toward milk-white and takes away most of its chroma, so
-- a young one wears its family's colours faintly and darkens into them.
-- Terrarium: and an elder deepens (#24): `old` (0 in its prime, 1 at the end)
-- takes its colours darker and richer, the way an old leaf's are. `earth`
-- (0..1, as it returns to the moss) draws them toward the moss's own green-brown.
local pale, old, earth = 0, 0, 0
local MOSS_H = 125
local function rgb(L, C, h, a)
    L, C = L + (0.92 - L) * 0.6 * pale, C * (1 - 0.65 * pale)
    L, C = L * (1 - 0.2 * old), C * (1 + 0.45 * old)
    if earth > 0 then
        local dh = (MOSS_H - h + 180) % 360 - 180
        L, C, h = L + (0.42 - L) * earth, C + (0.07 - C) * earth, h + dh * earth
    end
    local r, g, b = oklch(L, C, h)
    return {r, g, b, a or 1}
end

Skin.families = {
    worm = {
        hue = {-12, 58}, -- rose, coral, apricot
        colours = function(h)
            return {
                back    = rgb(0.62, 0.12, h),
                belly   = rgb(0.86, 0.06, h + 15),
                band    = rgb(0.67, 0.14, h - 6),  -- the clitellum
                mark    = rgb(0.42, 0.09, h - 4),
                outline = rgb(0.20, 0.04, h),
                shine   = rgb(0.88, 0.13, h + 20), -- an ember
                name    = rgb(0.82, 0.10, h),
                main    = 'back',
            }
        end,
    },
    blob = {
        hue = {150, 215}, -- mint, aqua, sky
        colours = function(h)
            return {
                core    = rgb(0.88, 0.09, h, 0.86),
                rim     = rgb(0.52, 0.09, h, 0.95),
                outline = rgb(0.28, 0.05, h),
                mark    = rgb(0.56, 0.13, h + 8, 0.9),
                trail   = rgb(0.93, 0.09, h),
                bubble  = rgb(0.94, 0.05, h),
                pupil   = rgb(0.20, 0.04, h),
                shine   = rgb(0.90, 0.12, h),
                name    = rgb(0.90, 0.10, h),
                main    = 'core',
            }
        end,
    },
    spider = {
        hue = {262, 318}, -- indigo, violet, plum
        colours = function(h)
            return {
                body    = rgb(0.34, 0.06, h),
                body_hi = rgb(0.48, 0.08, h),
                leg     = rgb(0.39, 0.06, h),
                leg_far = rgb(0.26, 0.04, h),
                joint   = rgb(0.56, 0.07, h),
                outline = rgb(0.14, 0.03, h),
                mark    = rgb(0.78, 0.10, h + 10),
                shine   = rgb(0.82, 0.15, h),
                name    = rgb(0.82, 0.10, h),
                main    = 'body',
            }
        end,
    },
}

-- A number in [0, 1) that's always the same for the same inputs (Fishbowl's
-- hash). For where the spots fall; it never touches a random stream.
function Skin.hash(a, b)
    local n = sin(a * 127.1 + b * 311.7) * 43758.5453
    return n - floor(n)
end

-- The skin for a body of plan `key` with `genome` (nil: the middle of each
-- gene), `young` (0..1) pale with youth, `aged` (0..1) deepened with age, and
-- `earthed` (0..1) gone back toward the moss
function Skin.of(key, genome, young, aged, earthed)
    local fam = Skin.families[key]
    local hue = genome and genome.hue or 0.5
    local h = fam.hue[1] + hue * (fam.hue[2] - fam.hue[1])
    pale, old, earth = young or 0, aged or 0, earthed or 0
    local skin = fam.colours(h)
    pale, old, earth = 0, 0, 0
    skin.h, skin.young, skin.old, skin.earth = h, young or 0, aged or 0, earthed or 0
    skin.pattern = Skin.PATTERNS[genome and genome.pattern or 2]
    skin.glow = genome and genome.glow or 0.5
    skin.seed = hue * 97 + skin.glow * 13 -- places the spots
    return skin
end

-- How bright the markings shine under `light` (DayCycle.env), 0..1. Eased,
-- so a middling glow still shows across the jar.
-- (and `flush`, 0..1, is how much a courting body's markings light up on
-- the beat, by day or night, #22)
-- Terrarium: the same skin aged (#24), keeping whatever a body added to it
-- (its eyes, a worm's rim)
function Skin.age(key, genome, skin, aged, earthed)
    local new = Skin.of(key, genome, skin.young, aged, earthed)
    for k, v in pairs(skin) do
        if new[k] == nil then new[k] = v end
    end
    return new
end

function Skin.shine(skin, light, flush)
    return skin.glow ^ 0.7 * math.max(light and light.glow or 0, 0.8 * (flush or 0))
end

--------------------------------------------------------------------------------
-- Glow. A body lists its markings as it draws them, as plain shapes:
--   {'disc', x, y, r}   {'ellipse', x, y, rx, ry}   {'line', {x1, y1, ...}, width}
--   {'mesh', mesh}      (a mesh whose vertex alpha is how much it glows)
--   {'halo', x, y, r}   (only the soft light around a broad marking)
-- and draw_emissive hands them here with the strength from Skin.shine. Each
-- shape is drawn as a soft halo and then a bright core, added onto the scene.

local Render

local function halo(x, y, r, a, c)
    love.graphics.setColor(c[1], c[2], c[3], a)
    Render.drawBlob(x, y, r)
end

function Skin.paint_glow(marks, skin, k)
    if k < 0.01 or not marks then return end
    Render = Render or require('jar.render')
    local c = skin.shine
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, m in ipairs(marks) do
        local kind = m[1]
        if kind == 'disc' then
            halo(m[2], m[3], m[4] * 4, 0.35 * k, c)
            love.graphics.setColor(c[1], c[2], c[3], 0.8 * k)
            love.graphics.circle('fill', m[2], m[3], m[4])
        elseif kind == 'ellipse' then
            halo(m[2], m[3], (m[4] + m[5]) * 1.6, 0.3 * k, c)
            love.graphics.setColor(c[1], c[2], c[3], 0.7 * k)
            love.graphics.ellipse('fill', m[2], m[3], m[4], m[5])
        elseif kind == 'line' then
            local pts, w = m[2], m[3]
            for i = 1, #pts - 1, 4 do halo(pts[i], pts[i + 1], w * 5, 0.22 * k, c) end
            love.graphics.setColor(c[1], c[2], c[3], 0.9 * k)
            love.graphics.setLineWidth(w)
            love.graphics.setLineJoin('bevel')
            love.graphics.line(pts)
        elseif kind == 'mesh' then
            love.graphics.setColor(c[1], c[2], c[3], 0.85 * k)
            love.graphics.draw(m[2])
        elseif kind == 'halo' then
            halo(m[2], m[3], m[4], 0.3 * k, c)
        end
    end
    love.graphics.pop()
end

return Skin
