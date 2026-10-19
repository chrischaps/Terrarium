-- From chrischaps/Character @ 925c35b (core/controller.lua)
-- Controller: turns a path into what a creature does next.
--
-- Walkers (worm, blob) are driven through their Mover: walk to a node, stand
-- on a takeoff node, launch with the ballistic solution, steer the landing.
-- Climbers (spider) crawl node to node over any surface and only use the
-- mover for jumps. If a landing goes wrong or progress stalls, it repaths.

local Pathfinder = require('nav.pathfinder')
local ballistics = require('nav.ballistics')
local log = require('core.log')

local Controller = {}
Controller.__index = Controller

local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt

function Controller.new(creature, graph)
    return setmetatable({
        creature = creature,
        graph = graph,
        path = nil,
        i = 1,
        goal = nil,
        flight = nil,
        stall = 0,           -- time since the last bit of progress
        still = 0,           -- time spent trying to walk without moving
        last_x = nil,
        repaths = 0,
        arrived = false,
    }, Controller)
end

-- Creature-shape adapters ------------------------------------------------------

local function climbs(c) return c.profile.climbs end

local function ready(c)
    if climbs(c) then return c:ready() end
    return c.mover.state == 'ground'
end

local function airborne(c)
    if climbs(c) then return c:airborne() end
    return c.mover.state == 'air'
end

local function support(c)
    if climbs(c) then return c:support() end
    return c.mover.solid
end

-- Public -----------------------------------------------------------------------

function Controller:start_node()
    local c = self.creature
    local x, y = c:anchor()
    local nx, ny
    if climbs(c) then nx, ny = c:normal() end
    return self.graph:node_near(x, y, support(c), nx, ny)
end

function Controller:go_to(goal)
    if not goal then return false end
    local c = self.creature
    if not ready(c) then
        -- Mid-jump: plan from wherever we land. Say yes if a path exists from
        -- the node we're flying toward (or the nearest one).
        local target = (self.flight and self.flight.node) or self:start_node()
        if not Pathfinder.find(self.graph, target, goal) then return false end
        self.pending = goal
        return true
    end
    self.pending = nil
    local path = Pathfinder.find(self.graph, self:start_node(), goal)
    self.goal = goal
    self.flight = nil
    self.stall, self.still = 0, 0
    self.arrived = false
    if path then
        self.path, self.i = path, 1
        return true
    end
    self.path = nil
    return false
end

function Controller:clear()
    self.path, self.goal, self.flight, self.pending = nil, nil, nil, nil
end

function Controller:has_path()
    return self.path ~= nil or self.pending ~= nil
end

function Controller:current_node()
    return self.path and self.path[self.i] and self.path[self.i].node
end

function Controller:repath(reason)
    self.repaths = self.repaths + 1
    log.info('ctrl', '%s repath (%s)', self.creature.profile.name, reason)
    local goal = self.goal
    if not goal or not self:go_to(goal) then
        self:clear()
    end
end

function Controller:advance()
    self.i = self.i + 1
    self.stall = 0
    if self.i > #self.path then
        self.path = nil
        self.arrived = true
    end
end

