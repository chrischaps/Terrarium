-- From chrischaps/Character @ 925c35b (core/navgraph.lua)
-- Navigation Graph: where a creature can stand, and how it can get between.
--
-- Built per creature profile, because a graph is a promise about a body:
--   radius, height  - clearance needed to stand somewhere
--   jump_vx/jump_vy - what ballistics.solve_jump may ask of it
--   step            - largest ledge it can walk up or down without jumping
--   climbs          - spiders get nodes on walls and ceilings too
--   span            - (climbers) the widest gap between solids its legs step across (Terrarium)
--   min_radius      - (Terrarium) a size bucket's graph is shared by bodies of every
--                     radius from this to `radius`, and every check covers them all
--   leaps           - (Terrarium, #73) false: it never jumps or falls, so no
--                     ballistic edges (a snail goes the long way round)
--   flies           - (Terrarium, #73) reserved for a body that crosses the air
--                     itself (the moth, #78); nothing reads it yet
--   hops            - (Terrarium, #76) it leaps along a surface as well as between
--                     them: jumps also join the nodes of one span up to `hop_max`
--                     apart (a springtail gets about by hopping)
--   walk_cost       - (Terrarium, #76) a walk edge costs this many times its length
--                     (1 if unset), so a body that would rather hop does
--   loft            - (Terrarium, #76) the lowest a leap's apex goes over its higher
--                     end (ballistics.solve_jump)
--   jump_flat       - (Terrarium, #76) what every leap costs on top of its length
--                     (60 if unset): a hopper's are cheap. No edge costs less than
--                     its chord, so A*'s straight-line heuristic never overestimates.
-- Ways of moving are flags on the profile, never a body's name.
--
-- Edge types:
--   walk  - along a surface (or a small step between surfaces)
--   crawl - along any surface incl. walls/ceilings and around corners (climbers)
--   jump  - ballistic arc, vx/vy precomputed by ballistics.solve_jump
--   fall  - step off an edge, vx precomputed by ballistics.solve_fall
--
-- Terrarium: jumps and falls carry `dare`, how much of the body they ask for
-- (1 is all it has), so a timid mind can leave the big ones out (mind.lua).

local ballistics = require('nav.ballistics')

local NavGraph = {}
NavGraph.__index = NavGraph

NavGraph.WALK, NavGraph.CRAWL, NavGraph.JUMP, NavGraph.FALL = 'walk', 'crawl', 'jump', 'fall'

local SPACING = 32        -- node spacing along a surface
local FACE_SPACING = 28   -- node spacing along walls/ceilings (climbers)
local MAX_JUMP_DX = 330
local sqrt, abs = math.sqrt, math.abs

local function dist(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return sqrt(dx * dx + dy * dy)
end

local function blank(level, profile)
    local self = setmetatable({}, NavGraph)
    self.level = level
    self.profile = profile
    self.nodes = {}
    self.edge_count = 0
    return self
end

function NavGraph:build()
    if self.profile.climbs then
        self:build_surface_nodes()
    else
        self:build_top_nodes()
    end
    if self.profile.leaps ~= false then self:build_ballistic_edges() end
    self:keep_home() -- Terrarium
    return self
end

function NavGraph.new(level, profile)
    return blank(level, profile):build()
end

-- Terrarium: a build a slice at a time (#16). A full graph takes several
-- milliseconds, which is a dropped frame when a clutch hatches at once. A
-- builder does `slice` units of work per :step() and returns the graph when
-- it's done: a pair of nodes weighed for a step or a join is 1, a jump solved
-- is JUMP_WORK, a node sorted by keep_home is NODE_WORK (a unit is about
-- 60 ns on the machine that measured them). The units are counted, never
-- timed, so a build finishes on the same sim step on every machine, and the
-- graph is the one NavGraph.new makes.
NavGraph.JUMP_WORK, NavGraph.NODE_WORK = 150, 80

local Builder = {}
Builder.__index = Builder
NavGraph.Builder = Builder -- (so the book, #30, knows one by name)

function NavGraph.builder(level, profile, slice)
    local graph = blank(level, profile)
    graph.left = slice
    local co = coroutine.create(function() graph:build() end)
    return setmetatable({graph = graph, co = co, slice = slice, slices = 0}, Builder)
end

function Builder:step()
    if self.done then return self.graph end
    self.graph.left = self.slice
    self.slices = self.slices + 1
    local ok, err = coroutine.resume(self.co)
    if not ok then error(err, 0) end
    if coroutine.status(self.co) == 'dead' then
        self.graph.left = nil
        self.done, self.co = true, nil
        return self.graph
    end
end

-- Count `n` units of work; a builder's graph pauses here when its slice is spent
function NavGraph:work(n)
    local left = self.left
    if not left then return end
    left = left - n
    if left <= 0 then
        coroutine.yield()
    else
        self.left = left
    end
end

-- Terrarium: keep only the largest set of nodes that can all reach each other.
-- Soil roofed over at both ends (under the arch, under the twig) can't be
-- walked into or jumped out of, so a walker's graph drops it and never offers
-- it as a goal. A climber gets in over the walls where a roof leaves a way
-- round (under the arch), but not under the twig: it lies flush on the stone
-- and the cairn, so the dish beneath is shut in for everyone (#77).
function NavGraph:keep_home()
    local nodes = self.nodes
    local n = #nodes
    if n == 0 then return end

    -- Kosaraju: finish order on the graph, then components on its reverse
    local back = {}
    for i = 1, n do back[i] = {} end
    for _, a in ipairs(nodes) do
        self:work(NavGraph.NODE_WORK)
        for _, e in ipairs(a.edges) do
            local list = back[e.to]
            list[#list + 1] = a.id
        end
    end
    local seen, order = {}, {}
    for root = 1, n do
        if not seen[root] then
            seen[root] = true
            local stack = {{root, 1}}
            while #stack > 0 do
                local top = stack[#stack]
                local edges = nodes[top[1]].edges
                local e = edges[top[2]]
                if e then
                    top[2] = top[2] + 1
                    if not seen[e.to] then
                        seen[e.to] = true
                        stack[#stack + 1] = {e.to, 1}
                    end
                else
                    order[#order + 1] = top[1]
                    stack[#stack] = nil
                end
            end
        end
    end
    local comp, sizes = {}, {}
    for k = n, 1, -1 do
        local root = order[k]
        if not comp[root] then
            local c = #sizes + 1
            sizes[c] = 0
            comp[root] = c
            local stack = {root}
            while #stack > 0 do
                local id = table.remove(stack)
                sizes[c] = sizes[c] + 1
                for _, from in ipairs(back[id]) do
                    if not comp[from] then
                        comp[from] = c
                        stack[#stack + 1] = from
                    end
                end
            end
        end
    end
    local home = 1
    for c, size in ipairs(sizes) do
        if size > sizes[home] then home = c end
    end
    if sizes[home] == n then return end

    -- Renumber what's kept; drop edges into what isn't
    local kept, new_id = {}, {}
    for _, a in ipairs(nodes) do
        if comp[a.id] == home then
            kept[#kept + 1] = a
            new_id[a.id] = #kept
        end
    end
    self.edge_count = 0
    for _, a in ipairs(kept) do
        a.id = new_id[a.id]
        local edges = {}
        for _, e in ipairs(a.edges) do
            if new_id[e.to] then
                e.to = new_id[e.to]
                edges[#edges + 1] = e
            end
        end
        a.edges = edges
        self.edge_count = self.edge_count + #edges
    end
    self.nodes = kept
    self.dropped = n - #kept
end

function NavGraph:add_node(n)
    n.id = #self.nodes + 1
    n.edges = {}
    self.nodes[n.id] = n
    return n
end

function NavGraph:connect(a, b, kind, cost, extra)
    for _, e in ipairs(a.edges) do
        if e.to == b.id and e.kind == kind then return end
    end
    local e = {to = b.id, kind = kind, cost = cost}
    if extra then for k, v in pairs(extra) do e[k] = v end end
    a.edges[#a.edges + 1] = e
    self.edge_count = self.edge_count + 1
    return e
end

-- Terrarium: is a body's circle clear, for every body the graph is shared by?
-- A body of radius r holds a circle of radius k*r centred a*r + b above
-- (x, y). Over r from min_radius to radius, those all lie inside one circle
-- about the middle radius's, a*(radius - min_radius)/2 wider than the biggest.
function NavGraph:clear(x, y, a, b, k)
    local p = self.profile
    local r1, r0 = p.radius, p.min_radius or p.radius
    local mid = (r0 + r1) / 2
    return self.level:circle_clear(x, y - a * mid - b, k * r1 + a * (r1 - r0) / 2)
end

-- Can the body stand at (x, y) on a top surface?
function NavGraph:fits(x, y)
    local p = self.profile
    return self:clear(x, y, 1, 1, 0.9)
       and self:clear(x, y, p.height / p.radius - 1, 0, 0.9) -- (height scales with radius)
end

--------------------------------------------------------------------------------
-- Walkers: nodes along exposed top surfaces
--------------------------------------------------------------------------------

function NavGraph:build_top_nodes()
    local level, p = self.level, self.profile
    local margin = math.max(8, p.radius * 0.7)
    local wc = p.walk_cost or 1 -- Terrarium (#76)
    self.spans = {}

    for _, span in ipairs(level:top_spans()) do
        local a, b = span.x0 + margin, span.x1 - margin
        if b >= a then
            local count = math.max(1, math.ceil((b - a) / SPACING))
            local prev = nil
            local list = {}
            for i = 0, count do
                local x = (count == 0) and a or (a + (b - a) * i / count)
                if b == a and i > 0 then break end
                if self:fits(x, span.y) then
                    local n = self:add_node({
                        x = x, y = span.y, nx = 0, ny = -1,
                        solid = span.solid, span = span, kind = 'top'
                    })
                    list[#list + 1] = n
                    if prev then
                        self:connect(prev, n, 'walk', dist(prev, n) * wc)
                        self:connect(n, prev, 'walk', dist(prev, n) * wc)
                    end
                    prev = n
                else
                    prev = nil
                end
            end
            if #list > 0 then
                list[1].end_left = true
                list[#list].end_right = true
                span.nodes = list
                self.spans[#self.spans + 1] = span
            end
        end
    end

    -- Small steps between neighbouring spans are walkable
    for _, a in ipairs(self.nodes) do
        self:work(#self.nodes)
        for _, b in ipairs(self.nodes) do
            if a.span ~= b.span and abs(b.x - a.x) <= margin * 2 + 6
               and abs(b.y - a.y) <= p.step then
                local mx, my = (a.x + b.x) / 2, math.min(a.y, b.y)
                if self:clear(mx, my, 1, 1, 0.8) then
                    self:connect(a, b, 'walk', (dist(a, b) + 4) * wc)
                end
            end
        end
    end

    -- A span end is a real drop-off only if no step continues past it
    for _, n in ipairs(self.nodes) do
        for _, e in ipairs(n.edges) do
            local m = self.nodes[e.to]
            if e.kind == 'walk' and m.span ~= n.span then
                if m.x > n.x then n.end_right = false else n.end_left = false end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Climbers: nodes around the whole exposed perimeter of every solid
--------------------------------------------------------------------------------

function NavGraph:exposed(x, y, nx, ny)
    local level = self.level
    local ox, oy = x + nx * 3, y + ny * 3
    if ox < 1 or ox > level.width - 1 or oy < 1 or oy > level.height - 1 then
        return false
    end
    -- Room for the body on this side of the surface
    local r = self.profile.radius
    return level:solid_at(ox, oy) == nil
       and level:circle_clear(x + nx * (r + 2), y + ny * (r + 2), r * 0.7)
end

-- Terrarium: is the face between two neighbouring nodes of a solid's ring
-- open all the way, a unit off it? (#77)
function NavGraph:open_face(a, b)
    local nx, ny = a.nx + b.nx, a.ny + b.ny
    local d = sqrt(nx * nx + ny * ny)
    nx, ny = nx / d, ny / d
    local steps = math.max(2, math.ceil(dist(a, b) / 4))
    for k = 1, steps - 1 do
        local t = k / steps
        if self.level:solid_at(a.x + (b.x - a.x) * t + nx, a.y + (b.y - a.y) * t + ny) then return false end
    end
    return true
end

function NavGraph:build_surface_nodes()
    local level = self.level
    local inv = 1 / sqrt(2)

    for _, s in ipairs(level.solids) do
        local L, T, R, B = s.x, s.y, s.x + s.w, s.y + s.h
        local ring = {}
        local function face(x0, y0, x1, y1, nx, ny)
            local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            local count = math.max(1, math.ceil(len / FACE_SPACING))
            for i = 1, count - 1 do
                local t = i / count
                ring[#ring + 1] = {x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t, nx = nx, ny = ny}
            end
        end
        -- Clockwise from top-left corner
        ring[#ring + 1] = {x = L, y = T, nx = -inv, ny = -inv, corner = true}
        face(L, T, R, T, 0, -1)
        ring[#ring + 1] = {x = R, y = T, nx = inv, ny = -inv, corner = true}
        face(R, T, R, B, 1, 0)
        ring[#ring + 1] = {x = R, y = B, nx = inv, ny = inv, corner = true}
        face(R, B, L, B, 0, 1)
        ring[#ring + 1] = {x = L, y = B, nx = -inv, ny = inv, corner = true}
        face(L, B, L, T, -1, 0)

        local made = {}
        for i, pt in ipairs(ring) do
            if self:exposed(pt.x, pt.y, pt.nx, pt.ny) then
                pt.solid = s
                pt.kind = (pt.ny == -1) and 'top' or (pt.corner and 'corner' or 'face')
                made[i] = self:add_node(pt)
            end
        end
        local count = #ring
        for i = 1, count do
            local a, b = made[i], made[i % count + 1]
            -- Terrarium: and only along open face (#77): a corner can be
            -- clear when the face beside it is covered (the arch's lip), and
            -- the way to the next node round would go through what covers it
            if a and b and self:open_face(a, b) then
                self:connect(a, b, 'crawl', dist(a, b))
                self:connect(b, a, 'crawl', dist(a, b))
            end
        end
    end

    -- Concave joins between different solids (wall meets floor, etc.)
    local level_ref = self.level
    -- Terrarium: across a gap between the solids no wider than its legs
    -- step (40 at Character's reach). Solids that touch always join, however
    -- far their nearest nodes sit from the corner.
    local span = self.profile.span or 40
    local near = math.max(40, span)
    local function gap(s, t)
        local gx = math.max(0, s.x - (t.x + t.w), t.x - (s.x + s.w))
        local gy = math.max(0, s.y - (t.y + t.h), t.y - (s.y + s.h))
        return sqrt(gx * gx + gy * gy)
    end
    for _, a in ipairs(self.nodes) do
        self:work(#self.nodes)
        for _, b in ipairs(self.nodes) do
            if a.solid ~= b.solid and abs(a.x - b.x) < near and abs(a.y - b.y) < near and gap(a.solid, b.solid) < span then
                local d = dist(a, b)
                if d < near then
                    local ax, ay = a.x + a.nx * 6, a.y + a.ny * 6
                    local bx, by = b.x + b.nx * 6, b.y + b.ny * 6
                    local clear = true
                    for k = 0, 6 do
                        local t = k / 6
                        if level_ref:solid_at(ax + (bx - ax) * t, ay + (by - ay) * t) then
                            clear = false
                            break
                        end
                    end
                    if clear then
                        self:connect(a, b, 'crawl', d + 2)
                    end
                end
            end
        end
    end

    -- Top nodes double as standing spots for jumps; mark span ends
    for _, n in ipairs(self.nodes) do
        if n.kind == 'top' then
            n.end_left, n.end_right = false, false
        end
    end
end

--------------------------------------------------------------------------------
-- Jumps and falls (shared by everyone)
--------------------------------------------------------------------------------

function NavGraph:build_ballistic_edges()
    local p, level = self.profile, self.level
    local tops = {}
    for _, n in ipairs(self.nodes) do
        if n.kind == 'top' then tops[#tops + 1] = n end
    end

    local flat = p.jump_flat or 60 -- Terrarium (#76)
    for _, a in ipairs(tops) do
        self:work(#tops)
        for _, b in ipairs(tops) do
            local dx, dy = b.x - a.x, b.y - a.y
            local across = a.solid ~= b.solid and abs(dx) <= MAX_JUMP_DX and not self:has_step(a, b)
            -- Terrarium: a hopper leaps along its own span too (#76)
            local hop = p.hops and a ~= b and a.span ~= nil and a.span == b.span and abs(dx) <= p.hop_max
            if across or hop then
                self:work(NavGraph.JUMP_WORK)
                -- Jump: any standing node to any other surface
                local vx, vy, t = ballistics.solve_jump(a.x, a.y, b.x, b.y, p, level) -- Terrarium: the lowest clear arc
                if vx then
                    local d = dist(a, b)
                    self:connect(a, b, 'jump', d * 1.25 + flat,
                        {vx = vx, vy = vy, t = t, dare = NavGraph.dare(p, vx, vy)})
                end

                -- Fall: only off the end of a span, in the direction of the drop
                if across and dy > p.step and not p.climbs then
                    local dir = (a.end_right and dx > 0) and 1 or ((a.end_left and dx < 0) and -1 or 0)
                    if dir ~= 0 then
                        local ex = (dir > 0) and a.span.x1 or a.span.x0
                        local fx, fvy, ft = ballistics.solve_fall(ex, a.y, b.x, b.y, p)
                        if fx and fx * dir > 20
                           and ballistics.arc_clear(level, ex, a.y, fx, 0, ft, p.radius, p.min_radius) then
                            self:connect(a, b, 'fall', dist(a, b) + 30,
                                {vx = fx, vy = 0, t = ft, ex = ex, dir = dir, dare = NavGraph.dare(p, fx, 0, dy)})
                        end
                    end
                end
            end
        end
    end
end

-- Terrarium: how much of a body's spring a leap asks for, 0 to 1: the larger
-- of its rise against the highest the body can rise and its speed against
-- the fastest it can go. A fall's drop counts as rising a third of it, so a
-- long way down is daunting too, but less than the same way up.
function NavGraph.dare(p, vx, vy, drop)
    local g = ballistics.GRAVITY
    local most = p.jump_vy * p.jump_vy / (2 * g)
    local rise = math.max(vy * vy / (2 * g), (drop or 0) / 3)
    return math.floor(math.min(1, math.max(rise / most, abs(vx) / p.jump_vx)) * 1000 + 0.5) / 1000
end

function NavGraph:has_step(a, b)
    for _, e in ipairs(a.edges) do
        if e.to == b.id and (e.kind == 'walk' or e.kind == 'crawl') then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

-- Nearest node to a creature standing on `solid` at (x, y) with normal (nx, ny)
function NavGraph:node_near(x, y, solid, nx, ny)
    local best, best_d = nil, math.huge
    for _, n in ipairs(self.nodes) do
        local d = (n.x - x) ^ 2 + (n.y - y) ^ 2
        if solid and n.solid ~= solid then d = d + 1e6 end
        if nx and (n.nx * nx + n.ny * ny) < 0.5 then d = d + 4000 end
        if d < best_d then best, best_d = n, d end
    end
    return best
end

-- Turn a click into a goal node, or nil if the click can't be stood on.
function NavGraph:snap_goal(x, y)
    local level = self.level

    if self.profile.climbs then
        -- Any surface within reach of the click: wall, ceiling or floor,
        -- even if the click itself landed a little inside the stone
        local best, best_d = nil, 60 * 60
        for _, n in ipairs(self.nodes) do
            local d = (n.x - x) ^ 2 + (n.y - y) ^ 2
            if d < best_d then best, best_d = n, d end
        end
        if best then return best end
    end

    local inside = level:solid_at(x, y)
    if inside then
        if y - inside.y < 36 and not level:solid_at(x, inside.y - 1) then
            y = inside.y - 1
        else
            return nil
        end
    end

    local sy, solid = level:surface_below(x, y)
    if not sy then return nil end
    local best, best_d = nil, math.huge
    for _, n in ipairs(self.nodes) do
        if n.solid == solid and n.kind == 'top' and abs(n.y - sy) < 1 then
            local d = abs(n.x - x)
            if d < best_d then best, best_d = n, d end
        end
    end
    return best
end

-- Random reachable node from `start` (used by idle wandering)
function NavGraph:random_node(gen, kinds)
    local pool = {}
    for _, n in ipairs(self.nodes) do
        if not kinds or kinds[n.kind] then pool[#pool + 1] = n end
    end
    if #pool == 0 then return nil end
    return pool[gen:random(1, #pool)]
end

function NavGraph:draw_debug(alpha)
    local k = alpha or 1
    local colors = {
        walk = {0.45, 0.95, 0.55, 0.35 * k}, crawl = {0.4, 0.8, 1.0, 0.35 * k},
        jump = {1.0, 0.85, 0.3, 0.16 * k}, fall = {1.0, 0.55, 0.3, 0.22 * k},
    }
    love.graphics.setLineWidth(1)
    for _, n in ipairs(self.nodes) do
        for _, e in ipairs(n.edges) do
            local m = self.nodes[e.to]
            love.graphics.setColor(colors[e.kind])
            if e.kind == 'jump' or e.kind == 'fall' then
                local x0 = e.ex or n.x
                local pts = ballistics.sample_arc(x0, n.y, e.vx, e.vy, e.t, 12)
                love.graphics.line(pts)
            else
                love.graphics.line(n.x, n.y, m.x, m.y)
            end
        end
    end
    for _, n in ipairs(self.nodes) do
        love.graphics.setColor(0.9, 1, 0.9, 0.8 * k)
        love.graphics.circle('fill', n.x, n.y, 2)
        love.graphics.setColor(0.9, 1, 0.9, 0.3 * k)
        love.graphics.line(n.x, n.y, n.x + n.nx * 6, n.y + n.ny * 6)
    end
end

return NavGraph
