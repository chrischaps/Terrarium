-- From chrischaps/Character @ 925c35b (creatures/blob.lua)
-- Blob: a pressure soft body.
--
-- A ring of points held together by edge constraints and a single area
-- (pressure) constraint, solved position-based so it never explodes. The ring
-- is carried by the anchor and rolls as it travels; landings are an impulse
-- into the floor, so the squash is real physics, not an animation. Pressure is
-- also the jump: it squats (pressure drops) and springs off (pressure spikes).
--
-- Terrarium: built from a genome (#13). `size` scales the ring, and with it
-- the body's profile: the clearance it needs, the step it rolls up, and how
-- hard it can spring, so a big blob jumps higher but no longer fits where a
-- small one goes, and each size gets its own nav graph. `pressure` is how
-- firmly it holds itself: a firm blob stays round and barely dents when it
-- lands, a soft one sags into a dome, squashes flat and wobbles back.
--
-- Terrarium: coloured from its genes (#15, bodies/skin.lua): mint to sky, and
-- glassy. Its markings ride the ring as it rolls, except a cap, which hangs
-- on top like a jelly's bell.
--
-- Terrarium: courting (#22), two blobs pulse in time. Each swells on the same
-- beat, the jar's clock, and leans in toward the other, and its markings
-- flush as it swells.
--
-- Terrarium: a hatchling (#23) is small, soft and pale, and swells in its
-- sleep (Blob:grow).

local Base = require('bodies.base')
local Genome = require('genome')
local Skin = require('bodies.skin')
local rng = require('core.rng')

local Blob = {}
Blob.__index = Blob

local fmath = require('core.fmath') -- Terrarium: the same sines compiled or not (#94)
local sqrt, sin, cos, abs, min, max, pi = math.sqrt, fmath.sin, fmath.cos, math.abs, math.min, math.max, math.pi

Blob.profile = {
    name = 'blob',
    radius = 19, height = 40, step = 20,
    walk_speed = 125, walk_accel = 520,
    jump_vx = 320, jump_vy = 520, air_accel = 520,
    anticipation = 0.18,
    hop_steps = true,
}

local N = 18
local PULSE = 1.3 -- Terrarium: seconds between a courting blob's swells (#22)
Blob.PULSE = PULSE -- (it hums on each, core/synth.lua, #28)
local R = 21 -- Terrarium: the ring's radius at size 1 (Character's blob)

-- Terrarium: the profile of a blob `size` times the standard one. A bigger
-- blob springs higher, but not in proportion to its size (jump height goes
-- with size^0.4), so the smallest still clears the stone from the soil, and
-- the biggest can no longer fit through the gaps it jumps over. One table per
-- size, so blobs of a size share it (and a nav graph).
local profiles = {}
function Blob.profile_for(size)
    if size == 1 then return Blob.profile end
    local p = profiles[size]
    if p then return p end
    local b, spring = Blob.profile, size ^ 0.2
    p = {}
    for k, v in pairs(b) do p[k] = v end
    p.size = size
    p.radius, p.height, p.step = b.radius * size, b.height * size, b.step * size
    p.walk_speed = b.walk_speed * size ^ 0.4
    p.jump_vx, p.jump_vy = b.jump_vx * spring, b.jump_vy * spring
    p.anticipation = b.anticipation * size ^ 0.5 -- a big blob squats longer
    profiles[size] = p
    return p
end

-- Terrarium: the profile a blob's nav graph is built from (#16). Sizes come in
-- Blob.BUCKETS stretches, and every blob in a stretch shares one graph, built
-- for the most limited body in it: the clearance of the biggest (the widest
-- radius, the tallest height) with the spring and step of the smallest. Every
-- blob of the stretch can travel whatever that graph offers. A small body
-- flies lower than a big one (its centre is a radius above its feet), so it
-- can clip a lip the big one clears: `min_radius` has the graph check every
-- radius in the stretch at once.
Blob.BUCKETS = 8
Blob.BUCKET_GENE = 'size' -- (#73: the gene the buckets divide, for the self-test)
local navs = {}
function Blob.nav_profile(genome)
    local k, lo, hi = Genome.bucket('blob', 'size', genome and genome.size or 1, Blob.BUCKETS)
    if navs[k] then return navs[k] end
    local small, big = Blob.profile_for(lo), Blob.profile_for(hi)
    local p = {}
    for key, v in pairs(small) do p[key] = v end
    p.size, p.sizes, p.bucket = nil, {lo, hi}, k
    p.bucket_label = string.format('sizes %.3f-%.3f', lo, hi)
    p.radius, p.height = big.radius, big.height
    p.min_radius = small.radius
    navs[k] = p
    return p
end

-- Terrarium: the body's own colours come from its skin (Skin.of)
local COLORS = {
    eye     = {0.96, 1.00, 0.98},
    eye_far = {0.96, 1.00, 0.98},
}

-- Terrarium: the parts of a blob its genes make: its size and the profile
-- that goes with it, and how firmly it holds itself. `young` (0..1) is how
-- pale it is (#23).
function Blob:take(genome, young)
    if genome then Genome.clamp(genome) end
    local size = genome and genome.size or 1
    local firm = genome and genome.pressure or 1
    self.genome = genome
    self.size, self.R = size, R * size
    self.profile = Blob.profile_for(size)
    self.nav = Blob.nav_profile(genome)
    self.edge_k = min(0.95, 0.8 * firm ^ 0.4)    -- how hard the skin holds its length
    self.area_k = min(1, 0.9 * firm ^ 0.5)       -- how hard it holds its volume
    self.sag = 260 / firm ^ 2                    -- a soft blob slumps into a dome
    self.sit = 0.96 + 0.1 * (firm - 1)           -- and its middle sits lower
    self.give = 0.55 / firm                      -- how far a landing carries into the floor
    self.dent = 0.08 / firm                      -- how much pressure a landing knocks out
    self.recover = 7 * firm                      -- how fast it fills back out
    self.rest_edge = 2 * self.R * sin(pi / N)
    self.area0 = 0.5 * N * self.R * self.R * sin(2 * pi / N)
    self.court_gap = self.R + 3 -- Terrarium: its half of the gap to a partner (#22)
    self.skin = Skin.of('blob', genome, young)
    self.skin.eye, self.skin.eye_far = COLORS.eye, COLORS.eye_far
    self.color_name = self.skin.name
end

function Blob.new(x, y, world, genome, young)
    local self = setmetatable({}, Blob)
    -- Terrarium: the body from its genes
    self:take(genome, young)
    local size = self.size
    self.mover = Base.Mover.new(x, y, self.profile)
    self.face = Base.Face.new()
    self.points = {}
    self.ax, self.ay = x, y
    self:layout(x, y)
    self.pressure = 1
    self.ardour, self.flush = 0, 0
    self.rot = 0
    self.trail = {}
    self.trail_dist = 0
    self.bubbles = {}
    for i = 1, 6 do
        self.bubbles[i] = {
            a = rng.range(rng.look, 0, 2 * pi), f = rng.range(rng.look, 0.15, 0.7),
            r = rng.range(rng.look, 1.1, 2.6) * size, drift = rng.range(rng.look, -0.4, 0.4),
        }
    end
    self.mesh = love.graphics.newMesh(N * 4 + 2, 'fan', 'stream')
    return self
end

function Blob:layout(x, y)
    local R = self.R
    for i = 1, N do
        local a = (i - 1) / N * 2 * pi
        local px, py = x + cos(a) * R, y - R + sin(a) * R
        self.points[i] = {x = px, y = py, px = px, py = py}
    end
end

-- Terrarium: grow into `genome` where it sits (#23). The ring swells about the
-- point it rests on, so it stays on the ground, and the pressure constraint
-- fills it out to its new area over the next steps.
function Blob:grow(genome, young)
    local was = self.R
    self:take(genome, young)
    local k, m = self.R / was, self.mover
    m.profile = self.profile
    for _, p in ipairs(self.points) do
        p.x, p.y = m.x + (p.x - m.x) * k, m.y + (p.y - m.y) * k
        p.px, p.py = p.x, p.y
    end
    for _, b in ipairs(self.bubbles) do b.r = b.r * k end
end

function Blob:get_name() return "Jelly Blob" end
function Blob:get_description() return "A pressure soft body that rolls and squishes" end

function Blob:anchor() return self.mover.x, self.mover.y end
function Blob:interp_points() return self.points end

function Blob:reset(x, y)
    self.mover = Base.Mover.new(x, y, self.profile)
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
    out[#out + 1] = {x = cx, y = cy, r = self.R + 5, vx = self.mover.vx, vy = self.mover.vy}
end

function Blob:light()
    local cx, cy = self:centroid()
    return cx, cy, 0.30, 0.95, 0.80, 95 * self.size
end

-- Add a velocity (px/s) to every point
function Blob:kick(vx, vy, dt)
    for _, p in ipairs(self.points) do
        p.px, p.py = p.px - vx * dt, p.py - vy * dt
    end
end

function Blob:update(dt, level, ctx)
    local R = self.R
    local m = self.mover
    local prev_state = m.state
    m:update(level, dt)
    for _, ev in ipairs(m:drain()) do
        if ev.kind == 'land' then
            -- Real squash: the body keeps falling into the floor for a moment
            self:kick(0, min(ev.impact, 700) * self.give, dt)
            self.pressure = 1 - self.dent
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
    -- Terrarium: courting, it swells on the beat its partner keeps, and leans
    -- in (#22)
    local court = ctx.court
    if court then self.court = court end
    self.ardour = self.ardour + ((court and 1 or 0) - self.ardour) * min(1, dt * 1.2)
    if self.ardour < 0.005 then self.ardour, self.court = 0, nil end
    local lean = 0
    self.flush = 0
    if self.court then
        local c, k = self.court, self.ardour
        if court and abs(c.x - m.x) > 1 then m.facing = c.x > m.x and 1 or -1 end
        local beat = (0.5 - 0.5 * cos(c.beat * 2 * pi / PULSE)) ^ 2
        target_pressure = target_pressure + k * (0.2 * beat - 0.05)
        lean = k * (c.x > m.x and 1 or -1) * R * 0.12
        self.flush = k * beat
    end
    self.pressure = self.pressure + (target_pressure - self.pressure) * min(1, dt * self.recover)

    -- Jiggle: integrate relative motion with a little sag
    local g = self.sag * dt * dt
    for _, p in ipairs(self.points) do
        local vx, vy = (p.x - p.px) * 0.982, (p.y - p.py) * 0.982
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx, p.y + vy + g
    end

    -- Soft tether of the centre to where the anchor says it should be
    cx, cy = self:centroid()
    local tx, ty = m.x + lean, m.y - R * (self.sit - 0.22 * squat)
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
                local c = (d - self.rest_edge) / d * 0.5 * self.edge_k
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
            local lambda = (target_area - A) / sum * self.area_k
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
            table.insert(self.trail, {x = m.x, y = m.y, life = 1, w = rng.range(rng.look, 4, 8) * self.size})
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
    local c = self.skin.trail
    for _, t in ipairs(self.trail) do
        local a = t.life * t.life
        love.graphics.setColor(c[1], c[2], c[3], 0.22 * a)
        love.graphics.ellipse('fill', t.x, t.y - 0.5, t.w, 1.6)
        love.graphics.setColor(1, 1, 1, 0.35 * a)
        love.graphics.ellipse('fill', t.x - 1, t.y - 1, t.w * 0.3, 0.6)
    end
end

function Blob:draw(ctx)
    local R, k = self.R, self.size
    local e = k ^ 0.6 -- Terrarium: small blobs have bigger eyes for their size
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
    local sk, marks = self.skin, {} -- Terrarium: its colours, and what glows
    local core, rimc, mark = sk.core, sk.rim, sk.mark
    local verts = {{cx + lx * 4 * k, cy + ly * 4 * k, 0, 0, core[1], core[2], core[3], core[4]}}
    for i = 0, count do
        local k = (i % count) + 1
        local x, y = out[k * 2 - 1], out[k * 2]
        local nx, ny = x - cx, y - cy
        local d = sqrt(nx * nx + ny * ny)
        if d > 0 then nx, ny = nx / d, ny / d end
        local rim = max(0, nx * lx + ny * ly)
        local r, g, b, a = rimc[1], rimc[2], rimc[3], rimc[4]
        r, g, b = r + rim * 0.45, g + rim * 0.35, b + rim * 0.15
        verts[#verts + 1] = {x, y, 0, 0, r, g, b, a}
    end
    if self.mesh:getVertexCount() ~= #verts then
        self.mesh = love.graphics.newMesh(#verts, 'fan', 'stream')
    end
    self.mesh:setVertices(verts)

    love.graphics.setColor(sk.outline)
    love.graphics.setLineWidth(2.2)
    love.graphics.setLineJoin('bevel')
    local loop = {}
    for i = 1, #out do loop[i] = out[i] end
    loop[#loop + 1], loop[#loop + 2] = out[1], out[2]
    love.graphics.line(loop)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.mesh)

    -- Terrarium: markings. A cap hangs on top like a jelly's bell, down to a
    -- scalloped hem; comb rows, spots and the inner ring ride the ring.
    local pattern = sk.pattern
    if pattern == 'capped' then
        local top = cy - R * sy
        local cap = {{cx, cy - R * 0.55 * sy, 0, 0, 1, 1, 1, 1}}
        for i = 0, count do
            local q = (i % count) + 1
            local x = cx + (out[q * 2 - 1] - cx) * 0.9
            local y = cy + (out[q * 2] - cy) * 0.9
            local hem = cy + R * sy * (-0.08 + 0.07 * cos((x - cx) / (R * sx) * 3 * pi))
            y = min(y, hem)
            cap[#cap + 1] = {x, y, 0, 0, 1, 1, 1, 0.7 + 0.3 * max(0, min(1, (hem - y) / (hem - top)))}
        end
        if not self.glow_mesh or self.glow_mesh:getVertexCount() ~= #cap then
            self.glow_mesh = love.graphics.newMesh(#cap, 'fan', 'stream')
        end
        self.glow_mesh:setVertices(cap)
        love.graphics.setColor(mark)
        love.graphics.draw(self.glow_mesh)
        marks[#marks + 1] = {'mesh', self.glow_mesh}
        marks[#marks + 1] = {'halo', cx, cy - R * 0.5 * sy, R * 1.6}
    elseif pattern == 'banded' then
        love.graphics.setColor(mark)
        love.graphics.setLineWidth(1.8 * k)
        for j = 0, 7 do
            local a = self.rot + j * pi / 4
            local ca, sa = cos(a) * R * sx, sin(a) * R * sy
            local pts = {cx + ca * 0.32, cy + sa * 0.32, cx + ca * 0.82, cy + sa * 0.82}
            love.graphics.line(pts)
            marks[#marks + 1] = {'line', pts, 1.8 * k}
        end
        love.graphics.setLineWidth(1)
    elseif pattern == 'spotted' then
        love.graphics.setColor(mark)
        for j = 1, 6 do
            local a = self.rot + (j + Skin.hash(sk.seed, j) * 0.6) * pi / 3
            local f = 0.3 + 0.42 * Skin.hash(j, sk.seed)
            local x, y, r = cx + cos(a) * R * f * sx, cy + sin(a) * R * f * sy, (1.8 + 1.2 * Skin.hash(sk.seed, j + 9)) * k
            love.graphics.circle('fill', x, y, r)
            marks[#marks + 1] = {'disc', x, y, r}
        end
    elseif pattern == 'striped' then
        local ring = {}
        for i = 1, #loop, 2 do
            ring[i], ring[i + 1] = cx + (loop[i] - cx) * 0.7, cy + (loop[i + 1] - cy) * 0.7
        end
        love.graphics.setColor(mark)
        love.graphics.setLineWidth(2 * k)
        love.graphics.line(ring)
        love.graphics.setLineWidth(1)
        marks[#marks + 1] = {'line', ring, 2 * k}
    end
    self.marks = marks

    -- Inner bubbles ride the rolling ring
    local bub = sk.bubble
    for _, b in ipairs(self.bubbles) do
        local a = b.a + self.rot
        local bx, by = cx + cos(a) * R * b.f * sx, cy + sin(a) * R * b.f * sy
        love.graphics.setColor(bub[1], bub[2], bub[3], 0.35)
        love.graphics.circle('line', bx, by, b.r)
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.circle('fill', bx - b.r * 0.3, by - b.r * 0.3, b.r * 0.3)
    end

    -- Specular highlight toward the light
    love.graphics.setColor(1, 1, 1, 0.55)
    local hx, hy = cx + lx * R * 0.55 * sx, cy + ly * R * 0.55 * sy - 2
    love.graphics.ellipse('fill', hx, hy, 4.2 * k * sx, 2.4 * k * sy)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle('fill', hx + k, hy - 0.5 * k, 1.2 * k)

    -- Eyes: upright frame, squished with the body
    local f = self.mover.facing
    local gx = self.face.gaze_x
    local ex = cx + (f * 3 + gx * 2) * k * sx
    local ey = cy - R * 0.28 * sy
    local sep = 6.5 * e * sx
    Base.draw_eye(self.face, ex - sep, ey, 3.6 * e, sx, sy, sk, false)
    Base.draw_eye(self.face, ex + sep, ey, 3.6 * e, sx, sy, sk, false)
    -- A small mouth that opens in the air
    local m = self.mover
    love.graphics.setColor(sk.outline)
    if m.state == 'air' then
        love.graphics.ellipse('fill', ex, ey + 7 * e * sy, 2.2 * e * sx, 2.6 * e * sy)
    else
        love.graphics.setLineWidth(1.2)
        love.graphics.arc('line', 'open', ex, ey + 4 * e * sy, 3 * e * sx, 0.5, pi - 0.5)
        love.graphics.setLineWidth(1)
    end
end

-- Terrarium: the markings, shining as the lamp dims (#15)
function Blob:draw_emissive(ctx)
    Skin.paint_glow(self.marks, self.skin, Skin.shine(self.skin, ctx and ctx.light, self.flush))
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

--------------------------------------------------------------------------------
-- Terrarium: what the self-test knows of a blob (#73); see Worm.LIMITS
Blob.LIMITS = {
    {measure = 'crushed', most = 0.5, says = 'lost %.0f%% of its area', scale = 100}, -- of its rest area
    {measure = 'inverted', most = 0, says = 'turned inside out'}, -- 1 once its ring has crossed itself
}

local function crosses(a, b, c, d)
    local function side(p, q, r) return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) end
    return side(a, b, c) * side(a, b, d) < 0 and side(c, d, a) * side(c, d, b) < 0
end

-- A ring that crosses itself is a blob turned inside out
local function inside_out(pts)
    local n = #pts
    for a = 1, n do
        for b = a + 2, n do
            if not (a == 1 and b == n) and crosses(pts[a], pts[a % n + 1], pts[b], pts[b % n + 1]) then return true end
        end
    end
    return false
end

-- Fold a look at blob `c` into `m`, the worst it has been: how much of its
-- area has been squeezed out, and whether it has turned inside out
function Blob.health(c, m, dt)
    m.crushed = max(m.crushed or 0, 1 - c:area() / c.area0)
    m.inverted = max(m.inverted or 0, inside_out(c.points) and 1 or 0)
    return m
end

-- How big blob `c` is built now: its size
function Blob.grown_size(c) return c.size end

-- `genome` with the body the sim works hardest for: the biggest
function Blob.heaviest(genome)
    genome.size = Genome.blob.by_name.size.real[2]
    return genome
end

-- How far either side of its anchor it lies, as a token (bodies/token.lua): its radius
function Blob.half(t) return t.R end

return Blob
