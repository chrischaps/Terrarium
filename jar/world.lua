-- From chrischaps/Character @ 925c35b (world/world.lua)
-- World: everything that lives in the cave, stepped at a fixed rate.
--
-- Three creatures share the cave. The one you've selected follows your clicks;
-- the others wander on their own, so the cave feels inhabited rather than
-- staged. Visual systems (flora, ambience, particles) step here too so that
-- what you see is always in sync with the physics.

local Level = require('jar.level')
local NavGraph = require('nav.navgraph')
local Controller = require('nav.controller')
local rng = require('core.rng')
local log = require('core.log')

local World = {}
World.__index = World

World.CREATURES = {
    {key = 'worm',   class = require('bodies.worm')},
    {key = 'blob',   class = require('bodies.blob')},
    {key = 'spider', class = require('bodies.spider')},
}

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
    self.selected = opts.selected or 1 -- 0: nobody is guided and everyone wanders
    self.wander = opts.wander ~= false
    self.creatures, self.graphs, self.controllers = {}, {}, {}
    self.idle_timers = {}

    local mouth = level_data.lamp or level_data.mouth -- Terrarium: the lamp above the jar
    self.light_dir = function(x, y)
        local dx, dy = mouth.x - x, mouth.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        return dx / d, dy / d
    end

    for i, def in ipairs(World.CREATURES) do
        local graph = NavGraph.new(self.level, def.class.profile)
        local spawn = level_data.spawns[def.key]
        local solid = self.level.by_id[spawn.solid]
        local c = def.class.new(spawn.x, solid.y, self)
        c.key = def.key
        c.mover.solid = solid
        if c.profile.climbs then
            c.solid = solid
            c:plant_all()
        end
        self.creatures[i] = c
        self.graphs[i] = graph
        self.controllers[i] = Controller.new(c, graph)
        self.idle_timers[i] = rng.range(rng.sim, 2, 6)
        log.info('nav', '%s graph: %d nodes, %d edges', def.key, #graph.nodes, graph.edge_count)
    end
    return self
end

function World:selected_creature()
    return self.creatures[self.selected]
end

function World:select(i)
    if self.creatures[i] then
        self.selected = i
        self.idle_timers[i] = 0
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
        local spawn = self.level.data.spawns[c.key]
        local solid = self.level.by_id[spawn.solid]
        c:reset(spawn.x, solid.y)
        c.mover.solid = solid
        if c.profile.climbs then c.solid = solid; c:plant_all() end
        self.controllers[i]:clear()
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

    for i, c in ipairs(self.creatures) do
        local ctrl = self.controllers[i]

        -- Unselected creatures wander now and then
        if self.wander and i ~= self.selected and not ctrl:has_path() then
            self.idle_timers[i] = self.idle_timers[i] - dt
            if self.idle_timers[i] <= 0 then
                self.idle_timers[i] = rng.range(rng.sim, 5, 14)
                local graph = self.graphs[i]
                local kinds = c.profile.climbs and nil or {top = true}
                local goal = graph:random_node(rng.sim, kinds)
                ctrl:go_to(goal)
            end
        end

        ctrl:update(dt)
        local look = ctrl.path and ctrl:current_node() or nil
        c:update(dt, self.level, {
            events = self.events,
            look_at = look and {x = look.x, y = look.y - 10} or nil,
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
