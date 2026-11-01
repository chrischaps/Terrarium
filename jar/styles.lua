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
-- A style that says `matte = true` is sent the frame's matte too (#98,
-- jar/matte.lua): which pixels are a creature, what kind of layer each is, and
-- how deep. main.lua draws one only for such a style. It's given as `seen`,
-- {matte, zoom}: zoom is how much nearer than the window a plate is, so a
-- line drawn round a creature can keep its weight on a portrait.
--
-- A style is drawing only. It sees the frame's pixels and nothing of the
-- World, so a jar hashes the same under every style (tests/ci.sh watches one
-- in a window under each of them).

local Render = require('jar.render')

local Styles = {}

Styles.DEFAULT = 'none'

Styles.list = {
    { name = 'none' },
    -- The seam's own test: the jar as a silver gelatin print, its light as
    -- grey on a gentle curve, the paper a little warm and the shadows a
    -- little cool, as a selenium-toned print's are
    { name = 'silver', shader = 'styles/silver', setup = function(sh)
        sh:send('tone', 0.6)
    end },
}

-- The probes (#98, a spike): what a style can do with a matte. They're only
-- in the list with --probes, so play, Tab and CI's watched styles don't see
-- them unless asked
local function sized(sh, w, h, _, seen)
    sh:send('px', { 1 / w, 1 / h })
    -- (a plate's lines a little lighter than its zoom, as a pen's are close up)
    sh:send('scale', seen.zoom and seen.zoom ^ 0.6 or math.max(1, h / 800))
end
Styles.probes = {
    -- the matte itself, in false colour: what a matte style is told
    { name = 'probe-matte', shader = 'styles/matte_view', matte = true },
    -- a hand-inked line round the creatures, and round nothing else
    { name = 'probe-ink', shader = 'styles/ink', matte = true, setup = sized },
    -- the scenery cut flat from paper in layers, the creatures as they are
    { name = 'probe-cut', shader = 'styles/cut', matte = true, setup = sized },
}

local by_name = {}
local function index()
    for i, s in ipairs(Styles.list) do
        s.index = i
        by_name[s.name] = s
    end
end
index()

-- --probes: the probes join the list, after the styles
function Styles.enable_probes()
    for _, s in ipairs(Styles.probes) do
        if not by_name[s.name] then Styles.list[#Styles.list + 1] = s end
    end
    index()
end

-- Does style `name` read the matte?
function Styles.wants_matte(name)
    local s = by_name[name]
    return s ~= nil and s.matte == true
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
-- to load, or a matte style given no matte), else a canvas of its size drawn
-- through the style's shader. It leaves the caller's canvas, transform and
-- shader as they were.
function Styles.apply(name, frame, time, seen)
    local s = by_name[name]
    local sh = s and s.shader and Render.shader(s.shader)
    if not sh or (s.matte and not (seen and seen.matte)) then return frame end
    local w, h = frame:getDimensions()
    local out = canvas(w, h)
    love.graphics.push('all')
    love.graphics.setCanvas(out)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(sh)
    if s.setup then s.setup(sh, w, h, time, seen or {}) end
    if s.matte then sh:send('matte', seen.matte) end
    love.graphics.draw(frame)
    love.graphics.pop()
    return out
end

return Styles
