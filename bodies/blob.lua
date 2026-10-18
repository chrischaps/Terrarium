-- From chrischaps/Character @ 925c35b (creatures/blob.lua)
-- Blob: a pressure soft body.
--
-- A ring of points held together by edge constraints and a single area
-- (pressure) constraint, solved position-based so it never explodes. The ring
-- is carried by the anchor and rolls as it travels; landings are an impulse
-- into the floor, so the squash is real physics, not an animation. Pressure is
-- also the jump: it squats (pressure drops) and springs off (pressure spikes).

local Base = require('bodies.base')
local rng = require('core.rng')

local Blob = {}
Blob.__index = Blob

local sqrt, sin, cos, abs, min, max, pi = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max, math.pi

Blob.profile = {
    name = 'blob',
    radius = 19, height = 40, step = 20,
    walk_speed = 125, walk_accel = 520,
    jump_vx = 320, jump_vy = 520, air_accel = 520,
    anticipation = 0.18,
    hop_steps = true,
}

local N = 18
local R = 21

local COLORS = {
    core    = {0.56, 0.92, 0.84, 0.86},
    rim     = {0.13, 0.46, 0.54, 0.95},
    outline = {0.05, 0.20, 0.24, 1},
    shine   = {1, 1, 1},
    eye     = {0.96, 1.00, 0.98},
    eye_far = {0.96, 1.00, 0.98},
    pupil   = {0.04, 0.14, 0.16},
    trail   = {0.55, 1.00, 0.88},
}

function Blob.new(x, y, world)
    local self = setmetatable({}, Blob)
    self.profile = Blob.profile
    self.mover = Base.Mover.new(x, y, Blob.profile)
    self.face = Base.Face.new()
    self.color_name = {0.55, 1, 0.88}
    self.points = {}
    self.ax, self.ay = x, y
    self:layout(x, y)
    self.rest_edge = 2 * R * sin(pi / N)
    self.area0 = 0.5 * N * R * R * sin(2 * pi / N)
    self.pressure = 1
    self.rot = 0
    self.trail = {}
    self.trail_dist = 0
    self.bubbles = {}
    for i = 1, 6 do
        self.bubbles[i] = {
            a = rng.range(rng.look, 0, 2 * pi), f = rng.range(rng.look, 0.15, 0.7),
            r = rng.range(rng.look, 1.1, 2.6), drift = rng.range(rng.look, -0.4, 0.4),
        }
    end
    self.mesh = love.graphics.newMesh(N * 4 + 2, 'fan', 'stream')
    return self
end

function Blob:layout(x, y)
    for i = 1, N do
        local a = (i - 1) / N * 2 * pi
        local px, py = x + cos(a) * R, y - R + sin(a) * R
        self.points[i] = {x = px, y = py, px = px, py = py}
    end
end

function Blob:get_name() return "Jelly Blob" end
function Blob:get_description() return "A pressure soft body that rolls and squishes" end

function Blob:anchor() return self.mover.x, self.mover.y end
function Blob:interp_points() return self.points end

function Blob:reset(x, y)
    self.mover = Base.Mover.new(x, y, Blob.profile)
    self.ax, self.ay = x, y
    self:layout(x, y)
end

function Blob:centroid()
    local cx, cy = 0, 0
    for _, p in ipairs(self.points) do cx, cy = cx + p.x, cy + p.y end
    return cx / N, cy / N
end

function Blob:area()
    local a = 0
    local pts = self.points
    for i = 1, N do
        local p, q = pts[i], pts[i % N + 1]
        a = a + (p.x * q.y - q.x * p.y)
    end
    return a * 0.5
end

