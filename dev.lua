-- From chrischaps/Character @ 925c35b (dev.lua)
-- Dev modes: verification without a human at the mouse.
--
--   lovec . --selftest                    nav integrity, arrival, determinism, replay
--   lovec . --test <name>[,<name>]        Terrarium: just these self-tests (graphs, trips,
--                                         framerate, lantern, day, replay, genome, worm, audio, or all;
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
-- by lamplight, rests through the night and lies still once it gets there,
-- and is up and about again by noon. Nobody leaves the jar, comes apart into
-- NaNs or ends up sunk in the scenery.
local DAY = 900
test('day', function(j, results)
    local World, level_data, fixed_dt = j.World, j.level_data, j.fixed_dt
    rng.seed(j.seed or 20261018)
    local w = World.new(level_data, {wander = true, selected = 0, hour = 13, day = DAY})
    local level = w.level
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
        check(results, m.nights == 1, '%s rested %d times in one night', who, m.nights)
        check(results, (still_for[i] or 0) > DAY * 0.2, '%s rested only %.0fs of the night', who, still_for[i] or 0)
        check(results, (moved_at_rest[i] or 0) < 4, '%s moved %.1fpx while resting', who, moved_at_rest[i] or 0)
        check(results, m:awake(w:hour()) and m.doing ~= 'rest', '%s is still asleep at noon', who)
        log.info('selftest', 'day   %-6s %-6s wandered %2d, grazed %d, rested %3.0fs', c.name, c.key, m.wanders, m.grazes,
            still_for[i] or 0)
    end
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
