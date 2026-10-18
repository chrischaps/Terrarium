-- Terrarium: a sealed jar of moss where soft-bodied creatures live their whole lives.
-- Character's worm, blob and spider live among its soil, cork arch, twig bridge, cairn and shelf.
--
--   love .                   watch the jar
--   lovec . --selftest       graph integrity, reachability, trips, determinism, audio (see dev.lua)
--   lovec . --seed <n>       a different jar
--   lovec . --hour <h|name>  open the jar at an hour (default: the clock; snaps: midday)
--   lovec . --day <sec>      a time-compressed day, e.g. --day 120 to watch one pass
--   lovec . --snap - <sec> <file.png>   run <sec> of sim, save a screenshot to the save dir

-- Same require style as Character, so ported files can require('LoveLibs.physics.verlet') unchanged
love.filesystem.setRequirePath("lib/?.lua;lib/?/init.lua;" .. love.filesystem.getRequirePath())

local dev = require('dev')
local rng = require('core.rng')
local World = require('jar.world')
local room = require('jar.room')
local C = require('jar.config')
local Tank = require('jar.tank')
local Render = require('jar.render')
local Scape = require('jar.scape')
local Glass = require('jar.glass')
local DayCycle = require('jar.daycycle')
local Plants = require('jar.plants')
local Motes = require('jar.motes')
local Scenery = require('jar.scenery')
local Condensation = require('jar.condensation')
local Ballistics = require('nav.ballistics')

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local args = dev.parse(arg or {})
local world
local accumulator = 0
local snapFrames -- --snap: frames drawn since the sim was fast-forwarded
local objects = {} -- stones and plants, back to front

-- The hour the jar was opened at and how long its day is. Like the seed, these
-- are inputs: the hour at any moment is DayCycle.hourAt(startHour, world.time).
local startHour, daySeconds

local function step()
    world:snapshot()
    world:step(STEP) -- steps the plants too, as the world's flora
    Motes.update(STEP)
end

function love.load()
    rng.seed(args.seed or SEED)
    if args.selftest then
        love.event.quit(dev.selftest(World, room, STEP) and 0 or 1)
        return
    end
    if args.navdump then
        dev.navdump(World, room, args.navdump.who, args.navdump.solid)
        love.event.quit(0)
        return
    end

    Render.init()
    Scape.init(rng.scape)
    Glass.init(rng.scape)

    startHour = DayCycle.parseHour(args.hour) or (args.snap and DayCycle.presets.midday) or DayCycle.clockHour()
    daySeconds = args.day or C.DAY_SECONDS

    world = World.new(room, { wander = not args.nowander, selected = 0 })
    local ledges = {}
    for _, s in ipairs(world.level.solids) do
        if s.moss and s.kind == 'ledge' then ledges[#ledges + 1] = s end
    end
    Plants.init(rng.scape, Scape.getStones(), ledges)
    world.flora = Plants
    Motes.init(rng.look, 120)
    Scenery.init(rng.scape, world.level)
    Condensation.init(rng.scape) -- last, so the jar's composition doesn't shift

    for _, s in ipairs(Scape.getStones()) do objects[#objects + 1] = s end
    for _, p in ipairs(Plants.all()) do objects[#objects + 1] = p end
    table.sort(objects, function(a, b) return a.d < b.d end)

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

-- Terrarium: --nav shows every creature's graph in its own colour; --nav <who>
-- shows one, with its jumps and falls
local function drawNav()
    love.graphics.setShader()
    love.graphics.setLineWidth(1)
    for i = #world.graphs, 1, -1 do
        local g, who = world.graphs[i], world.creatures[i]
        if args.nav == true or args.nav == who.key then
            local c = who.color_name or { 1, 1, 1 }
            local off = args.nav == true and (i - 2) * 1.5 or 0
            for _, n in ipairs(g.nodes) do
                for _, e in ipairs(n.edges) do
                    local m = g.nodes[e.to]
                    if e.kind == 'walk' or e.kind == 'crawl' then
                        love.graphics.setColor(c[1], c[2], c[3], 0.6)
                        love.graphics.line(n.x, n.y + off, m.x, m.y + off)
                    elseif args.nav ~= true then
                        love.graphics.setColor(c[1], c[2], c[3], e.kind == 'fall' and 0.22 or 0.12)
                        love.graphics.line(Ballistics.sample_arc(e.ex or n.x, n.y, e.vx, e.vy, e.t, 12))
                    end
                end
            end
            for _, n in ipairs(g.nodes) do
                love.graphics.setColor(c[1], c[2], c[3], 0.95)
                love.graphics.circle('fill', n.x, n.y + off, 2)
            end
        end
    end
end

local function drawCreatures(alpha)
    -- Draw between the last two steps; the sim never sees the blended points
    world:interpolate(alpha)
    local ctx = { light_dir = world.light_dir }
    Render.useObject(C.PLANE_D)
    for _, c in ipairs(world.creatures) do
        if c.draw_trail then c:draw_trail() end
    end
    for _, c in ipairs(world.creatures) do c:draw(ctx) end
    love.graphics.setShader()
    for _, c in ipairs(world.creatures) do
        if c.draw_emissive then c:draw_emissive() end
    end
    world:restore()
end

local function drawObject(o)
    if o.kind == "plant" then Plants.draw(o) else Scape.drawStone(o) end
end

-- Everything in the jar, back to front. The scape behind FAR_D and the room
-- around the jar are drawn soft, as a shallow depth of field.
local function drawScene(light)
    love.graphics.setCanvas(Render.canvas("room"))
    love.graphics.clear(0, 0, 0, 1)
    Scape.drawRoom(light)
    love.graphics.setCanvas(Render.canvas("scene"))
    love.graphics.clear(0, 0, 0, 1)
    Render.drawSoft("room", 2.6)

    Glass.drawBack(light)
    Scape.drawBed(light)
    Render.beginObjects(light)

    love.graphics.setCanvas(Render.canvas("far"))
    love.graphics.clear(0, 0, 0, 0)
    local i = 1
    while objects[i] and objects[i].d < C.FAR_D do
        drawObject(objects[i])
        i = i + 1
    end
    love.graphics.setShader()
    love.graphics.setCanvas(Render.canvas("scene"))
    Render.drawSoft("far", 1.0)

    while objects[i] and objects[i].d < C.PLANE_D do
        drawObject(objects[i])
        i = i + 1
    end
    love.graphics.setShader()
    Motes.drawBack(light)

    -- The creatures' plane, in level coordinates
    Tank.pushPlane()
    Scenery.draw(light, world.time)
    drawCreatures(accumulator / STEP)
    if args.nav then drawNav() end
    love.graphics.pop()

    for j = i, #objects do drawObject(objects[j]) end
    love.graphics.setShader()

    Plants.drawGlow(light)
    Motes.drawFront(light)
    Scape.drawFront(light)
    Condensation.draw(light) -- on the inside of the glass, under its dust
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
    -- Render reads the jar's clock; it never moves it
    drawScene(DayCycle.evaluate(DayCycle.hourAt(startHour, world.time + accumulator, daySeconds)))
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
