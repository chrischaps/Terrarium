-- Glide: the coarse step's controller (#27, #31).
--
-- It answers a mind the way Controller does (go_to, clear, has_path, goal,
-- arrived, pace), but it drives a Token (bodies/token.lua), not a body: the
-- anchor slides along each edge of the path at its body's own speed, and a
-- jump or a fall takes its edge's time in the air. There's no physics to go
-- wrong, so it never stalls, misses a landing or repaths, and it doesn't care
-- how coarse the step is: a long step only carries it across more edges.
--
-- The edge it's on (`leg`) belongs to the token, not the glide, so a moult
-- that hands the token a new graph and a new glide doesn't strand it halfway.

local Pathfinder = require('nav.pathfinder')

local Glide = {}
Glide.__index = Glide

local sqrt, abs, max = math.sqrt, math.abs, math.max

function Glide.new(token, graph)
    return setmetatable({
        creature = token,
        graph = graph,
        path = nil,
        i = 1,
        goal = nil,
        arrived = false,
        pace = 1, -- of its body's own speed it moves at (an elder slows, #24)
    }, Glide)
end

-- The node it's at, or will be at once it's off the edge it's on
function Glide:start_node()
    local c = self.creature
    local leg = c.leg
    if leg then return self.graph:node_near(leg.to.x, leg.to.y, leg.to.solid, leg.to.nx, leg.to.ny) end
    return self.graph:node_near(c.x, c.y, c.solid or c.mover.solid, c.profile.climbs and c.nx, c.profile.climbs and c.ny)
end

function Glide:go_to(goal, dare)
    if not goal then return false end
    self.dare = dare
    local path = Pathfinder.find(self.graph, self:start_node(), goal, dare)
    self.goal, self.arrived = goal, false
    self.path, self.i = path, 1
    return path ~= nil
end

function Glide:clear()
    self.path, self.goal = nil, nil
end

function Glide:has_path()
    return self.path ~= nil
end

function Glide:current_node()
    return self.path and self.path[self.i] and self.path[self.i].node
end

-- The edge from where the token is to the next node of the path, and how long
-- it takes: walking or crawling at its pace, or a leap (crouch, then flight)
function Glide:leg(step)
    local c, p = self.creature, self.creature.profile
    local n, e = step.node, step.edge
    local kind = e and e.kind or 'walk'
    local dx, dy = n.x - c.x, n.y - c.y
    local d = sqrt(dx * dx + dy * dy)
    local t
    if kind == 'jump' then
        t = (p.anticipation or 0.12) + e.t
    elseif kind == 'fall' then
        t = abs(e.ex - c.x) / (p.walk_speed * self.pace) + e.t
    elseif p.climbs then
        -- (slower round an edge, as a spider is, by how far it has to turn)
        local turn = c.nx and n.nx and 1 - (c.nx * n.nx + c.ny * n.ny) or 0
        t = d * (1 + 1.25 * max(0, turn)) / (p.crawl_speed * self.pace)
    else
        t = d / (p.walk_speed * self.pace)
    end
    return {to = n, x = c.x, y = c.y, t = t, at = 0, air = kind == 'jump' or kind == 'fall'}
end

function Glide:update(dt)
    local c = self.creature
    while dt > 0 do
        local leg = c.leg
        if not leg then
            local step = self.path and self.path[self.i]
            if not step then return end
            leg = self:leg(step)
            c.leg = leg
            if leg.air then c:fly(true) end
        end
        local n = leg.to
        if leg.at + dt < leg.t then
            leg.at = leg.at + dt
            local u = leg.at / leg.t
            c:set(leg.x + (n.x - leg.x) * u, leg.y + (n.y - leg.y) * u)
            return
        end
        dt = dt - (leg.t - leg.at)
        c.leg = nil
        c:set(n.x, n.y, n.solid, n.nx, n.ny)
        if leg.air then c:fly(false) end
        -- (a leg begun on an old path finishes before the new one starts)
        if self.path and self.path[self.i] and self.path[self.i].node == n then
            self.i = self.i + 1
            if self.i > #self.path then
                self.path = nil
                self.arrived = true
            end
        end
    end
end

return Glide
