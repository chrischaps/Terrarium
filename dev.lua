-- From chrischaps/Character @ 925c35b (dev.lua)
-- Dev modes: verification without a human at the mouse.
--
--   lovec . --selftest                    nav integrity, arrival, determinism, replay
--   lovec . --test <name>[,<name>]        Terrarium: just these self-tests (graphs, trips,
--                                         framerate, lantern, day, replay, genome, worm, blob, spider,
--                                         hatch, crowd, ranges, moss, audio, or all;
--                                         --seed <n> reseeds the day)
--   lovec . --headless                    Terrarium: no window (implied by --test,
--                                         --selftest, --replay and --navdump; --window undoes it)
--   lovec . --snap <who> <sec> <file> [--goal x y] [--debug] [--nav]
--                                         run <sec> of sim, save a screenshot
--                                         to the save dir (who: worm|blob|spider)
--        [--zoom cx cy z]                 magnify around a virtual point
--        [--frames n every]               n shots, <every> sim seconds apart
--        [--nolight] [--nopost]           skip the light map / post effects
--   lovec . --script <file.lua>           run a capture script (save dir first); it
--                                         returns {run = function(api)}, see main.lua
--   lovec . --bench <sec>                 run the real game uncapped, report frame times
--                                         (once the eggs are out and 3 s have passed)
--   lovec . --crowd <n>                   Terrarium: lay eggs of random genomes until the
--                                         jar holds n creatures
--   lovec . --seed <n>                    seed the simulation RNG
--   lovec . --hour <h|name>               Terrarium: start the jar at this hour
--   lovec . --day <sec>                   Terrarium: a day lasts <sec> (time-compressed)
--   lovec . --follow <who>                Terrarium: hold the lantern up to worm|blob|spider
--   lovec . --genome "<plan> gene=v ..."  Terrarium: the first resident of that plan has
--                                         this genome (repeat for the second)
--   lovec . --replay <sec>                Terrarium: open the jar twice, step both <sec>,
--                                         print the state hash, exit 1 if they differ
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
        -- Terrarium: one named test, or a comma list (see dev.tests())
        elseif a == '--test' then o.selftest = true; o.test = args[i + 1]; i = i + 1
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
        elseif a == '--crowd' then o.crowd = tonumber(args[i + 1]); i = i + 1
        elseif a == '--help' then o.help = true
        elseif a == '--script' then o.script = args[i + 1]; i = i + 1
        elseif a == '--nolight' then o.nolight = true
        elseif a == '--nopost' then o.nopost = true
        elseif a == '--nowander' then o.nowander = true
        -- Terrarium: the jar's hour at load, and a dev-compressed day length
        elseif a == '--hour' then o.hour = args[i + 1]; i = i + 1
        elseif a == '--day' then o.day = tonumber(args[i + 1]); i = i + 1
        elseif a == '--follow' then o.follow = args[i + 1]; i = i + 1
        -- Terrarium: a body to look at, e.g. --genome "worm segments=24 stiffness=0.9"
        elseif a == '--genome' then
            o.genomes = o.genomes or {}
            o.genomes[#o.genomes + 1] = args[i + 1]
            i = i + 1
        elseif a == '--replay' then o.replay = tonumber(args[i + 1]); i = i + 1
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

-- Terrarium: the self-test is a list of named tests, so --test <name> runs
-- one and later tests (200 genomes, the 30-day population run) slot in here.
-- Each takes the jar's parts in `j` and records into `results`.
local rng = require('core.rng')
local TESTS = {}
local function test(name, fn) TESTS[#TESTS + 1] = {name = name, fn = fn} end

-- 1. Graph integrity
test('graphs', function(j, results)
    local World, level_data = j.World, j.level_data
    local Pathfinder = require('nav.pathfinder')
    local ballistics = require('nav.ballistics')
    rng.seed(1)
    local world = World.new(level_data, {wander = false})
    local checked = {}
    for i, c in ipairs(world.creatures) do -- Terrarium: every graph, once (a blob's is its size's)
        local g = world.graphs[i]
        if checked[g] then goto next_graph end
        checked[g] = true
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
        ::next_graph::
    end
end)

-- 2. Arrival: chained trips between random reachable goals
test('trips', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local Pathfinder = require('nav.pathfinder')
    local world
    local trips = 0
    local fails_by = {}
    for k, def in ipairs(World.CREATURES) do
        rng.seed(100 + k)
        world = World.new(level_data, {wander = false})
        local i = world:first(def.key) -- Terrarium: the first of each kind
        world:select(i)
        local c, ctrl, g = world.creatures[i], world.controllers[i], world.graphs[i]
        local gen = love.math.newRandomGenerator(500 + k)
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
    results.trips = (results.trips or 0) + trips
end)

-- 3. Frame-rate independence: same steps, different frame groupings
test('framerate', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local function run(frame_dt)
        rng.seed(42)
        local w = World.new(level_data, {wander = true})
        local goals = {worm = {620, 300}, blob = {120, 300}, spider = {400, 40}}
        for i, c in ipairs(w.creatures) do
            w:select(i)
            w:click(goals[c.key][1], goals[c.key][2])
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
end)

-- Terrarium: 3b. The lantern only watches. A jar where it follows each
-- creature in turn (picked by clicking where it is) plays out exactly
-- like a jar where nobody ever picked it up.
test('lantern', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
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
end)

-- Terrarium: 3c. The M1 gate (#9). All six residents live through a whole
-- day, compressed to DAY seconds, starting at midday. Each wanders and grazes
-- through its own day, rests through its own night and lies still once it
-- gets there, and is up and about again by noon, or (a night owl, #21) asleep
-- at noon both times, having slept twice. Nobody leaves the jar, comes apart
-- into NaNs or ends up sunk in the scenery.
local DAY = 900
test('day', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    rng.seed(j.seed or 20261018)
    local w = World.new(level_data, {wander = true, selected = 0, hour = 13, day = DAY})
    local level = w.level
    local owl = {} -- asleep at noon
    for i, m in ipairs(w.minds) do owl[i] = not m:awake(w:hour()) end
    local lost, still_for, moved_at_rest = {}, {}, {}
    local last = {}
    local steps = math.floor(DAY / fixed_dt + 0.5)
    for s = 1, steps do
        w:step(fixed_dt)
        if s % 30 == 0 then
            for i, c in ipairs(w.creatures) do
                local x, y = c:anchor()
                if not lost[i] and (x ~= x or y ~= y or x < 0 or x > level.data.width or y < 0 or y > level.by_id.soil.y + 20) then
                    lost[i] = string.format('(%.0f,%.0f) at %.0fs', x, y, w.time)
                end
                -- Asleep means still: once resting, the anchor barely moves
                local m = w.minds[i]
                if m.doing == 'rest' and last[i] then
                    still_for[i] = (still_for[i] or 0) + 30 * fixed_dt
                    local d = math.abs(x - last[i][1]) + math.abs(y - last[i][2])
                    moved_at_rest[i] = math.max(moved_at_rest[i] or 0, d)
                end
                last[i] = m.doing == 'rest' and {x, y} or nil
            end
        end
    end
    for i, c in ipairs(w.creatures) do
        local m, who = w.minds[i], string.format('%s the %s', c.name, c.key)
        local sunk, n = 0, 0
        for _, p in ipairs(c:interp_points()) do
            n = n + 1
            if level:solid_at(p.x, p.y) then sunk = sunk + 1 end
        end
        check(results, not lost[i], '%s left the jar %s', who, lost[i] or '')
        check(results, sunk <= n / 2, '%s ended the day sunk in a solid (%d of %d points)', who, sunk, n)
        check(results, m.wanders >= 3, '%s wandered only %d times', who, m.wanders)
        check(results, m.grazes >= 1, '%s never grazed', who)
        check(results, m.nights == (owl[i] and 2 or 1), '%s rested %d times in one night', who, m.nights)
        check(results, (still_for[i] or 0) > DAY * 0.2, '%s rested only %.0fs of the night', who, still_for[i] or 0)
        check(results, (moved_at_rest[i] or 0) < 4, '%s moved %.1fpx while resting', who, moved_at_rest[i] or 0)
        if owl[i] then
            check(results, not m:awake(w:hour()) and m.doing == 'rest', '%s, a night owl, is up at noon', who)
        else
            check(results, m:awake(w:hour()) and m.doing ~= 'rest', '%s is still asleep at noon', who)
        end
        log.info('selftest', 'day   %-6s %-6s wandered %2d, grazed %d, followed %d, rested %3.0fs%s', c.name, c.key,
            m.wanders, m.grazes, m.follows, still_for[i] or 0, owl[i] and ' (a night owl)' or '')
    end
end)

-- Terrarium: 3c. Moss (#20). Half an hour of a morning leaves the moss
-- cropped bare where the residents grazed and worn short where they walked,
-- with most of it still lush. Then, with nobody left to eat it, the lamp grows every patch back by the
-- next afternoon, and the night between grows none. The regrowth takes
-- one-second steps: growth is smooth enough not to need the fixed one.
local MOSS_WATCH = 1800
test('moss', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local DayCycle = require('jar.daycycle')
    local Moss = require('jar.moss')
    rng.seed(j.seed or 20261018)
    local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.morning})
    local m = w.moss
    check(results, m.count > 300, 'moss: only %d cells over the mossy tops', m.count)
    for _ = 1, math.floor(MOSS_WATCH / fixed_dt + 0.5) do w:step(fixed_dt) end

    local bare, worn, cropped = 0, 0, {}
    for i = 1, m.count do
        local f = m.h[i] / m.cap[i]
        -- Feet wear moss no lower than Moss.WORN; below that, something ate it
        if m.h[i] < Moss.WORN then bare = bare + 1 elseif f < 0.8 then worn = worn + 1 end
        if f < 0.8 then cropped[#cropped + 1] = i end
    end
    check(results, bare >= 20, 'moss: %.0f minutes of grazing left only %d cells bare', MOSS_WATCH / 60, bare)
    check(results, worn >= 40, 'moss: %.0f minutes of walking wore only %d cells short', MOSS_WATCH / 60, worn)
    local lush = m.count - bare - worn
    check(results, lush >= m.count / 4, 'moss: %.0f minutes stripped the jar (%d of %d cells still lush)',
        MOSS_WATCH / 60, lush, m.count)

    local hour = w:hour()
    local until_afternoon = ((24 + DayCycle.presets.afternoon - hour) % 24 + 24) * 3600
    local dusk, dawn
    for t = 1, until_afternoon do
        local h = (hour + t / 3600) % 24
        m:update(1, DayCycle.lampAt(h))
        if not dusk and h >= 23 then dusk = {unpack(m.h)} end
        if dusk and not dawn and h >= 5 and h < 5.5 then dawn = {unpack(m.h)} end
    end
    local grew_at_night = 0
    for i = 1, m.count do
        if dusk and dawn and dawn[i] ~= dusk[i] then grew_at_night = grew_at_night + 1 end
    end
    check(results, dusk and dawn and grew_at_night == 0, 'moss: %d cells grew in the dark', grew_at_night)
    local back, worst = 0, 1
    for _, i in ipairs(cropped) do
        local f = m.h[i] / m.cap[i]
        worst = math.min(worst, f)
        if f >= 0.9 then back = back + 1 end
    end
    check(results, back == #cropped, 'moss: by the next afternoon only %d of %d cropped cells grew back (lowest %.2f)',
        back, #cropped, worst)
    log.info('selftest', 'moss         %d cells: %d bare and %d worn after %.0f min; %d of %d back by the next afternoon',
        m.count, bare, worn, MOSS_WATCH / 60, back, #cropped)
end)

-- Terrarium: 3c. Temperament (#21). Opposite temperaments look different
-- within a minute of watching. Each trait is tried on one resident twice,
-- from the same seed, the gene at one end and then the other, and everything
-- else the same: a bold worm roams farther from home than a timid one, which
-- stays near its own and never takes a leap bigger than it dares; a sociable
-- blob keeps nearer the others than a loner; and at ten at night an early
-- riser has gone to bed while a night owl is still up and about.
local function subject(plan, body, temper)
    return string.format('%s %s hue=0.5 pattern=1 glow=0.5 %s', plan, body, temper)
end
local WORM, BLOB = 'segments=14 stiffness=0.5', 'size=1 pressure=1'
test('temperament', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local SEEDS = {1, 2, 3, 4}
    -- One minute of the jar at `hour`, with `genomes`, calling `watch(w)` every half second
    local function minute(seed, hour, genomes, watch)
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, hour = hour, genomes = genomes})
        for s = 1, math.floor(60 / fixed_dt + 0.5) do
            w:step(fixed_dt)
            if s % 60 == 0 then watch(w) end
        end
        return w
    end
    local function mean(t)
        local sum = 0
        for _, v in ipairs(t) do sum = sum + v end
        return sum / #t
    end

    -- Boldness: Loam, from the soil at the left of the jar
    local roam = {[0] = {}, [1] = {}}
    for _, seed in ipairs(SEEDS) do
        for b = 0, 1 do
            local far, leap, dared = 0, 0, nil
            local w = minute(seed, 10, {subject('worm', WORM, 'boldness=' .. b .. ' sociability=0.5 chronotype=0.2')},
                function(w)
                    local c, ctrl = w.creatures[1], w.controllers[1]
                    local x = c:anchor()
                    far = math.max(far, math.abs(x - c.home.x))
                    for _, st in ipairs(ctrl.path or {}) do
                        if st.edge and st.edge.dare then leap = math.max(leap, st.edge.dare) end
                    end
                    dared = w.minds[1].dare
                end)
            roam[b][#roam[b] + 1] = far
            if b == 0 then
                check(results, leap <= dared, 'temperament: a timid worm (seed %d) took a leap of %.2f, daring %.2f',
                    seed, leap, dared)
                check(results, far <= w.minds[1].range + 160, 'temperament: a timid worm (seed %d) went %.0f from home',
                    seed, far)
            end
        end
    end
    check(results, mean(roam[1]) > 2 * mean(roam[0]), 'temperament: a bold worm roamed %.0f from home, a timid one %.0f',
        mean(roam[1]), mean(roam[0]))

    -- Sociability: Dew, among the other five
    local apart = {[0] = {}, [1] = {}}
    for _, seed in ipairs(SEEDS) do
        for s = 0, 1 do
            local gaps = {}
            minute(seed, 10, {subject('blob', BLOB, 'boldness=1 sociability=' .. s .. ' chronotype=0.2')}, function(w)
                local me = w:first('blob')
                local x, y = w.creatures[me]:anchor()
                local d = math.huge
                for i, o in ipairs(w.creatures) do
                    if i ~= me then
                        local ox, oy = o:anchor()
                        d = math.min(d, math.sqrt((ox - x) ^ 2 + (oy - y) ^ 2))
                    end
                end
                gaps[#gaps + 1] = d
            end)
            apart[s][#apart[s] + 1] = mean(gaps)
        end
    end
    check(results, mean(apart[1]) < 0.6 * mean(apart[0]),
        'temperament: a sociable blob kept %.0f from the nearest other, a loner %.0f', mean(apart[1]), mean(apart[0]))

    -- Chronotype: Loam an early riser and Rill a night owl, at ten at night
    local slept, up = 0, 0
    for _, seed in ipairs(SEEDS) do
        local w = minute(seed, 22, {subject('worm', WORM, 'boldness=0.5 sociability=0.5 chronotype=0'),
            subject('worm', WORM, 'boldness=0.5 sociability=0.5 chronotype=1')}, function() end)
        local lark, owl = w.minds[1], w.minds[2]
        if lark.doing == 'rest' or lark.doing == 'to_rest' then slept = slept + 1 end
        if owl.doing ~= 'rest' and owl.doing ~= 'to_rest' and owl.wanders + owl.follows > 0 then up = up + 1 end
    end
    check(results, slept == #SEEDS and up == #SEEDS,
        'temperament: at ten at night %d of %d early risers had gone to bed and %d night owls were about',
        slept, #SEEDS, up)
    log.info('selftest', 'temperament  roamed %.0f bold, %.0f timid; kept %.0f sociable, %.0f alone; %d/%d up at night',
        mean(roam[1]), mean(roam[0]), mean(apart[1]), mean(apart[0]), up, #SEEDS)
end)

-- Terrarium: 3c. Courtship (#22). Nobody is told to court. Over a day of the
-- jar from the lamp coming on, pairs that keep meeting court of their own
-- accord: in every seed's day somebody does, and over the seeds every plan
-- does. A pair is always of one plan, both fed, and side by side all the
-- while; and nobody courts twice between one sleep and the next.
test('court', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local DayCycle = require('jar.daycycle')
    local SEEDS = j.seed and {j.seed} or {20261018, 1, 2, 3}
    local by_plan = {worm = 0, blob = 0, spider = 0}
    for _, seed in ipairs(SEEDS) do
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.lampon, day = DAY})
        local courts, apart, since = 0, 0, {}
        w.events:on(function(ev)
            if ev.kind == 'court' then
                local a, b = ev.who, ev.with
                check(results, a.key == b.key, 'court: a %s courted a %s (seed %d)', a.key, b.key, seed)
            elseif ev.kind == 'courted' then
                courts = courts + 1
                by_plan[ev.who.key] = by_plan[ev.who.key] + 1
            end
        end)
        local twice = {}
        for s = 1, math.floor(DAY / fixed_dt + 0.5) do
            w:step(fixed_dt)
            for i, m in ipairs(w.minds) do
                if m.doing == 'court' then
                    if not since[i] then
                        since[i] = m.courts
                        check(results, m.hunger < 0.6, 'court: %s courted hungry (%.2f, seed %d)',
                            w.creatures[i].name, m.hunger, seed)
                    end
                    local x, y = w.creatures[i]:anchor()
                    local ox, oy = w.creatures[m.with]:anchor()
                    apart = math.max(apart, math.sqrt((ox - x) ^ 2 + (oy - y) ^ 2))
                else
                    since[i] = nil
                end
                -- (courtships counted since it last slept)
                if m.doing == 'rest' or not twice[i] then twice[i] = m.courts end
                if m.courts - twice[i] > 1 then
                    check(results, false, 'court: %s courted twice between sleeps (seed %d)', w.creatures[i].name, seed)
                    twice[i] = m.courts
                end
            end
        end
        check(results, courts >= 1, 'court: nobody courted in a day of seed %d', seed)
        check(results, apart < 100, 'court: a pair courted %.0f apart (seed %d)', apart, seed)
        log.info('selftest', 'court  seed %-9d %d courtships, widest pair %.0f apart', seed, courts, apart)
    end
    if not j.seed then
        for plan, n in pairs(by_plan) do
            check(results, n >= 1, 'court: no %s courted in %d days', plan, #SEEDS)
        end
    end
    log.info('selftest', 'court        worms %d, blobs %d, spiders %d over %d days', by_plan.worm, by_plan.blob,
        by_plan.spider, #SEEDS)
end)

-- Terrarium: 3c. Eggs (#23), the gate. In a jar of 900-second days from
-- lamp-on, the first pair to court lays a clutch in the moss, each egg a
-- child of the two. The clutch hatches about a day later, small and pale (the
-- body of its genome at nothing grown, its graphs built while it waited),
-- and each hatchling grows a stage at a time in its sleep, never twice in
-- one, until it's its own genome, its own colours, and on its own graph. A
-- few seconds after each moult its body is whole: a worm's new segments
-- joined on, a blob filled out, a spider standing on its feet.
-- Grown, a child mixes its parents: some genes from one, some from the other.
local EGGS_DAYS = 5
test('eggs', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local DayCycle = require('jar.daycycle')
    local Genome = require('genome')
    local SEEDS = j.seed and {j.seed} or {20261018, 2}
    local mixed, raised = 0, 0
    for _, seed in ipairs(SEEDS) do
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.lampon, day = DAY})
        local clutch, hatched, laid_at = nil, {}, nil
        local moults, slept, settle = {}, {}, {}
        w.events:on(function(ev)
            if ev.kind == 'laid' and not clutch then
                clutch, laid_at = ev.eggs, w.time
            elseif ev.kind == 'hatched' and clutch then
                for _, egg in ipairs(clutch) do
                    local c = w.creatures[egg.who]
                    if c == ev.who then
                        egg.c = c -- (by the creature: indices move as the old die, #24)
                        hatched[#hatched + 1] = egg
                        -- Hatched about a day after it was laid, small and pale
                        local waited = (w.time - egg.laid) / DAY
                        check(results, waited >= World.INCUBATE[1] - 0.01 and waited <= World.INCUBATE[2] + 0.01,
                            'eggs: an egg hatched after %.2f days (seed %d)', waited, seed)
                        local small = Genome.young(egg.genome, 0)
                        for _, g in ipairs(Genome[egg.key].own) do
                            check(results, c.genome[g.name] == small[g.name], 'eggs: a %s hatched with %s %s, not %s (seed %d)',
                                egg.key, g.name, tostring(c.genome[g.name]), tostring(small[g.name]), seed)
                        end
                        check(results, c.skin.young == 1, 'eggs: a %s hatched in its grown colours (seed %d)', egg.key, seed)
                    end
                end
            elseif ev.kind == 'moulted' then
                local c = ev.who
                local nights = w.minds[w:index_of(c)].nights
                check(results, slept[c] ~= nights, 'eggs: a %s moulted twice in one sleep (seed %d)', c.key, seed)
                slept[c] = nights
                moults[c] = (moults[c] or 0) + 1
                settle[#settle + 1] = {c = c, at = w.time + 3}
            end
        end)
        local steps, grown = math.floor(EGGS_DAYS * DAY / dt), false
        -- Whole after growing: no segment stretched past twice its length, a
        -- blob holding most of its area, a spider with its feet on something
        local function whole(c)
            if not w:index_of(c) then return end
            local ok, what = true, ''
            if c.key == 'worm' then
                for k = 2, #c.points do
                    local a, b = c.points[k - 1], c.points[k]
                    if (b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 > (2 * 8.5) ^ 2 then ok, what = false, 'torn' end
                end
            elseif c.key == 'blob' then
                ok, what = math.abs(c:area()) > 0.5 * c.area0, 'crushed'
            else
                local feet = 0
                for _, leg in ipairs(c.legs) do feet = feet + (leg.grounded and 1 or 0) end
                ok, what = feet >= #c.legs / 2, 'off its feet'
            end
            check(results, ok, 'eggs: a %s was %s after a moult (seed %d)', c.key, what, seed)
        end
        for _ = 1, steps do
            w:step(dt)
            while settle[1] and w.time >= settle[1].at do whole(table.remove(settle, 1).c) end
            if clutch and #hatched == #clutch then
                grown = true
                for _, egg in ipairs(clutch) do grown = grown and not w.young[w:index_of(egg.c) or 0] end
                if grown and #settle == 0 then break end
            end
        end
        check(results, clutch ~= nil, 'eggs: nobody laid in %d days of seed %d', EGGS_DAYS, seed)
        if clutch then
            local s = w.level.by_id[clutch[1].solid]
            check(results, #clutch >= World.CLUTCH[1] and #clutch <= World.CLUTCH[2] and s.moss,
                'eggs: a clutch of %d laid on %s (seed %d)', #clutch, s.id, seed)
            check(results, #hatched == #clutch, 'eggs: %d of %d eggs hatched (seed %d)', #hatched, #clutch, seed)
            for _, egg in ipairs(clutch) do
                local a, b = egg.parents[1], egg.parents[2]
                local c = egg.c
                local i = c and w:index_of(c)
                if not i then c = nil end
                -- Each gene is one parent's, give or take a mutation's step
                local from = {0, 0}
                for _, g in ipairs(Genome[egg.key].genes) do
                    local v, va, vb = egg.genome[g.name], a[g.name], b[g.name]
                    local near = g.real and Genome.BIG * (g.real[2] - g.real[1]) + 1e-9 or 1
                    if g.pick then
                        local function at(x) for k, p in ipairs(g.pick) do if p == x then return k end end end
                        v, va, vb = at(v), at(va), at(vb)
                    end
                    local da, db = math.abs(v - va), math.abs(v - vb)
                    check(results, math.min(da, db) <= near, 'eggs: a child\'s %s %s is no parent\'s (%s, %s; seed %d)',
                        g.name, tostring(egg.genome[g.name]), tostring(a[g.name]), tostring(b[g.name]), seed)
                    if da < db then from[1] = from[1] + 1 elseif db < da then from[2] = from[2] + 1 end
                end
                if from[1] > 0 and from[2] > 0 then mixed = mixed + 1 end
                if c then
                    -- Grown into its genome, on its own graph
                    local body = c.genome
                    for _, g in ipairs(Genome[egg.key].own) do
                        check(results, body[g.name] == egg.genome[g.name], 'eggs: a grown %s has %s %s, not %s (seed %d)',
                            egg.key, g.name, tostring(body[g.name]), tostring(egg.genome[g.name]), seed)
                    end
                    check(results, not w.young[i] and not w.minds[i].young and c.skin.young == 0,
                        'eggs: a hatchling never grew up (seed %d, %d moults)', seed, moults[c] or 0)
                    check(results, moults[c] == World.STAGES, 'eggs: a hatchling moulted %d times (seed %d)',
                        moults[c] or 0, seed)
                    check(results, w.graphs[i] == w.navs[c.nav] and w.controllers[i].graph == w.graphs[i],
                        'eggs: a grown %s walks a graph not its own (seed %d)', egg.key, seed)
                    local x, y = c:anchor()
                    check(results, x > 0 and x < level_data.width and y < 600,
                        'eggs: a %s grew up outside the jar at %.0f, %.0f (seed %d)', egg.key, x, y, seed)
                    raised = raised + 1
                end
            end
            log.info('selftest', 'eggs  seed %-9d %s clutch of %d laid at %.0f s, hatched %s, grown by %.0f s',
                seed, clutch[1].key, #clutch, laid_at, #hatched == #clutch and 'all' or (#hatched .. ''), w.time)
        end
    end
    -- And every plan's growing, wherever the seeds' clutches fell: a hatchling
    -- of the biggest body each plan has, moulted in turn as if each were a
    -- night, settles whole into each new body and ends as its genome
    for _, key in ipairs({'worm', 'blob', 'spider'}) do
        rng.seed(23)
        local w = World.new(level_data, {wander = false, selected = 0, hour = DayCycle.presets.night, day = DAY})
        local g = Genome.random(key, rng.sim)
        g.segments, g.size, g.reach = g.segments and 24, g.size and 1.4, g.reach and 1.3
        local r
        for _, res in ipairs(level_data.residents) do r = r or (res.key == key and res) end
        local egg = w:lay(g, r.x + 30, r.solid, nil, {young = true})
        while #w.eggs > 0 do w:step(dt) end
        local i = egg.who
        w.young[i].born = -math.huge
        for stage = 1, World.STAGES do
            w.minds[i].doing, w.minds[i].nights = 'rest', stage
            for _ = 1, 2 / dt do w:step(dt) end
            check(results, w.young[i] == nil or w.young[i].stage == stage, 'eggs: a %s didn\'t moult on night %d', key, stage)
            local c = w.creatures[i]
            if key == 'worm' then
                local most = 0
                for k = 2, #c.points do
                    local a, b = c.points[k - 1], c.points[k]
                    most = math.max(most, math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2))
                end
                check(results, most < 2 * 8.5 and #c.points == c.n, 'eggs: a worm grown to %d segments is torn (%.1f)',
                    c.n, most)
            elseif key == 'blob' then
                check(results, math.abs(c:area()) > 0.8 * c.area0, 'eggs: a blob grown to size %.2f hasn\'t filled out',
                    c.size)
            else
                local feet = 0
                for _, leg in ipairs(c.legs) do feet = feet + (leg.grounded and 1 or 0) end
                check(results, feet == #c.legs, 'eggs: a spider grown to reach %.2f stands on %d of %d feet',
                    c.scale, feet, #c.legs)
            end
        end
        local c = w.creatures[i]
        check(results, not w.young[i] and c.genome.segments == g.segments and c.genome.size == g.size
            and c.genome.reach == g.reach and w.graphs[i] == w.navs[c.nav], 'eggs: a %s didn\'t grow into its genome', key)
    end
    check(results, mixed >= 1, 'eggs: no child mixed its parents\' genes')
    log.info('selftest', 'eggs         %d raised, %d with genes from both parents', raised, mixed)
end)

-- Terrarium: 3c. Death (#24), the gate. Every creature has three to five jar
-- days, and a resident has lived up to one of them when the jar opens. One of
-- each plan is brought near its end: an elder walks at less than its own pace
-- and wears deeper colours. When its time has come it goes to bed in the moss
-- (a spider too, off its ledge), dies in its sleep there, fades for FADE
-- seconds and is gone. Everyone else is renumbered without a thread left
-- hanging (no mind follows, courts or remembers meeting the dead), the jar
-- carries on, and the moss it lay on, pressed flat, grows back by the next
-- afternoon taller than moss can grow there by itself. Two runs of one seed
-- are the same jar after a death.
test('death', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local DayCycle = require('jar.daycycle')
    local Moss = require('jar.moss')
    local Skin = require('bodies.skin')
    local statehash = require('core.statehash')
    local SEEDS = j.seed and {j.seed} or {20261018, 5}

    -- Every list the World keeps by creature index agrees with the others
    local function consistent(w, seed)
        local n, ok = #w.creatures, true
        for _, list in ipairs({w.graphs, w.controllers, w.minds, w.genomes, w.lives}) do ok = ok and #list == n end
        for k, m in ipairs(w.minds) do
            ok = ok and w.controllers[k].creature == w.creatures[k]
            ok = ok and (m.with == nil or (m.with >= 1 and m.with <= n and m.with ~= k))
            for q in pairs(m.met) do ok = ok and q >= 1 and q <= n end
            for q in pairs(m.near) do ok = ok and q >= 1 and q <= n end
        end
        for q in pairs(w.young) do ok = ok and q >= 1 and q <= n end
        check(results, ok, 'death: the jar lost count of who is who after a death (seed %d)', seed)
    end

    -- One run of `seed`. With `upto`, it stops at that step and returns the
    -- state hash; otherwise it checks everything, and returns the step and
    -- hash at the end of the step the first one went back to the moss.
    local function run(seed, upto)
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.lampon, day = DAY})
        if not upto then
            for _, life in ipairs(w.lives) do
                check(results, life.span >= World.LIFE[1] * DAY and life.span <= World.LIFE[2] * DAY
                    and life.born <= 0 and life.born >= -World.LIVED * DAY,
                    'death: a resident born at %.0f s with %.2f days to live (seed %d)', life.born, life.span / DAY, seed)
            end
        end
        -- One of each plan with a fifth of a short life left, and a third of
        -- its kind beside it so the floor (#26) doesn't spare it
        local old, count = {}, 0
        for _, key in ipairs({'worm', 'blob', 'spider'}) do
            local i = w:first(key)
            local r = w.creatures[i].home
            w:lay(w.genomes[i], r.x + 40, r.solid)
        end
        for _, key in ipairs({'worm', 'blob', 'spider'}) do
            local i = w:first(key)
            w.lives[i].span, w.lives[i].born = DAY, -0.8 * DAY
            old[w.creatures[i]] = {key = key, name = w.creatures[i].name, genome = w.genomes[i]}
            count = count + 1
        end
        local returned, first = 0, nil
        w.events:on(function(ev)
            local o = old[ev.who]
            if not o then return end
            local c = ev.who
            if ev.kind == 'dying' then
                local i = w:index_of(c)
                local life = w.lives[i]
                o.dying = w.time
                o.asleep = w.time < w:end_of(i) + World.GRACE * DAY
                local on = c.profile.climbs and c.solid or c.mover.solid
                o.moss = on and on.moss
            elseif ev.kind == 'returned' then
                o.returned = w.time
                returned = returned + 1
                for _, r in ipairs(w.remains) do
                    if r.at == w.time and r.x == ev.x then o.remains = r end
                end
                o.cells = {}
                local m = w.moss
                for k = 1, m.count do
                    if m.rich[k] >= 0.3 and m.x[k] >= o.remains.x0 - 10 and m.x[k] <= o.remains.x1 + 10 then
                        o.cells[#o.cells + 1] = k
                    end
                end
                o.pressed = true
                for _, k in ipairs(o.cells) do o.pressed = o.pressed and m.h[k] <= Moss.WORN end
            end
        end)

        local steps = math.floor(2.5 * DAY / dt)
        for s = 1, steps do
            w:step(dt)
            if upto and s == upto then return statehash.of(w).total end
            if s == 1 then
                -- Elders: slower than their bodies can go, and deeper in colour
                for c, o in pairs(old) do
                    local i = w:index_of(c)
                    local base = Skin.of(c.key, c.genome)
                    local fresh, aged = base[base.main], c.skin[base.main]
                    check(results, w.controllers[i].pace < 0.95, 'death: an elder %s walks at %.2f of its pace (seed %d)',
                        o.key, w.controllers[i].pace, seed)
                    check(results, c.skin.old > 0 and aged[1] + aged[2] + aged[3] < fresh[1] + fresh[2] + fresh[3],
                        'death: an elder %s hasn\'t deepened (seed %d)', o.key, seed)
                end
            end
            if returned > 0 and not first then
                first = {step = s, hash = statehash.of(w).total}
                consistent(w, seed)
            end
            if returned == count then break end
        end
        consistent(w, seed)

        for c, o in pairs(old) do
            check(results, o.returned ~= nil, 'death: %s the %s never went back to the moss (seed %d)', o.name, o.key, seed)
            if o.returned then
                check(results, o.asleep, 'death: %s the %s died awake (seed %d)', o.name, o.key, seed)
                check(results, o.moss, 'death: %s the %s died off the moss (seed %d)', o.name, o.key, seed)
                check(results, math.abs(o.returned - o.dying - World.FADE) < 2 * dt,
                    'death: %s the %s faded in %.1f s (seed %d)', o.name, o.key, o.returned - o.dying, seed)
                check(results, w:index_of(c) == nil, 'death: %s the %s is still in the jar (seed %d)', o.name, o.key, seed)
                check(results, #o.cells >= 2, 'death: %s the %s left only %d rich cells (seed %d)', o.name, o.key, #o.cells, seed)
                check(results, o.pressed, 'death: the moss under %s the %s was never pressed down (seed %d)', o.name, o.key, seed)
                log.info('selftest', 'death seed %-9d %-6s %-6s died asleep at %.2f days, gone %.0f s later, %d cells rich',
                    seed, o.key, o.name, (o.dying + 0.8 * DAY) / DAY, o.returned - o.dying, #o.cells)
            end
        end

        -- The jar carries on without them
        for _ = 1, math.floor(30 / dt) do w:step(dt) end
        consistent(w, seed)

        -- By the next afternoon the patches it lay on are back, taller than
        -- the moss there grows by itself (the moss alone, a second at a time)
        local m, hour = w.moss, w:hour()
        local until_afternoon = ((24 + DayCycle.presets.afternoon - hour) % 24 + 24) * 3600
        for t = 1, until_afternoon do m:update(1, DayCycle.lampAt((hour + t / 3600) % 24)) end
        for _, o in pairs(old) do
            local taller, low = 0, math.huge
            for _, k in ipairs(o.cells or {}) do
                if m.h[k] > m.cap[k] + 0.05 then taller = taller + 1 end
                low = math.min(low, m.h[k] - m.cap[k])
            end
            check(results, o.cells and taller == #o.cells,
                'death: by the next afternoon only %d of %d cells where the %s lay grew back rich (lowest %.2f over)',
                taller, o.cells and #o.cells or 0, o.key, low)
        end
        return first
    end

    for k, seed in ipairs(SEEDS) do
        local first = run(seed)
        if k == 1 and first then
            local again = run(seed, first.step)
            check(results, again == first.hash, 'death: two runs of seed %d differ after a death', seed)
        end
    end
end)

-- Terrarium: 3c. The floor (#26). Every resident is brought to the end of its
-- life, and with two of each kind, every kind is scarce: nobody dies, and each
-- pair courts after a single meeting. A kind is never down to fewer than two,
-- counting its eggs, and never empty of creatures while it has no eggs. Once a
-- kind has eggs in the moss it isn't scarce, and its elders die as they would
-- have; the last two of a kind outlive their time. Then a few ordinary jar
-- days, where nothing is rigged, keep every kind and stay under CAPACITY.
local FLOOR_DAYS = 6
test('floor', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local DayCycle = require('jar.daycycle')
    local SEEDS = j.seed and {j.seed} or {20261018, 3, 7}
    local KEYS = {'worm', 'blob', 'spider'}

    -- How many of each kind there are, counting eggs and not the dying, and
    -- how many are creatures
    local function counts(w)
        local n, alive = {}, {}
        for _, key in ipairs(KEYS) do n[key], alive[key] = 0, 0 end
        for i, c in ipairs(w.creatures) do
            alive[c.key] = alive[c.key] + 1
            if not w.lives[i].dying then n[c.key] = n[c.key] + 1 end
        end
        for _, egg in ipairs(w.eggs) do n[egg.key] = n[egg.key] + 1 end
        return n, alive
    end
    local function holds(w, n, alive, what, seed)
        for _, key in ipairs(KEYS) do
            if n[key] < World.FLOOR or (alive[key] == 0 and n[key] == 0) then
                check(results, false, 'floor: %s, the %ss were down to %d (%d alive, seed %d, %.2f days)',
                    what, key, n[key], alive[key], seed, w.time / DAY)
                return false
            end
        end
        return true
    end

    for _, seed in ipairs(SEEDS) do
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.lampon, day = DAY})
        for _, life in ipairs(w.lives) do life.span, life.born = DAY, -0.99 * DAY end
        local residents = {}
        for i, c in ipairs(w.creatures) do residents[c] = i end
        local laid, died, outlived = {}, {}, {}
        w.events:on(function(ev)
            if ev.kind == 'laid' then
                laid[ev.who.key] = laid[ev.who.key] or w.time
            elseif ev.kind == 'dying' and residents[ev.who] then
                local key = ev.who.key
                check(results, laid[key] ~= nil, 'floor: a %s died before its kind had eggs (seed %d)', key, seed)
                died[key] = (died[key] or 0) + 1
            end
        end)
        local ok = true
        for _ = 1, math.floor(2.5 * DAY / dt) do
            w:step(dt)
            local n, alive = counts(w)
            ok = ok and holds(w, n, alive, 'scarce', seed)
            for c in pairs(residents) do
                local i = w:index_of(c)
                if i and w.time > w.lives[i].born + w.lives[i].span then outlived[c.key] = true end
            end
        end
        for _, key in ipairs(KEYS) do
            check(results, outlived[key], 'floor: no %s outlived its time (seed %d)', key, seed)
            check(results, laid[key] ~= nil, 'floor: the scarce %ss laid nothing in 2.5 days (seed %d)', key, seed)
            if laid[key] then
                check(results, (died[key] or 0) >= 1, 'floor: no %s elder died after its kind laid (seed %d)', key, seed)
            end
        end
        log.info('selftest', 'floor seed %-9d laid at %.2f/%.2f/%.2f days (worm/blob/spider), %d/%d/%d elders gone',
            seed, (laid.worm or -DAY) / DAY, (laid.blob or -DAY) / DAY, (laid.spider or -DAY) / DAY,
            died.worm or 0, died.blob or 0, died.spider or 0)
    end

    -- An ordinary jar for a few days
    local seed = SEEDS[1]
    rng.seed(seed)
    local w = World.new(level_data, {wander = true, selected = 0, hour = DayCycle.presets.lampon, day = DAY})
    local most, fewest, deaths, births = 0, math.huge, 0, 0
    w.events:on(function(ev)
        if ev.kind == 'returned' then deaths = deaths + 1 elseif ev.kind == 'hatched' then births = births + 1 end
    end)
    local ok, every, by_key = true, math.floor(DAY / 4 / dt), {worm = {}, blob = {}, spider = {}}
    for s = 1, math.floor(FLOOR_DAYS * DAY / dt) do
        w:step(dt)
        local n, alive = counts(w)
        ok = ok and holds(w, n, alive, 'in an ordinary jar', seed)
        most = math.max(most, #w.creatures + #w.eggs)
        fewest = math.min(fewest, #w.creatures)
        if s % every == 0 then
            for _, key in ipairs(KEYS) do table.insert(by_key[key], n[key]) end
        end
    end
    check(results, most <= World.CAPACITY, 'floor: the jar held %d', most)
    check(results, deaths >= 1, 'floor: nobody died in %d days', FLOOR_DAYS)
    local n = counts(w)
    log.info('selftest', 'floor        %d days of seed %d: %d hatched, %d died, %d to %d in the jar, now %d/%d/%d',
        FLOOR_DAYS, seed, births, deaths, fewest, most, n.worm, n.blob, n.spider)
    -- (each kind, eggs and all, every quarter of a day)
    for _, key in ipairs(KEYS) do
        log.info('selftest', 'floor        %-7s %s', key .. 's', table.concat(by_key[key], ' '))
    end
end)

-- Terrarium: 3c. A pinch of food (#25), the gate. In a jar at midday, a pinch
-- dropped beside one that's up and about falls from under the lid and settles
-- on what's below it, never in it, and the awake ones near enough come over
-- and nibble it; one beyond its notice carries on. The jar keeps only
-- Food.PINCHES pinches, and one comes back each 1/PINCHES of a day. Two runs
-- with the same pinch are the same jar.
test('food', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    local Food = require('jar.food')
    local statehash = require('core.statehash')
    local SEEDS = j.seed and {j.seed} or {20261018, 1, 2}
    local function seconds(w, sec, each)
        for _ = 1, math.floor(sec / fixed_dt + 0.5) do
            w:step(fixed_dt)
            if each then each() end
        end
    end

    local function run(seed)
        rng.seed(seed)
        local w = World.new(level_data, {wander = true, selected = 0, day = DAY})
        seconds(w, 5)
        -- Beside the first one up and about on the soil
        local x
        for i, c in ipairs(w.creatures) do
            local m = w.minds[i]
            if not x and (m.doing == 'idle' or m.doing == 'wander' or m.doing == 'graze') then
                local cx, cy = c:anchor()
                if cy > 540 then x = cx + (cx < 1000 and 90 or -90) end
            end
        end
        x = x or 960
        w:pinch(x)
        local crumbs = #w.food.crumbs
        -- Everyone up and free, and how near it is, when the crumbs are down
        local near, came, soon, nibbled = {}, {}, {}, {}
        local landed
        w.events:on(function(ev)
            if ev.kind == 'nibbled' then nibbled[ev.who] = (nibbled[ev.who] or 0) + 1 end
        end)
        local down = false
        seconds(w, 90, function()
            if not down then
                down = true
                for _, f in ipairs(w.food.crumbs) do down = down and f.down end
                if down then
                    landed = w.time
                    for _, f in ipairs(w.food.crumbs) do
                        check(results, f.solid and math.abs(f.y - f.solid.y) < 1e-6 and not w.level:solid_at(f.x, f.y - 1),
                            'food: a crumb settled at (%.0f, %.0f), not on a top (seed %d)', f.x, f.y, seed)
                    end
                    for i, c in ipairs(w.creatures) do
                        local m = w.minds[i]
                        local cx, cy = c:anchor()
                        local d = math.sqrt((cx - x) ^ 2 + (cy - w.food.crumbs[1].y) ^ 2)
                        if m:awake(w:hour()) and (m.doing ~= 'to_rest' and m.doing ~= 'rest') then
                            near[c] = {d = d, m = m}
                        end
                    end
                end
            end
            for i, m in ipairs(w.minds) do
                if m.doing == 'to_treat' or m.doing == 'nibble' then
                    came[w.creatures[i]] = true
                    if landed and w.time - landed < 2 then soon[w.creatures[i]] = true end
                end
            end
        end)
        check(results, down, 'food: the crumbs were still falling after 90 s (seed %d)', seed)
        local eaters, close, stayed, who = 0, 0, 0, {}
        for _, c in ipairs(w.creatures) do
            if nibbled[c] then who[#who + 1] = c.name or c.key end
        end
        for c, o in pairs(near) do
            if nibbled[c] then eaters = eaters + 1 end
            if o.d < 200 and not (o.m.doing == 'court' or o.m.doing == 'await' or o.m.doing == 'to_court') then
                close = close + 1
                check(results, came[c], 'food: %s, %.0f from the pinch, never came over (seed %d)', c.name or c.key, o.d, seed)
            end
            if o.d > o.m.notice + 80 then
                stayed = stayed + 1
                check(results, not soon[c], 'food: %s came for crumbs %.0f off, past its notice (seed %d)',
                    c.name or c.key, o.d, seed)
            end
        end
        local left = #w.food.crumbs
        check(results, eaters >= 1 and left < crumbs, 'food: nobody ate any of the pinch (seed %d)', seed)
        log.info('selftest', 'food   seed %-9d %d crumbs at %4.0f, %d eaten by %s (%d were close), %d too far to notice',
            seed, crumbs, x, crumbs - left, table.concat(who, ', '), close, stayed)
        return w, x
    end

    local first
    for k, seed in ipairs(SEEDS) do
        local w, x = run(seed)
        if k == 1 then first = {seed = seed, x = x, hash = statehash.of(w).total} end
    end

    -- A pinch is history: the same pinch at the same moment is the same jar
    rng.seed(first.seed)
    local w = World.new(level_data, {wander = true, selected = 0, day = DAY})
    seconds(w, 5)
    w:pinch(first.x)
    seconds(w, 90)
    check(results, statehash.of(w).total == first.hash, 'food: two runs with the same pinch differ (seed %d)', first.seed)

    -- A small treat: the jar keeps a few pinches, and they come back over the day
    local given = 1
    while w:pinch(500) do given = given + 1 end
    check(results, given == Food.PINCHES, 'food: %d pinches in a row, wanted %d', given, Food.PINCHES)
    local wait = DAY / Food.PINCHES
    local due = (1 - w.food.pantry) * wait -- (the one given first is partly back already)
    seconds(w, due - 3)
    check(results, not w:pinch(500), 'food: a pinch came back after %.0f s, sooner than 1/%d of a day', due - 3, Food.PINCHES)
    seconds(w, 4)
    check(results, w:pinch(500) ~= nil, 'food: no pinch came back after %.0f s', due + 1)
    check(results, #w.food.given == given + 1, 'food: the jar kept %d pinches, given %d', #w.food.given, given + 1)
    -- and what nobody eats is gone into the moss before long
    seconds(w, Food.KEEP + 30)
    check(results, #w.food.crumbs == 0, 'food: %d crumbs still lying after %d s', #w.food.crumbs, Food.KEEP + 30)
    log.info('selftest', 'food         %d pinches a day, one back every %.0f s of a %d s day', Food.PINCHES, wait, DAY)
end)

-- Terrarium: 3d. Replay. The whole jar (scape, plants, creatures) opened
-- twice from one seed is the same jar after ten minutes of its life.
test('replay', function(j, results)
    check(results, dev.replay(j.open_jar, 7, 600, j.fixed_dt, j.step), 'replay: two runs of seed 7 diverged')
end)

-- Terrarium: 3e. Genomes (#10). Random ones come back in range and survive a
-- trip through their string form exactly; out-of-range and missing genes are
-- held to the range, and text that isn't a genome is turned away.
test('genome', function(_, results)
    local Genome = require('genome')
    local gen = love.math.newRandomGenerator(1010)
    for _, key in ipairs(Genome.order) do
        local bad, drift, seen = 0, 0, {}
        for n = 1, 2000 do
            local g = Genome.random(key, gen)
            if n == 1 then log.info('selftest', 'genome       %s', Genome.serialise(g)) end
            if not Genome.valid(g) then bad = bad + 1 end
            local s = Genome.serialise(g)
            local back = Genome.parse(s)
            for _, gene in ipairs(Genome[key].genes) do
                if not back or back[gene.name] ~= g[gene.name] then drift = drift + 1 end
                seen[gene.name] = seen[gene.name] or {}
                seen[gene.name][g[gene.name]] = true
            end
            if not back or Genome.serialise(back) ~= s then drift = drift + 1 end
        end
        check(results, bad == 0, 'genome: %d random %s genomes out of range', bad, key)
        check(results, drift == 0, 'genome: %d %s genes changed on a round trip', drift, key)
        -- every pick value and both ends of every int turn up
        for _, gene in ipairs(Genome[key].genes) do
            local want = gene.pick or (gene.int and {gene.int[1], gene.int[2]}) or {}
            for _, v in ipairs(want) do
                check(results, seen[gene.name][v], 'genome: %s %s never drew %s', key, gene.name, tostring(v))
            end
        end

        -- Way out of range, wrong types, NaN, a gene from another plan
        local wild = {plan = key, hue = 7, glow = -3, boldness = 0 / 0, sociability = 'lots', legs = 5,
            segments = 99.6, stiffness = -1, size = 1e9, pressure = -1e9, reach = 1 / 0, wings = 2}
        Genome.clamp(wild)
        check(results, Genome.valid(wild) and wild.wings == nil, 'genome: clamp left a %s out of range: %s', key,
            Genome.serialise(wild))
        local partial = Genome.parse(key .. ' hue=0.25 chronotype=2')
        check(results, partial and Genome.valid(partial) and partial.hue == 0.25 and partial.chronotype == 1,
            'genome: a partial %s string did not read', key)
    end
    local spider = Genome.parse('spider legs=5 reach=1.0004')
    check(results, spider and spider.legs == 4 and spider.reach == 1, 'genome: picks and reals did not snap')
    local renamed = Genome.parse('worm plan=3 segments=12')
    check(results, renamed and renamed.plan == 'worm' and renamed.segments == 12, 'genome: a gene called plan renamed it')
    for _, junk in ipairs({'', 'fish hue=0.5', 'worm hue=blue', 'worm =3', 42}) do
        check(results, Genome.parse(junk) == nil, 'genome: read %q as a genome', tostring(junk))
    end
    log.info('selftest', 'genome       2000 per plan in range and round-trip exactly')

    -- Inheritance (#11). The same seed gives the same family, line after line.
    local function line(seed, key)
        local g = love.math.newRandomGenerator(seed)
        local a, b, out = Genome.random(key, g), Genome.random(key, g), {}
        for n = 1, 200 do
            a, b = b, Genome.child(a, b, g)
            out[n] = Genome.serialise(b)
        end
        return table.concat(out, '\n')
    end
    for _, key in ipairs(Genome.order) do
        check(results, line(1111, key) == line(1111, key), 'genome: seed 1111 bred two different %s lines', key)
        check(results, line(1111, key) ~= line(1112, key), 'genome: seeds 1111 and 1112 bred the same %s line', key)
    end
    check(results, not pcall(Genome.child, Genome.random('worm', gen), Genome.random('blob', gen), gen),
        'genome: a worm bred with a blob')

    -- Each gene comes from one parent or the other, about half and half.
    -- Parents sit at opposite ends of every range, and no step reaches halfway.
    for _, key in ipairs(Genome.order) do
        local a, b = {plan = key}, {plan = key}
        for _, g in ipairs(Genome[key].genes) do
            local r = g.real or g.int or {g.pick[1], g.pick[#g.pick]}
            a[g.name], b[g.name] = r[1], r[2]
        end
        local from_a, total, bad = 0, 0, 0
        for _ = 1, 2000 do
            local c = Genome.child(a, b, gen)
            if not Genome.valid(c) then bad = bad + 1 end
            for _, g in ipairs(Genome[key].genes) do
                if math.abs(c[g.name] - a[g.name]) < math.abs(c[g.name] - b[g.name]) then from_a = from_a + 1 end
                total = total + 1
            end
        end
        check(results, bad == 0, 'genome: %d %s children out of range', bad, key)
        check(results, math.abs(from_a / total - 0.5) < 0.03, 'genome: %s children took %.0f%% from one parent', key,
            100 * from_a / total)
    end

    -- 10k mutations of every gene, each from an even spread across its range.
    -- Folding keeps the spread even: the end cells of a histogram hold their
    -- share, and a real lands exactly on an end value no more often than on any
    -- other thousandth (a clamp would put about ten times that there). Picks move
    -- one value at most, and about 1 real step in 20 is a big one.
    local N, big, reals = 10000, 0, 0
    local function small_reach(g) return Genome.STEP * (g.real[2] - g.real[1]) + 0.001 end
    for _, key in ipairs(Genome.order) do
        for _, g in ipairs(Genome[key].genes) do
            local cells, count, far, ends = 20, {}, 0, 0
            if g.int then cells = g.int[2] - g.int[1] + 1 elseif g.pick then cells = #g.pick end
            for c = 1, cells do count[c] = 0 end
            for _ = 1, N do
                local start = Genome.random(key, gen)
                local v0 = start[g.name]
                local v = Genome.mutate(start, gen)[g.name]
                local c
                if g.real then
                    local lo, hi = g.real[1], g.real[2]
                    c = math.min(cells, math.floor((v - lo) / (hi - lo) * cells) + 1)
                    if v == lo or v == hi then ends = ends + 1 end
                    if math.abs(v - v0) > small_reach(g) then big = big + 1 end
                    reals = reals + 1
                elseif g.int then
                    c = v - g.int[1] + 1
                else
                    for i, p in ipairs(g.pick) do
                        if p == v then c = i end
                        if p == v0 and (g.pick[i - 1] ~= v and g.pick[i] ~= v and g.pick[i + 1] ~= v) then far = far + 1 end
                    end
                end
                count[c] = count[c] + 1
            end
            local share = N / cells
            for _, c in ipairs({1, cells}) do
                check(results, math.abs(count[c] / share - 1) < 0.2, 'genome: %s %s end cell %d holds %d, its share is %.0f',
                    key, g.name, c, count[c], share)
            end
            if g.real then
                -- both end values together cover one thousandth of the range
                local thousandth = N * 0.001 / (g.real[2] - g.real[1])
                check(results, ends < 3 * thousandth, 'genome: %s %s piled %d onto its ends, a thousandth holds %.0f',
                    key, g.name, ends, thousandth)
            end
            check(results, far == 0, 'genome: %s %s jumped past a neighbour %d times', key, g.name, far)
        end
    end
    local want = Genome.BIG_CHANCE * ((Genome.BIG - Genome.STEP) / Genome.BIG) ^ 2
    check(results, math.abs(big / reals / want - 1) < 0.25, 'genome: %.1f%% of real steps were big, wanted about %.1f%%',
        100 * big / reals, 100 * want)
    log.info('selftest', 'genome       children breed true from a seed; 10k mutations per gene, no pile-up at the ends')
end)

-- Terrarium: 3f. The worm's genes (#12). The extremes have to look different
-- where it matters, at the shelf's edge: each worm lies along the slate with
-- its head near the glass and its tail out over the drop. A stiff one holds a
-- line out over the air, a loose one drapes. Then each crawls along the soil,
-- and the long one's body carries more bunches than the short one's.
-- Colour (#15): the families never share a colour, the markings show against
-- the skin, the glow is only there when the lamp dims, and every pattern on
-- every plan draws (into the null renderer) without touching the sim.
test('colour', function(j, results)
    local Genome, Skin, colour = require('genome'), require('bodies.skin'), require('core.colour')
    local DayCycle = require('jar.daycycle')
    local statehash = require('core.statehash')

    -- Each family's main colour across its whole hue gene
    local STEPS = 40
    local samples = {}
    for _, key in ipairs(Genome.order) do
        samples[key] = {}
        local faint = math.huge
        for i = 0, STEPS do
            local sk = Skin.of(key, {plan = key, hue = i / STEPS, pattern = 1, glow = 0.5})
            local c = sk[sk.main]
            samples[key][#samples[key] + 1] = c
            faint = math.min(faint, colour.distance(c[1], c[2], c[3], sk.mark[1], sk.mark[2], sk.mark[3]))
        end
        check(results, faint > 0.15, 'colour: a %s marking can be as close as %.3f to its skin', key, faint)
    end
    -- The nearest any two creatures of different families come, in OKLab. 0.02
    -- is about the least you'd notice side by side; families should be far
    -- clearer apart than that.
    local nearest, pair = math.huge, ''
    for a = 1, #Genome.order do
        for b = a + 1, #Genome.order do
            local ka, kb = Genome.order[a], Genome.order[b]
            for _, ca in ipairs(samples[ka]) do
                for _, cb in ipairs(samples[kb]) do
                    local d = colour.distance(ca[1], ca[2], ca[3], cb[1], cb[2], cb[3])
                    if d < nearest then nearest, pair = d, ka .. '/' .. kb end
                end
            end
        end
    end
    log.info('selftest', 'colour       families at least %.3f apart (closest %s)', nearest, pair)
    check(results, nearest > 0.2, 'colour: a %s pair are only %.3f apart', pair, nearest)

    -- Glow: nothing under the lamp, all of it in the dark
    local sk = Skin.of('worm', {plan = 'worm', hue = 0.5, pattern = 1, glow = 0.8})
    for _, name in ipairs({'midday', 'morning', 'afternoon'}) do
        local env = DayCycle.evaluate(DayCycle.presets[name])
        check(results, Skin.shine(sk, env) == 0, 'colour: a worm glows %.2f at %s', Skin.shine(sk, env), name)
    end
    local night = Skin.shine(sk, DayCycle.evaluate(DayCycle.presets.night))
    check(results, night > 0.7, 'colour: glow 0.8 shines only %.2f at night', night)

    -- Every pattern on every plan draws, glows, and leaves the sim alone
    local undrawn = {}
    for p, pattern in ipairs(Skin.PATTERNS) do
        local genomes = {}
        for _, key in ipairs(Genome.order) do
            local g = Genome.random(key, love.math.newRandomGenerator(p))
            g.pattern = p
            genomes[#genomes + 1] = g
        end
        rng.seed(15)
        local w = j.World.new(j.level_data, {wander = false, selected = 0, genomes = genomes})
        for _ = 1, 60 do w:step(j.fixed_dt) end
        local before = statehash.of(w).total
        local ctx = {light_dir = w.light_dir, light = {glow = 1}}
        for _, key in ipairs(Genome.order) do
            local c = w.creatures[w:first(key)]
            c:draw(ctx)
            c:draw_emissive(ctx)
            local n = #(c.marks or {}) + #(c.local_marks or {})
            if n == 0 then undrawn[#undrawn + 1] = key .. ' ' .. pattern end
        end
        check(results, statehash.of(w).total == before, 'colour: drawing %s creatures changed the state hash', pattern)
    end
    check(results, #undrawn == 0, 'colour: no markings drawn for %s', table.concat(undrawn, ', '))
end)

test('worm', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local SEG_LEN = 8.5
    local function worm(genome)
        rng.seed(12)
        local w = World.new(level_data, {wander = false, selected = 0, genomes = {genome}})
        local i = w:first('worm')
        return w, i, w.creatures[i]
    end

    -- How far the tail hangs below the slate after 4s lying still, and how far
    -- out past the edge the body stays within a body's width of the top. The
    -- head lies 30px in from the edge, so even a short worm is half over it.
    local shelf = assert(require('jar.level').new(level_data).by_id.shelf)
    local function droop(genome)
        local w, _, c = worm(genome)
        c:reset(shelf.x + 30, shelf.y, 1)
        c.mover.solid = shelf
        for _ = 1, math.floor(4 / dt) do w:step(dt) end
        local tail, held = c.points[#c.points], 0
        for _, p in ipairs(c.points) do
            if p.x < shelf.x and p.y < shelf.y + 18 then held = math.max(held, shelf.x - p.x) end
        end
        return tail.y - shelf.y, held, c
    end
    local report = {}
    for _, n in ipairs({10, 24}) do
        local loose, loose_held = droop(string.format('worm segments=%d stiffness=0.2', n))
        local stiff, stiff_held = droop(string.format('worm segments=%d stiffness=0.9', n))
        report[#report + 1] = string.format('%d segs: tail %.0f/%.0fpx below, held out %.0f/%.0fpx', n, stiff, loose,
            stiff_held, loose_held)
        -- (a long worm's tail comes to rest on the tor below, stiff or loose)
        check(results, n > 12 or loose > stiff + 12, 'worm: %d segments, the loose tail hangs %.0fpx and the stiff one %.0fpx',
            n, loose, stiff)
        check(results, stiff_held > loose_held + 8, 'worm: %d segments, stiff held out %.0fpx, loose %.0fpx', n,
            stiff_held, loose_held)
    end

    -- Bunches while crawling: runs of shortened segments along the body,
    -- counted every 1/10s while it crawls across the soil
    local function humps(genome)
        local w, i, c = worm(genome)
        local soil, arch = w.level.by_id.soil, w.level.by_id.arch
        c:reset(arch.x + 150, soil.y, -1) -- under the arch toward its foot
        c.mover.solid = soil
        assert(w.controllers[i]:go_to(w.graphs[i]:snap_goal(arch.x + 55, soil.y - 4)), 'worm: no way along the soil')
        -- (only its crawl counts, for up to 4s once it's under way: a worm
        -- laid facing away from the foot would turn round first)
        local runs, samples, under_way = 0, 0, 0
        for _ = 1, math.floor(10 / dt) do
            w:step(dt)
            under_way = c.turning and 0 or under_way + 1
            if under_way > math.floor(4 / dt) then break end
            if under_way > 60 and under_way % 12 == 0 and c.mover.state == 'ground' and math.abs(c.mover.vx) > 20 then
                local inside = false
                for k = 2, #c.points - 1 do
                    local a, b = c.points[k], c.points[k + 1]
                    local short = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) < SEG_LEN * 0.9
                    if short and not inside then runs = runs + 1 end
                    inside = short
                end
                samples = samples + 1
            end
        end
        return runs / math.max(1, samples)
    end
    local short, long = humps('worm segments=10 stiffness=0.55'), humps('worm segments=24 stiffness=0.55')
    report[#report + 1] = string.format('bunches %.1f on 10 segs, %.1f on 24', short, long)
    check(results, short > 0.5 and long > short * 2, 'worm: crawling, %.1f bunches on 10 segments and %.1f on 24',
        short, long)

    -- With no genome it's Character's worm, and a genome reaches the body
    local _, _, c = worm(nil)
    check(results, c.genome and #c.points == c.genome.segments, 'worm: a resident has %d points for %s', #c.points,
        c.genome and require('genome').serialise(c.genome) or 'no genome')
    log.info('selftest', 'worm         %s', table.concat(report, '; '))
end)

-- Terrarium: blobs from their genes (#13). Size sets the profile and so the
-- nav graph; pressure, how round it holds itself and how deep a landing goes.
test('blob', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local Pathfinder = require('nav.pathfinder')
    local function blob(genome)
        rng.seed(13)
        local w = World.new(level_data, {wander = false, selected = 0, genomes = {genome}})
        local i = w:first('blob')
        return w, i, w.creatures[i]
    end

    -- Every size gets to every mossy top from where it hatched, and back,
    -- and its graph is its own: a bigger blob has fewer places it fits
    local report, jumps_at, nodes_at = {}, {}, {}
    for k = 0, 8 do
        local size = 0.6 + k * 0.1
        local w, i = blob(string.format('blob size=%.1f', size))
        local g = w.graphs[i]
        local start = w.controllers[i]:start_node()
        -- (Dew hatches on the open soil between the cairn and the flat stone,
        -- with a jump of 80 or more to every top)
        local x = w.creatures[i]:anchor()
        check(results, start and math.abs(start.x - x) < 30, 'blob: size %.1f hatched at x=%.0f, its nearest node is at %.0f',
            size, x, start and start.x or -1)
        local seen, cut, jumps = {}, {}, 0
        for _, n in ipairs(g.nodes) do
            if n.kind == 'top' and not seen[n.solid.id] and Pathfinder.find(g, start, n) and Pathfinder.find(g, n, start) then
                seen[n.solid.id] = true
            end
            for _, e in ipairs(n.edges) do if e.kind == 'jump' then jumps = jumps + 1 end end
        end
        for _, s in ipairs(w.level.solids) do
            if s.moss and not seen[s.id] then cut[#cut + 1] = s.id end
        end
        check(results, #cut == 0, 'blob: size %.1f cannot get to and from %s', size, table.concat(cut, ', '))
        jumps_at[k], nodes_at[k] = jumps, #g.nodes
    end
    -- Terrarium: places it fits, not jumps. Across the wide jar's open soil a
    -- longer reach links more of them, so jumps peak in the middle sizes.
    report[#report + 1] = string.format('nodes %d/%d/%d and jumps %d/%d/%d at size 0.6/1/1.4', nodes_at[0], nodes_at[4],
        nodes_at[8], jumps_at[0], jumps_at[4], jumps_at[8])
    check(results, nodes_at[0] >= nodes_at[4] and nodes_at[4] > nodes_at[8],
        'blob: nodes by size %d, %d, %d (the graph should shrink as it grows)', nodes_at[0], nodes_at[4], nodes_at[8])

    -- Height over width of the ring
    local function aspect(c)
        local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
        for _, p in ipairs(c.points) do
            x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y)
        end
        return (y1 - y0) / (x1 - x0)
    end
    -- At rest on the soil, then at its flattest after a 150px drop onto it
    local function land(genome)
        local w, _, c = blob(genome)
        local soil = w.level.by_id.soil
        c:reset(120, soil.y)
        c.mover.solid = soil
        for _ = 1, math.floor(2 / dt) do w:step(dt) end
        local rest, flat, landed = aspect(c), math.huge, false
        c:reset(120, soil.y - 150)
        c.mover:release(0, 0)
        for _ = 1, math.floor(2 / dt) do
            w:step(dt)
            landed = landed or c.mover.state == 'ground'
            if landed then flat = math.min(flat, aspect(c)) end
        end
        return rest, flat
    end
    local soft_rest, soft_flat = land('blob size=1 pressure=0.5')
    local firm_rest, firm_flat = land('blob size=1 pressure=1.5')
    report[#report + 1] = string.format('pressure 0.5/1.5 rests %.2f/%.2f, lands %.2f/%.2f', soft_rest, firm_rest,
        soft_flat, firm_flat)
    check(results, firm_rest > soft_rest + 0.08, 'blob: at rest a firm blob is %.2f tall for its width, a soft one %.2f',
        firm_rest, soft_rest)
    check(results, firm_flat > soft_flat + 0.2, 'blob: landing, a firm blob flattens to %.2f, a soft one %.2f',
        firm_flat, soft_flat)
    -- The ticket's pair: a small firm blob and a large soft one
    local _, small_flat = land('blob size=0.6 pressure=1.5')
    local _, large_flat = land('blob size=1.4 pressure=0.5')
    report[#report + 1] = string.format('small firm lands %.2f, large soft %.2f', small_flat, large_flat)
    check(results, small_flat > large_flat + 0.12, 'blob: a small firm blob flattens to %.2f, a large soft one %.2f',
        small_flat, large_flat)

    -- The extremes travel their own graphs: chained trips between tops
    for _, genome in ipairs({'blob size=0.6 pressure=1.5', 'blob size=1.4 pressure=0.5'}) do
        local w, i, c = blob(genome)
        w:select(i)
        local ctrl, g = w.controllers[i], w.graphs[i]
        local gen = love.math.newRandomGenerator(1300)
        local ok, n = 0, 0
        for _ = 1, 16 do
            local goal, start = g:random_node(gen, {top = true}), ctrl:start_node()
            if goal and start and goal ~= start and Pathfinder.find(g, start, goal) then
                n = n + 1
                ctrl:go_to(goal)
                local arrived = drive(w, ctrl, 25, dt)
                local x, y = c:anchor()
                if arrived and math.abs(x - goal.x) < 6 and math.abs(y - goal.y) < 6 then
                    ok = ok + 1
                else
                    local step = ctrl.path and ctrl.path[ctrl.i]
                    results.fail[#results.fail + 1] = string.format('blob: %s trip %s->%s stopped at (%.0f,%.0f) on %s, edge %s',
                        genome, start.solid.id, goal.solid.id, x, y, c.mover.state,
                        step and step.edge and step.edge.kind or '-')
                    ctrl:clear()
                    c:reset(goal.x, goal.y)
                    c.mover.solid = goal.solid
                end
            end
        end
        report[#report + 1] = string.format('%s %d/%d trips', genome:match('size=%S+'), ok, n)
        check(results, n > 8 and ok == n, 'blob: %s arrived on %d of %d trips', genome, ok, n)
        results.trips = (results.trips or 0) + n
    end

    -- With no genome it's Character's blob, and a genome reaches the body
    local Blob = require('bodies.blob')
    check(results, Blob.new(100, 100).profile == Blob.profile, "blob: built without a genome, it is not Character's")
    local _, _, c = blob(nil)
    check(results, c.genome and c.profile.radius == Blob.profile_for(c.genome.size).radius,
        "blob: a resident's profile is not its size's")
    log.info('selftest', 'blob         %s', table.concat(report, '; '))
end)

-- Terrarium: spiders from their genes (#14). Legs set the gait's groups;
-- reach the legs' length, and with it the stride and the gaps its graph steps.
test('spider', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local Spider = require('bodies.spider')
    local function spider(genome)
        rng.seed(14)
        local w = World.new(level_data, {wander = false, selected = 0, genomes = {genome}})
        local i = w:first('spider')
        return w, i, w.creatures[i]
    end
    local report = {}

    -- The gait: two groups of half the legs, each standing on both sides
    for _, legs in ipairs({4, 6, 8}) do
        local _, _, c = spider(string.format('spider legs=%d reach=1', legs))
        local count = {0, 0}
        local sides = {{}, {}}
        for _, leg in ipairs(c.legs) do
            count[leg.def.group] = count[leg.def.group] + 1
            sides[leg.def.group][leg.def.near] = true
        end
        check(results, #c.legs == legs and count[1] == legs / 2 and count[2] == legs / 2,
            'spider: %d legs built as %d, in groups of %d and %d', legs, #c.legs, count[1], count[2])
        check(results, sides[1][true] and sides[1][false] and sides[2][true] and sides[2][false],
            'spider: %d legs, a gait group stands on one side only', legs)
    end

    -- Reach is the graph's: longer legs step across wider gaps between solids
    local joins = {}
    for _, reach in ipairs({0.7, 1.3}) do
        local w, i = spider(string.format('spider legs=8 reach=%.1f', reach))
        local n = 0
        for _, node in ipairs(w.graphs[i].nodes) do
            for _, e in ipairs(node.edges) do
                if e.kind == 'crawl' and w.graphs[i].nodes[e.to].solid ~= node.solid then n = n + 1 end
            end
        end
        joins[#joins + 1] = n
        -- (and a short reach still has all of the jar: solids that touch
        -- join however far apart their nearest nodes are)
        check(results, (w.graphs[i].dropped or 0) == 0, 'spider: at reach %.1f its graph seals off %d nodes', reach,
            w.graphs[i].dropped or 0)
    end
    report[#report + 1] = string.format('joins %d/%d at reach 0.7/1.3', joins[1], joins[2])
    check(results, joins[2] > joins[1], 'spider: %d joins between solids at reach 0.7, %d at 1.3', joins[1], joins[2])

    -- The ticket's walk: a lap of the cork arch, over its top, down to the
    -- soil past its lip and back along its underside, with every leg count
    -- at both ends of reach. A stumble is a planted foot the leg can't reach
    -- (the chain's tip off the foothold), a foot planted on nothing, or fewer
    -- than half the legs on the ground.
    local laps
    local function lap(w)
        local arch, soil = w.level.by_id.arch, w.level.by_id.soil
        return {
            {arch.x - 70, soil.y, soil, 0, -1}, {arch.x + arch.w / 2, arch.y, arch, 0, -1},
            {arch.x + arch.w + 60, soil.y, soil, 0, -1}, {arch.x + arch.w / 2, arch.y + arch.h, arch, 0, 1},
            {arch.x - 70, soil.y, soil, 0, -1},
        }
    end
    for _, legs in ipairs({4, 6, 8}) do
        for _, reach in ipairs({0.7, 1, 1.3}) do
            local genome = string.format('spider legs=%d reach=%.1f', legs, reach)
            local w, i, c = spider(genome)
            w:select(i)
            local ctrl, g = w.controllers[i], w.graphs[i]
            laps = lap(w)
            c:reset(laps[1][1], laps[1][2])
            c.solid = laps[1][3]
            c:plant_all()
            local frames, slipped, bare, unsupported, missed = 0, 0, 0, 0, {}
            for k = 2, #laps do
                local p = laps[k]
                local goal = g:node_near(p[1], p[2], p[3], p[4], p[5])
                local arrived = goal and ctrl:go_to(goal)
                for _ = 1, math.floor(20 / dt) do
                    w:step(dt)
                    if c.mode == 'attached' then
                        frames = frames + 1
                        local planted = 0
                        for _, leg in ipairs(c.legs) do
                            if not leg.stepping and not (c.tap and c.legs[c.tap.leg] == leg) then
                                planted = planted + 1
                                local tip = leg.chain.joints[#leg.chain.joints]
                                if (tip.x - leg.foot.x) ^ 2 + (tip.y - leg.foot.y) ^ 2 > 4 then slipped = slipped + 1 end
                                if not leg.grounded then bare = bare + 1 end
                            end
                        end
                        if planted < legs / 2 then unsupported = unsupported + 1 end
                    end
                    if not ctrl:has_path() then break end
                end
                local x, y = c:anchor()
                if not (arrived and not ctrl:has_path() and math.abs(x - goal.x) < 6 and math.abs(y - goal.y) < 6) then
                    missed[#missed + 1] = string.format('%d (%.0f,%.0f)', k, x, y)
                    ctrl:clear()
                end
            end
            -- (per leg-frame for feet, per frame for support)
            local slip, air, alone = slipped / (frames * legs), bare / (frames * legs), unsupported / frames
            report[#report + 1] = string.format('%d/%.1f slip %.3f air %.3f alone %.3f', legs, reach, slip, air, alone)
            check(results, #missed == 0, 'spider: %s did not make the lap of the arch at %s', genome, table.concat(missed, ', '))
            check(results, slip < 0.01 and air < 0.01 and alone < 0.01,
                'spider: %s stumbled on the arch: %.1f%% of feet slipped, %.1f%% stood on nothing, %.1f%% of the time on too few legs',
                genome, slip * 100, air * 100, alone * 100)
        end
    end

    -- With no genome it's Character's spider, and a genome reaches the body
    check(results, Spider.new(100, 100).profile == Spider.profile and #Spider.new(100, 100).legs == 8,
        "spider: built without a genome, it is not Character's")
    local _, _, c = spider(nil)
    check(results, c.genome and #c.legs == c.genome.legs and c.profile == Spider.profile_for(c.genome.reach),
        "spider: a resident's body is not its genome's")
    log.info('selftest', 'spider       %s', table.concat(report, '; '))
end)

-- Terrarium: graphs by size bucket, built a slice at a time (#16). A bucket's
-- graph must be honest for every body in the bucket, a sliced build must be
-- the graph a whole one makes, and a clutch of sixteen hatching at once must
-- never cost a frame.
test('hatch', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local NavGraph = require('nav.navgraph')
    local Level = require('jar.level')
    local ballistics = require('nav.ballistics')
    local statehash = require('core.statehash')
    local Genome = require('genome')
    local Worm, Blob, Spider = require('bodies.worm'), require('bodies.blob'), require('bodies.spider')
    local level = Level.new(level_data)
    local report = {}

    -- Every body in a bucket can travel its graph: each jump is one it can make
    -- and fly clear of the level, each fall one it drops clear through, each
    -- step one it can walk up. Bodies are tried every hundredth of the gene.
    local graphs = {}
    local function honest(nav, body, what)
        graphs[nav] = graphs[nav] or NavGraph.new(level, nav)
        local g = graphs[nav]
        local bad = {}
        for _, n in ipairs(g.nodes) do
            for _, e in ipairs(n.edges) do
                local m = g.nodes[e.to]
                if e.kind == 'jump' and not ballistics.solve_jump(n.x, n.y, m.x, m.y, body, level) then
                    bad[#bad + 1] = string.format('jump %d->%d', n.id, m.id)
                elseif e.kind == 'fall' and not ballistics.arc_clear(level, e.ex, n.y, e.vx, 0, e.t, body.radius) then
                    bad[#bad + 1] = string.format('fall %d->%d', n.id, m.id)
                elseif e.kind == 'walk' and n.solid ~= m.solid and math.abs(m.y - n.y) > body.step then
                    bad[#bad + 1] = string.format('step %d->%d', n.id, m.id)
                end
            end
        end
        check(results, body.radius <= nav.radius and body.step >= nav.step and body.jump_vy >= nav.jump_vy
            and (body.span or 0) >= (nav.span or 0), 'hatch: %s is more able than its graph assumes', what)
        check(results, #bad == 0, 'hatch: %s cannot travel its bucket graph (%s)', what, table.concat(bad, ', '))
        return g
    end
    local blobs, spiders = {}, {}
    for k = 0, Blob.BUCKETS - 1 do
        local nav = Blob.nav_profile({size = 0.6 + (k + 0.5) * 0.8 / Blob.BUCKETS})
        check(results, nav.bucket == k, 'hatch: blob bucket %d is filed as %s', k, tostring(nav.bucket))
        for size = nav.sizes[1], nav.sizes[2] + 1e-9, 0.01 do
            size = math.floor(size * 1000 + 0.5) / 1000
            honest(nav, Blob.profile_for(size), 'blob size ' .. size)
        end
        blobs[#blobs + 1] = nav
    end
    for k = 0, Spider.BUCKETS - 1 do
        local nav = Spider.nav_profile({reach = 0.7 + (k + 0.5) * 0.6 / Spider.BUCKETS})
        check(results, nav.bucket == k, 'hatch: spider bucket %d is filed as %s', k, tostring(nav.bucket))
        for reach = nav.reaches[1], nav.reaches[2] + 1e-9, 0.0075 do
            reach = math.floor(reach * 1000 + 0.5) / 1000
            honest(nav, Spider.profile_for(reach), 'spider reach ' .. reach)
        end
        spiders[#spiders + 1] = nav
    end
    -- Neighbours meet: the top of one bucket is the bottom of the next
    check(results, Blob.nav_profile({size = 0.6}).bucket == 0 and Blob.nav_profile({size = 1.4}).bucket == 7
        and Blob.nav_profile({size = 0.7}).bucket == 1 and Blob.nav_profile({size = 0.699}).bucket == 0,
        'hatch: blob sizes are filed in the wrong buckets')
    check(results, Blob.nav_profile({size = 0.83}) == Blob.nav_profile({size = 0.87}),
        'hatch: two blobs of one bucket have different nav profiles')

    -- A sliced build is the whole build, whatever the slice
    local hash = function(g) return statehash.of({time = 0, level = level, creatures = {}, graphs = {g}}).total end
    for _, nav in ipairs({Worm.nav_profile(), blobs[1], spiders[8]}) do
        local whole = hash(NavGraph.new(level, nav))
        for _, slice in ipairs({1000, World.BUILD_SLICE}) do
            local b, g = NavGraph.builder(level, nav, slice), nil
            repeat g = b:step() until g
            check(results, hash(g) == whole and b.slices > 1, 'hatch: %s built in slices of %d is not the whole graph',
                nav.name, slice)
        end
    end

    -- The worst clutch: sixteen eggs laid in one step where each plan's
    -- residents hatched, a blob in every size bucket and a spider in every
    -- reach bucket (their other genes random), so every graph the residents
    -- don't already have is built at once. Each egg waits for its bucket's.
    local function clutch()
        rng.seed(16)
        local w = World.new(level_data, {wander = true, selected = 0})
        local spots = {}
        for _, r in ipairs(level_data.residents) do spots[r.key] = spots[r.key] or r end
        for k = 1, 16 do
            local key = k <= 8 and 'blob' or 'spider'
            local g, b = Genome.random(key, rng.sim), (k - 1) % 8 + 0.5
            if key == 'blob' then g.size = 0.6 + b * 0.1 else g.reach = 0.7 + b * 0.075 end
            local r = spots[key]
            w:lay(g, r.x + (k % 5 - 2) * 6, r.solid, 'egg ' .. k)
        end
        local residents, builds = #w.creatures, #w.building
        local frames, worst, hatched_at = {}, 0, nil
        local steps = 0
        while steps < 2400 do
            local t0 = love.timer.getTime()
            w:step(dt); w:step(dt) -- a frame at 60 fps
            local took = love.timer.getTime() - t0
            steps = steps + 2
            if #w.eggs > 0 or hatched_at == steps - 2 then
                worst = math.max(worst, took)
            else
                frames[#frames + 1] = took
            end
            if #w.eggs == 0 and not hatched_at then hatched_at = steps end
        end
        table.sort(frames)
        return w, {residents = residents, builds = builds, hatched_at = hatched_at, worst = worst,
            typical = frames[math.floor(#frames / 2) + 1] or 0, settled = frames[#frames] or 0}
    end
    local w, s = clutch()
    check(results, s.hatched_at and #w.creatures == s.residents + 16, 'hatch: %d of 16 eggs hatched in 20 s',
        #w.creatures - s.residents)
    local residents_have = {}
    for i = 1, s.residents do residents_have[w.creatures[i].nav] = true end
    local need = 0
    for _, nav in ipairs(blobs) do need = need + (residents_have[nav] and 0 or 1) end
    for _, nav in ipairs(spiders) do need = need + (residents_have[nav] and 0 or 1) end
    check(results, s.builds == need, 'hatch: a clutch needing %d graphs queued %d builds', need, s.builds)
    local wrong = 0
    for i, c in ipairs(w.creatures) do
        if w.graphs[i] ~= w.navs[c.nav] or w.controllers[i].graph ~= w.graphs[i] then wrong = wrong + 1 end
    end
    check(results, wrong == 0, 'hatch: %d creatures walk a graph that is not their bucket\'s', wrong)
    -- The same clutch again from the same seed is the same jar
    local again, s2 = clutch()
    check(results, statehash.of(w).total == statehash.of(again).total, 'hatch: two clutches from one seed differ')
    -- Never a dropped frame: no frame of the clutch (two steps, building and
    -- hatching) takes a 60 fps frame. A real cost slows every run; a hiccup
    -- from the collector or the machine doesn't, so a slow one gets a third.
    local worst = math.min(s.worst, s2.worst)
    if worst >= 1 / 60 then worst = math.min(worst, select(2, clutch()).worst) end
    s.worst = worst
    check(results, worst < 1 / 60, 'hatch: a frame of the clutch took %.1f ms', worst * 1000)
    report[#report + 1] = string.format('%d builds, all 16 out after %.2f s; frames while hatching at most %.2f ms '
        .. '(after: typically %.2f, at most %.2f)', s.builds, s.hatched_at * dt, s.worst * 1000, s.typical * 1000,
        s.settled * 1000)
    log.info('selftest', 'hatch        %s', table.concat(report, '; '))
end)

-- Terrarium: a full jar (#18). Sixteen of the heaviest bodies (the longest
-- worms, the biggest blobs, eight-legged spiders) live on full soft bodies, so
-- the sim must leave most of a 60 fps frame for drawing them. `--crowd 16
-- --bench <sec>` measures the drawn frame. Eggs hatch between a frame's
-- snapshot and its draw, so this draws between steps the way main.lua does.
local CROWD, CROWD_BUDGET = 16, 1 / 240 -- s of sim per 60 fps frame (two steps)
test('crowd', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local Genome = require('genome')
    local function crowd()
        rng.seed(18)
        local w = World.new(level_data, {wander = true, selected = 0})
        for k = #w.creatures + 1, CROWD do
            local r = level_data.residents[(k - 1) % #level_data.residents + 1]
            local g = Genome.random(r.key, rng.sim)
            g.segments, g.size, g.legs = g.segments and 24, g.size and 1.4, g.legs and 8
            w:lay(g, r.x + (k % 5 - 2) * 8, r.solid, 'crowd ' .. k)
        end
        local frames, steps, ok, err = {}, 0, true, nil
        while steps < 2400 do
            local t0 = love.timer.getTime()
            for _ = 1, 2 do w:snapshot(); w:step(dt) end
            local took = love.timer.getTime() - t0
            steps = steps + 2
            ok, err = pcall(function() w:interpolate(0.5); w:restore() end)
            if not ok then break end
            if #w.eggs == 0 and steps > 600 then frames[#frames + 1] = took end
        end
        table.sort(frames)
        return w, ok, err, frames[math.ceil(#frames * 0.95)] or math.huge, frames[math.ceil(#frames * 0.5)] or 0
    end
    local w, ok, err, p95, median = crowd()
    check(results, ok, 'crowd: drawing between steps failed: %s', tostring(err))
    check(results, #w.creatures == CROWD, 'crowd: %d of %d creatures hatched', #w.creatures, CROWD)
    -- A slow run from the machine gets a second try; a real cost slows both
    if p95 >= CROWD_BUDGET then p95 = math.min(p95, select(4, crowd())) end
    check(results, p95 < CROWD_BUDGET, 'crowd: %d creatures take %.2f ms of sim a frame (budget %.2f)',
        CROWD, p95 * 1000, CROWD_BUDGET * 1000)
    log.info('selftest', 'crowd        %d heaviest bodies: sim %.2f ms a frame (p95 %.2f, budget %.2f)', #w.creatures,
        median * 1000, p95 * 1000, CROWD_BUDGET * 1000)
end)

-- Terrarium: the ranges (#17). Two hundred random genomes per plan, each in a
-- jar of its own, hatched where its plan's first resident lives. Each tours a
-- mossy top, the shelf and home again, and is watched every tenth of a second
-- for the ways a body goes wrong: it stalls, leaves the jar, sinks into the
-- scenery or comes apart (a worm torn or knotted, a blob crushed or turned
-- inside out, a spider standing on feet its legs don't reach). A genome that
-- fails is reported with its body genes and which quarter of each range they
-- fell in; the fix is to mend the body, or shrink that range in genome.lua.
local RANGES = 200
local LIMITS = {
    sunk = 4,       -- px any point may be inside the scenery (a foot rests on its surface)
    torn = 2,       -- a worm segment's length over its rest length
    knot = 2,       -- s a worm may stay knotted (three sharp bends): a dropped tail shakes out
    crushed = 0.5,  -- of a blob's rest area lost
    slip = 0.02,    -- of a spider's planted feet its legs don't reach
}
test('ranges', function(j, results)
    local World, level_data, dt = j.World, j.level_data, j.fixed_dt
    local Genome = require('genome')
    local level = require('jar.level').new(level_data)
    local shelf = level.by_id.shelf
    local tops = {} -- the mossy tops a tour visits, one per genome in turn
    for _, s in ipairs(level.solids) do
        if s.moss and s ~= shelf and s.id ~= 'soil' then tops[#tops + 1] = s end
    end
    local home = {}
    for _, r in ipairs(level_data.residents) do home[r.key] = home[r.key] or r end
    local every = math.floor(0.1 / dt + 0.5)
    local W, H = level_data.width, level_data.height

    -- How far a point is inside the scenery (0 outside it)
    local function depth(x, y)
        local s = level:solid_at(x, y)
        if not s then return 0 end
        return math.min(x - s.x, s.x + s.w - x, y - s.y, s.y + s.h - y)
    end
    local function crosses(a, b, c, d)
        local function side(p, q, r) return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) end
        return side(a, b, c) * side(a, b, d) < 0 and side(c, d, a) * side(c, d, b) < 0
    end
    -- A ring that crosses itself is a blob turned inside out
    local function inside_out(pts)
        local n = #pts
        for a = 1, n do
            for b = a + 2, n do
                if not (a == 1 and b == n) and crosses(pts[a], pts[a % n + 1], pts[b], pts[b % n + 1]) then return true end
            end
        end
        return false
    end
    -- A worm's longest segment over its rest length, and how many joints bend
    -- back on themselves (a hairpin turn has one or two, a knot three or more)
    local function worm_shape(pts)
        local most, sharp = 0, 0
        for k = 2, #pts do
            local a, b, q = pts[k - 1], pts[k], pts[k + 1]
            local ux, uy = b.x - a.x, b.y - a.y
            most = math.max(most, math.sqrt(ux * ux + uy * uy))
            if q then
                local vx, vy = q.x - b.x, q.y - b.y
                local d = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
                if d > 0 and (ux * vx + uy * vy) / d < -0.17 then sharp = sharp + 1 end
            end
        end
        return most / 8.5, sharp
    end
    -- A spider's planted feet that its legs don't reach or that stand on nothing
    local function slipped(c)
        if c.mode ~= 'attached' then return 0, 0 end
        local bad, planted = 0, 0
        for _, leg in ipairs(c.legs) do
            if not leg.stepping and not (c.tap and c.legs[c.tap.leg] == leg) then
                planted = planted + 1
                local tip = leg.chain.joints[#leg.chain.joints]
                if (tip.x - leg.foot.x) ^ 2 + (tip.y - leg.foot.y) ^ 2 > 4 or not leg.grounded then bad = bad + 1 end
            end
        end
        return bad, planted
    end

    -- One genome's tour: its worst measures, and what went wrong
    local function tour(genome, top)
        local r = home[genome.plan]
        local solo = setmetatable({residents = {{key = r.key, name = r.name, solid = r.solid, x = r.x, genome = genome}}},
            {__index = level_data})
        rng.seed(17)
        local w = World.new(solo, {wander = false, selected = 1})
        local c, ctrl, g = w.creatures[1], w.controllers[1], w.graphs[1]
        local stops = {{top.x + top.w / 2, top}, {shelf.x + shelf.w / 2, shelf}, {r.x, w.level.by_id[r.solid]}}
        local m = {sunk = 0, torn = 0, knot = 0, crushed = 0, slips = 0, planted = 0, faults = {}}
        local knotted = 0
        for _, stop in ipairs(stops) do
            local goal = g:node_near(stop[1], stop[2].y, stop[2], 0, -1)
            local going = goal and ctrl:go_to(goal)
            local steps = 0
            while going and ctrl:has_path() and steps < 60 / dt do
                w:step(dt)
                steps = steps + 1
                if steps % every == 0 then
                    for _, p in ipairs(c:interp_points()) do
                        if not (p.x >= 0 and p.x <= W and p.y >= 0 and p.y <= H) then -- (NaN too)
                            m.out = m.out or string.format('left the jar at (%.0f,%.0f)', p.x, p.y)
                        else
                            m.sunk = math.max(m.sunk, depth(p.x, p.y))
                        end
                    end
                    if c.key == 'worm' then
                        local stretch, sharp = worm_shape(c.points)
                        knotted = sharp >= 3 and knotted + every * dt or 0
                        m.torn, m.knot = math.max(m.torn, stretch), math.max(m.knot, knotted)
                    elseif c.key == 'blob' then
                        m.crushed = math.max(m.crushed, 1 - c:area() / c.area0)
                        m.inverted = m.inverted or inside_out(c.points)
                    else
                        local bad, planted = slipped(c)
                        m.slips, m.planted = m.slips + bad, m.planted + planted
                    end
                end
            end
            local x, y = c:anchor()
            if not (going and not ctrl:has_path() and math.abs(x - goal.x) < 8 and math.abs(y - goal.y) < 8) then
                m.faults[#m.faults + 1] = string.format('never reached the %s (stopped at %.0f,%.0f)', stop[2].id, x, y)
                -- (carry on from there, so one stall doesn't hide the rest)
                ctrl:clear()
                c:reset(goal and goal.x or stop[1], goal and goal.y or stop[2].y)
                c.mover.solid = stop[2]
                if c.profile.climbs then c.solid = stop[2]; c:plant_all() end
            end
        end
        m.slip = m.slips / math.max(1, m.planted)
        local f = m.faults
        if m.out then f[#f + 1] = m.out end
        if m.sunk > LIMITS.sunk then f[#f + 1] = string.format('sank %.1fpx into the scenery', m.sunk) end
        if m.torn > LIMITS.torn then f[#f + 1] = string.format('tore a segment to %.1fx its length', m.torn) end
        if m.knot >= LIMITS.knot then f[#f + 1] = string.format('stayed knotted %.1fs', m.knot) end
        if m.crushed > LIMITS.crushed then
            f[#f + 1] = string.format('was crushed to %.0f%% of its area', 100 * (1 - m.crushed))
        end
        if m.inverted then f[#f + 1] = 'turned inside out' end
        if m.slip > LIMITS.slip then
            f[#f + 1] = string.format("stood on feet it can't reach %.1f%% of the time", 100 * m.slip)
        end
        return m
    end

    local t0 = love.timer.getTime()
    for p, key in ipairs(Genome.order) do
        local gen = love.math.newRandomGenerator(1700 + p)
        local own = Genome[key].own
        local failed, worst, by_quarter = {}, {}, {}
        for _, gene in ipairs(own) do by_quarter[gene.name] = {0, 0, 0, 0} end
        for n = 1, RANGES do
            local genome = Genome.random(key, gen)
            local m = tour(genome, tops[(n - 1) % #tops + 1])
            for _, k in ipairs({'sunk', 'torn', 'knot', 'crushed', 'slip'}) do worst[k] = math.max(worst[k] or 0, m[k]) end
            if #m.faults > 0 then
                local body = {key}
                for _, gene in ipairs(own) do
                    local v = genome[gene.name]
                    local r = gene.real or gene.int or {gene.pick[1], gene.pick[#gene.pick]}
                    local q = math.min(4, math.floor((v - r[1]) / (r[2] - r[1]) * 4) + 1)
                    by_quarter[gene.name][q] = by_quarter[gene.name][q] + 1
                    body[#body + 1] = gene.name .. '=' .. v
                end
                failed[#failed + 1] = table.concat(body, ' ') .. ': ' .. table.concat(m.faults, '; ')
            end
        end
        check(results, #failed == 0, 'ranges: %d of %d %s genomes failed', #failed, RANGES, key)
        for k = 1, math.min(#failed, 12) do results.fail[#results.fail + 1] = 'ranges:   ' .. failed[k] end
        for _, gene in ipairs(#failed > 0 and own or {}) do
            local q = by_quarter[gene.name]
            log.info('selftest', 'ranges       %s %s failures by quarter of its range, low to high: %d %d %d %d', key,
                gene.name, q[1], q[2], q[3], q[4])
        end
        local measures = {
            worm = string.format('segments at most %.2fx, knots at most %.1fs', worst.torn, worst.knot),
            blob = string.format('at most %.0f%% of its area squeezed out', 100 * worst.crushed),
            spider = string.format('feet slipped at most %.1f%% of the time', 100 * worst.slip),
        }
        log.info('selftest', 'ranges       %-6s %d/%d toured the moss and the shelf; sank at most %.1fpx, %s', key,
            RANGES - #failed, RANGES, worst.sunk, measures[key])
        results.trips = (results.trips or 0) + 3 * RANGES
    end
    log.info('selftest', 'ranges       %d genomes per plan in %.0fs', RANGES, love.timer.getTime() - t0)
end)

-- 4. Audio: every event path runs without error (not a listening test)
test('audio', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
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
end)

function dev.tests()
    local names = {}
    for _, t in ipairs(TESTS) do names[#names + 1] = t.name end
    return names
end

-- Run the tests named in `only` (a comma list; nil or 'all' runs every one).
-- Returns true when every check passed, or nil and a message for a name it
-- doesn't know.
function dev.selftest(World, level_data, fixed_dt, open_jar, step, only, seed)
    local j = {World = World, level_data = level_data, fixed_dt = fixed_dt, open_jar = open_jar, step = step, seed = seed}
    local want
    if only and only ~= 'all' then
        want = {}
        for name in only:gmatch('[^,]+') do want[name] = true end
        for _, t in ipairs(TESTS) do want[t.name] = want[t.name] and t end
        for name, t in pairs(want) do
            if t == true then return nil, string.format('no test %q (there are: %s)', name, table.concat(dev.tests(), ', ')) end
        end
    end
    local results = {total = 0, pass = 0, fail = {}}
    local t0 = love.timer.getTime()
    for _, t in ipairs(TESTS) do
        if not want or want[t.name] then t.fn(j, results) end
    end
    log.info('selftest', '%d/%d checks passed (%d trips) in %.1fs', results.pass, results.total, results.trips or 0,
        love.timer.getTime() - t0)
    for _, f in ipairs(results.fail) do log.info('selftest', 'FAIL %s', f) end
    return #results.fail == 0
end

-- Terrarium: a jar is its seed plus its history. Open the jar twice from the
-- same seed, step each for <seconds> the way the game does, and compare state
-- hashes. --replay prints the hash so separate processes (and CI runs) can compare
-- them too: a mismatch there means something read the wall clock, a table
-- address, or pairs() order.
function dev.replay(open_jar, seed, seconds, fixed_dt, step)
    local statehash = require('core.statehash')
    local Plants = require('jar.plants')
    local steps = math.floor(seconds / fixed_dt + 0.5)
    local function run()
        local t0 = love.timer.getTime()
        local w = open_jar(seed)
        for _ = 1, steps do step(w) end
        local h = statehash.of(w, Plants.all())
        log.info('dev', 'replay  seed %d  %d steps (%.0fs of jar)  hash %s  in %.1fs', seed, steps, seconds, h.total,
            love.timer.getTime() - t0)
        return h
    end
    local a, b = run(), run()
    local where = statehash.diverged(a, b)
    if where then
        log.info('dev', 'replay  FAIL the two runs diverged, first in %s', where)
        for i, p in ipairs(a.parts) do
            log.info('dev', 'replay    %-12s %s  %s', p[1], p[2], b.parts[i] and b.parts[i][2] or '-')
        end
    else
        log.info('dev', 'replay  identical')
    end
    return where == nil, a.total
end

-- Print every node on one solid with its edges, for a creature's graph
function dev.navdump(World, level_data, who, solid_id, genomes)
    local world = World.new(level_data, {wander = false, genomes = genomes})
    local g = world.graph_of[who]
    if not g then return end
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

return dev