function Blob:influencers(out)
    local cx, cy = self:centroid()
    out[#out + 1] = {x = cx, y = cy, r = R + 5, vx = self.mover.vx, vy = self.mover.vy}
end

function Blob:light()
    local cx, cy = self:centroid()
    return cx, cy, 0.30, 0.95, 0.80, 95
end

-- Add a velocity (px/s) to every point
function Blob:kick(vx, vy, dt)
    for _, p in ipairs(self.points) do
        p.px, p.py = p.px - vx * dt, p.py - vy * dt
    end
end

function Blob:update(dt, level, ctx)
    local m = self.mover
    local prev_state = m.state
    m:update(level, dt)
    for _, ev in ipairs(m:drain()) do
        if ev.kind == 'land' then
            -- Real squash: the body keeps falling into the floor for a moment
            self:kick(0, min(ev.impact, 700) * 0.55, dt)
            self.pressure = 0.92
            ctx.events:emit('land', {x = m.x, y = m.y, impact = ev.impact, who = self})
        elseif ev.kind == 'jump' then
            -- Spring off: stretch upward, pressure spike
            for _, p in ipairs(self.points) do
                local cx, cy = self:centroid()
                if p.y < cy then p.py = p.py + 1.4 end
            end
            self.pressure = 1.12
            ctx.events:emit('jump', {x = m.x, y = m.y, vx = ev.vx, vy = ev.vy, who = self})
        end
    end

    -- Carry the ring with the anchor (no velocity injected)
    local dx, dy = m.x - self.ax, m.y - self.ay
    self.ax, self.ay = m.x, m.y
    local cx, cy = self:centroid()

    -- Rolling: rotate the ring about its centre in proportion to travel
    local droll = (m.state == 'ground') and dx / R or dx / R * 0.25
    self.rot = self.rot + droll
    local cr, sr = cos(droll), sin(droll)
    for _, p in ipairs(self.points) do
        local rx, ry = p.x - cx, p.y - cy
        local qx, qy = p.px - cx, p.py - cy
        p.x, p.y = cx + rx * cr - ry * sr + dx, cy + rx * sr + ry * cr + dy
        p.px, p.py = cx + qx * cr - qy * sr + dx, cy + qx * sr + qy * cr + dy
    end

    -- Squat while anticipating a jump
    local squat = m.state == 'anticipate' and 1 or 0
    local target_pressure = 1 - 0.2 * squat
    self.pressure = self.pressure + (target_pressure - self.pressure) * min(1, dt * 7)

    -- Jiggle: integrate relative motion with a little sag
    local g = 260 * dt * dt
    for _, p in ipairs(self.points) do
        local vx, vy = (p.x - p.px) * 0.982, (p.y - p.py) * 0.982
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx, p.y + vy + g
    end

    -- Soft tether of the centre to where the anchor says it should be
    cx, cy = self:centroid()
    local tx, ty = m.x, m.y - R * (0.96 - 0.22 * squat)
    local k = 0.16
    local ox, oy = (tx - cx) * k, (ty - cy) * k
    for _, p in ipairs(self.points) do
        p.x, p.y = p.x + ox, p.y + oy
    end

    -- Constraints
    local pts = self.points
    local target_area = self.area0 * self.pressure
    local air = m.state == 'air'
    for _ = 1, 5 do
        for i = 1, N do
            local a, b = pts[i], pts[i % N + 1]
            local ex, ey = b.x - a.x, b.y - a.y
            local d = sqrt(ex * ex + ey * ey)
            if d > 1e-5 then
                local c = (d - self.rest_edge) / d * 0.5 * 0.8
                a.x, a.y = a.x + ex * c, a.y + ey * c
                b.x, b.y = b.x - ex * c, b.y - ey * c
            end
        end
        -- Area (pressure): move each point along its area gradient
        local A = self:area()
        local grads, sum = {}, 0
        for i = 1, N do
            local prev, nxt = pts[(i - 2) % N + 1], pts[i % N + 1]
            local gx, gy = 0.5 * (nxt.y - prev.y), 0.5 * (prev.x - nxt.x)
            grads[i] = gx; grads[i + N] = gy
            sum = sum + gx * gx + gy * gy
        end
        if sum > 1e-6 then
            local lambda = (target_area - A) / sum * 0.9
            for i = 1, N do
                local p = pts[i]
                p.x, p.y = p.x + grads[i] * lambda, p.y + grads[i + N] * lambda
            end
        end
        for i = 1, N do
            level:resolve_point(pts[i], 1.5, air and 0.95 or 0.7, 0.05)
        end
    end

    -- Slime trail
    if m.state == 'ground' and abs(dx) > 0 then
        self.trail_dist = self.trail_dist + abs(dx)
        if self.trail_dist > 7 then
            self.trail_dist = 0
            table.insert(self.trail, {x = m.x, y = m.y, life = 1, w = rng.range(rng.look, 4, 8)})
            if #self.trail > 120 then table.remove(self.trail, 1) end
        end
    end
    for i = #self.trail, 1, -1 do
        local t = self.trail[i]
        t.life = t.life - dt / 7
        if t.life <= 0 then table.remove(self.trail, i) end
    end

    -- Face
    local idle = m.state == 'ground' and abs(m.vx) < 5
    local lx, ly = m.facing * 0.6, 0
    if ctx.look_at then
        local ddx, ddy = ctx.look_at.x - cx, ctx.look_at.y - cy
        local d = sqrt(ddx * ddx + ddy * ddy)
        if d > 1 then lx, ly = ddx / d, ddy / d end
    end
    if m.state == 'air' then ly = m.vy > 0 and 0.6 or -0.5 end
    self.face:update(dt, lx, ly, idle and not ctx.look_at)
    for _, b in ipairs(self.bubbles) do
        b.a = b.a + b.drift * dt
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function Blob:outline_points(steps)
    local pts = self.points
    local out = {}
    for i = 1, N do
        local p0, p1 = pts[(i - 2) % N + 1], pts[i]
        local p2, p3 = pts[i % N + 1], pts[(i + 1) % N + 1]
        for s = 0, steps - 1 do
            local t = s / steps
            local t2, t3 = t * t, t * t * t
            out[#out + 1] = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            out[#out + 1] = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        end
    end
    return out
end

function Blob:draw_trail()
    for _, t in ipairs(self.trail) do
        local a = t.life * t.life
        love.graphics.setColor(COLORS.trail[1], COLORS.trail[2], COLORS.trail[3], 0.22 * a)
        love.graphics.ellipse('fill', t.x, t.y - 0.5, t.w, 1.6)
        love.graphics.setColor(1, 1, 1, 0.35 * a)
        love.graphics.ellipse('fill', t.x - 1, t.y - 1, t.w * 0.3, 0.6)
    end
end

function Blob:draw(ctx)
    local cx, cy = self:centroid()
    local out = self:outline_points(4)
    local count = #out / 2
    local lx, ly = ctx.light_dir(cx, cy)

    -- Extent for eye squish
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, count do
        local x, y = out[i * 2 - 1], out[i * 2]
        minx, maxx = min(minx, x), max(maxx, x)
        miny, maxy = min(miny, y), max(maxy, y)
    end
    local sx, sy = (maxx - minx) / (2 * R), (maxy - miny) / (2 * R)

    -- Body fan: bright core offset toward the light, deep rim
    local verts = {{cx + lx * 4, cy + ly * 4, 0, 0, COLORS.core[1], COLORS.core[2], COLORS.core[3], COLORS.core[4]}}
    for i = 0, count do
        local k = (i % count) + 1
        local x, y = out[k * 2 - 1], out[k * 2]
        local nx, ny = x - cx, y - cy
        local d = sqrt(nx * nx + ny * ny)
        if d > 0 then nx, ny = nx / d, ny / d end
        local rim = max(0, nx * lx + ny * ly)
        local r, g, b, a = COLORS.rim[1], COLORS.rim[2], COLORS.rim[3], COLORS.rim[4]
        r, g, b = r + rim * 0.45, g + rim * 0.35, b + rim * 0.15
        verts[#verts + 1] = {x, y, 0, 0, r, g, b, a}
    end
    if self.mesh:getVertexCount() ~= #verts then
        self.mesh = love.graphics.newMesh(#verts, 'fan', 'stream')
    end
    self.mesh:setVertices(verts)

    love.graphics.setColor(COLORS.outline)
    love.graphics.setLineWidth(2.2)
    love.graphics.setLineJoin('bevel')
    local loop = {}
    for i = 1, #out do loop[i] = out[i] end
    loop[#loop + 1], loop[#loop + 2] = out[1], out[2]
    love.graphics.line(loop)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.mesh)

    -- Inner bubbles ride the rolling ring
    for _, b in ipairs(self.bubbles) do
        local a = b.a + self.rot
        local bx, by = cx + cos(a) * R * b.f * sx, cy + sin(a) * R * b.f * sy
        love.graphics.setColor(0.85, 1, 0.95, 0.35)
        love.graphics.circle('line', bx, by, b.r)
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.circle('fill', bx - b.r * 0.3, by - b.r * 0.3, b.r * 0.3)
    end

    -- Specular highlight toward the light
    love.graphics.setColor(1, 1, 1, 0.55)
    local hx, hy = cx + lx * R * 0.55 * sx, cy + ly * R * 0.55 * sy - 2
    love.graphics.ellipse('fill', hx, hy, 4.2 * sx, 2.4 * sy)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle('fill', hx + 1, hy - 0.5, 1.2)

    -- Eyes: upright frame, squished with the body
    local f = self.mover.facing
    local gx = self.face.gaze_x
    local ex = cx + (f * 3 + gx * 2) * sx
    local ey = cy - R * 0.28 * sy
    local sep = 6.5 * sx
    Base.draw_eye(self.face, ex - sep, ey, 3.6, sx, sy, COLORS, false)
    Base.draw_eye(self.face, ex + sep, ey, 3.6, sx, sy, COLORS, false)
    -- A small mouth that opens in the air
    local m = self.mover
    love.graphics.setColor(COLORS.outline)
    if m.state == 'air' then
        love.graphics.ellipse('fill', ex, ey + 7 * sy, 2.2 * sx, 2.6 * sy)
    else
        love.graphics.setLineWidth(1.2)
        love.graphics.arc('line', 'open', ex, ey + 4 * sy, 3 * sx, 0.5, pi - 0.5)
        love.graphics.setLineWidth(1)
    end
end

-- X-ray: the ring, its edge constraints and the pressure pushing outward
function Blob:draw_xray(ctx)
    local c = self.color_name
    local cx, cy = self:centroid()
    local pts = self.points
    love.graphics.setLineWidth(1)
    for _, p in ipairs(pts) do
        love.graphics.setColor(c[1], c[2], c[3], 0.22)
        love.graphics.line(cx, cy, p.x, p.y)
    end
    local ring = {}
    for _, p in ipairs(pts) do ring[#ring + 1] = p.x; ring[#ring + 1] = p.y end
    ring[#ring + 1], ring[#ring + 2] = pts[1].x, pts[1].y
    love.graphics.setLineWidth(1.4)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.line(ring)
    for _, p in ipairs(pts) do
        love.graphics.setColor(1, 1, 0.95, 0.95)
        love.graphics.circle('fill', p.x, p.y, 1.4)
    end
    love.graphics.setColor(c[1], c[2], c[3], 0.5)
    love.graphics.circle('line', cx, cy, 3)
    love.graphics.setColor(1, 1, 0.95, 0.6)
    love.graphics.line(self.mover.x - 3, self.mover.y, self.mover.x + 3, self.mover.y)
    love.graphics.setLineWidth(1)
end

function Blob:draw_debug()
    love.graphics.setColor(0.6, 1, 0.9, 0.6)
    for i, p in ipairs(self.points) do
        local q = self.points[i % N + 1]
        love.graphics.line(p.x, p.y, q.x, q.y)
        love.graphics.circle('fill', p.x, p.y, 1.5)
    end
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.circle('fill', self.mover.x, self.mover.y, 2.5)
end

return Blob
