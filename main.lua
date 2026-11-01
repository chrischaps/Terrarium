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
--   lovec . --style <name>   look at the jar in a style (jar/styles.lua; --styles lists them)
--   tab                      the next style
--   love . --frame           the Pi frame (#90): fullscreen, no cursor, no keys; a tap
--                            follows, a long press drops food, and SIGTERM quits
--                            through love.quit, leaving $EASEL_DATA/thumb.png if it's set
--   love . --away <time>     come back to a jar left that long ago: 90m, 36h, 2d (jar days)
--                            or seconds, lived on the coarse step while the glass is fogged
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
local Catchup = require('jar.catchup')
local Passing = require('jar.passing')
local Lantern = require('jar.lantern')
local Ballistics = require('nav.ballistics')
local Genome = require('genome')
local Synth = require('core.synth')
local Styles = require('jar.styles')
local Screen = require('core.screen')
local Touch = require('core.touch')
local Book = require('book')
local Pages = require('jar.pages')

local STEP = 1 / 120 -- fixed simulation step; everything alive advances on this clock
local SEED = 20261018 -- a jar is its seed plus its history

local args = dev.parse(arg or {})
-- --interpret: LuaJIT's compiler off, so tests/ci.sh can check a jar run
-- interpreted hashes the same as a compiled one (core/fmath.lua)
if args.interpret then jit.off() end
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
local watchReplay -- likewise: --replay in a window draws what it runs
local style = args.style or Styles.DEFAULT -- the look the finished frame is drawn in (#94)
local shown, shownFont -- {name, at}: a style just switched to, named in the corner for a moment
-- How the jar's view goes on a w x h screen (#90): in a window the room shows
-- round the jar, and on the frame the glass's inside fills it (#110)
local function fitFor(w, h)
    return args.frame and Screen.tank(w, h) or Screen.fit(w, h, C.W, C.H)
end
local view = fitFor(C.W, C.H) -- the jar's view on the window
-- The open family book's fit: always the window's, so on the frame it's no
-- bigger than in a window and none of it is lost off the screen's edges
local leaf = Screen.fit(C.W, C.H, C.W, C.H)

local touch = Touch.new() -- a finger on the frame's glass
local book -- the family book (#32): everyone who has lived in the jar
local pages -- and the book itself, on the desk and open, wherever there's a window
local passing -- the moment on opening a jar that was left (#31), while it lasts

-- On the frame the closed book is off the screen, below it on the desk, so
-- it's found by its ribbon, up over the bottom edge (jar/pages.lua)
local function tabOn(f, w, h)
    local x, y = Screen.toView(f, w - Pages.TAB_X, h)
    return { x = x, y = y, k = f.k }
end
local function tuck()
    if pages and args.frame then pages.tab = tabOn(view, love.graphics.getDimensions()) end
end

-- A point on the screen, in the view's pixels the book is drawn in: the
-- jar's, or the open book's own
local function onBook(x, y)
    return Screen.toView(pages and pages.open and leaf or view, x, y)
end

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
    tuck()
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
    if args.styles then
        -- --styles: the looks there are, one a line (tests/ci.sh watches the jar in each)
        print(table.concat(Styles.names(), '\n'))
        love.event.quit(0)
        return
    end
    if not Styles.get(style) then
        print('[style] no style ' .. style .. '; there are ' .. table.concat(Styles.names(), ', '))
        love.event.quit(2)
        return
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
        -- open the jar twice and step both for <sec>; print the hash. In a
        -- window, both are drawn as they go, in the style, which must change nothing
        local watch = not headless.active() and watchReplay or nil
        local same, hash = dev.replay(openJar, args.seed or SEED, args.replay, STEP, step, watch)
        print('hash ' .. hash)
        love.event.quit(same and 0 or 1)
        return
    end

    startHour = DayCycle.parseHour(args.hour) or (args.snap and DayCycle.presets.midday) or DayCycle.clockHour()
    daySeconds = args.day or C.DAY_SECONDS
    if args.away then
        -- (left that long ago, so it comes back at this hour, less any days past the cap)
        local away = args.away.days and args.away.days * daySeconds or args.away.seconds
        startHour = (startHour - Catchup.span(away, daySeconds) / daySeconds * 24) % 24
    end

    world = openJar(args.seed or SEED, startHour, daySeconds)
    furnish()
    if not (args.snap or args.script) then
        -- it hears what the World says happened, after each step
        synth = Synth.new()
        synth:mute(args.mute)
        -- (but not to what happened while you were away)
        world.events:on(function(ev)
            if not world.catching then synth:on_event(ev, world, lantern:following(world)) end
        end)
    end

    -- Terrarium: the time the jar was left, lived on the coarse step (#31).
    -- --away opens it that long before now and catches it up; the book (#30)
    -- will ask the same of a saved jar, with the time since it was saved. A
    -- snap or a script gets it at once, and play gets the moment.
    if args.away then
        local away = args.away.days and args.away.days * daySeconds or args.away.seconds
        if args.snap or args.script or args.bench then
            Catchup.now(world, away)
        else
            passing = Passing.begin(world, away)
        end
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
        print(string.format("[frame] %dx%d, the jar at %.3f from (%.1f, %.1f)", love.graphics.getWidth(),
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
    if pages and pages:press(onBook(x, y)) then return end
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
    if passing then
        if passing:update(dt) then passing = nil end
        if passing and passing:catching() then return end -- (nothing to hear, follow or touch yet)
    end
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
        local over = pages and pages:over(onBook(love.mouse.getPosition()))
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

-- Terrarium: under a style that draws each thing on its own (pencil-each,
-- #95), `draw` through the style's body pass, bounded by x0, y0, x1, y1 in
-- the canvas's px (or the whole canvas, with none). Anything that isn't
-- drawn this way is the ground the things stand on.
local function alone(seed, draw, x0, y0, x1, y1)
    if not x0 then x0, y0, x1, y1 = -math.huge, -math.huge, math.huge, math.huge end
    Styles.body(style, world.time, x0, y0, x1, y1, nil, nil, seed, draw)
end

-- Creature i and its glow, on its own. Its bounds and middle come from its
-- drawn points, PAD over for legs, shell and glow, and its hatching is
-- anchored to its middle, so it goes where the creature goes.
local PAD = 40
local function drawAlone(i, c, ctx)
    local x0, y0, x1, y1, mx, my, n = math.huge, math.huge, -math.huge, -math.huge, 0, 0, 0
    for _, p in ipairs(c:interp_points()) do
        x0, y0 = math.min(x0, p.x), math.min(y0, p.y)
        x1, y1 = math.max(x1, p.x), math.max(y1, p.y)
        mx, my, n = mx + p.x, my + p.y, n + 1
    end
    if n == 0 then return Remains.through(world, i, 'draw', ctx) end
    local sx0, sy0 = love.graphics.transformPoint(x0 - PAD, y0 - PAD)
    local sx1, sy1 = love.graphics.transformPoint(x1 + PAD, y1 + PAD)
    local ax, ay = love.graphics.transformPoint(mx / n, my / n)
    local seed = math.floor((c.genome.hue or 0) * 977) % 101
    Styles.body(style, world.time, sx0, sy0, sx1, sy1, ax, ay, seed, function()
        Render.useObject(C.PLANE_D)
        Remains.through(world, i, 'draw', ctx)
        love.graphics.setShader()
        if c.draw_emissive then Remains.through(world, i, 'draw_emissive', ctx, 'add') end
    end)
end

local function drawCreatures(alpha, light)
    -- Draw between the last two steps; the sim never sees the blended points.
    -- (A jar catching up is only anchors, and the moment draws those, #31.)
    local bodies = not world.coarse
    if bodies then world:interpolate(alpha) end
    local ctx = { light_dir = world.light_dir, light = light }
    local each = Styles.each(style)
    -- The small things: trails, clutches, what the dead kept, crumbs, and
    -- spores off the returned (under pencil-each, all on their own together)
    local function litter()
        Render.useObject(C.PLANE_D)
        for _, c in ipairs(bodies and world.creatures or {}) do
            if c.draw_trail then c:draw_trail() end
        end
        Eggs.draw(world, light) -- Terrarium: clutches in the moss (#23)
        Remains.draw_left(world) -- Terrarium: and what the dead kept, grown over (#77)
        Food.draw(world.food, world.time, alpha, world.moss) -- Terrarium: crumbs you dropped in (#25)
        if not each then return end
        love.graphics.setShader()
        Remains.draw(world)
        Eggs.draw_emissive(world, light)
        Food.draw_emissive(world.food, light, world.time, alpha)
    end
    if each then
        alone(7, litter)
        for i, c in ipairs(bodies and world.creatures or {}) do drawAlone(i, c, ctx) end
        if bodies then world:restore() end
        return
    end
    litter()
    -- (a dying one through Remains, sinking and fading into the moss, #24)
    for i in ipairs(bodies and world.creatures or {}) do
        Remains.through(world, i, 'draw', ctx)
    end
    love.graphics.setShader()
    Remains.draw(world)
    Eggs.draw_emissive(world, light)
    Food.draw_emissive(world.food, light, world.time, alpha)
    for i, c in ipairs(bodies and world.creatures or {}) do
        if c.draw_emissive then Remains.through(world, i, 'draw_emissive', ctx, 'add') end
    end
    if bodies then world:restore() end
end

local function drawObject(o, each)
    if each then
        -- (a stone or plant on its own, pencil-each)
        local x0, y0, x1, y1
        if o.kind == "plant" then x0, y0, x1, y1 = Plants.bounds(o) else x0, y0, x1, y1 = Scape.stoneBounds(o) end
        return alone(math.floor(o.x * 7 + o.d * 97) % 101, function() drawObject(o) end, x0, y0, x1, y1)
    end
    if o.kind == "plant" then Plants.draw(o) else Scape.drawStone(o) end
end

-- The scenery and the moss on it, in level coordinates; under pencil-each
-- each piece on its own, and the moss on its own, over what lies under them
local function drawProps(light)
    if not Styles.each(style) then
        Scenery.draw(light, world.time)
        Moss.draw(world.moss, light, world.time, world.creatures)
        return
    end
    Scenery.drawGround(light, world.time)
    for k, p in ipairs(Scenery.all()) do
        local x0, y0, x1, y1 = Scenery.bounds(p)
        local sx0, sy0 = love.graphics.transformPoint(x0, y0)
        local sx1, sy1 = love.graphics.transformPoint(x1, y1)
        alone(k, function() Scenery.drawPiece(p) end, sx0, sy0, sx1, sy1)
    end
    alone(3, function() Moss.draw(world.moss, light, world.time, world.creatures) end)
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

    local each = Styles.each(style)
    Glass.drawBack(light)
    if each then alone(5, function() Scape.drawBed(light) end, Scape.bedBounds()) else Scape.drawBed(light) end
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
        drawObject(objects[i], each)
        i = i + 1
    end
    love.graphics.setShader()
    Motes.drawBack(light)

    -- The creatures' plane, in level coordinates
    if plane ~= false then
        Tank.pushPlane()
        drawProps(light)
        drawCreatures(accumulator / STEP, light)
        if passing then passing:draw() end
        lantern:draw(light)
        if args.nav then drawNav() end
        love.graphics.pop()
    end

    for j = i, #objects do drawObject(objects[j], each) end
    love.graphics.setShader()

    Plants.drawGlow(light)
    Motes.drawFront(light)
    -- (the soil's face against the front glass)
    if each then alone(6, function() Scape.drawFront(light) end, Scape.frontBounds()) else Scape.drawFront(light) end
    Condensation.draw(light, passing and passing:glass()) -- on the inside of the glass, under its dust
    -- (the glass shifts as the cursor does; the frame has none, so it's still)
    Glass.drawFront(light, not args.frame and (Screen.toView(view, love.mouse.getPosition())) or nil)
    lantern:drawGlass(light)
    -- (the family book lies on the desk in front of the glass, #32)
    if pages and plane ~= false then pages:drawClosed(light) end
    love.graphics.setCanvas()
end

-- The finished frame in the style (#94), then the front glass bends the view
-- a little at its edges and the room vignettes. Every frame goes through
-- here: the window's, --snap's, a capture script's and the frame's thumb. A
-- plate brings its own canvas, size and clock, and has no glass in front of
-- it. A `fit` (core/screen.lua) draws the jar's frame on a screen of another
-- shape.
local function composite(plate, w, h, time, fit)
    time = time or love.timer.getTime()
    local frame = Styles.apply(style, plate or Render.canvas("scene"), time)
    local sh = Render.shader("composite")
    love.graphics.setColor(1, 1, 1, 1)
    if fit then Screen.push(fit) end
    if sh then
        love.graphics.setShader(sh)
        local rect = plate and { 0, 0, 0, 0 } or { Glass.frontRect() }
        if fit then
            -- the shader finds the glass in the screen's pixels
            for i = 1, 4 do rect[i] = rect[i] * fit.k + (i % 2 == 1 and fit.x or fit.y) end
        end
        sh:send("glassRect", rect)
        local glass = Styles.glass(style) -- (a style may want no fringe or grain)
        sh:send("aberration", glass.aberration)
        sh:send("vignette", glass.vignette)
        sh:send("grain", glass.grain)
        sh:send("time", time % 1000)
        sh:send("size", { w or C.W, h or C.H })
    end
    love.graphics.draw(frame)
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
    drawProps(light)
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

-- --replay in a window: each run's jar drawn every WATCH steps, the way
-- love.draw draws it, in the style. Watching a jar must change nothing in it.
local WATCH = 30
function watchReplay(w, s)
    if s % WATCH ~= 0 then return end
    if world ~= w then
        -- (dev.replay opens its jars at midday with a full-length day)
        world, accumulator = w, 0
        startHour, daySeconds = DayCycle.presets.midday, C.DAY_SECONDS
        furnish()
    end
    drawScene(DayCycle.evaluate(DayCycle.hourAt(startHour, w.time, daySeconds)))
    composite(nil, nil, nil, w.time)
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

    -- Render later frames in style `name` (#94; --style's, else none, to
    -- begin with). Returns the one it was.
    function api.style(name)
        assert(Styles.get(name), 'no style ' .. tostring(name))
        style, name = name, style
        return name
    end

    -- Advance the jar by `seconds` of fixed steps
    function api.step(seconds)
        for _ = 1, math.max(1, math.floor(seconds / STEP + 0.5)) do step() end
    end

    -- Terrarium: come back to the open jar `seconds` after it was left (#31).
    -- Returns the moment, or nil if the time was short enough to live at once.
    function api.away(seconds)
        passing = Passing.begin(world, seconds)
        return passing
    end

    -- A frame of the moment, `dt` long, with `steps` coarse steps of catch-up
    -- in it (so a capture is exact), and the live jar going on once it's back.
    -- Returns false once the moment is over.
    function api.pass(dt, steps)
        if not passing then return false end
        local over = passing:update(dt, steps or 1)
        if not passing:catching() then api.step(dt) end
        if over then passing = nil end
        return not over
    end

    -- Render a frame into a w x h canvas (default the window's size) and return it.
    --
    -- With opts.fit (core/screen.lua), through that fit, as a w x h screen
    -- shows it; with opts.frame, as the frame shows it (#110): the glass's
    -- inside filling it, and the book's ribbon to find it by.
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
            local fit, tab = opts.frame and Screen.tank(w, h) or opts.fit, pages and pages.tab
            if pages and opts.frame then pages.tab = tabOn(fit, w, h) end
            drawScene(light)
            love.graphics.setCanvas({ target, stencil = true })
            love.graphics.clear(0, 0, 0, 1)
            if fit then
                -- (through a fit, core/screen.lua, as a screen of that shape shows it)
                composite(nil, nil, nil, world.time, fit)
                if pages and pages.tab then
                    Screen.push(fit)
                    pages:drawTab()
                    love.graphics.pop()
                end
                Screen.push(Screen.fit(w, h, C.W, C.H)) -- (the open book, as on a screen)
            else
                love.graphics.push()
                love.graphics.scale(w / C.W, h / C.H)
                composite(nil, nil, nil, world.time)
            end
            if pages then pages:draw() end
            love.graphics.pop()
            love.graphics.setCanvas()
            if pages then pages.tab = tab end
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
    if pages and pages.tab then
        -- the book's ribbon, on the frame (its desk is off the screen)
        Screen.push(view)
        pages:drawTab()
        love.graphics.pop()
    end
    if pages and pages.shown > 0 then
        -- the family book, open over the jar (#32)
        Screen.push(leaf)
        pages:draw()
        love.graphics.pop()
    end
    touch:draw()
    if bench and bench.warm <= 0 then bench.draw[#bench.draw + 1] = love.timer.getTime() - t0 end
    if shown then
        -- The style's name, low in the corner, held a moment and let go
        local a = math.min(1, 2 - (love.timer.getTime() - shown.at) / 0.9)
        if a <= 0 then
            shown = nil
        else
            shownFont = shownFont or love.graphics.newFont(13)
            love.graphics.setFont(shownFont)
            love.graphics.setColor(0.93, 0.90, 0.82, 0.75 * a)
            love.graphics.print(shown.name, 28, love.graphics.getHeight() - 44)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

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
    view, leaf = fitFor(w, h), Screen.fit(w, h, C.W, C.H)
    tuck()
end

-- Click a creature to follow it with the lantern; click anywhere else to let
-- go. Right-click in the jar to drop in a pinch of food there (#25). On the
-- frame, the left button is a finger too: a touchscreen may come as a pointer.
function love.mousepressed(x, y, button, istouch)
    if not world or capture or istouch or (passing and passing:catching()) then return end
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
    if world and not capture and not (passing and passing:catching()) then touch:press(id, x, y) end
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
    if key == "tab" and not capture then
        style = Styles.after(style)
        shown = { name = style, at = love.timer.getTime() }
    end
end

-- Easel's card for the jar (#90): the frame as it stands, at 640 x 360, cropped
-- the way the frame's own screen is
local function saveThumb(file)
    local w, h = 640, 360
    local canvas = love.graphics.newCanvas(w, h)
    drawScene(DayCycle.evaluate(DayCycle.hourAt(startHour, world.time + accumulator, daySeconds)))
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    composite(nil, nil, nil, world.time, fitFor(w, h))
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
