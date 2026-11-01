-- Terrarium: the jar's looks (#93, #94). A style is one pass over the finished
-- frame: the whole jar drawn, then the style, then the front glass bending it
-- and the room vignetting it (main.lua's composite). The window, --snap and a
-- capture script's frames and plates all go through it, so a capture shows
-- what the window shows.
--
-- A style is {name, shader, setup(sh, w, h, time)}. `shader` is a file in
-- shaders/ (styles live in shaders/styles/), loaded through Render.shader, so
-- one that doesn't compile prints its error and the frame goes through as it
-- was. `setup` sends the shader what it needs for a w x h frame at `time`.
-- `none` has no shader: it's the jar as it has always looked, and the default.
--
-- A style is drawing only. It sees the frame's pixels and nothing of the
-- World, so a jar hashes the same under every style (tests/ci.sh watches one
-- in a window under each of them).

local Render = require('jar.render')
local bit = require('bit')

local Styles = {}

Styles.DEFAULT = 'none'

-- What the front glass does to a frame after its style (main.lua's composite):
-- the colour fringe toward its edges, the film's grain and the room's vignette. A
-- style may set its own `glass` (a drawing on paper has no fringe or grain).
Styles.GLASS = { aberration = 0.012, grain = 0.010, vignette = 0.40 }

-- A sheet of drawing paper, made once the first time it's asked for: PAPER
-- px square, tiling, r its tooth (fine, a little long in the grain, as laid
-- paper's is), g a mottle (where the sheet took more size or less), b a slow
-- wobble for a line to wander by. It's made by hashing, so it draws from no
-- stream and is the same sheet every time.
Styles.PAPER = 512
local sheet
local function paper()
    if sheet then return sheet end
    local N = Styles.PAPER
    -- one octave of tiling value noise: a lattice of `cw` x `ch` px cells
    local function octave(cw, ch, seed)
        local nx, ny = N / cw, N / ch
        local grid = {}
        for j = 0, ny - 1 do
            for i = 0, nx - 1 do
                local h = bit.bxor(bit.tobit(i * 73856093), bit.tobit(j * 19349663), bit.tobit(seed * 83492791))
                h = bit.bxor(h, bit.rshift(h, 13))
                h = bit.tobit(bit.band(h, 0xfffff) * 1046527 + bit.rshift(h, 20))
                h = bit.bxor(h, bit.rshift(h, 16))
                grid[j * nx + i] = bit.band(h, 0xffff) / 0xffff
            end
        end
        return function(x, y)
            local fx, fy = x / cw, y / ch
            local i, j = math.floor(fx), math.floor(fy)
            local u, v = fx - i, fy - j
            u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
            local i1, j1 = (i + 1) % nx, (j + 1) % ny
            local a, b = grid[j * nx + i], grid[j * nx + i1]
            local c, d = grid[j1 * nx + i], grid[j1 * nx + i1]
            return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
        end
    end
    local fine, fibre, coarse = octave(1, 1, 1), octave(4, 1, 2), octave(8, 8, 3)
    local m1, m2, m3 = octave(128, 128, 4), octave(32, 32, 5), octave(16, 16, 6)
    local wobble = octave(64, 64, 7)
    local data = love.image.newImageData(N, N)
    data:mapPixel(function(x, y)
        local tooth = 0.25 * fine(x, y) + 0.45 * fibre(x, y) + 0.30 * coarse(x, y)
        tooth = math.min(1, math.max(0, (tooth - 0.5) * 2.2 + 0.5))
        local mottle = 0.55 * m1(x, y) + 0.30 * m2(x, y) + 0.15 * m3(x, y)
        return tooth, mottle, wobble(x, y), 1
    end)
    sheet = love.graphics.newImage(data)
    sheet:setWrap('repeat', 'repeat')
    sheet:setFilter('linear', 'linear')
    return sheet
end

-- Under pencil-each, how much of the page round the things in the jar is
-- drawn: a wash of graphite as deep as `wash` where it's darkest, and the
-- edges there `line` as hard as a thing's own
Styles.GROUND = { wash = 0.14, line = 0.2 }

-- What both pencil passes are sent (shaders/styles/pencil_common.glsl)
local function pencil(sh, w, h, time)
    sh:send('paper', paper())
    sh:send('size', { w, h })
    sh:send('time', time % 1000)
    sh:send('boil', 0.5)
    sh:send('exposure', 6.5)
    sh:send('contrast', 1.6)
end

Styles.list = {
    { name = 'none' },
    -- The seam's own test: the jar as a silver gelatin print, its light as
    -- grey on a gentle curve, the paper a little warm and the shadows a
    -- little cool, as a selenium-toned print's are
    { name = 'silver', shader = 'styles/silver', setup = function(sh)
        sh:send('tone', 0.6)
    end },
    -- A sketchbook page (#95): the jar's edges in graphite, its shade
    -- hatched, crossed where it's dark, its light the bare paper. The
    -- hatching is anchored to the page and holds still; the line boils a
    -- little, as a drawn line does. Paper takes no fringe or film grain.
    -- The whole finished frame is drawn at once.
    { name = 'pencil', shader = 'styles/pencil', glass = { aberration = 0, grain = 0, vignette = 0.40 },
        setup = function(sh, w, h, time)
            pencil(sh, w, h, time)
            sh:send('masked', 0)
        end },
    -- The same page with each thing in the jar drawn on its own first (#95's
    -- A/B, which it won): every creature, piece of scenery, stone and fern,
    -- the soil's bed, the moss, and the small things together, each with its
    -- outline from its own silhouette and its hatching on itself (`each`, a
    -- pass main.lua runs per thing), a creature's riding with it. What's left
    -- is the ground they're drawn on: the room, the air and the far side of
    -- the jar, kept to the paper, a faint wash of graphite where it's dark
    -- (GROUND.wash) and its edges a faint line (GROUND.line).
    { name = 'pencil-each', shader = 'styles/pencil', glass = { aberration = 0, grain = 0, vignette = 0.12 },
        setup = function(sh, w, h, time)
            pencil(sh, w, h, time)
            sh:send('masked', 1)
            sh:send('ground', { Styles.GROUND.wash, Styles.GROUND.line })
        end,
        each = { shader = 'styles/pencil_body', setup = pencil } },
}

local by_name = {}
for i, s in ipairs(Styles.list) do
    s.index = i
    by_name[s.name] = s
end

function Styles.get(name) return by_name[name] end

-- The glass's fringe and grain over a frame in style `name`
function Styles.glass(name)
    local s = by_name[name]
    return s and s.glass or Styles.GLASS
end

function Styles.names()
    local out = {}
    for i, s in ipairs(Styles.list) do out[i] = s.name end
    return out
end

-- The style after `name`, round to the first again (the Tab key in play)
function Styles.after(name)
    local s = by_name[name] or by_name[Styles.DEFAULT]
    return Styles.list[s.index % #Styles.list + 1].name
end

-- One canvas per frame size: the window's, and each size a script renders at
-- (and another of each for a body drawn on its own)
local canvases = {}
local function canvas(w, h, what)
    local key = (what or '') .. w .. 'x' .. h
    if not canvases[key] then
        canvases[key] = love.graphics.newCanvas(w, h, { format = 'rgba16f' })
        canvases[key]:setFilter('linear', 'linear')
    end
    return canvases[key]
end

-- The frame in style `name`: `frame` itself for none (or a shader that failed
-- to load), else a canvas of its size drawn through the style's shader. It
-- leaves the caller's canvas, transform and shader as they were.
function Styles.apply(name, frame, time)
    local s = by_name[name]
    local sh = s and s.shader and Render.shader(s.shader)
    if not sh then return frame end
    local w, h = frame:getDimensions()
    local out = canvas(w, h)
    love.graphics.push('all')
    love.graphics.setCanvas(out)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(sh)
    if s.setup then s.setup(sh, w, h, time) end
    love.graphics.draw(frame)
    love.graphics.pop()
    return out
end

-- Whether style `name` draws each creature on its own (pencil-each)
function Styles.each(name)
    local s = by_name[name]
    return s and s.each and Render.shader(s.each.shader) and true or false
end

-- One thing under a style that draws each on its own (a creature, a stone, a
-- piece of the scenery): `draw()` draws it, as it would be drawn into the
-- canvas being drawn into, onto a clear canvas the same size, and that's laid
-- into the canvas through the style's body pass, which also takes the thing
-- out of the canvas's alpha so the frame's own pass leaves it be. x0, y0, x1,
-- y1 bound it and ax, ay is its middle (the bounds' middle if not given), all
-- in that canvas's px; `seed` is its own. Drawing only, like the style.
local quad
local MARGIN = 8
function Styles.body(name, time, x0, y0, x1, y1, ax, ay, seed, draw)
    local s = by_name[name]
    local sh = Render.shader(s.each.shader)
    local target = love.graphics.getCanvas()
    local w, h
    if target then w, h = target:getDimensions() else w, h = love.graphics.getDimensions() end
    x0, y0 = math.max(0, math.floor(x0)), math.max(0, math.floor(y0))
    x1, y1 = math.min(w, math.ceil(x1)), math.min(h, math.ceil(y1))
    if x1 <= x0 or y1 <= y0 then return end
    ax, ay = ax or (x0 + x1) / 2, ay or (y0 + y1) / 2
    local alone = canvas(w, h, 'body')
    love.graphics.push('all')
    love.graphics.setCanvas(alone)
    -- (cleared a little past where it's laid in, since the line's samples
    -- reach over the edge, and the last body drawn alone is still there)
    local m = MARGIN
    local cx0, cy0 = math.max(0, x0 - m), math.max(0, y0 - m)
    love.graphics.setScissor(cx0, cy0, math.min(w, x1 + m) - cx0, math.min(h, y1 + m) - cy0)
    love.graphics.clear(0, 0, 0, 0)
    draw()
    love.graphics.pop()

    quad = quad or love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    quad:setViewport(x0, y0, x1 - x0, y1 - y0, w, h)
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(sh)
    s.each.setup(sh, w, h, time)
    sh:send('anchor', { ax, ay })
    sh:send('seed', seed)
    sh:send('mask', 0)
    love.graphics.setColorMask(true, true, true, false)
    love.graphics.setBlendMode('alpha', 'premultiplied')
    love.graphics.draw(alone, quad, x0, y0)
    sh:send('mask', 1)
    love.graphics.setColorMask(false, false, false, true)
    love.graphics.setBlendMode('multiply', 'premultiplied')
    love.graphics.draw(alone, quad, x0, y0)
    love.graphics.pop()
end

return Styles
