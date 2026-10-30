-- From chrischaps/Character @ 925c35b (world/world.lua)
-- World: everything that lives in the cave, stepped at a fixed rate.
--
-- Terrarium: six creatures share the jar, two of each of its cast's three
-- kinds (#74), drawn from its seed, in the room's homes for them. Each has a
-- mind (mind.lua) whose needs and temperament choose among grazing, wandering, following, courting and resting by the jar's
-- hour, and a courting body is told its partner and their beat. In dev a
-- selected one follows clicks instead. Each body gets
-- the nav graph of its nav profile (its size bucket's); bodies with the same
-- one share it. Eggs laid in the jar hatch once their graph is built, a slice
-- per step. A pair that has courted lays a clutch in the moss nearby (#23):
-- each egg a child of the two, hatching about a day later as a small, pale
-- body that grows into its genome in three moults, one a sleep. Each lives
-- three to five jar days (#24): an elder slows and its colours deepen, and at
-- the end it dies in its sleep, fades into the moss where it lay, and leaves
-- that patch to grow back greener. A kind down to two is quietly spared
-- (#26): it stops ageing and courts sooner until it has eggs in the moss. A pinch of food dropped in (#25) falls
-- and settles here, and whoever is near comes over to it. The moss grid (jar/moss.lua) grows under
-- the lamp and is grazed and trodden here. Visual systems (flora, ambience,
-- particles) step here too so that what you see is always in sync with the
-- physics.
--
-- Terrarium: opened `coarse` (#27, #31), the creatures are tokens: anchors
-- with no soft bodies (bodies/token.lua), each glided along its own graph
-- (nav/glide.lua). The minds, moss, eggs, ageing and the floor are the same,
-- so the jar can be stepped COARSE seconds at a time, and a month of it run
-- in a minute and a half.

local sq = require('core.fmath').sq -- Terrarium: x ^ 2 isn't one number in LuaJIT (#94)
local Level = require('jar.level')
local NavGraph = require('nav.navgraph')
local Controller = require('nav.controller')
local Glide = require('nav.glide')
local Token = require('bodies.token')
local Mind = require('mind')
local Moss = require('jar.moss')
local Food = require('jar.food')
local DayCycle = require('jar.daycycle')
local Genome = require('genome')
local Skin = require('bodies.skin')
local C = require('jar.config')
local rng = require('core.rng')
local log = require('core.log')
local bit = require('bit')

local World = {}
World.__index = World

-- (`grazes`: it feeds on the soil's moss, so a cast can't leave that unkept, #74)
World.CREATURES = {
    {key = 'worm',   class = require('bodies.worm'),   grazes = true},
    {key = 'blob',   class = require('bodies.blob'),   grazes = true},
    {key = 'spider', class = require('bodies.spider'), grazes = true},
    {key = 'springtail', class = require('bodies.springtail'), grazes = true}, -- (#76)
    {key = 'snail',  class = require('bodies.snail'),  grazes = true}, -- (#77)
}
local CLASS, GRAZES = {}, {}
for _, def in ipairs(World.CREATURES) do CLASS[def.key], GRAZES[def.key] = def.class, def.grazes end

-- Terrarium: the body module of kind `key` (#77: a mind asks it where its kind
-- sleeps, and Remains how to draw what one left)
function World.class_of(key) return CLASS[key] end

-- Terrarium: a jar's cast (#74). The room has homes for a pair of every kind,
-- and each jar is home to CAST of them, drawn from its seed. CAST is the
-- six-resident jar M3 was tuned on, so CAPACITY, FLOOR and RESERVE still add
-- up, and CLASSIC is that jar's cast. The draw is a hash of the seed and each
-- kind's name, not a stream, so casting moves no stream: a jar whose cast is
-- the classic one opens exactly as it did before there were casts.
World.CAST = 3
World.CLASSIC = {'worm', 'blob', 'spider'}

-- a * b, wrapped to 32 bits without losing any (b below 2^32)
local function mul32(a, b)
    return bit.tobit(bit.band(a, 0xffff) * b + bit.lshift(bit.rshift(a, 16) * b, 16))
end

-- A 32-bit hash of a string: FNV-1a, as core/statehash.lua folds it, then
-- MurmurHash3's finish, so the last few characters reach every bit
local function hash(s)
    local h = -2128831035
    for i = 1, #s do h = mul32(bit.bxor(h, s:byte(i)), 16777619) end
    h = mul32(bit.bxor(h, bit.rshift(h, 16)), 0x85ebca6b)
    h = mul32(bit.bxor(h, bit.rshift(h, 13)), 0xc2b2ae35)
    return bit.bxor(h, bit.rshift(h, 16))
end
World.hash = hash -- (the book names the jar's own by it, #32)

-- The kinds a jar in `level_data` can hold: each with a body and a home, in Genome.order
function World.kinds(level_data)
    local homed, out = {}, {}
    for _, r in ipairs(level_data.homes) do homed[r.key] = true end
    for _, key in ipairs(Genome.order) do
        if CLASS[key] and homed[key] then out[#out + 1] = key end
    end
    return out
end

-- `seed`'s cast of CAST kinds from `pool`, in pool order. Each kind draws a
-- lot (a hash of the seed and its name) and the lowest lots are cast; if none
-- of them is one that `grazes(key)`, the lowest grazer takes the last place.
function World.draw_cast(seed, pool, grazes)
    local lot = {}
    for _, key in ipairs(pool) do lot[key] = hash(tostring(seed) .. ':' .. key) end
    local order = {}
    for i, key in ipairs(pool) do order[i] = key end
    table.sort(order, function(a, b)
        if lot[a] ~= lot[b] then return lot[a] < lot[b] end
        return a < b
    end)
    local cast, fed = {}, false
    for k = 1, math.min(World.CAST, #order) do
        cast[order[k]] = true
        fed = fed or grazes(order[k])
    end
    if not fed then
        for k = World.CAST + 1, #order do
            if grazes(order[k]) then
                cast[order[World.CAST]], cast[order[k]] = nil, true
                break
            end
        end
    end
    local out = {}
    for _, key in ipairs(pool) do
        if cast[key] then out[#out + 1] = key end
    end
    return out
end

-- The cast a jar from `seed` in `level_data` is home to
function World.cast_of(level_data, seed)
    return World.draw_cast(seed, World.kinds(level_data), function(key) return GRAZES[key] end)
end

-- `cast` (a list of kinds, in any order) in Genome.order, once each, or nil
-- and why it can't be a cast in `level_data`
function World.check_cast(level_data, cast)
    local can, want, out = {}, {}, {}
    for _, key in ipairs(World.kinds(level_data)) do can[key] = true end
    for _, key in ipairs(cast) do
        if not can[key] then
            return nil, string.format('no %s can live in this jar (there are: %s)', tostring(key),
                table.concat(World.kinds(level_data), ', '))
        end
        want[key] = true
    end
    for _, key in ipairs(Genome.order) do
        if want[key] then out[#out + 1] = key end
    end
    if #out == 0 then return nil, 'a cast needs at least one kind' end
    return out
end

-- The homes in `level_data` that `cast`'s pairs move into, in the room's order
function World.residents(level_data, cast)
    local in_cast, out = {}, {}
    for _, key in ipairs(cast) do in_cast[key] = true end
    for _, r in ipairs(level_data.homes) do
        if in_cast[r.key] then out[#out + 1] = r end
    end
    return out
end

-- Tiny event bus: emit during a step, flush to listeners after it
local Bus = {}
Bus.__index = Bus
function Bus.new() return setmetatable({queue = {}, listeners = {}}, Bus) end
function Bus:emit(kind, data) data.kind = kind; self.queue[#self.queue + 1] = data end
function Bus:on(fn) self.listeners[#self.listeners + 1] = fn end
function Bus:flush()
    local q = self.queue
    self.queue = {}
    for _, ev in ipairs(q) do
        for _, fn in ipairs(self.listeners) do fn(ev) end
    end
end

function World.new(level_data, opts)
    opts = opts or {}
    local self = setmetatable({}, World)
    self.level = Level.new(level_data)
    self.moss = Moss.new(self.level) -- Terrarium: over every mossy top (#20)
    self.food = Food.new(self.level) -- Terrarium: crumbs you've dropped in (#25)
    self.events = Bus.new()
    self.time = 0
    -- Terrarium: the hour the jar opened at and how long its day is (inputs, like the seed)
    self.start_hour = opts.hour or DayCycle.presets.midday
    self.day_seconds = opts.day
    self.selected = opts.selected or 1 -- 0: nobody is guided and everyone wanders
    self.wander = opts.wander ~= false
    self.coarse = opts.coarse -- Terrarium: tokens, not bodies (#27)
    -- Terrarium: who lives here (#74): opts.cast, or the jar seed's (opts.seed,
    -- or the seed the streams were last seeded from)
    self.cast = assert(World.check_cast(level_data, opts.cast or World.cast_of(level_data, opts.seed or rng.jar)))
    local residents = World.residents(level_data, self.cast)
    for _, r in ipairs(residents) do
        -- (a climber can start up a wall: `y` up its face, #77)
        assert((r.x or (r.y and CLASS[r.key].profile.climbs)) and not r.under,
            'world: no ' .. r.key .. ' can start there yet')
    end
    self.creatures, self.graphs, self.controllers = {}, {}, {}
    self.minds = {}
    self.graph_of = {} -- the first resident's graph, per kind

    local mouth = level_data.lamp or level_data.mouth -- Terrarium: the lamp above the jar
    self.light_dir = function(x, y)
        local dx, dy = mouth.x - x, mouth.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        return dx / d, dy / d
    end

    -- Terrarium: each resident is built from a genome. A jar draws its own from
    -- rng.sim; opts.genomes (strings or tables) stand in for the first residents
    -- of their plans, in order, so a dev run can look at a chosen body.
    local given = {}
    for _, g in ipairs(opts.genomes or {}) do
        g = type(g) == 'string' and assert(Genome.parse(g)) or Genome.copy(g)
        given[g.plan] = given[g.plan] or {}
        table.insert(given[g.plan], g)
    end
    self.genomes = {}
    for i, r in ipairs(residents) do
        local mine = given[r.key] and table.remove(given[r.key], 1)
        self.genomes[i] = Genome.clamp(mine or (r.genome and Genome.copy(r.genome)) or Genome.random(r.key, rng.sim))
    end

    -- Terrarium: a graph is built from the body's nav profile (#16), so bodies
    -- that share one (every worm, blobs of a size bucket, spiders of a reach
    -- bucket) share a graph. The residents' are built whole as the jar opens;
    -- a hatchling's is built a slice per step while its egg waits.
    self.navs = {}     -- nav profile -> its graph, once built
    self.building = {} -- builds under way, oldest first
    self.eggs = {}     -- hatchlings waiting for their graph, in the order laid
    self.young = {}    -- creature index -> how far a hatchling has grown, until it's grown
    self.shells = {}   -- what's left of the eggs that hatched lately, until they fade
    self.lives = {}    -- creature index -> when it was born and how long it has (#24)
    self.remains = {}  -- where the dead went back to the moss lately, until their spores settle
    -- Terrarium: a pair that has courted lays a clutch (#23)
    self.events:on(function(ev)
        if ev.kind == 'courted' then self:clutch(ev.who, ev.with) end
    end)
    for i, r in ipairs(residents) do
        local nav = CLASS[r.key].nav_profile(self.genomes[i])
        if not self.navs[nav] then self:built(r.key, nav, NavGraph.new(self.level, nav)) end
        self:place(r.key, self.genomes[i], r.x, r.solid, r.name, nil, r.y)
    end
    self:census()
    return self
end

-- Work spent on hatchlings' graphs per step: about half a millisecond, so a clutch
-- of sixteen never costs a frame. A full graph is roughly 200,000 units.
World.BUILD_SLICE = 15000

function World:built(key, nav, graph)
    self.navs[nav] = graph
    local tag = nav.bucket_label and ' (' .. nav.bucket_label .. ')' or ''
    log.info('nav', '%s graph%s: %d nodes, %d edges', key, tag, #graph.nodes, graph.edge_count)
end

-- Where a climber `y` up the face of `solid` that looks into the jar is
-- (#77): that face's x, and its normal
local function on_face(level, solid)
    if solid.x + solid.w / 2 < level.width / 2 then return solid.x + solid.w, 1 end
    return solid.x, -1
end

-- A creature from `genome`, standing at `x` on solid `solid_id`, with the
-- graph of its nav profile (which must be built already). `young`, it's a
-- hatchling, with the body of its genome at nothing grown. Terrarium: with
-- `y`, a climber starts that far up the face of the solid instead (#77).
function World:place(key, genome, x, solid_id, name, young, y)
    local i = #self.creatures + 1
    local solid = self.level.by_id[solid_id]
    local body = young and Genome.young(genome, 0) or Genome.copy(genome)
    local nx
    if y then x, nx = on_face(self.level, solid) end
    local c
    if self.coarse then
        c = Token.new(key, CLASS[key], x, y or solid.y, body, young and 1 or nil)
    else
        c = CLASS[key].new(x, y or solid.y, self, body, young and 1 or nil)
    end
    c.key, c.name = key, name
    c.home = {x = x, solid = solid_id, y = y}
    -- (every body carries a Base.Mover, even a climber that only jumps with it, #73)
    assert(c.mover, 'world: a ' .. key .. ' has no mover')
    c.mover.solid = solid
    if c.profile.climbs then
        c.solid = solid
        if nx then
            if self.coarse then c:set(x, y, solid, nx, 0) else c.nx, c.ny, c.tnx, c.tny = nx, 0, nx, 0 end
        end
        c:plant_all()
    end
    local graph = assert(self.navs[c.nav], 'world: no graph built for this body')
    self.creatures[i] = c
    self.genomes[i] = Genome.copy(genome)
    self.graph_of[key] = self.graph_of[key] or graph
    self.graphs[i] = graph
    self.controllers[i] = (self.coarse and Glide or Controller).new(c, graph)
    self.minds[i] = Mind.new(genome)
    if young then
        self.young[i] = {stage = 0, born = self.time, nights = 0}
        self.minds[i].young = true
    end
    -- Terrarium: its lifespan (#24). A hatchling's starts now; one placed
    -- grown (a resident) has already lived some of its life.
    local day = self:day_length()
    local lived = young and 0 or day * rng.range(rng.sim, 0, World.LIVED)
    self.lives[i] = {born = self.time - lived, span = day * rng.range(rng.sim, World.LIFE[1], World.LIFE[2]), spared = 0}
    self.minds[i].scarce = self.scarce and self.scarce[key]
    return i
end

-- Terrarium: lay an egg at `x` on solid `solid_id`. It hatches on a later step,
-- once the graph for its body is ready, and a whole clutch laid together
-- shares the builds it needs. Returns the egg.
--
-- With `opts.due`, it waits until the jar's clock reaches it as well; with
-- `opts.young`, it hatches small (#23), and waits for the graph of every body
-- it will grow through, so its graphs are built while it incubates and a
-- moult never waits on one. `opts.parents` are the genomes it came from.
function World:lay(genome, x, solid_id, name, opts)
    opts = opts or {}
    genome = Genome.clamp(Genome.copy(genome))
    local key = genome.plan
    local navs = {}
    for k = opts.young and 0 or World.STAGES, World.STAGES do
        navs[#navs + 1] = CLASS[key].nav_profile(Genome.young(genome, k / World.STAGES))
    end
    local egg = {key = key, genome = genome, x = x, solid = solid_id, name = name, nav = navs[#navs], navs = navs,
        laid = self.time, due = opts.due or self.time, young = opts.young, parents = opts.parents}
    self.eggs[#self.eggs + 1] = egg
    for _, nav in ipairs(navs) do
        local queued = self.navs[nav] ~= nil
        for _, b in ipairs(self.building) do queued = queued or b.nav == nav end
        if not queued then
            local b = NavGraph.builder(self.level, nav, World.BUILD_SLICE)
            b.nav, b.key = nav, key
            self.building[#self.building + 1] = b
        end
    end
    return egg
end

-- Terrarium: clutches (#23). A pair lays one to three eggs, while the jar
-- holds fewer than CAPACITY (counting the eggs already in it), in a row in
-- the moss nearest where they courted. Each egg is a child of the two from
-- Genome.child, and hatches about a jar day later.
World.CAPACITY = 16
World.CLUTCH = {1, 3}
World.INCUBATE = {0.9, 1.1} -- jar days
World.EGG_GAP = 16          -- between the eggs of a clutch
World.STAGES = 3            -- moults from hatchling to grown
World.GROW = 1.5            -- jar days from hatching to grown, at the soonest
World.SHELL = 40            -- seconds an empty shell lies in the moss

-- Terrarium: ageing and death (#24)
World.LIFE = {3, 5}   -- jar days a creature lives
World.LIVED = 1       -- up to this many of them a resident has lived when the jar opens
World.ELDER = 0.7     -- of its life, after which it's an elder
World.SLOW = 0.45     -- how much of its pace an elder has lost by the end
World.GRACE = 0.5     -- jar days past its time it waits to fall asleep before dying awake
World.FADE = 90       -- seconds it takes to settle into the moss and fade
World.SPORES = 30     -- seconds the spores it gives up keep drifting after
World.KEPT = 1.5      -- jar days what a body keeps (a snail's shell, #77) lies in the moss after

-- Terrarium: the floor (#26). A kind down to FLOOR, counting its eggs but not
-- its dying, is scarce: its clock stops, so none of them dies, and its minds
-- court sooner (Mind:ready), and held HELD days, will take any leap to reach
-- each other (Mind:daring). The other kinds' clutches leave RESERVE places
-- in the jar for each scarce one's. It's never shown, and never told.
World.FLOOR = 2
World.RESERVE = 2
World.HELD = 1 -- jar days spared before it'll take any leap to reach its own kind (#27)

-- Terrarium: the coarse step, in seconds (#27)
World.COARSE = 1

-- Which kinds are scarce, into `self.scarce` and each mind's `scarce`. Only
-- the cast's kinds are counted (#74), and any other that has been laid here:
-- a kind the jar never held isn't scarce, and leaves no room for itself.
function World:census()
    local n = {}
    for _, key in ipairs(self.cast) do n[key] = 0 end
    for i, c in ipairs(self.creatures) do
        if not self.lives[i].dying then n[c.key] = (n[c.key] or 0) + 1 end
    end
    for _, egg in ipairs(self.eggs) do n[egg.key] = (n[egg.key] or 0) + 1 end
    self.scarce = {}
    for key, k in pairs(n) do self.scarce[key] = k <= World.FLOOR or nil end
    for i, c in ipairs(self.creatures) do self.minds[i].scarce = self.scarce[c.key] end
end

function World:day_length()
    return self.day_seconds or C.DAY_SECONDS
end

local function index_of(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

-- The mossy top nearest (x, y) that `graph` stands on
local function nest(graph, x, y)
    local best, best_d
    for _, n in ipairs(graph.nodes) do
        if n.kind == 'top' and n.solid.moss then
            local d = sq(n.x - x) + sq(n.y - y)
            if not best_d or d < best_d then best, best_d = n, d end
        end
    end
    return best
end

-- A clutch from creatures `a` and `b`, laid near `a`. Returns the eggs.
function World:clutch(a, b)
    local i, j = index_of(self.creatures, a), index_of(self.creatures, b)
    self:census()
    local room = World.CAPACITY - #self.creatures - #self.eggs
    for key in pairs(self.scarce) do
        if key ~= a.key then room = room - World.RESERVE end
    end
    if not (i and j) or room <= 0 then return {} end
    local x, y = a:anchor()
    local spot = nest(self.graphs[i], x, y)
    if not spot then return {} end
    local count = math.min(room, rng.sim:random(World.CLUTCH[1], World.CLUTCH[2]))
    local s, day = spot.solid, self:day_length()
    local lo, hi = s.x + 12, s.x + s.w - 12
    local first = math.max(lo, math.min(hi - (count - 1) * World.EGG_GAP, spot.x - (count - 1) * World.EGG_GAP / 2))
    local eggs = {}
    for k = 1, count do
        local child = Genome.child(self.genomes[i], self.genomes[j], rng.sim)
        local due = self.time + day * rng.range(rng.sim, World.INCUBATE[1], World.INCUBATE[2])
        eggs[k] = self:lay(child, first + (k - 1) * World.EGG_GAP, s.id, nil,
            {due = due, young = true, parents = {Genome.copy(self.genomes[i]), Genome.copy(self.genomes[j])}})
    end
    self.events:emit('laid', {who = a, with = b, eggs = eggs, x = spot.x, y = spot.y})
    return eggs
end

-- One slice of the oldest build, then hatch every egg that's due and whose
-- graphs are ready
function World:hatch()
    local b = self.building[1]
    if b then
        local graph = b:step()
        if graph then
            table.remove(self.building, 1)
            self:built(b.key, b.nav, graph)
        end
    end
    while self.shells[1] and self.time - self.shells[1].at > World.SHELL do table.remove(self.shells, 1) end
    if #self.eggs == 0 then return end
    local waiting = {}
    for _, egg in ipairs(self.eggs) do
        local ready = self.time >= egg.due
        for _, nav in ipairs(egg.navs) do ready = ready and self.navs[nav] ~= nil end
        if ready then
            egg.who = self:place(egg.key, egg.genome, egg.x, egg.solid, egg.name, egg.young)
            local y = self.level.by_id[egg.solid].y
            self.events:emit('hatched', {who = self.creatures[egg.who], egg = egg, x = egg.x, y = y})
            if egg.young then
                self.shells[#self.shells + 1] = {key = egg.key, genome = egg.genome, x = egg.x, y = y, at = self.time}
            end
        else
            waiting[#waiting + 1] = egg
        end
    end
    self.eggs = waiting
end

-- Terrarium: a hatchling grows in its sleep (#23). Once it has slept since
-- its last moult, and it's old enough for the next (a stage every GROW /
-- STAGES of a jar day), it grows a third of the way more toward its genome
-- where it lies, and takes the graph of its new body. The last moult leaves
-- it grown: full-sized, its own colours, and ready to court.
function World:moult(i)
    local y, c, m = self.young[i], self.creatures[i], self.minds[i]
    if m.doing ~= 'rest' or m.nights <= y.nights or self.controllers[i]:has_path() then return end
    if c.profile.climbs then
        if c.mode ~= 'attached' then return end
    elseif c.mover.state ~= 'ground' then
        return
    end
    local due = math.floor(World.STAGES * (self.time - y.born) / (World.GROW * self:day_length()))
    if y.stage >= math.min(due, World.STAGES) then return end
    y.stage, y.nights = y.stage + 1, m.nights
    local grown = y.stage / World.STAGES
    c:grow(Genome.young(self.genomes[i], grown), 1 - grown)
    local graph = assert(self.navs[c.nav], 'world: no graph built for a moult')
    if graph ~= self.graphs[i] then
        self.graphs[i] = graph
        self.controllers[i] = (self.coarse and Glide or Controller).new(c, graph)
    end
    if y.stage == World.STAGES then
        self.young[i], m.young = nil, nil
    end
    local x, ay = c:anchor()
    self.events:emit('moulted', {who = c, stage = y.stage, grown = grown, x = x, y = ay})
end

-- Terrarium: when creature `i`'s time comes (later by the time it was spared, #26)
function World:end_of(i)
    local life = self.lives[i]
    return life.born + life.spared + life.span
end

-- Terrarium: how far through its life creature `i` is (0 born, 1 its time),
-- and how old (0 until it's an elder, 1 at the end)
function World:age_of(i)
    local life = self.lives[i]
    local t = (self.time - life.born - life.spared) / life.span
    return t, math.max(0, math.min(1, (t - World.ELDER) / (1 - World.ELDER)))
end

-- Terrarium: a creature grows old (#24). An elder walks slower and its colours
-- deepen. When its time has come its last bed is in the moss, and it dies in
-- its sleep there (or, if it hasn't slept GRACE days on, wherever it settles),
-- and fades over FADE seconds before it's gone. While its kind is scarce
-- (#26) none of that time counts, and its time can't come.
function World:age(i, dt)
    local life, c, m, ctrl = self.lives[i], self.creatures[i], self.minds[i], self.controllers[i]
    if life.dying then
        if self.time - life.dying >= World.FADE then self:return_to_moss(i) end
        return
    end
    if self.scarce[c.key] then life.spared = life.spared + dt end
    m.held = life.spared > World.HELD * self:day_length() or nil
    local t, old = self:age_of(i)
    ctrl.pace = 1 - World.SLOW * old
    -- (its skin is redone in steps as it deepens, not every step)
    local shade = math.floor(old * 24) / 24
    if (c.skin.old or 0) ~= shade then c.skin = Skin.age(c.key, c.genome, c.skin, shade) end
    if t < 1 or self.scarce[c.key] then
        m.last = nil
        return
    end
    m.last = true
    local settled
    if c.profile.climbs then settled = c.mode == 'attached' else settled = c.mover.state == 'ground' end
    local asleep = m.doing == 'rest' and not ctrl:has_path()
    if not (settled and (asleep or self.time > self:end_of(i) + World.GRACE * self:day_length())) then return end
    life.dying = self.time
    local o = m.with and self.minds[m.with]
    if o and o.with == i then
        o.with, o.lead = nil, nil
        o:set('idle', 2)
        self.controllers[m.with]:clear()
    end
    m.with, m.lead, m.dying = nil, nil, true
    m:set('rest')
    ctrl:clear()
    if c.face then c.face.closing = true end
    self:census() -- (so the last two of a kind outlive it)
    local x, y = c:anchor()
    self.events:emit('dying', {who = c, x = x, y = y})
end

-- How far creature `i` has faded into the moss (0 alive, 1 gone)
function World:fading(i)
    local life = self.lives[i]
    return life and life.dying and math.min(1, (self.time - life.dying) / World.FADE) or 0
end

-- Terrarium: the end of a fade. The moss it lay on is pressed down and will
-- grow back rich (Moss:enrich), a few spores drift up for a while, and the
-- creature is gone from the jar.
function World:return_to_moss(i)
    local c = self.creatures[i]
    local x0, x1, y = math.huge, -math.huge, -math.huge
    for _, p in ipairs(c:interp_points()) do
        x0, x1, y = math.min(x0, p.x), math.max(x1, p.x), math.max(y, p.y)
    end
    local s = self.moss:enrich(x0, x1, y)
    local x = (x0 + x1) / 2
    y = s and s.y or y
    local r = {key = c.key, x = x, y = y, x0 = x0, x1 = x1, at = self.time, born = self.lives[i].born, faded = World.FADE}
    -- (and what its body keeps stays in the moss a while, #77)
    local kept = CLASS[c.key].keeps and not self.coarse and CLASS[c.key].keeps(c)
    if kept then r.kept, r.keep = kept, World.KEPT * self:day_length() end
    self.remains[#self.remains + 1] = r
    self:remove(i)
    self.events:emit('returned', {who = c, index = i, x = x, y = y})
end

-- Take creature `i` out of the jar, and renumber everything that knew the
-- others by index
function World:remove(i)
    local function shift(t)
        local out = {}
        for k, v in pairs(t) do
            if k < i then out[k] = v elseif k > i then out[k - 1] = v end
        end
        return out
    end
    for _, list in ipairs({self.creatures, self.graphs, self.controllers, self.minds, self.genomes, self.lives}) do
        table.remove(list, i)
    end
    if self.snap then self.snap = shift(self.snap) end
    if self.saved then self.saved = shift(self.saved) end
    self.young = shift(self.young)
    for k, m in ipairs(self.minds) do
        m.met, m.near = shift(m.met), shift(m.near)
        if m.with == i then
            -- whoever was following or courting it (that ends at bedtime, but
            -- a dev run can put it anywhere)
            m.with, m.lead = nil, nil
            if m.doing ~= 'rest' and m.doing ~= 'to_rest' then
                self.controllers[k]:clear()
                m:set('idle', 2)
            end
        elseif m.with and m.with > i then
            m.with = m.with - 1
        end
    end
    if self.selected == i then self.selected = 0 elseif self.selected > i then self.selected = self.selected - 1 end
end

-- Terrarium: drop a pinch of food from under the lid at x (#25), if the jar
-- has one left today. A pinch is an input, like the seed: it lands on the
-- step it's given, and the food keeps when and where. Returns its crumbs.
function World:pinch(x)
    local crumbs = self.food:pinch(x, self.time)
    if crumbs then self.events:emit('pinch', {x = x, crumbs = #crumbs}) end
    return crumbs
end

-- Terrarium: the jar's hour now
function World:hour()
    return DayCycle.hourAt(self.start_hour, self.time, self.day_seconds)
end

-- Terrarium: the index of creature `c` now (indices move up as the dead are
-- taken out, #24), or nil if it's gone
function World:index_of(c)
    return index_of(self.creatures, c)
end

-- The first resident of a kind, by index
function World:first(key)
    for i, c in ipairs(self.creatures) do
        if c.key == key then return i end
    end
end

function World:selected_creature()
    return self.creatures[self.selected]
end

function World:select(i)
    if self.creatures[i] then
        self.selected = i
    end
end

-- Send the selected creature toward a clicked point.
-- Returns the goal node (or nil) and whether a path exists.
function World:click(x, y)
    local i = self.selected
    local goal = self.graphs[i]:snap_goal(x, y)
    if not goal then return nil, false end
    local ok = self.controllers[i]:go_to(goal)
    return goal, ok
end

function World:reset()
    for i, c in ipairs(self.creatures) do
        local r = c.home
        local solid = self.level.by_id[r.solid]
        c:reset(r.x, r.y or solid.y)
        c.mover.solid = solid
        if c.profile.climbs then
            c.solid = solid
            if r.y then
                local _, nx = on_face(self.level, solid)
                c.nx, c.ny, c.tnx, c.tny = nx, 0, nx, 0
            end
            c:plant_all()
        end
        self.controllers[i]:clear()
        self.minds[i] = Mind.new(self.genomes[i])
        self.minds[i].young = self.young[i] and true or nil
        local life = self.lives[i] -- (an old one is no younger for it)
        self.minds[i].last = self.time >= self:end_of(i) and not self.scarce[c.key] or nil
        self.minds[i].dying = life.dying and true or nil
        self.minds[i].scarce = self.scarce[c.key]
    end
end

-- Collect everything that pushes flora and scatters fireflies
function World:influencers()
    local out = {}
    for _, c in ipairs(self.creatures) do c:influencers(out) end
    return out
end

-- Render interpolation: remember where every drawn point was before a step,
-- then draw between that and now. Physics never sees the blended positions.
function World:snapshot()
    self.snap = self.snap or {}
    for i, c in ipairs(self.creatures) do
        local s = self.snap[i] or {}
        for k, p in ipairs(c:interp_points()) do
            local q = s[k] or {}
            q[1], q[2] = p.x, p.y
            s[k] = q
        end
        self.snap[i] = s
    end
end

function World:interpolate(alpha)
    if not self.snap then return end
    self.saved = self.saved or {}
    for i, c in ipairs(self.creatures) do
        -- Terrarium: one hatched in the last step has no snapshot yet; it's drawn where it is
        local s, saved = self.snap[i] or {}, self.saved[i] or {}
        for k, p in ipairs(c:interp_points()) do
            local q = s[k]
            local v = saved[k] or {}
            v[1], v[2] = p.x, p.y
            saved[k] = v
            if q then
                p.x, p.y = q[1] + (p.x - q[1]) * alpha, q[2] + (p.y - q[2]) * alpha
            end
        end
        self.saved[i] = saved
    end
end

function World:restore()
    if not self.saved then return end
    for i, c in ipairs(self.creatures) do
        local saved = self.saved[i]
        for k, p in ipairs(c:interp_points()) do
            local v = saved and saved[k]
            if v then p.x, p.y = v[1], v[2] end
        end
    end
end

function World:step(dt)
    self.time = self.time + dt
    local hour = self:hour()
    self:hatch()
    self:census() -- Terrarium: which kinds are down to two (#26)
    self.food:update(dt, self.time, self:day_length()) -- Terrarium: crumbs fall and settle (#25)

    for i, c in ipairs(self.creatures) do
        local ctrl, mind = self.controllers[i], self.minds[i]

        -- Terrarium: everyone but a dev-selected creature lives by its mind,
        -- until it's dying
        if self.wander and i ~= self.selected and not mind.dying then
            mind:update(dt, hour, self, i)
        end

        ctrl:update(dt)
        if not self.coarse then -- (a token has no body to move)
            local look = ctrl.path and ctrl:current_node() or nil
            c:update(dt, self.level, {
                events = self.events,
                look_at = look and {x = look.x, y = look.y - 10} or mind:look(c, self),
                light_dir = self.light_dir,
                court = mind:courting(self, i), -- Terrarium: its partner and their beat (#22)
                rest = mind.doing == 'rest', -- Terrarium: asleep, for a body that sleeps its own way (#76)
            })
        end
        -- Terrarium: feet on the way somewhere wear the moss they cross
        if ctrl:has_path() then
            local x, y = c:anchor()
            self.moss:tread(x, y, dt)
        end
        if ctrl.arrived then
            ctrl.arrived = false
            local ax, ay = c:anchor()
            self.events:emit('arrived', {who = c, x = ax, y = ay})
        end
    end

    -- Terrarium: hatchlings grow in their sleep (#23)
    for i = 1, #self.creatures do
        if self.young[i] then self:moult(i) end
    end
    -- Terrarium: everyone ages, and the old die in their sleep (#24)
    for i = #self.creatures, 1, -1 do self:age(i, dt) end
    -- (the spores settle, and what a body kept is grown over, #77)
    for k = #self.remains, 1, -1 do
        local r = self.remains[k]
        if self.time - r.at > (r.keep or World.SPORES) then table.remove(self.remains, k) end
    end
    Mind.meet(self) -- Terrarium: who has met whom, for courting (#22)
    self.moss:update(dt, DayCycle.lampAt(hour))
    if self.flora then self.flora:update(dt, self:influencers(), self.time) end
    if self.ambience then self.ambience:update(dt, self) end
    if self.fx then self.fx:update(dt) end
    self.events:flush()
end

return World
