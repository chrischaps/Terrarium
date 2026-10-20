-- From chrischaps/Character @ 925c35b (world/world.lua)
-- World: everything that lives in the cave, stepped at a fixed rate.
--
-- Terrarium: six creatures share the jar, two of each kind (the room's
-- residents). Each has a mind (mind.lua) whose needs and temperament choose
-- among grazing, wandering, following and resting by the jar's hour. In dev a
-- selected one follows clicks instead. Each body gets
-- the nav graph of its nav profile (its size bucket's); bodies with the same
-- one share it. Eggs laid in the jar hatch once their graph is built, a slice
-- per step. The moss grid (jar/moss.lua) grows under the lamp and is grazed
-- and trodden here. Visual systems (flora, ambience, particles) step here too
-- so that what you see is always in sync with the physics.

local Level = require('jar.level')
local NavGraph = require('nav.navgraph')
local Controller = require('nav.controller')
local Mind = require('mind')
local Moss = require('jar.moss')
local DayCycle = require('jar.daycycle')
local Genome = require('genome')
local rng = require('core.rng')
local log = require('core.log')

local World = {}
World.__index = World

World.CREATURES = {
    {key = 'worm',   class = require('bodies.worm')},
    {key = 'blob',   class = require('bodies.blob')},
    {key = 'spider', class = require('bodies.spider')},
}
local CLASS = {}
for _, def in ipairs(World.CREATURES) do CLASS[def.key] = def.class end

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
    self.events = Bus.new()
    self.time = 0
    -- Terrarium: the hour the jar opened at and how long its day is (inputs, like the seed)
    self.start_hour = opts.hour or DayCycle.presets.midday
    self.day_seconds = opts.day
    self.selected = opts.selected or 1 -- 0: nobody is guided and everyone wanders
    self.wander = opts.wander ~= false
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
    for i, r in ipairs(level_data.residents) do
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
    for i, r in ipairs(level_data.residents) do
        local nav = CLASS[r.key].nav_profile(self.genomes[i])
        if not self.navs[nav] then self:built(r.key, nav, NavGraph.new(self.level, nav)) end
        self:place(r.key, self.genomes[i], r.x, r.solid, r.name)
    end
    return self
end

-- Work spent on hatchlings' graphs per step: about half a millisecond, so a clutch
-- of sixteen never costs a frame. A full graph is roughly 200,000 units.
World.BUILD_SLICE = 15000

function World:built(key, nav, graph)
    self.navs[nav] = graph
    local tag = (nav.sizes and string.format(' (sizes %.3f-%.3f)', nav.sizes[1], nav.sizes[2]))
        or (nav.reaches and string.format(' (reaches %.3f-%.3f)', nav.reaches[1], nav.reaches[2])) or ''
    log.info('nav', '%s graph%s: %d nodes, %d edges', key, tag, #graph.nodes, graph.edge_count)
end

-- A creature from `genome`, standing at `x` on solid `solid_id`, with the
-- graph of its nav profile (which must be built already)
function World:place(key, genome, x, solid_id, name)
    local i = #self.creatures + 1
    local solid = self.level.by_id[solid_id]
    local c = CLASS[key].new(x, solid.y, self, Genome.copy(genome))
    c.key, c.name = key, name
    c.home = {x = x, solid = solid_id}
    c.mover.solid = solid
    if c.profile.climbs then
        c.solid = solid
        c:plant_all()
    end
    local graph = assert(self.navs[c.nav], 'world: no graph built for this body')
    self.creatures[i] = c
    self.genomes[i] = Genome.copy(genome)
    self.graph_of[key] = self.graph_of[key] or graph
    self.graphs[i] = graph
    self.controllers[i] = Controller.new(c, graph)
    self.minds[i] = Mind.new(genome)
    return i
end

-- Terrarium: lay an egg at `x` on solid `solid_id`. It hatches on a later step,
-- once the graph for its body is ready, and a whole clutch laid together
-- shares the builds it needs. Returns the egg.
function World:lay(genome, x, solid_id, name)
    genome = Genome.clamp(Genome.copy(genome))
    local key = genome.plan
    local nav = CLASS[key].nav_profile(genome)
    local egg = {key = key, genome = genome, x = x, solid = solid_id, name = name, nav = nav}
    self.eggs[#self.eggs + 1] = egg
    if not self.navs[nav] then
        local queued = false
        for _, b in ipairs(self.building) do queued = queued or b.nav == nav end
        if not queued then
            local b = NavGraph.builder(self.level, nav, World.BUILD_SLICE)
            b.nav, b.key = nav, key
            self.building[#self.building + 1] = b
        end
    end
    return egg
end

-- One slice of the oldest build, then hatch every egg whose graph is ready
function World:hatch()
    local b = self.building[1]
    if b then
        local graph = b:step()
        if graph then
            table.remove(self.building, 1)
            self:built(b.key, b.nav, graph)
        end
    end
    if #self.eggs == 0 then return end
    local waiting = {}
    for _, egg in ipairs(self.eggs) do
        if self.navs[egg.nav] then
            egg.who = self:place(egg.key, egg.genome, egg.x, egg.solid, egg.name)
            self.events:emit('hatched', {who = self.creatures[egg.who], x = egg.x, y = self.level.by_id[egg.solid].y})
        else
            waiting[#waiting + 1] = egg
        end
    end
    self.eggs = waiting
end

-- Terrarium: the jar's hour now
function World:hour()
    return DayCycle.hourAt(self.start_hour, self.time, self.day_seconds)
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
        c:reset(r.x, solid.y)
        c.mover.solid = solid
        if c.profile.climbs then c.solid = solid; c:plant_all() end
        self.controllers[i]:clear()
        self.minds[i] = Mind.new(self.genomes[i])
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

    for i, c in ipairs(self.creatures) do
        local ctrl, mind = self.controllers[i], self.minds[i]

        -- Terrarium: everyone but a dev-selected creature lives by its mind
        if self.wander and i ~= self.selected then
            mind:update(dt, hour, self, i)
        end

        ctrl:update(dt)
        local look = ctrl.path and ctrl:current_node() or nil
        c:update(dt, self.level, {
            events = self.events,
            look_at = look and {x = look.x, y = look.y - 10} or mind:look(c, self),
            light_dir = self.light_dir,
        })
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

    self.moss:update(dt, DayCycle.lampAt(hour))
    if self.flora then self.flora:update(dt, self:influencers(), self.time) end
    if self.ambience then self.ambience:update(dt, self) end
    if self.fx then self.fx:update(dt) end
    self.events:flush()
end

return World
