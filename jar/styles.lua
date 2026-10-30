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