function Controller:update(dt)
    local c = self.creature
    if self.pending and ready(c) and not (self.flight and self.flight.launched) then
        self:go_to(self.pending)
    end
    if not self.path then
        if climbs(c) then c:halt(dt) end
        return
    end

    self.stall = self.stall + dt
    if self.stall > 7 then
        self.stall = 0
        self:repath('stalled')
        return
    end

    -- In flight: steer for the landing node
    if airborne(c) then
        if self.flight then
            self.flight.launched = true
            if self.flight.kind == 'fall' and not self.flight.boosted then
                self.flight.boosted = true
                c.mover.vx = self.flight.vx
            end
            local n = self.flight.node
            if climbs(c) then c:steer(n.x, n.y, dt) else c.mover:steer(n.x, n.y, dt) end
        end
        return
    end
    if not ready(c) then return end   -- anticipating a jump

    local x, y = c:anchor()

    -- Just landed from a planned flight?
    if self.flight and self.flight.launched then
        local n = self.flight.node
        self.flight = nil
        if support(c) == n.solid and abs(y - n.y) < 3 and abs(x - n.x) < 60 then
            self:advance()
        else
            self:repath('off-target landing')
        end
        return
    end

    local step = self.path[self.i]
    local n, e = step.node, step.edge
    local kind = e and e.kind or 'walk'
    local last = self.i == #self.path

    if kind == 'walk' or kind == 'crawl' then
        if climbs(c) then
            if c:crawl_to(n, dt, last and 0.8 or 1) then self:advance() end
        else
            -- A step up onto a different surface: the blob hops it
            if c.profile.hop_steps and e and n.solid ~= support(c) and n.y < y - 5 then
                local vx, vy = ballistics.solve_jump(x, y, n.x, n.y, c.profile, self.graph.level)
                if vx then
                    c.mover:launch(vx, vy, 0.08)
                    self.flight = {node = n, kind = 'hop'}
                    return
                end
            end
            local dx = n.x - x
            if abs(dx) < 2.5 and (support(c) == n.solid or abs(y - n.y) < 3) then
                self:advance()
            else
                local speed = c.profile.walk_speed
                if last then speed = speed * max(0.35, min(1, abs(dx) / 30)) end
                c.mover:walk(dx > 0 and 1 or -1, speed)
                self:watch_still(x, dt)
            end
        end

    elseif kind == 'jump' then
        local from = self.path[self.i - 1] and self.path[self.i - 1].node
        if from and (abs(x - from.x) > 4 or abs(y - from.y) > 3) then
            -- Line up on the takeoff spot first
            if climbs(c) then
                c:crawl_to(from, dt, 0.8)
            else
                c.mover:walk(from.x > x and 1 or -1, c.profile.walk_speed * 0.6)
                self:watch_still(x, dt)
            end
            return
        end
        -- Terrarium: the same lowest clear arc the graph found, from where it stands
        local vx, vy = ballistics.solve_jump(x, y, n.x, n.y, c.profile, self.graph.level)
        if not vx then vx, vy = e.vx, e.vy end
        if climbs(c) then c:launch(vx, vy) else c.mover:launch(vx, vy) end
        self.flight = {node = n, kind = 'jump'}

    elseif kind == 'fall' then
        -- Walk off the edge; steering takes over once airborne
        self.flight = {node = n, kind = 'fall', vx = e.vx}
        c.mover:walk(e.dir, c.profile.walk_speed)
        self:watch_still(x, dt)
    end
end

-- Walking but not moving for a while means something is in the way
function Controller:watch_still(x, dt)
    if self.last_x and abs(x - self.last_x) < 0.05 then
        self.still = self.still + dt
        if self.still > 1.2 then
            self.still = 0
            self:repath('blocked')
        end
    else
        self.still = 0
    end
    self.last_x = x
end

-- Draw the remaining path: walks as dotted lines, jumps as true arcs
function Controller:draw_path(alpha, color, time)
    if not self.path then return end
    local c = self.creature
    local x, y = c:anchor()
    color = color or {1, 0.9, 0.7}
    local t = time or 0
    local px, py = x, y
    for k = self.i, #self.path do
        local step = self.path[k]
        local n, e = step.node, step.edge
        local kind = e and e.kind or 'walk'
        local pts
        local from = self.path[k - 1] and self.path[k - 1].node
        if (kind == 'jump' or kind == 'fall') and from then
            local x0 = e.ex or from.x
            pts = ballistics.sample_arc(x0, from.y, e.vx, e.vy, e.t, 20)
        else
            pts = {px, py, n.x, n.y}
        end
        -- Dots along the polyline
        local spacing = 7
        local carry = (t * 18) % spacing
        for i = 1, #pts - 3, 2 do
            local ax, ay, bx, by = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
            local seg = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
            local d = spacing - carry
            while d < seg do
                local u = d / seg
                love.graphics.setColor(color[1], color[2], color[3], alpha * 0.7)
                love.graphics.circle('fill', ax + (bx - ax) * u, ay + (by - ay) * u - 2, 1.1)
                d = d + spacing
            end
            carry = (carry + seg) % spacing
        end
        px, py = n.x, n.y
    end
end

return Controller
