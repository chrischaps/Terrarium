-- Climb: what a body that rides any surface answers the controller (#77).
--
-- A climber's anchor `a` sits on a surface, floor, wall or ceiling, and its
-- normal (nx, ny) says which way is up. nav/controller.lua drives it node to
-- node over its surface graph (the profile's `climbs`) through this interface,
-- and only hands it to the shared ballistic mover for a leap:
--   ready()             on a surface, free to set off along it
--   airborne()          in the air
--   support()           the solid it's on
--   normal()            which way is up for it
--   crawl_to(node, dt, speed_scale)  crawl straight toward a node, easing its
--                       normal round to the node's; true on arrival
--   halt(dt)            ease to a stop
--   launch(vx, vy)      crouch for a leap (a climber whose profile `leaps` may)
--   steer(tx, ty, dt)   steer the leap toward its landing
--   plant_all()         set itself down on the surface where it is (its own:
--                       a spider's feet, a snail's foot)
--   mode                'attached', 'anticipate' or 'air'
-- Climb.into gives a body module every one of these it doesn't define itself
-- (all but plant_all). The body keeps the fields they read and write: `a`,
-- `nx`/`ny` and the normal it's easing toward (`tnx`/`tny`), `mode`, `solid`,
-- `facing`, `speed`, `pace` (how fast it's really going), `crawled` (whether
-- it crawled this step), `gait` (of its speed its body lets it go now), and
-- its `mover`.
--
-- The spider's (#14) came first, and the snail and the inchworm (#79) share it.

local Base = require('bodies.base')

local Climb = {}

local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max

function Climb:ready() return self.mode == 'attached' end
function Climb:airborne() return self.mode == 'air' end
function Climb:support() return self.solid end
function Climb:normal() return self.nx, self.ny end

-- Body frame: tangent (along the surface, toward facing) and normal (up)
function Climb:frame()
    local nx, ny = self.nx, self.ny
    local tx, ty = -ny * self.facing, nx * self.facing
    return tx, ty, nx, ny
end

-- Crawl straight toward a node; blends the normal across the move.
-- Returns true on arrival.
function Climb:crawl_to(node, dt, speed_scale)
    if self.mode ~= 'attached' then return false end
    local dx, dy = node.x - self.a.x, node.y - self.a.y
    local d = sqrt(dx * dx + dy * dy)
    local speed = self.profile.crawl_speed * (speed_scale or 1) * self.gait -- Terrarium: held back by its body
    -- Terrarium: and careful round an edge, by how far it has yet to turn
    local turn = 1 - (self.nx * node.nx + self.ny * node.ny)
    speed = speed / (1 + 2.5 * max(0, turn))
    -- Terrarium: and it gets going, rather than setting off at full speed
    -- before its legs have
    self.pace = self.pace + (speed - self.pace) * min(1, dt * 6)
    self.crawled = true
    local step = min(d, self.pace * dt)
    if d > 0.5 then
        self.a.x, self.a.y = self.a.x + dx / d * step, self.a.y + dy / d * step
        -- Face along the direction of travel relative to the current normal
        local along = dx * (-self.ny) + dy * self.nx
        if abs(along) > 0.2 * d then self.facing = along > 0 and 1 or -1 end
        self.speed = self.speed + (speed - self.speed) * min(1, dt * 8)
    end
    -- Normal eases toward the destination node's normal as we close in
    local w = (d < 34) and (1 - d / 34) or 0
    local nx = self.nx + (node.nx - self.nx) * w
    local ny = self.ny + (node.ny - self.ny) * w
    self.tnx, self.tny = nx, ny
    self.solid = (d < 16) and node.solid or self.solid
    if d <= 0.6 then
        self.solid = node.solid
        return true
    end
    return false
end

function Climb:halt(dt)
    self.speed = self.speed * max(0, 1 - dt * 10)
end

function Climb:launch(vx, vy)
    if self.mode ~= 'attached' then return false end
    self.mover = Base.Mover.new(self.a.x, self.a.y, self.profile)
    self.mover.solid = self.solid
    self.mover:launch(vx, vy)
    self.mode = 'anticipate'
    if vx ~= 0 then self.facing = vx > 0 and 1 or -1 end
    self.tnx, self.tny = 0, -1
    return true
end

function Climb:steer(tx, ty, dt)
    if self.mode == 'air' then self.mover:steer(tx, ty, dt) end
end

-- Ease the normal toward the one it's turning to (tnx, tny), at `rate` a second
function Climb:turn_normal(dt, rate)
    local k = min(1, dt * rate)
    local nx = self.nx + (self.tnx - self.nx) * k
    local ny = self.ny + (self.tny - self.ny) * k
    local d = sqrt(nx * nx + ny * ny)
    if d > 1e-4 then self.nx, self.ny = nx / d, ny / d end
end

-- Give body module `class` every part of the interface it doesn't have
local PARTS = {'ready', 'airborne', 'support', 'normal', 'frame', 'crawl_to', 'halt', 'launch', 'steer', 'turn_normal'}
function Climb.into(class)
    for _, name in ipairs(PARTS) do
        if class[name] == nil then class[name] = Climb[name] end
    end
    return class
end

--------------------------------------------------------------------------------
-- Finding the surface

-- A point inside the scenery moved to the nearest clear spot within `reach`:
-- rings of 16 directions, 1px apart. Faces alone won't do, since a stone's
-- foot is buried in the soil and the seam between them is inside both (#17).
-- Returns the point and whether it moved.
local AROUND = {}
for k = 0, 15 do AROUND[k + 1] = {math.cos(k * math.pi / 8), math.sin(k * math.pi / 8)} end
function Climb.outside(level, x, y, reach)
    if not level:solid_at(x, y) then return x, y, false end
    for r = 1, reach or 24 do
        for _, d in ipairs(AROUND) do
            local qx, qy = x + d[1] * r, y + d[2] * r
            if not level:solid_at(qx, qy) then return qx, qy, true end
        end
    end
    return x, y, false
end

-- Where a body riding (x, y) with tangent (tx, ty) and normal (nx, ny) would
-- be `d` along its surface (back along it, for d < 0), walking the real
-- geometry: on along the surface, up a face that stands across the way (a
-- concave corner), or over an edge and down its side (a convex one), a few
-- corners at most. `k` scales how far it looks for the surface. Returns the
-- point, the surface's normal there, and whether it stayed on a surface.
function Climb.along(level, x, y, tx, ty, nx, ny, d, k)
    local s = d >= 0 and 1 or -1
    local dx, dy = tx * s, ty * s -- the way it goes
    local left = abs(d)
    local feel = 2 * k            -- how far off the surface it feels for it
    for _ = 1, 4 do
        -- A face standing across the way: on to it, then up it (felt for from a
        -- little behind, so one it's in the corner of already is found too)
        local ox, oy = x + (nx - dx) * feel, y + (ny - dy) * feel
        local h = not level:solid_at(ox, oy) and level:raycast(ox, oy, dx, dy, left + feel)
        if h then
            h = max(0, h - feel)
            x, y = x + dx * h, y + dy * h -- (the corner, on both faces)
            left = left - h
            dx, dy, nx, ny = nx, ny, -dx, -dy
        else
            -- On along the surface, if it's still under it there
            local px, py = x + dx * left, y + dy * left
            local down = level:raycast(px + nx * feel, py + ny * feel, -nx, -ny, 2 * feel)
            if down and not level:solid_at(px + nx * feel, py + ny * feel) then
                local qx, qy = px + nx * (feel - down), py + ny * (feel - down)
                return qx, qy, nx, ny, true
            end
            -- Over the edge: back from below it to the side it went over, then down that
            local bx, by = px - nx * feel, py - ny * feel
            local back = not level:solid_at(bx, by) and level:raycast(bx, by, -dx, -dy, left)
            if not back then return px, py, nx, ny, false end
            local edge = left - back
            x, y = x + dx * edge, y + dy * edge
            left = back
            dx, dy, nx, ny = -nx, -ny, dx, dy
            if left < 0.01 then return x, y, nx, ny, true end
        end
        if left < 0.01 then return x, y, nx, ny, true end
    end
    return x, y, nx, ny, false
end

return Climb
