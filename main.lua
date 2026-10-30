-- Terrarium: a sealed jar of moss where soft-bodied creatures live their whole lives.
-- Character's worm, blob and spider live among its soil, cork arch, twig bridge, cairn and shelf.
--
--   love .                   watch the jar
--   lovec . --selftest       graph integrity, reachability, trips, determinism, audio (see dev.lua)
--   lovec . --seed <n>       a different jar
--   lovec . --hour <h|name>  open the jar at an hour (default: the clock; snaps: midday)
--   lovec . --day <sec>      a time-compressed day, e.g. --day 120 to watch one pass
--   lovec . --snap - <sec> <file.png>   run <sec> of sim, save a screenshot to the save dir
--   lovec . --follow <who>   hold the lantern up to the worm, blob or spider (click to follow in play)
--   right-click              drop a pinch of food into the jar there (a few a day)
--   the book on the desk, b  open the family book (#32); click a page to turn it, off it to close
--   m                        hush the jar, or listen again (--mute opens it hushed)
--   love . --frame           the Pi frame (#90): fullscreen, no cursor, no keys; a tap
--                            follows, a long press drops food, and SIGTERM quits
--                            through love.quit, leaving $EASEL_DATA/thumb.png if it's set
--   lovec . --replay <sec>   open the jar twice, run <sec> of sim, check both hash the same
--   lovec . --test <name>    one self-test (graphs, trips, framerate, lantern, day, replay, genome, worm, blob, audio)
--   lovec . --genome "worm segments=24 stiffness=0.9"   the first worm has this body
--   love . --script scripts/lineup.lua   run a capture script: offscreen, frame-exact stills
--   lovec . --headless --script scripts/listen.lua   a jar's scenes as a WAV, to hear with your eyes closed
--   sh tests/ci.sh           what CI runs; test modes have no window (core/headless.lua)

-- Same require style as Character, so ported files can require('LoveLibs.physics.verlet') unchanged
love.filesystem.setRequirePath("lib/?.lua;lib/?/init.lua;" .. love.filesystem.getRequirePath())

-- No window (conf.lua): stand in a null renderer before anything that draws loads
local headless = require('core.headless')
if headless.active() then headless.install() end

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
local Moss = require('jar.moss')
local Eggs = require('jar.eggs')
local Remains = require('jar.remains')
local Food = require('jar.food')
local Condensation = require('jar.condensation')
local Lantern = require('jar.lantern')
local Ballistics = require('nav.ballistics')
local Genome = require('genome')
local Synth = require('core.synth')
local Screen = require('core.screen')
local Touch = require('core.touch')
local Book = require('book')
local Pages = require('jar.pages')

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local args = dev.parse(arg or {})
local world
local accumulator = 0
local snapFrames -- --snap: frames drawn since the sim was fast-forwarded
local objects = {} -- stones and plants, back to front
local lantern = Lantern.new() -- you watch with it; the World never knows it's there
local synth -- the jar heard through its glass (#28), only while you watch it live
local bench -- --bench: frame, update and draw times, once the eggs have hatched
local capture -- --script: {co = coroutine, last = canvas}
local scriptApi -- defined below love.load; forward-declared so load can see it
local sitting -- a portrait for the family book (#32), defined with the plates below
local view = Screen.fit(C.W, C.H, C.W, C.H) -- the jar's view on the window (#90)
local touch = Touch.new() -- a finger on the frame's glass
local book -- the family book (#32): everyone who has lived in the jar
local pages -- and the book itself, on the desk and open, wherever there's a window

-- The hour the jar was opened at and how long its day is. Like the seed, these
-- are inputs: the hour at any moment is DayCycle.hourAt(startHour, world.time).
local startHour, daySeconds

local function step(w)
    w = w or world
    w:snapshot()
    w:step(STEP) -- steps the plants too, as the world's flora
    Motes.update(STEP)
end

-- Compose the jar from its seed: the scape, glass, plants and scenery draw
-- from rng.scape in this order, the creatures from rng.sim, the motes from
-- rng.look. The replay check in dev.lua opens jars the same way (at midday,
-- with a full-length day). The hour and day length are inputs like the seed:
-- minds sleep and wake by them. `level` is the jar's room unless a capture
-- script brings its own. Who lives in it is the seed's cast (#74), or `cast`,
-- or --cast's.
local function openJar(seed, hour, day, level, cast)
    rng.seed(seed)
    Scape.init(rng.scape)
    Glass.init(rng.scape)
    local w = World.new(level or room, { wander = not args.nowander, selected = 0, hour = hour, day = day,
        genomes = args.genomes, cast = cast or args.cast, seed = seed })
    local ledges = {}
    for _, s in ipairs(w.level.solids) do
        if s.moss and s.kind == 'ledge' then ledges[#ledges + 1] = s end
    end
    Plants.init(rng.scape, Scape.getStones(), ledges)
    w.flora = Plants
    Motes.init(rng.look, 120)
    Scenery.init(rng.scape, w.level)
    Condensation.init(rng.scape) -- last, so the jar's composition doesn't shift
    -- The lantern follows by index: when one goes back to the moss, it lets go
    -- of it, and keeps up with the others as they're renumbered
    w.events:on(function(ev)
        if ev.kind == 'returned' then lantern:forget(ev.index) end
    end)
    -- (and the family book hears who comes and goes, and keeps their portraits)
    book = Book.new(w, seed)
    pages = not headless.active() and Pages.new(book) or nil
    -- --crowd <n>: eggs of random genomes where the residents live, until the jar
    -- holds n (they hatch once their graphs are built)
    local homes = World.residents(level or room, w.cast)
    for k = #w.creatures + 1, args.crowd or 0 do
        local r = homes[(k - 1) % #homes + 1]
        w:lay(Genome.random(r.key, rng.sim), r.x + (k % 5 - 2) * 8, r.solid, 'crowd ' .. k)
    end
    return w
end

-- The stones and plants the jar was composed with, back to front
local function furnish()
    objects = {}
    for _, s in ipairs(Scape.getStones()) do objects[#objects + 1] = s end
    for _, p in ipairs(Plants.all()) do objects[#objects + 1] = p end
    table.sort(objects, function(a, b) return a.d < b.d end)
end

function love.load()
    rng.seed(args.seed or SEED)
    if args.cast then
        -- --cast worm,blob,spider: these kinds move in, whatever the seed's cast (#74)
        local cast, err = World.check_cast(room, args.cast)
        if not cast then
            print('[cast] ' .. err)
            love.event.quit(2)
            return
        end
        args.cast = cast
    end
    if args.selftest then
        local ok, err = dev.selftest(World, room, STEP, openJar, step, args.test, args.seed, args.skip, args.day, args.cast)
        if err then print('[selftest] ' .. err) end
        love.event.quit(ok and 0 or (err and 2 or 1))
        return
    end
    if args.navdump then
        dev.navdump(World, room, args.navdump.who, args.navdump.solid, args.genomes)
        love.event.quit(0)
        return
    end

    Render.init()
    if args.replay then
        -- open the jar twice and step both for <sec>; print the hash
        local same, hash = dev.replay(openJar, args.seed or SEED, args.replay, STEP, step)
        print('hash ' .. hash)
        love.event.quit(same and 0 or 1)
        return
    end

    startHour = DayCycle.parseHour(args.hour) or (args.snap and DayCycle.presets.midday) or DayCycle.clockHour()
    daySeconds = args.day or C.DAY_SECONDS

    world = openJar(args.seed or SEED, startHour, daySeconds)
    furnish()
    if not (args.snap or args.script) then
        -- it hears what the World says happened, after each step
        synth = Synth.new()
        synth:mute(args.mute)
        world.events:on(function(ev) synth:on_event(ev, world, lantern:following(world)) end)
    end

    if args.snap then
        for _ = 1, math.floor((args.snap.seconds or 1) / STEP) do step() end
        snapFrames = 0
    end
    if args.bench then
        love.window.setVSync(0)
        bench = { warm = 3, times = {}, update = {}, draw = {} }
    end
    if not headless.active() then love.resize(love.graphics.getDimensions()) end
    if args.frame then
        love.mouse.setVisible(false)
        print(string.format('[frame] %dx%d, the jar at %.2f from (%d, %d)', love.graphics.getWidth(),
            love.graphics.getHeight(), view.k, view.x, view.y))
        io.stdout:flush() -- (a launcher reading this knows the jar is up)
    end
    if args.follow then
        for i, c in ipairs(world.creatures) do
            if c.key == args.follow then lantern.who = i end
        end
        lantern:update(10, world) -- already up to full brightness
    end
    if args.script then
        local chunk, err = love.filesystem.load(args.script)
        if not chunk then error(err) end
        local script = chunk()
        local api = scriptApi()
        capture = { co = coroutine.create(function() script.run(api) end) }
    end
end

-- --bench: the median, 95th percentile and worst of each, in ms
local function report(b)
    local out = {}
    for _, k in ipairs({ 'times', 'update', 'draw' }) do
        local t = b[k]
        table.sort(t)
        out[#out + 1] = string.format('%s %.2f / %.2f / %.2f', k == 'times' and 'frame' or k,
            t[math.ceil(#t * 0.5)] * 1000, t[math.ceil(#t * 0.95)] * 1000, t[#t] * 1000)
    end
    print(string.format('[bench] %d creatures, %d frames (median / p95 / worst ms): %s', #world.creatures,
        #b.times, table.concat(out, ', ')))
end

local function benchFrame(dt, took)
    if bench.warm > 0 then
        if #world.eggs == 0 then bench.warm = bench.warm - dt end
        return
    end
    bench.times[#bench.times + 1] = dt
    bench.update[#bench.update + 1] = took
    bench.elapsed = (bench.elapsed or 0) + dt
    if bench.elapsed >= args.bench then
        report(bench)
        love.event.quit()
    end
end

-- Follow whoever is at a point on the screen with the lantern, or let go.
-- Terrarium: or, on the family book (#32), open it, turn its pages, close it.
local function followAt(x, y)
    if pages and pages:press(Screen.toView(view, x, y)) then return end
    local lx, ly = Tank.toLevel(Screen.toView(view, x, y))
    if lantern:pick(world, lx, ly) and synth then synth:chime(lx) end
end

-- Drop a pinch of food in at a point on the screen, if it's over the jar and
-- there's one left to give (#25)
local function pinchAt(x, y)
    local lx, ly = Tank.toLevel(Screen.toView(view, x, y))
    return lx > C.GLASS_L and lx < C.GLASS_R and ly < C.GLASS_B and world:pinch(lx)
end

function love.update(dt)
    if capture then
        local ok, err = coroutine.resume(capture.co)
        if not ok then
            print('[script] ' .. tostring(err))
            print(debug.traceback(capture.co))
            love.event.quit(1)
        elseif coroutine.status(capture.co) == 'dead' then
            love.event.quit(0)
        end
        return
    end
    if not world or snapFrames then return end
    local t0 = bench and love.timer.getTime()
    accumulator = accumulator + math.min(dt, 0.25)
    while accumulator >= STEP do
        step()
        accumulator = accumulator - STEP
    end
    lantern:update(dt, world)
    if synth then synth:update(dt, world, lantern:following(world)) end

    -- A finger held still on the frame's glass drops a pinch of food there
    -- (but not while the family book is open, or onto it)
    local held, hx, hy = touch:update(dt)
    if held == 'hold' and (pages and (pages.open or pages:overClosed(Screen.toView(view, hx, hy))) or not pinchAt(hx, hy)) then
        touch:empty()
    end
    if pages then
        pages:update(dt)
        if not pages.open then sitting() end
    end

    -- A hand over anyone you could follow, or the book
    if love.mouse.isCursorSupported() and not args.frame then
        local vx, vy = Screen.toView(view, love.mouse.getPosition())
        local over = pages and pages:over(vx, vy)
        if not (pages and pages.open) then
            local lx, ly = Tank.toLevel(vx, vy)
            over = over or Lantern.creatureAt(world, lx, ly)
        end
        love.mouse.setCursor(over and love.mouse.getSystemCursor("hand") or nil)
    end
    if bench then benchFrame(dt, love.timer.getTime() - t0) end
end

-- Terrarium: --nav shows every creature's graph in its own colour; --nav <who>
-- shows one, with its jumps and falls
local function drawNav()
    love.graphics.setShader()
    love.graphics.setLineWidth(1)
    for i = #World.CREATURES, 1, -1 do
        local key = World.CREATURES[i].key
        local g, who = world.graph_of[key], world.creatures[world:first(key) or 0]
        if g and who and (args.nav == true or args.nav == key) then
            local c = who.color_name or { 1, 1, 1 }
            local off = args.nav == true and (i - (#World.CREATURES + 1) / 2) * 1.5 or 0
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

local function drawCreatures(alpha, light)
    -- Draw between the last two steps; the sim never sees the blended points
    world:interpolate(alpha)
    local ctx = { light_dir = world.light_dir, light = light }
    Render.useObject(C.PLANE_D)
    for _, c in ipairs(world.creatures) do
        if c.draw_trail then c:draw_trail() end
    end
    Eggs.draw(world, light) -- Terrarium: clutches in the moss (#23)
    Remains.draw_left(world) -- Terrarium: and what the dead kept, grown over (#77)
    Food.draw(world.food, world.time, alpha, world.moss) -- Terrarium: crumbs you dropped in (#25)
    -- (a dying one through Remains, sinking and fading into the moss, #24)
    for i, c in ipairs(world.creatures) do
        Remains.through(world, i, 'draw', ctx)
    end
    love.graphics.setShader()
    Remains.draw(world)
    Eggs.draw_emissive(world, light)
    Food.draw_emissive(world.food, light, world.time, alpha)
    for i, c in ipairs(world.creatures) do
        if c.draw_emissive then Remains.through(world, i, 'draw_emissive', ctx, 'add') end
    end
    world:restore()
end

local function drawObject(o)
    if o.kind == "plant" then Plants.draw(o) else Scape.drawStone(o) end
end

-- Everything in the jar, back to front. The scape behind FAR_D and the room
-- around the jar are drawn soft, as a shallow depth of field. A plate (see
-- scriptApi) draws the creatures' plane itself, so `plane == false` leaves it out.
local function drawScene(light, plane)
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
    if plane ~= false then
        Tank.pushPlane()
        Scenery.draw(light, world.time)
        Moss.draw(world.moss, light, world.time, world.creatures)
        drawCreatures(accumulator / STEP, light)
        lantern:draw(light)
        if args.nav then drawNav() end
        love.graphics.pop()
    end

    for j = i, #objects do drawObject(objects[j]) end
    love.graphics.setShader()

    Plants.drawGlow(light)
    Motes.drawFront(light)
    Scape.drawFront(light)
    Condensation.draw(light) -- on the inside of the glass, under its dust
    -- (the glass shifts as the cursor does; the frame has none, so it's still)
    Glass.drawFront(light, not args.frame and (Screen.toView(view, love.mouse.getPosition())) or nil)
    lantern:drawGlass(light)
    -- (the family book lies on the desk in front of the glass, #32)
    if pages and plane ~= false then pages:drawClosed(light) end
    love.graphics.setCanvas()
end

-- The front glass bends the view a little at its edges; the room vignettes.
-- A capture script's plate brings its own canvas, size and clock, and has no
-- glass in front of it. A `fit` (core/screen.lua) draws the jar's frame on a
-- screen of another shape.
local function composite(scene, w, h, time, fit)
    local sh = Render.shader("composite")
    love.graphics.setColor(1, 1, 1, 1)
    if fit then Screen.push(fit) end
    if sh then
        love.graphics.setShader(sh)
        local rect = scene and { 0, 0, 0, 0 } or { Glass.frontRect() }
        if fit then
            -- the shader finds the glass in the screen's pixels
            for i = 1, 4 do rect[i] = rect[i] * fit.k + (i % 2 == 1 and fit.x or fit.y) end
        end
        sh:send("glassRect", rect)
        sh:send("aberration", 0.012)
        sh:send("vignette", 0.40)
        sh:send("grain", 0.010)
        sh:send("time", (time or love.timer.getTime()) % 1000)
        sh:send("size", { w or C.W, h or C.H })
    end
    love.graphics.draw(scene or Render.canvas("scene"))
    love.graphics.setShader()
    if fit then love.graphics.pop() end
end

-- Offscreen canvases, kept by name and size
local canvases = {}
local function canvas(name, w, h, hdr)
    local key = name .. w .. 'x' .. h
    canvases[key] = canvases[key] or love.graphics.newCanvas(w, h, hdr and { format = 'rgba16f' } or nil)
    return canvases[key]
end

-- A plate, onto `target`: the stretch of the creatures' plane `v` = {x0, y0,
-- x1, y1}, in level units, drawn across the target's width at full
-- resolution. Behind it is the window's own frame, enlarged and blurred
-- (`blur`), so the plane stands sharp in a shallow depth of field.
local function plate(target, v, light, blur)
    local w, h = target:getDimensions()
    drawScene(light, false)
    -- The view's corners in the window's frame, to line the jar up behind it
    Tank.pushPlane()
    local sx0, sy0 = love.graphics.transformPoint(v[1], v[2])
    local sx1 = love.graphics.transformPoint(v[3], v[2])
    love.graphics.pop()
    local a = w / (sx1 - sx0)
    love.graphics.setCanvas(Render.canvas("far"))
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Render.canvas("scene"))
    local soft, k = Render.blur("far", blur or 3)

    local plane = canvas('plate', w, h, true)
    love.graphics.setCanvas(plane)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(soft, -sx0 * a, -sy0 * a, 0, a * k, a * k)
    love.graphics.push()
    love.graphics.scale(w / (v[3] - v[1]))
    love.graphics.translate(-v[1], -v[2])
    Render.beginObjects(light, { w / 2, w * 0.45 })
    Scenery.draw(light, world.time)
    Moss.draw(world.moss, light, world.time, world.creatures)
    drawCreatures(1, light)
    love.graphics.pop()
    love.graphics.setShader()

    love.graphics.setCanvas(target)
    love.graphics.clear(0, 0, 0, 1)
    composite(plane, w, h, world.time)
    love.graphics.setCanvas()
    return target
end

-- Terrarium: a portrait of creature `c` for the family book (#32): a plate
-- of it where it stands, in the warm light of a lamp-lit afternoon whatever
-- the hour, so every page is lit alike. It's drawing; the World never knows.
-- Into `into`, its last portrait, if it has one.
local PORTRAIT_HOUR = DayCycle.presets.afternoon
local function sit(c, into)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(c:interp_points()) do
        x0, y0 = math.min(x0, p.x), math.min(y0, p.y)
        x1, y1 = math.max(x1, p.x), math.max(y1, p.y)
    end
    local P = Pages.PORTRAIT
    local aspect = P.h / P.w
    local span = math.max(x1 - x0, (y1 - y0) / aspect, 40) * 2.1 + 40
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local v = { cx - span / 2, cy - span * aspect * 0.64, cx + span / 2, cy + span * aspect * 0.36 }
    return plate(into or love.graphics.newCanvas(P.w * 2, P.h * 2), v, DayCycle.evaluate(PORTRAIT_HOUR), 2.2)
end

-- Whoever is due a portrait sits for it now (one at a time, now and then)
function sitting()
    local n, c = pages:sitting()
    if n then pages:hang(n, sit(c, pages.portraits[n])) end
end

-- The API a --script capture file drives (from Character's main.lua). Time
-- only moves when the script steps it and frames render offscreen, so a
-- capture is exact: the same script gives the same jar on any machine.
function scriptApi()
    local api = { STEP = STEP, Genome = Genome, World = World, room = room, args = args, Book = Book }

    -- Open a jar from `seed` at `hour` (a number or a preset name such as
    -- 'midday'), in the jar's room or in `level`. Its composition is the seed's.
    -- Terrarium: `day` compresses its day to that many seconds, as --day does,
    -- and `cast` is who lives there (#74), if not the seed's.
    function api.open(seed, hour, level, day, cast)
        startHour = DayCycle.parseHour(hour) or DayCycle.presets.midday
        daySeconds = day or C.DAY_SECONDS
        world = openJar(seed, startHour, daySeconds, level, cast)
        furnish()
        accumulator = 0
        return world
    end

    -- Advance the jar by `seconds` of fixed steps
    function api.step(seconds)
        for _ = 1, math.max(1, math.floor(seconds / STEP + 0.5)) do step() end
    end

    -- Render a frame into a w x h canvas (default the window's size) and return it.
    --
    -- With opts.view = {x0, y0, x1, y1}, a plate instead: that stretch of the
    -- creatures' plane, in level units, drawn across the canvas's width at full
    -- resolution. Behind it is the window's own frame, enlarged and blurred
    -- (opts.blur), so the plane stands sharp in a shallow depth of field.
    function api.render(w, h, opts)
        opts = opts or {}
        w, h = w or C.W, h or C.H
        local light = DayCycle.evaluate(DayCycle.hourAt(startHour, world.time, daySeconds))
        local target = canvas('target', w, h)
        local v = opts.view
        if not v then
            drawScene(light)
            love.graphics.setCanvas({ target, stencil = true })
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.push()
            love.graphics.scale(w / C.W, h / C.H)
            composite(nil, nil, nil, world.time)
            if pages then pages:draw() end
            love.graphics.pop()
            love.graphics.setCanvas()
            capture.last = target
            return target
        end

        capture.last = plate(target, v, light, opts.blur)
        return target
    end

    -- Terrarium: the family book (#32). `api.book()` is the jar's, and
    -- `api.portraits()` sits everyone due a portrait now, as live play does
    -- between frames; call it as the jar goes on, or the book has no faces.
    -- `api.page(spread)` opens the book at that spread (1 is the title and
    -- what happened while you were away) and `api.page(nil)` closes it; an
    -- open book is drawn over api.render's whole frame. `api.page(spread, t)`
    -- is its leaf `t` of the way through turning over to the next.
    function api.book() return book end
    function api.portraits()
        pages.clock = world.time
        while true do
            local n, c = pages:sitting(true)
            if not n then break end
            pages:hang(n, sit(c, pages.portraits[n]))
        end
    end
    function api.page(spread, turning)
        if spread then
            pages:show(true)
            pages.spread, pages.shown, pages.turn = math.max(1, math.min(pages:spreads(), spread)), 1, nil
            if turning then
                pages.turn = { from = pages.spread, to = pages.spread + 1, t = turning }
                pages.spread = pages.spread + 1
            end
        else
            pages:show(false)
            pages.shown = 0
        end
    end

    -- Save a canvas as a PNG in the save directory
    function api.save(c, file)
        c:newImageData():encode('png', file)
        print('[script] saved ' .. love.filesystem.getSaveDirectory() .. '/' .. file)
    end

    function api.yield() coroutine.yield() end
    return api
end

function love.draw()
    if capture then
        -- The last captured frame, fitted to the window, while a script runs
        if capture.last then
            local cw, ch = capture.last:getDimensions()
            local k = math.min(love.graphics.getWidth() / cw, love.graphics.getHeight() / ch)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(capture.last, 0, 0, 0, k, k)
        end
        return
    end
    if not world then return end
    local t0 = bench and love.timer.getTime()
    -- Render reads the jar's clock; it never moves it
    drawScene(DayCycle.evaluate(DayCycle.hourAt(startHour, world.time + accumulator, daySeconds)))
    composite(nil, nil, nil, nil, view)
    if pages and pages.shown > 0 then
        -- the family book, open over the jar (#32)
        Screen.push(view)
        pages:draw()
        love.graphics.pop()
    end
    touch:draw()
    if bench and bench.warm <= 0 then bench.draw[#bench.draw + 1] = love.timer.getTime() - t0 end

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

function love.resize(w, h)
    view = Screen.fit(w, h, C.W, C.H)
end

-- Click a creature to follow it with the lantern; click anywhere else to let
-- go. Right-click in the jar to drop in a pinch of food there (#25). On the
-- frame, the left button is a finger too: a touchscreen may come as a pointer.
function love.mousepressed(x, y, button, istouch)
    if not world or capture or istouch then return end
    if button == 1 and args.frame then
        touch:press('mouse', x, y)
    elseif button == 1 then
        followAt(x, y)
    elseif button == 2 and not (pages and pages.open) then
        pinchAt(x, y)
    end
end

function love.mousemoved(x, y, _, _, istouch)
    if not istouch then touch:move('mouse', x, y) end
end

function love.mousereleased(x, y, button, istouch)
    if button == 1 and not istouch and touch:release('mouse', x, y) == 'tap' then followAt(x, y) end
end

-- A tap follows, as a click does; a long press is a pinch (Touch:update)
function love.touchpressed(id, x, y)
    if world and not capture then touch:press(id, x, y) end
end

function love.touchmoved(id, x, y)
    touch:move(id, x, y)
end

function love.touchreleased(id, x, y)
    local tap, tx, ty = touch:release(id, x, y)
    if tap then followAt(tx, ty) end
end

function love.keypressed(key)
    if args.frame then return end -- the frame has no keys; Easel ends it with SIGTERM
    if pages and pages:key(key) then return end -- b opens the family book; Escape closes it
    if key == "escape" then love.event.quit() end
    if key == "m" and synth then synth:mute(not synth.muted) end
end

-- Easel's card for the jar (#90): the frame as it stands, at 640 x 360, cropped
-- the way the frame's own screen is
local function saveThumb(file)
    local w, h = 640, 360
    local canvas = love.graphics.newCanvas(w, h)
    drawScene(DayCycle.evaluate(DayCycle.hourAt(startHour, world.time + accumulator, daySeconds)))
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    composite(nil, nil, nil, world.time, Screen.fit(w, h, C.W, C.H))
    love.graphics.setCanvas()
    local out, err = io.open(file, 'wb')
    if not out then
        print('[frame] no thumb: ' .. tostring(err))
        return
    end
    out:write(canvas:newImageData():encode('png'):getString())
    out:close()
    print('[frame] saved ' .. file)
end

-- Every way out comes through here: Escape, closing the window, and the SIGTERM
-- Easel sends (SDL turns it into a quit). When the book (#30) lands, it's saved here.
function love.quit()
    local easel = os.getenv('EASEL_DATA')
    if easel and easel ~= '' and world and not capture and love.window.isOpen() then
        saveThumb(easel .. '/thumb.png')
    end
end
