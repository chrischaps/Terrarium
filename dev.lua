-- From chrischaps/Character @ 925c35b (dev.lua)
-- Dev modes: verification without a human at the mouse.
--
--   lovec . --selftest                    nav integrity, arrival, determinism, replay
--   lovec . --test <name>[,<name>]        Terrarium: just these self-tests (graphs, trips,
--                                         framerate, lantern, day, replay, genome, worm, blob, spider,
--                                         hatch, ranges, audio, or all;
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
