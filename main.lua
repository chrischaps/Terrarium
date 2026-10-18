-- Terrarium: a sealed jar of moss where soft-bodied creatures live their whole lives.
-- For now the jar is a test room (soil and one stone) with Character's worm, blob and spider.
--
--   love .                   watch the jar
--   lovec . --selftest       graph integrity, reachability, trips, determinism, audio (see dev.lua)
--   lovec . --seed <n>       a different jar
--   lovec . --snap - <sec> <file.png>   run <sec> of sim, save a screenshot to the save dir

-- Same require style as Character, so ported files can require('LoveLibs.physics.verlet') unchanged
love.filesystem.setRequirePath("lib/?.lua;lib/?/init.lua;" .. love.filesystem.getRequirePath())

local dev = require('dev')
local rng = require('core.rng')
local World = require('jar.world')
local room = require('jar.testroom')

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local args = dev.parse(arg or {})
local world
local accumulator = 0
local tick = 0
local motes = {}
local snapFrames -- --snap: frames drawn since the sim was fast-forwarded

local jar = { x = 240, y = 120, w = room.width, h = room.height, r = 48 }

local palette = {
    room     = { 0.06, 0.06, 0.08 },
    glass    = { 0.75, 0.88, 0.92, 0.18 },
    rim      = { 0.85, 0.95, 1.00, 0.35 },
    soilDeep = { 0.18, 0.12, 0.09 },
    soil     = { 0.27, 0.19, 0.13 },
    moss     = { 0.36, 0.52, 0.24 },
    stone    = { 0.42, 0.40, 0.37 },
    stoneLit = { 0.55, 0.53, 0.48 },
    lamp     = { 1.00, 0.86, 0.60 },
    mote     = { 1.00, 0.95, 0.80 },
}

local function step()
    tick = tick + 1
    world:snapshot()
    world:step(STEP)
    for _, m in ipairs(motes) do
        m.y = m.y - m.rise * STEP
        m.x = m.x + math.sin((tick + m.phase) * 0.01) * 6 * STEP
        if m.y < 20 then m.y = jar.h * 0.75 end
    end
end

function love.load()
    rng.seed(args.seed or SEED)
    if args.selftest then
        love.event.quit(dev.selftest(World, room, STEP) and 0 or 1)
        return
    end

    world = World.new(room, { wander = not args.nowander, selected = 0 })
    for _ = 1, 40 do
        motes[#motes + 1] = {
            x = rng.look:random() * jar.w,
            y = rng.look:random() * jar.h * 0.7,
            rise = 2 + rng.look:random() * 6,
            phase = rng.look:random() * 1000,
            size = 0.8 + rng.look:random() * 1.4,
        }
    end

    if args.snap then
        for _ = 1, math.floor((args.snap.seconds or 1) / STEP) do step() end
        snapFrames = 0
    end
end

function love.update(dt)
    if not world or snapFrames then return end
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

-- Ledges and stones from the room (the soil is drawn as bands below)
local function drawStones()
    for _, s in ipairs(world.level.solids) do
        if s.kind == 'ledge' then
            love.graphics.setColor(0, 0, 0, 0.18)
            love.graphics.ellipse("fill", s.x + s.w / 2, world.level.by_id.soil.y, s.w * 0.55, 6)
            love.graphics.setColor(palette.stone)
            love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 10, 10)
            love.graphics.setColor(palette.stoneLit)
            love.graphics.rectangle("fill", s.x + 4, s.y + 2, s.w - 8, s.h * 0.35, 6, 6)
            if s.moss then
                love.graphics.setColor(palette.moss)
                love.graphics.rectangle("fill", s.x + 6, s.y - 2, s.w - 12, 5, 2, 2)
            end
        end
    end
end

local function drawCreatures(alpha)
    -- Draw between the last two steps; the sim never sees the blended points
    world:interpolate(alpha)
    local ctx = { light_dir = world.light_dir }
    for _, c in ipairs(world.creatures) do
        if c.draw_trail then c:draw_trail() end
    end
    for _, c in ipairs(world.creatures) do c:draw(ctx) end
    for _, c in ipairs(world.creatures) do
        if c.draw_emissive then c:draw_emissive() end
    end
    world:restore()
end

function love.draw()
    if not world then return end
    love.graphics.clear(palette.room)
    lampGlow()

    local x, y, w, h, r = jar.x, jar.y, jar.w, jar.h, jar.r
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, w, h, r, r)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.setColor(palette.soilDeep)
    love.graphics.rectangle("fill", 0, h * 0.78, w, h * 0.22)
    love.graphics.setColor(palette.soil)
    love.graphics.rectangle("fill", 0, h * 0.72, w, h * 0.08)
    love.graphics.setColor(palette.moss)
    love.graphics.rectangle("fill", 0, h * 0.70, w, h * 0.03)

    drawStones()
    drawCreatures(accumulator / STEP)

    for _, m in ipairs(motes) do
        love.graphics.setColor(palette.mote[1], palette.mote[2], palette.mote[3], 0.35)
        love.graphics.circle("fill", m.x, m.y, m.size)
    end
    love.graphics.pop()

    love.graphics.setStencilTest()

    love.graphics.setColor(palette.glass)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setColor(palette.rim)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    love.graphics.rectangle("fill", x + 40, y + 30, 6, h * 0.5, 3, 3) -- glass highlight

    if snapFrames then
        snapFrames = snapFrames + 1
        local file = args.snap.file or "snap.png"
        if snapFrames == 2 then
            love.graphics.captureScreenshot(file)
        elseif snapFrames > 3 then
            print("[dev] saved " .. love.filesystem.getSaveDirectory() .. "/" .. file)
            love.event.quit()
        end
    end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
end
