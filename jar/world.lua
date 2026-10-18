-- From chrischaps/Character @ 925c35b (world/world.lua)
-- World: everything that lives in the cave, stepped at a fixed rate.
--
-- Terrarium: six creatures share the jar, two of each kind (the room's
-- residents). Each has a mind (mind.lua) that wanders, grazes and rests by the
-- jar's hour. In dev a selected one follows clicks instead. Bodies of a kind
-- share one nav graph, since it's built from the body. Visual systems (flora, ambience, particles) step here too so that
-- what you see is always in sync with the physics.

local Level = require('jar.level')
local NavGraph = require('nav.navgraph')
local Controller = require('nav.controller')
local Mind = require('mind')
local DayCycle = require('jar.daycycle')
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
    self.events = Bus.new()
    self.time = 0
    -- Terrarium: the hour the jar opened at and how long its day is (inputs, like the seed)
    self.start_hour = opts.hour or DayCycle.presets.midday
    self.day_seconds = opts.day
    self.selected = opts.selected or 1 -- 0: nobody is guided and everyone wanders
    self.wander = opts.wander ~= false
    self.creatures, self.graphs, self.controllers = {}, {}, {}
    self.minds = {}
    self.graph_of = {} -- one graph per kind

    local mouth = level_data.lamp or level_data.mouth -- Terrarium: the lamp above the jar
    self.light_dir = function(x, y)
        local dx, dy = mouth.x - x, mouth.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        return dx / d, dy / d
    end

    for _, def in ipairs(World.CREATURES) do
        local graph = NavGraph.new(self.level, def.class.profile)
        self.graph_of[def.key] = graph
        log.info('nav', '%s graph: %d nodes, %d edges', def.key, #graph.nodes, graph.edge_count)
    end
    for i, r in ipairs(level_data.residents) do
        local solid = self.level.by_id[r.solid]
        local c = CLASS[r.key].new(r.x, solid.y, self)
        c.key, c.name = r.key, r.name
        c.mover.solid = solid
        if c.profile.climbs then
            c.solid = solid
            c:plant_all()
        end
        self.creatures[i] = c
        self.graphs[i] = self.graph_of[r.key]
        self.controllers[i] = Controller.new(c, self.graphs[i])
        self.minds[i] = Mind.new()
    end
    return self
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
        local r = self.level.data.residents[i]
        local solid = self.level.by_id[r.solid]
        c:reset(r.x, solid.y)
        c.mover.solid = solid
        if c.profile.climbs then c.solid = solid; c:plant_all() end
        self.controllers[i]:clear()
        self.minds[i] = Mind.new()
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
        local s, saved = self.snap[i], self.saved[i] or {}
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

    for i, c in ipairs(self.creatures) do
        local ctrl, mind = self.controllers[i], self.minds[i]

        -- Terrarium: everyone but a dev-selected creature lives by its mind
        if self.wander and i ~= self.selected then
            mind:update(dt, hour, c, ctrl, self.graphs[i])
        end

        ctrl:update(dt)
        local look = ctrl.path and ctrl:current_node() or nil
        c:update(dt, self.level, {
            events = self.events,
            look_at = look and {x = look.x, y = look.y - 10} or mind:look(c),
            light_dir = self.light_dir,
        })
        if ctrl.arrived then
            ctrl.arrived = false
            local ax, ay = c:anchor()
            self.events:emit('arrived', {who = c, x = ax, y = ay})
        end
    end

    if self.flora then self.flora:update(dt, self:influencers(), self.time) end
    if self.ambience then self.ambience:update(dt, self) end
    if self.fx then self.fx:update(dt) end
    self.events:flush()
end

return World
