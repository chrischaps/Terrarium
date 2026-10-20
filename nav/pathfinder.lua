-- From chrischaps/Character @ 925c35b (core/pathfinder.lua)
-- A* over a NavGraph, with a binary heap open set and a closed set.
-- Returns a list of steps {node = n, edge = e} where edge is how we arrive at
-- n (nil for the first step).
--
-- Terrarium: `dare` (0 to 1, optional) leaves out the jumps and falls that ask
-- more of the body than that (navgraph's `edge.dare`), and makes the ones it
-- keeps cost more the timider it is, so a timid body walks the long way round.

local Pathfinder = {}

local sqrt = math.sqrt

local function h(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return sqrt(dx * dx + dy * dy)
end

-- Minimal binary heap keyed on f
local function push(heap, id, f)
    heap[#heap + 1] = {id, f}
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p][2] <= heap[i][2] then break end
        heap[p], heap[i] = heap[i], heap[p]
        i = p
    end
end

local function pop(heap)
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local i, n = 1, #heap
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if l <= n and heap[l][2] < heap[s][2] then s = l end
            if r <= n and heap[r][2] < heap[s][2] then s = r end
            if s == i then break end
            heap[s], heap[i] = heap[i], heap[s]
            i = s
        end
    end
    return top[1]
end

function Pathfinder.find(graph, start, goal, dare)
    if not start or not goal then return nil end
    if start == goal then return {{node = start}} end

    local nodes = graph.nodes
    local g, came, via, closed = {[start.id] = 0}, {}, {}, {}
    local heap = {}
    push(heap, start.id, h(start, goal))

    while #heap > 0 do
        local id = pop(heap)
        if id == goal.id then
            local path = {}
            local cur = id
            while cur do
                table.insert(path, 1, {node = nodes[cur], edge = via[cur]})
                cur = came[cur]
            end
            return path
        end
        if not closed[id] then
            closed[id] = true
            local node = nodes[id]
            for _, e in ipairs(node.edges) do
                if not closed[e.to] and not (dare and e.dare and e.dare > dare) then
                    local ng = g[id] + ((dare and e.dare) and e.cost * (1 + 2 * (1 - dare)) or e.cost)
                    if ng < (g[e.to] or math.huge) then
                        g[e.to] = ng
                        came[e.to] = id
                        via[e.to] = e
                        push(heap, e.to, ng + h(nodes[e.to], goal))
                    end
                end
            end
        end
    end
    return nil
end

return Pathfinder
