-- Terrarium: the jar's looks (#93, #94). A style is a pass over the finished
-- frame, or a few: the whole jar drawn, then the style, then the front glass
-- bending it and the room vignetting it (main.lua's composite). The window,
-- --snap and a capture script's frames and plates all go through it, so a
-- capture shows what the window shows.
--
-- A style is {name, shader, setup(sh, w, h, time, frame)}. `shader` is a
-- file in shaders/ (styles live in shaders/styles/), loaded through
-- Render.shader, so one that doesn't compile prints its error and the frame
-- goes through as it was. `setup` sends the shader what it needs for a w x h
-- frame at `time`. A style that takes more than one pass lists them instead,
-- `passes = {{shader, setup, scale}, ...}` (#96): each draws the one before
-- it (the first draws the frame) onto a canvas `scale` times the frame's size
-- (1 if absent), and `frame`, handed to every setup, is the jar as it was
-- drawn. `none` has no shader: it's the jar as it has always looked, and the
-- default.
--
-- A style is drawing only. It sees the frame's pixels and nothing of the
-- World, so a jar hashes the same under every style (tests/ci.sh watches one
-- in a window under each of them). Nor does it read the clock for anything
-- that moves: a still jar is a still picture.

local Render = require('jar.render')
local W = require('jar.config').W

local Styles = {}

Styles.DEFAULT = 'none'

-- One pixel of the window's frame (C.W wide) in texture coordinates of a
-- w x h frame, so a style looks the same at every size a script renders at
function Styles.px(w, h) return { 1 / W, w / (W * h) } end

Styles.list = {
    { name = 'none' },
    -- The seam's own test: the jar as a silver gelatin print, its light as
    -- grey on a gentle curve, the paper a little warm and the shadows a
    -- little cool, as a selenium-toned print's are
    { name = 'silver', shader = 'styles/silver', setup = function(sh)
        sh:send('tone', 0.6)
    end },
    -- The jar painted (#96). Its washes are the frame flattened at half size
    -- (a Kuwahara filter: each pixel takes the calmest of the eight sectors
    -- round it), bled a little past their lines. Then they're laid on paper:
    -- pooled dark at their wet edges, mottled where the pigment dried
    -- unevenly, settled into the paper's tooth where they're thick, over a
    -- faint pencil underdrawing, with the lights left as paper and the glows
    -- still glowing. All its noise is fixed to the frame.
    { name = 'watercolour', passes = {
        { shader = 'styles/watercolour_wash', scale = 0.5, setup = function(sh, w, h)
            sh:send('px', Styles.px(w, h))
        end },
        { shader = 'styles/watercolour', setup = function(sh, w, h, _, frame)
            sh:send('frame', frame)
            sh:send('px', Styles.px(w, h))
        end },
    } },
}

-- A style's passes: its own list, or its one shader as a list of one
function Styles.passes(s)
    if s.passes then return s.passes end
    if s.shader then return { { shader = s.shader, setup = s.setup } } end
    return {}
end

local by_name = {}
for i, s in ipairs(Styles.list) do
    s.index = i
    by_name[s.name] = s
end

function Styles.get(name) return by_name[name] end

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

-- One canvas per pass and size: the window's, and each size a script renders at
local canvases = {}
local function canvas(i, w, h)
    local key = i .. ':' .. w .. 'x' .. h
    if not canvases[key] then
        canvases[key] = love.graphics.newCanvas(w, h, { format = 'rgba16f' })
        canvases[key]:setFilter('linear', 'linear')
    end
    return canvases[key]
end

-- The frame in style `name`: `frame` itself for none (or a style with a
-- shader that failed to load), else a canvas of its size drawn through the
-- style's passes. It leaves the caller's canvas, transform and shader as
-- they were.
function Styles.apply(name, frame, time)
    local s = by_name[name]
    local passes, shaders = s and Styles.passes(s) or {}, {}
    if #passes == 0 then return frame end
    for i, p in ipairs(passes) do
        shaders[i] = Render.shader(p.shader)
        if not shaders[i] then return frame end
    end
    local w, h = frame:getDimensions()
    local src = frame
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    for i, p in ipairs(passes) do
        local k = p.scale or 1
        local out = canvas(i, math.floor(w * k + 0.5), math.floor(h * k + 0.5))
        local ow, oh = out:getDimensions()
        local sw, sh = src:getDimensions()
        love.graphics.setCanvas(out)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setShader(shaders[i])
        if p.setup then p.setup(shaders[i], w, h, time, frame) end
        love.graphics.draw(src, 0, 0, 0, ow / sw, oh / sh)
        src = out
    end
    love.graphics.pop()
    return src
end

return Styles
