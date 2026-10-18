-- Terrarium: a sealed jar of moss where soft-bodied creatures live their whole lives.
-- This is the placeholder scene from the repo scaffold: an empty jar, lit from above.

local lib = "lib/LoveLibs/"
package.path = package.path .. ";" .. lib .. "?.lua;" .. lib .. "?/init.lua"

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local rng
local accumulator = 0
local tick = 0
local motes = {}

local jar = { x = 240, y = 120, w = 800, h = 600, r = 48 }

local palette = {
    room     = { 0.06, 0.06, 0.08 },
    glass    = { 0.75, 0.88, 0.92, 0.18 },
    rim      = { 0.85, 0.95, 1.00, 0.35 },
    soilDeep = { 0.18, 0.12, 0.09 },
    soil     = { 0.27, 0.19, 0.13 },
    moss     = { 0.36, 0.52, 0.24 },
    lamp     = { 1.00, 0.86, 0.60 },
    mote     = { 1.00, 0.95, 0.80 },
}

local function step()
    tick = tick + 1
    for _, m in ipairs(motes) do
        m.y = m.y - m.rise * STEP
        m.x = m.x + math.sin((tick + m.phase) * 0.01) * 6 * STEP
        if m.y < jar.y + 20 then m.y = jar.y + jar.h * 0.75 end
    end
end

function love.load()
    rng = love.math.newRandomGenerator(SEED)
    for _ = 1, 40 do
        motes[#motes + 1] = {
            x = jar.x + rng:random() * jar.w,
            y = jar.y + rng:random() * jar.h * 0.7,
            rise = 2 + rng:random() * 6,
            phase = rng:random() * 1000,
            size = 0.8 + rng:random() * 1.4,
        }
    end
end

function love.update(dt)
    accumulator = accumulator + math.min(dt, 0.25)
    while accumulator >= STEP do
        step()
        accumulator = accumulator - STEP
    end
end

local function lampGlow()
    local cx = jar.x + jar.w / 2
    for i = 12, 1, -1 do
        local a = 0.012 * (13 - i)
        love.graphics.setColor(palette.lamp[1], palette.lamp[2], palette.lamp[3], a)
        love.graphics.ellipse("fill", cx, jar.y - 40, 60 * i, 40 * i)
    end
end

function love.draw()
    love.graphics.clear(palette.room)
    lampGlow()

    local x, y, w, h, r = jar.x, jar.y, jar.w, jar.h, jar.r
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, w, h, r, r)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    love.graphics.setColor(palette.soilDeep)
    love.graphics.rectangle("fill", x, y + h * 0.78, w, h * 0.22)
    love.graphics.setColor(palette.soil)
    love.graphics.rectangle("fill", x, y + h * 0.72, w, h * 0.08)
    love.graphics.setColor(palette.moss)
    love.graphics.rectangle("fill", x, y + h * 0.70, w, h * 0.03)

    for _, m in ipairs(motes) do
        love.graphics.setColor(palette.mote[1], palette.mote[2], palette.mote[3], 0.35)
        love.graphics.circle("fill", m.x, m.y, m.size)
    end

    love.graphics.setStencilTest()

    love.graphics.setColor(palette.glass)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setColor(palette.rim)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    love.graphics.rectangle("fill", x + 40, y + 30, 6, h * 0.5, 3, 3) -- glass highlight
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
end
