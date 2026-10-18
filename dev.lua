-- From chrischaps/Character @ 925c35b (dev.lua)
-- Dev modes: verification without a human at the mouse.
--
--   lovec . --selftest                    nav integrity, arrival, determinism
--   lovec . --snap <who> <sec> <file> [--goal x y] [--debug] [--nav]
--                                         run <sec> of sim, save a screenshot
--                                         to the save dir (who: worm|blob|spider)
--        [--zoom cx cy z]                 magnify around a virtual point
--        [--frames n every]               n shots, <every> sim seconds apart
--        [--nolight] [--nopost]           skip the light map / post effects
--   lovec . --script <file.lua>           run a capture script (save dir first); it
--                                         returns {run = function(api)}, see main.lua
--   lovec . --bench <sec>                 run the real game uncapped, report frame times
--   lovec . --seed <n>                    seed the simulation RNG
--   lovec . --hour <h|name>               Terrarium: start the jar at this hour
--   lovec . --day <sec>                   Terrarium: a day lasts <sec> (time-compressed)
--   lovec . --follow <who>                Terrarium: hold the lantern up to worm|blob|spider
--
-- The fixed-step sim makes all of this deterministic.

local log = require('core.log')

local dev = {}

function dev.parse(args)
    local o = {}
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == '--selftest' then o.selftest = true
        elseif a == '--snap' then
            o.snap = {who = args[i + 1], seconds = tonumber(args[i + 2]), file = args[i + 3]}
            i = i + 3
        elseif a == '--goal' then
            o.goal = {x = tonumber(args[i + 1]), y = tonumber(args[i + 2])}
            i = i + 2
        elseif a == '--seed' then o.seed = tonumber(args[i + 1]); i = i + 1
        elseif a == '--debug' then o.debug = true
        elseif a == '--nav' then
            o.nav = true
            -- Terrarium: --nav <who> shows one creature's graph, jumps and all
            local who = args[i + 1]
            if who == 'worm' or who == 'blob' or who == 'spider' then o.nav = who; i = i + 1 end
        elseif a == '--zoom' then
            o.zoom = {x = tonumber(args[i + 1]), y = tonumber(args[i + 2]), z = tonumber(args[i + 3])}
            i = i + 3
        elseif a == '--frames' then
            o.frames = {n = tonumber(args[i + 1]), every = tonumber(args[i + 2])}
            i = i + 2
        elseif a == '--bench' then o.bench = tonumber(args[i + 1]); i = i + 1
        elseif a == '--help' then o.help = true
        elseif a == '--script' then o.script = args[i + 1]; i = i + 1
        elseif a == '--nolight' then o.nolight = true
        elseif a == '--nopost' then o.nopost = true
        elseif a == '--nowander' then o.nowander = true
        -- Terrarium: the jar's hour at load, and a dev-compressed day length
        elseif a == '--hour' then o.hour = args[i + 1]; i = i + 1
        elseif a == '--day' then o.day = tonumber(args[i + 1]); i = i + 1
        elseif a == '--follow' then o.follow = args[i + 1]; i = i + 1
        elseif a == '--navdump' then o.navdump = {who = args[i + 1], solid = args[i + 2]}; i = i + 2
        end
        i = i + 1
    end
    return o
end

--------------------------------------------------------------------------------
-- Selftest
--------------------------------------------------------------------------------

