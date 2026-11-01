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
-- the colour fringe toward its edges and the film's grain. A style may set its
-- own `glass` (a drawing on paper has neither).
Styles.GLASS = { aberration = 0.012, grain = 0.010 }

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
    { name = 'pencil', shader = 'styles/pencil', glass = { aberration = 0, grain = 0 },
        setup = function(sh, w, h, time)
            sh:send('paper', paper())
            sh:send('size', { w, h })
            sh:send('time', time % 1000)
            sh:send('boil', 0.5)
            sh:send('exposure', 6.5)
            sh:send('contrast', 1.6)
        end },
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
local canvases = {}
local function canvas(w, h)
    local key = w .. 'x' .. h
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

return Styles
