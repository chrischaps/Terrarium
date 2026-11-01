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
-- A style that needs more than one pass brings `draw(frame, time, kx, ky)`
-- instead, and returns its canvas and the scale to draw that at. `kx`, `ky`
-- are how many of the target's pixels a pixel of the frame covers, so it can
-- draw at the target's own pixels and stay sharp (ascii's glyphs at 1080p).
-- One with a size to it brings `adjust(dir)` ([ and ] in play) and `label()`,
-- what the corner says it is.
--
-- A style is drawing only. It sees the frame's pixels and nothing of the
-- World, so a jar hashes the same under every style (tests/ci.sh watches one
-- in a window under each of them).

local Render = require('jar.render')
local Ascii = require('jar.ascii')

local Styles = {}

Styles.DEFAULT = 'none'

-- What the front glass does to a frame after its style (main.lua's composite):
-- the colour fringe toward its edges and the film's grain. A style may set its
-- own `glass` (a drawing on paper has neither).
Styles.GLASS = { aberration = 0.012, grain = 0.010 }

Styles.list = {
    { name = 'none' },
    -- The seam's own test: the jar as a silver gelatin print, its light as
    -- grey on a gentle curve, the paper a little warm and the shadows a
    -- little cool, as a selenium-toned print's are
    { name = 'silver', shader = 'styles/silver', setup = function(sh)
        sh:send('tone', 0.6)
    end },
    -- The jar on a character grid, a moth-eaten roguelike of moss and
    -- creatures (#97, jar/ascii.lua): a glyph a cell by its light, a stroke
    -- where an edge runs through it, inked in the cell's colour. No fringe:
    -- the glass would split a glyph's fine strokes into their colours.
    { name = 'ascii', shader = 'styles/ascii', draw = Ascii.draw,
        adjust = Ascii.step, label = Ascii.label, glass = { aberration = 0, grain = 0.010 } },
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

-- What the corner calls style `name` when it's switched to or resized
function Styles.label(name)
    local s = by_name[name]
    return s and s.label and s.label() or name
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

-- The frame in style `name`, and the scale to draw it at: `frame` itself for
-- none (or a shader that failed to load), else a canvas of its size drawn
-- through the style's shader, or what the style's own `draw` makes of it at
-- `kx` x `ky` of the target's pixels to a frame pixel. It leaves the caller's
-- canvas, transform and shader as they were.
function Styles.apply(name, frame, time, kx, ky)
    local s = by_name[name]
    if s and s.draw then return s.draw(frame, time, kx, ky) end
    local sh = s and s.shader and Render.shader(s.shader)
    if not sh then return frame, 1, 1 end
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
    return out, 1, 1
end

return Styles