local function check(results, ok, fmt, ...)
    results.total = results.total + 1
    if ok then
        results.pass = results.pass + 1
    else
        results.fail[#results.fail + 1] = string.format(fmt, ...)
    end
end

-- Run the sim until the controller arrives or time runs out
local function drive(world, ctrl, seconds, dt)
    local steps = math.floor(seconds / dt)
    for s = 1, steps do
        world:step(dt)
        if not ctrl:has_path() then
            return true, s * dt
        end
    end
    return false, seconds
end

function dev.selftest(World, level_data, fixed_dt)
    local rng = require('core.rng')
    local Pathfinder = require('nav.pathfinder')
    local ballistics = require('nav.ballistics')
    local results = {total = 0, pass = 0, fail = {}}
    local t0 = love.timer.getTime()

    -- 1. Graph integrity
    rng.seed(1)
    local world = World.new(level_data, {wander = false})
    for i, c in ipairs(world.creatures) do
        local g = world.graphs[i]
        local inside, bad_arcs, edges = 0, 0, 0
        for _, n in ipairs(g.nodes) do
            if world.level:solid_at(n.x + n.nx * 2, n.y + n.ny * 2) then inside = inside + 1 end
            for _, e in ipairs(n.edges) do
                edges = edges + 1
                if e.kind == 'jump' or e.kind == 'fall' then
                    local x0 = e.ex or n.x
                    if not ballistics.arc_clear(world.level, x0, n.y, e.vx, e.vy, e.t, c.profile.radius) then
                        bad_arcs = bad_arcs + 1
                    end
                end
            end
        end
        check(results, inside == 0, '%s: %d nodes inside solids', c.key, inside)
        check(results, bad_arcs == 0, '%s: %d arcs hit geometry', c.key, bad_arcs)
        check(results, #g.nodes > 20 and edges > 40, '%s: graph too small (%d nodes)', c.key, #g.nodes)
        log.info('selftest', '%-6s graph  %3d nodes  %4d edges  (%d sealed off)', c.key, #g.nodes, edges, g.dropped or 0)

        -- Every surface the creature can stand on should be reachable from
        -- its spawn, and it should be able to get back again.
        local start = world.controllers[i]:start_node()
        local unreachable, stranded = {}, {}
        local seen = {}
        for _, n in ipairs(g.nodes) do
            if n.kind == 'top' and not seen[n.solid.id] then
                seen[n.solid.id] = true
                if not Pathfinder.find(g, start, n) then
                    unreachable[#unreachable + 1] = n.solid.id
                elseif not Pathfinder.find(g, n, start) then
                    stranded[#stranded + 1] = n.solid.id
                end
            end
        end
        check(results, #unreachable == 0, '%s: cannot reach %s', c.key, table.concat(unreachable, ', '))
        check(results, #stranded == 0, '%s: stranded on %s', c.key, table.concat(stranded, ', '))

        -- Terrarium: every piece of scenery with moss on it is somewhere this
        -- body can stand (the moss grid grows there, and selection happens there)
        local missing = {}
        for _, s in ipairs(world.level.solids) do
            if s.moss and not seen[s.id] then missing[#missing + 1] = s.id end
        end
        check(results, #missing == 0, '%s: no footing on %s', c.key, table.concat(missing, ', '))
    end

    -- 2. Arrival: chained trips between random reachable goals
    local trips = 0
    local fails_by = {}
    for i, def in ipairs(World.CREATURES) do
        rng.seed(100 + i)
        world = World.new(level_data, {wander = false})
        world:select(i)
        local c, ctrl, g = world.creatures[i], world.controllers[i], world.graphs[i]
        local gen = love.math.newRandomGenerator(500 + i)
        local ok_count, n_trips = 0, 0
        local kinds = c.profile.climbs and nil or {top = true}
        for _ = 1, 40 do
            local goal = g:random_node(gen, kinds)
            local start = ctrl:start_node()
            if goal and start and goal ~= start and Pathfinder.find(g, start, goal) then
                n_trips = n_trips + 1
                ctrl:go_to(goal)
                local arrived, took = drive(world, ctrl, 25, fixed_dt)
                local x, y = c:anchor()
                local close = math.abs(x - goal.x) < 6 and math.abs(y - goal.y) < 6
                if arrived and close then
                    ok_count = ok_count + 1
                else
                    local step = ctrl.path and ctrl.path[ctrl.i]
                    results.fail[#results.fail + 1] = string.format(
                        '%s: trip %d->%d failed at (%.0f,%.0f) arrived=%s edge=%s repaths=%d',
                        def.key, start.id, goal.id, x, y, tostring(arrived),
                        step and step.edge and step.edge.kind or '-', ctrl.repaths)
                    ctrl:clear()
                    -- put it back on a known node before the next trip
                    c:reset(goal.x, goal.y)
                    c.mover.solid = goal.solid
                    if c.profile.climbs then c.solid = goal.solid; c.nx, c.ny, c.tnx, c.tny = goal.nx, goal.ny, goal.nx, goal.ny; c:plant_all() end
                end
            end
        end
        trips = trips + n_trips
        results.total = results.total + 1
        if ok_count == n_trips then results.pass = results.pass + 1 end
        log.info('selftest', '%-6s trips  %d/%d arrived', def.key, ok_count, n_trips)
        fails_by[def.key] = n_trips - ok_count
    end

    -- 3. Frame-rate independence: same steps, different frame groupings
    local function run(frame_dt)
        rng.seed(42)
        local w = World.new(level_data, {wander = true})
        for i = 1, #w.creatures do
            w:select(i)
            w:click(i == 1 and 620 or (i == 2 and 120 or 400), i == 3 and 40 or 300)
        end
        w:select(1)
        local acc, steps = 0, 0
        while steps < 1200 do
            acc = acc + frame_dt
            while acc >= fixed_dt and steps < 1200 do
                w:step(fixed_dt)
                acc = acc - fixed_dt
                steps = steps + 1
            end
        end
        local out = {}
        for _, c in ipairs(w.creatures) do
            local x, y = c:anchor()
            out[#out + 1] = string.format('%.6f,%.6f', x, y)
        end
        return table.concat(out, ' ')
    end
    local a, b, c = run(1 / 30), run(1 / 60), run(1 / 240)
    check(results, a == b and b == c, 'frame-rate dependence: 30fps=%s 60fps=%s 240fps=%s', a, b, c)
    log.info('selftest', 'determinism  %s', (a == b and b == c) and 'identical at 30/60/240 fps' or 'MISMATCH')

    -- Terrarium: 3b. The lantern only watches. A jar where it follows each
    -- creature in turn (picked by clicking where it is) plays out exactly
    -- like a jar where nobody ever picked it up.
    local Lantern = require('jar.lantern')
    local function watched(follow)
        rng.seed(42)
        local w = World.new(level_data, {wander = true, selected = 0})
        local lantern = Lantern.new()
        for s = 1, 2400 do
            if follow and s % 600 == 1 then
                local c = w.creatures[math.floor(s / 600) % #w.creatures + 1]
                local x, y = c:anchor()
                lantern:pick(w, x, y)
            end
            w:step(fixed_dt)
            if follow then lantern:update(1 / 60, w) end
        end
        local out = {}
        for _, c in ipairs(w.creatures) do
            local x, y = c:anchor()
            out[#out + 1] = string.format('%.6f,%.6f', x, y)
        end
        return table.concat(out, ' '), lantern.who
    end
    local plain = watched(false)
    local followed, held = watched(true)
    check(results, held ~= nil, 'lantern: clicking a creature did not pick it')
    check(results, plain == followed, 'lantern changed the jar: %s vs %s', plain, followed)
    log.info('selftest', 'lantern      %s', plain == followed and 'watching changes nothing' or 'MISMATCH')

    -- 4. Audio: every event path runs without error (not a listening test)
    local ok_audio, err = pcall(function()
        local Synth = require('core.synth')
        local synth = Synth.new()
        rng.seed(9)
        local w = World.new(level_data, {wander = true})
        for _, c in ipairs(w.creatures) do
            for _, kind in ipairs({'jump', 'land', 'step', 'arrived'}) do
                synth:on_event({kind = kind, who = c, x = 300, y = 300, vx = 100, vy = -400, impact = 500, near = true},
                    w:selected_creature())
            end
        end
        synth:on_event({kind = 'splash', x = 100, y = 100, speed = 300}, w:selected_creature())
        synth:on_event({kind = 'spores', x = 100, y = 100}, w:selected_creature())
        synth:chime(2, 400)
        synth:nope(400)
        for _ = 1, 30 do w:step(fixed_dt); synth:update(fixed_dt, w) end
        love.audio.stop()
    end)
    check(results, ok_audio, 'audio: %s', tostring(err))

    log.info('selftest', '%d/%d checks passed (%d trips) in %.1fs', results.pass, results.total, trips,
        love.timer.getTime() - t0)
    for _, f in ipairs(results.fail) do log.info('selftest', 'FAIL %s', f) end
    return #results.fail == 0
end

-- Print every node on one solid with its edges, for a creature's graph
function dev.navdump(World, level_data, who, solid_id)
    local world = World.new(level_data, {wander = false})
    for i, c in ipairs(world.creatures) do
        if c.key == who then
            local g = world.graphs[i]
            for _, n in ipairs(g.nodes) do
                if n.solid.id == solid_id then
                    local es = {}
                    for _, e in ipairs(n.edges) do
                        local m = g.nodes[e.to]
                        es[#es + 1] = string.format('%s->%d(%s)', e.kind, m.id, m.solid.id)
                    end
                    print(string.format('#%d %s (%.0f,%.0f) n=(%.2f,%.2f) L=%s R=%s : %s', n.id, n.kind, n.x, n.y,
                        n.nx, n.ny, tostring(n.end_left), tostring(n.end_right), table.concat(es, ' ')))
                end
            end
        end
    end
end

return dev
