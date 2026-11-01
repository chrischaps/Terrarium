-- Terrarium: the matte (#98), a spike. A style (#94) sees only the finished
-- frame's colour, so it can't tell a worm from the stone it's on, or know
-- what's in front of what. The matte is a side canvas the size of the frame
-- that says, for every pixel: is it a creature (r), what kind of layer it is
-- (g), and how deep (b).
--
-- The draw code says which layer it's drawing with `Matte.mark(kind, d)`, in
-- the order it already draws in. Outside the matte a mark does nothing. The
-- matte itself is the plane drawn again (main.lua's drawMatte) inside
-- `Matte.draw`, which for that pass puts the matte shader in place of every
-- shader the draw code asks for and leaves out everything drawn additively
-- (glows, light), so each draw lays down only its shape. The real frame is
-- never drawn this way, and a jar never knows it's being matted.
--
-- Why a second pass and not MRT (setCanvas{scene, matte}): LÖVE's default
-- shader, and every `vec4 effect` shader, writes its colour to every canvas
-- bound, so one pass would need every shader on the plane rewritten as
-- `void effect()` with love_Canvases[]. The spike measures the second pass;
-- see the write-up in #98 for what MRT would save.

local Render = require('jar.render')

local Matte = {}

-- The layers, back to front as the jar draws them. 0 is nothing drawn: the
-- room, the back glass, the light
Matte.KINDS = { soil = 1, scape = 2, solid = 3, moss = 4, small = 5, creature = 6 }
Matte.LAST = 6

local active = false
local shader
local real = {}
local wanted, drawing = true, true -- this layer goes in; this blend isn't additive

local function mask()
    local on = wanted and drawing
    love.graphics.setColorMask(on, on, on, on)
end

-- The layer drawn from here on: one of KINDS at depth d (0 back, 1 front),
-- or nil for something that isn't a layer and stays out of the matte
function Matte.mark(kind, d)
    if not active then return end
    wanted = kind ~= nil
    drawing = true
    if wanted then
        local k = Matte.KINDS[kind]
        shader:send('layer', { kind == 'creature' and 1 or 0, k / Matte.LAST, math.max(0, math.min(1, d or 0)) })
    end
    real.setBlendMode('alpha', 'premultiplied')
    mask()
end

function Matte.active() return active end

-- One matte per frame size (the window's, and each a plate is drawn at). Eight
-- bits a channel is enough: a creature, one of seven kinds, and 256 depths
local canvases = {}
function Matte.canvas(w, h)
    local key = w .. 'x' .. h
    if not canvases[key] then
        canvases[key] = love.graphics.newCanvas(w, h)
        canvases[key]:setFilter('linear', 'linear')
    end
    return canvases[key]
end

-- Run `fn` (which draws) into `canvas` as a matte. Nothing outside it changes:
-- the caller's canvas, shader, blend mode and colour mask are as they were.
function Matte.draw(canvas, fn)
    shader = shader or Render.shader('matte')
    if not shader then return false end
    local g = love.graphics
    g.push('all')
    g.setCanvas(canvas)
    g.origin()
    g.clear(0, 0, 0, 1)
    real.setShader, real.setBlendMode = g.setShader, g.setBlendMode
    real.setShader(shader)
    -- (push('all')/pop put back what the matte set, so these only need to
    -- catch what the draw code sets itself)
    g.setShader = function() real.setShader(shader) end
    g.setBlendMode = function(mode)
        drawing = mode == 'alpha' or mode == 'replace' or mode == nil
        real.setBlendMode('alpha', 'premultiplied')
        mask()
    end
    active = true
    Matte.mark(nil)
    local ok, err = pcall(fn)
    active = false
    g.setShader, g.setBlendMode = real.setShader, real.setBlendMode
    g.pop()
    if not ok then error(err, 0) end
    return true
end

return Matte
