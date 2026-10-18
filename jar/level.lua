-- From chrischaps/Character @ 925c35b (world/level.lua)
-- Level: the solids of a cave plus spatial queries over them.
local collision = require('jar.collision')

local Level = {}
Level.__index = Level

function Level.new(data)
    local self = setmetatable({}, Level)
    self.data = data
    self.width = data.width
    self.height = data.height
    self.solids = {}
    self.by_id = {}
    for i, s in ipairs(data.solids) do
        local solid = {}
        for k, v in pairs(s) do solid[k] = v end
        solid.index = i
        self.solids[i] = solid
        self.by_id[s.id] = solid
    end
    return self
end

function Level:solid_at(x, y, pad)
    return collision.solid_at(self.solids, x, y, pad)
end

function Level:raycast(ox, oy, dx, dy, maxd, pad)
    return collision.raycast(self.solids, ox, oy, dx, dy, maxd, pad)
end

function Level:resolve_point(p, r, grip, bounce)
    return collision.resolve_point(self.solids, p, r, grip, bounce)
end

function Level:circle_clear(x, y, r)
    return collision.circle_clear(self.solids, x, y, r)
end

-- First walkable top surface at or below (x, y). Returns surface y and solid.
-- A point resting exactly on a top counts as "at" it.
function Level:surface_below(x, y, maxd)
    local d, _, ny, s = self:raycast(x, y - 0.5, 0, 1, maxd or 2000)
    if d and ny == -1 then
        return y - 0.5 + d, s
    end
    return nil
end

-- Top surface spans (x0, x1, y) that are exposed: not covered by another solid
-- directly on top. Used by navigation and decoration.
function Level:top_spans()
    local spans = {}
    for _, s in ipairs(self.solids) do
        local x0, x1 = math.max(s.x, 22), math.min(s.x + s.w, self.width - 22)
        if x1 > x0 and s.y > 0 and s.y < self.height then
            -- Walk across the top in small steps, splitting where covered
            local start = nil
            local step = 2
            for x = x0, x1, step do
                local open = self:solid_at(x, s.y - 1) == nil
                if open and not start then start = x end
                if (not open or x + step > x1) and start then
                    local stop = open and x1 or x - step
                    if stop - start >= 8 then
                        spans[#spans + 1] = {x0 = start, x1 = stop, y = s.y, solid = s}
                    end
                    start = nil
                end
            end
        end
    end
    return spans
end

return Level
