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
local C = require('jar.config')
local Tank = require('jar.tank')
local Render = require('jar.render')
local Scape = require('jar.scape')
local Glass = require('jar.glass')

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local args = dev.parse(arg or {})
local world
local accumulator = 0
local tick = 0
local motes = {}
local snapFrames -- --snap: frames drawn since the sim was fast-forwarded

local light = C.LIGHT -- one still evening until the day cycle (#3)

local palette = {
    moss     = { 0.36, 0.52, 0.24 },
    stone    = { 0.42, 0.40, 0.37 },
    stoneLit = { 0.55, 0.53, 0.48 },
    mote     = { 1.00, 0.95, 0.80 },
}

local function step()
    tick = tick + 1
    world:snapshot()
    world:step(STEP)
    for _, m in ipairs(motes) do
        m.y = m.y - m.rise * STEP
        m.x = m.x + math.sin((tick + m.phase) * 0.01) * 6 * STEP
        if m.y < C.GLASS_T + 10 then m.y = C.SOIL_Y - 10 end
    end
end

function love.load()
    rng.seed(args.seed or SEED)
    if args.selftest then
        love.event.quit(dev.selftest(World, room, STEP) and 0 or 1)
        return
    end

    Render.init()
    Scape.init(rng.scape)
    Glass.init(rng.scape)

    world = World.new(room, { wander = not args.nowander, selected = 0 })
    for _ = 1, 40 do
        motes[#motes + 1] = {
            x = C.GLASS_L + rng.look:random() * (C.GLASS_R - C.GLASS_L),
            y = C.GLASS_T + rng.look:random() * (C.SOIL_Y - C.GLASS_T),
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

-- Everything in the jar, back to front. The scape behind FAR_D and the room
-- around the jar are drawn soft, as a shallow depth of field.
local function drawScene()
    local stones = Scape.getStones()

    love.graphics.setCanvas(Render.canvas("room"))
    love.graphics.clear(0, 0, 0, 1)
    Scape.drawRoom(light)
    love.graphics.setCanvas(Render.canvas("scene"))
    love.graphics.clear(0, 0, 0, 1)
    Render.drawSoft("room", 2.6)

    Glass.drawBack(light)
    Scape.drawBed()
    Render.beginObjects(light)

    love.graphics.setCanvas(Render.canvas("far"))
    love.graphics.clear(0, 0, 0, 0)
    local i = 1
    while stones[i] and stones[i].d < C.FAR_D do
        Scape.drawStone(stones[i])
        i = i + 1
    end
    love.graphics.setShader()
    love.graphics.setCanvas(Render.canvas("scene"))
    Render.drawSoft("far", 1.0)

    while stones[i] and stones[i].d < C.PLANE_D do
        Scape.drawStone(stones[i])
        i = i + 1
    end
    love.graphics.setShader()

    -- The creatures' plane, in level coordinates
    Tank.pushPlane()
    drawStones()
    drawCreatures(accumulator / STEP)
    for _, m in ipairs(motes) do
        love.graphics.setColor(palette.mote[1], palette.mote[2], palette.mote[3], 0.35)
        love.graphics.circle("fill", m.x, m.y, m.size)
    end
    love.graphics.pop()

    for j = i, #stones do Scape.drawStone(stones[j]) end
    love.graphics.setShader()

    Scape.drawFront()
    Glass.drawFront(light, love.mouse.getX())
    love.graphics.setCanvas()
end

-- The front glass bends the view a little at its edges; the room vignettes
local function composite()
    local sh = Render.shader("composite")
    love.graphics.setColor(1, 1, 1, 1)
    if sh then
        love.graphics.setShader(sh)
        sh:send("glassRect", { Glass.frontRect() })
        sh:send("aberration", 0.012)
        sh:send("vignette", 0.40)
        sh:send("grain", 0.010)
        sh:send("time", love.timer.getTime() % 1000)
        sh:send("size", { C.W, C.H })
    end
    love.graphics.draw(Render.canvas("scene"))
    love.graphics.setShader()
end

function love.draw()
    if not world then return end
    drawScene()
    composite()

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
