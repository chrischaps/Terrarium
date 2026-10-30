-- From chrischaps/Character @ 925c35b (creatures/worm.lua)
-- Worm: a verlet body that crawls.
--
-- The head rides the anchor; the body is a chain of verlet points with ground
-- friction. While walking, a peristaltic wave travels tail-ward: segments
-- bunch up and arch, and the head surges forward in time with it, so the body
-- looks like it is doing the work. Drawn as a tapered mesh along a smoothed
-- spine, shaded dorsal-to-belly with a rim of light from the cave mouth.
--
-- Terrarium: built from a genome (#12). `segments` is its length and how many
-- bunches run down it while it crawls: a short worm inches along under one
-- hump, a long one ripples with three. `stiffness` is muscle tone: a stiff worm
-- carries its own weight and holds a line out over a ledge, a loose one bears
-- less of it and drapes, and bunches deeper as it crawls.
--
-- Terrarium: a worm never crawls tail-first. When its way lies back along its
-- own body it turns: the head rears a little and crawls back over its back,
-- and the body follows it like a rope (its segments only pull, never push),
-- so a fold runs down the body until the tail comes round behind.
--
-- Terrarium: coloured from its genes (#15, bodies/skin.lua): rose to apricot,
-- with its markings in the skin's mark colour, glowing at night.
--
-- Terrarium: courting (#22), two worms coil together. Each one's head loops
-- round the point between them, half a turn from its partner's, so the two
-- bodies follow their heads up and over each other and twine; and the
-- markings flush with every turn.
--
-- Terrarium: a hatchling (#23) is short, loose and pale, and grows in its
-- sleep: Worm:grow adds segments at its tail.

local sq = require('core.fmath').sq -- Terrarium: x ^ 2 isn't one number in LuaJIT (#94)
local Base = require('bodies.base')
local Genome = require('genome')
local Skin = require('bodies.skin')

local Worm = {}
Worm.__index = Worm

local sqrt, sin, cos, abs, min, max = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max
local G = 980

Worm.profile = {
    name = 'worm',
    radius = 9, height = 22, step = 22,
    walk_speed = 96, walk_accel = 700,
    jump_vx = 300, jump_vy = 480, air_accel = 600,
    anticipation = 0.16,
}

-- Terrarium: the profile a worm's nav graph is built from (#16). A worm's
-- length and stiffness change how it crawls, not where it fits or how far it
-- jumps, so every worm shares Character's graph.
function Worm.nav_profile(genome) return Worm.profile end

local SEGMENTS = 13 -- Terrarium: a worm built without a genome (Character's)
local SEG_LEN = 8.5
local FOLD = 0.6 -- Terrarium: the shortest a segment gets in the fold of a turn
-- Terrarium: the stiffness every tone below was tuned at (Character's worm).
-- It's the middle of the gene's range.
local STIFF = 0.55

-- Terrarium: bunches along a worm of n segments while it crawls (10 -> 1, 24 -> 3)
local function bunches(n) return 1 + (n - 10) / 7 end

-- Terrarium: courting (#22)
local COURT_GAP = 9       -- its half of the gap between it and a partner
local COIL = 0.12        -- the ring its head makes, in radius per unit of its length
local COIL_SPIN = 1.6     -- radians a second round it
Worm.COIL_SPIN = COIL_SPIN -- (its song keeps the turn, core/synth.lua, #28)

-- Terrarium: the body's own colours come from its skin (Skin.of); these are
-- the lamp's light on it and its eyes
local COLORS = {
    rim      = {1.00, 0.78, 0.48},
    eye      = {1.00, 0.96, 0.88},
    eye_far  = {0.80, 0.72, 0.70},
    pupil    = {0.10, 0.05, 0.08},
}

-- Terrarium: the parts of a worm its genes make: its length, its tone, its
-- clitellum and how thick each segment is. `young` (0..1) is how pale it is (#23).
function Worm:take(genome, young)
    if genome then Genome.clamp(genome) end
    self.skin = Skin.of('worm', genome, young)
    self.skin.rim, self.skin.eye, self.skin.eye_far, self.skin.pupil = COLORS.rim, COLORS.eye, COLORS.eye_far, COLORS.pupil
    self.color_name = self.skin.name
    local n = genome and genome.segments or SEGMENTS
    local stiff = (genome and genome.stiffness or STIFF) / STIFF
    self.genome = genome
    self.n = n
    self.wave = 2 * math.pi * bunches(n) / (n - 1) -- radians of crawl wave per segment
    self.tone = sq(stiff)                         -- leaning on the line of the segments ahead
    self.reach = 1 / stiff                        -- how fast that fades toward the tail
    self.bend = stiff ^ 0.5                       -- smoothing each joint
    self.bear = min(1, 0.4 / stiff)               -- the share of its weight it doesn't carry
    self.squeeze = 0.24 * stiff ^ -0.5            -- how short a bunched segment gets
    self.band = math.floor(0.35 * (n - 1) + 0.5) + 1 -- the clitellum, a third of the way down
    self.radii = {}
    for i = 1, n do
        local t = (i - 1) / (n - 1)
        local r = 8.6 * (1 - t) ^ 0.75 + 2.4 * t
        if i == self.band or i == self.band + 1 then r = r + 1.1 end   -- the band (clitellum)
        self.radii[i] = r
    end
end

function Worm.new(x, y, world, genome, young)
    local self = setmetatable({}, Worm)
    self.world = world
    self.profile = Worm.profile
    self.nav = Worm.nav_profile(genome)
    self.mover = Base.Mover.new(x, y, Worm.profile)
    self.face = Base.Face.new()
    -- Terrarium: the body from its genes
    self:take(genome, young)
    local n = self.n
    self.points = {}
    local dir = Worm.layout_dir(world and world.level, x, y, 1, n)
    for i = 1, n do
        local px = x - (i - 1) * SEG_LEN * dir
        self.points[i] = {x = px, y = y - 7, px = px, py = y - 7}
    end
    self.phase = 0
    self.head_lift = 0
    self.coil = 0
    self.squash = 0
    self.look_x, self.look_y = 1, 0
    self.court_gap = COURT_GAP -- Terrarium: its half of the gap to a partner (#22)
    self.ardour, self.flush = 0, 0
    self.mesh = nil
    return self
end

-- Terrarium: grow into `genome` where it lies (#23). New segments come at the
-- tail, the way an earthworm's do, each laid on along the line of the last
-- two (or on the last, if that line runs into the scenery), and the chain
-- settles them in its next steps.
function Worm:grow(genome, young)
    local level = self.world and self.world.level
    self:take(genome, young)
    local pts = self.points
    while #pts < self.n do
        local a, b = pts[#pts - 1], pts[#pts]
        local dx, dy = b.x - a.x, b.y - a.y
        local d = sqrt(dx * dx + dy * dy)
        local x, y = b.x, b.y
        if d > 0.01 then x, y = b.x + dx / d * SEG_LEN, b.y + dy / d * SEG_LEN end
        if level and level:solid_at(x, y) then x, y = b.x, b.y end
        pts[#pts + 1] = {x = x, y = y, px = x, py = y}
    end
end

function Worm:get_name() return "Earthworm" end
function Worm:get_description() return "A verlet chain that crawls by peristalsis" end

function Worm:anchor() return self.mover.x, self.mover.y end
function Worm:interp_points() return self.points end

-- Which way to lay the body from a head at (x, y): behind the facing
-- direction if the whole line is clear, otherwise the other way
function Worm.layout_dir(level, x, y, facing, n)
    local function clear(dir)
        if not level then return true end
        for i = 1, (n or SEGMENTS) - 1 do
            if level:solid_at(x - i * SEG_LEN * dir, y - 7) then return false end
        end
        return true
    end
    if clear(facing) then return facing end
    if clear(-facing) then return -facing end
    return facing
end

function Worm:reset(x, y, facing)
    facing = facing or 1
    self.mover = Base.Mover.new(x, y, Worm.profile)
    local dir = Worm.layout_dir(self.world and self.world.level, x, y, facing, self.n)
    self.mover.facing = dir
    self.turning = nil
    for i, p in ipairs(self.points) do
        p.x, p.y = x - (i - 1) * SEG_LEN * dir, y - 7
        p.px, p.py = p.x, p.y
    end
end

-- Circles other things (flora, fireflies) should get out of the way of
function Worm:influencers(out)
    for i = 1, #self.points, 3 do
        local p = self.points[i]
        out[#out + 1] = {x = p.x, y = p.y, r = self.radii[i] + 6, vx = (p.x - p.px) * 120, vy = (p.y - p.py) * 120}
    end
end

function Worm:light()
    local p = self.points[1]
    return p.x, p.y, 0, 0, 0, 0
end

-- Terrarium: turning. It starts when the head sets off back along its own
-- body, and goes on until the fold has run out of the body (nothing lies
-- further back than the tail) with the tail behind the head. A worm that stops
-- halfway lies folded until it moves again. Heading back the other way is
-- another turn, and leaving the ground ends it.
function Worm:update_turn()
    local m, pts = self.mover, self.points
    local going = (m.state == 'ground' and abs(m.vx) > 5) and (m.vx > 0 and 1 or -1) or 0
    local head, tail = pts[1], pts[#pts]
    if self.turning then
        if m.state ~= 'ground' then
            self.turning = nil
        elseif going ~= 0 then
            self.turning = going
            local t, folded = going, false
            for i = 1, #pts - 1 do
                if pts[i].x * t < tail.x * t - 2 then folded = true break end
            end
            if not folded and (head.x - tail.x) * t > SEG_LEN then self.turning = nil end
        end
    end
    if not self.turning and going ~= 0 then
        local mid = pts[math.ceil(#pts / 2)]
        if (head.x - mid.x) * going < -SEG_LEN then self.turning = going end
    end
end

function Worm:update(dt, level, ctx)
    local m = self.mover
    self.clock = (self.clock or 0) + dt
    -- The head surges in time with the body wave
    if m.want_dir and m.want_dir ~= 0 then
        local surge = 0.5 + 0.5 * sin(self.phase + 1.2)
        m.want_speed = (m.want_speed or self.profile.walk_speed) * (0.55 + 0.75 * surge)
        -- Terrarium: and slows to come round
        if self.turning then m.want_speed = m.want_speed * 0.6 end
    end
    m:update(level, dt)
    self:update_turn()
    for _, ev in ipairs(m:drain()) do
        if ev.kind == 'land' then
            self.squash = min(1, ev.impact / 500)
            ctx.events:emit('land', {x = m.x, y = m.y, impact = ev.impact, who = self})
        elseif ev.kind == 'jump' then
            ctx.events:emit('jump', {x = m.x, y = m.y, vx = ev.vx, vy = ev.vy, who = self})
        end
    end

    local moving = m.state == 'ground' and abs(m.vx) > 5
    local speed_frac = min(1, abs(m.vx) / self.profile.walk_speed)
    if moving then
        self.phase = self.phase + dt * 9 * (0.4 + speed_frac)
    end

    -- Head target: anchor, lifted a little when idle, dipped while coiling
    local idle = m.state == 'ground' and not moving
    local want_lift = idle and (3.5 + 1.8 * sin(self.clock * 1.3)) or (moving and 2 or 0)
    if self.turning then want_lift = self.radii[1] * 1.4 end -- Terrarium: rears to cross its back
    if m.state == 'anticipate' then want_lift = -2 end
    self.head_lift = self.head_lift + (want_lift - self.head_lift) * min(1, dt * 6)
    self.coil = self.coil + (((m.state == 'anticipate') and 1 or 0) - self.coil) * min(1, dt * 14)
    self.squash = max(0, self.squash - dt * 5)

    local head = self.points[1]
    local hr = self.radii[1]
    local hx, hy = m.x, m.y - hr + 1 - self.head_lift
    if m.state == 'air' then hy = m.y - hr end
    -- Terrarium: courting, the head loops round the point between the two,
    -- half a turn from its partner's (#22)
    local court = ctx.court
    if court then self.court = court end
    self.ardour = self.ardour + ((court and 1 or 0) - self.ardour) * min(1, dt * 1.2)
    if self.ardour < 0.005 then self.ardour, self.court = 0, nil end
    self.flush = 0
    if self.court and m.state == 'ground' then
        local c, k = self.court, self.ardour
        if court and abs(c.x - m.x) > 1 then m.facing = c.x > m.x and 1 or -1 end
        local a = c.beat * COIL_SPIN + (c.side > 0 and 0 or math.pi)
        local r = COIL * self.n * SEG_LEN
        local cx, cy = (m.x + c.x) * 0.5, m.y - hr - r
        hx = hx + (cx + r * cos(a) - hx) * k
        hy = hy + (cy - r * sin(a) - hy) * k
        self.flush = k * (0.5 + 0.5 * sin(a))
    end
    head.px, head.py = head.x, head.y
    head.x, head.y = hx, hy

    -- Integrate the body
    local air = m.state == 'air'
    local damp = air and 0.996 or 0.985
    -- A worm holds its own body (a muscular hydrostat): on the ground only part
    -- of gravity reaches the body, so a tail over a ledge droops instead of
    -- hanging straight down. In flight it trails with full weight.
    local g = G * dt * dt * (air and 1 or self.bear)
    for i = 2, #self.points do
        local p = self.points[i]
        local vx, vy = (p.x - p.px) * damp, (p.y - p.py) * damp
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx, p.y + vy + g
        -- Peristaltic arch: compressed segments lift
        if moving then
            local w = sin(self.phase - i * self.wave)
            if w > 0.3 and p.contact then
                p.y = p.y - w * 0.35
            end
        end
    end

    -- Constraints: rest lengths ripple with the peristaltic wave
    for _ = 1, 6 do
        for i = 1, #self.points - 1 do
            local a, b = self.points[i], self.points[i + 1]
            local rest = SEG_LEN
            if moving and not self.turning then
                rest = rest * (1 - self.squeeze * max(0, sin(self.phase - i * self.wave)))
            end
            rest = rest * (1 - 0.3 * self.coil)
            local dx, dy = b.x - a.x, b.y - a.y
            local d = sqrt(dx * dx + dy * dy)
            -- Terrarium: turning, the body only follows (see the top), though
            -- no segment gives way past FOLD of its length, or a long soft
            -- worm's fold bunches into a zigzag instead of one bend
            if self.turning and d < rest then rest = max(d, rest * FOLD) end
            if d > 0.0001 and d ~= rest then
                local diff = (d - rest) / d
                if i == 1 then
                    b.x, b.y = b.x - dx * diff, b.y - dy * diff
                else
                    a.x, a.y = a.x + dx * diff * 0.5, a.y + dy * diff * 0.5
                    b.x, b.y = b.x - dx * diff * 0.5, b.y - dy * diff * 0.5
                end
            end
        end
        -- Bending stiffness: nudge each joint toward its neighbours' midpoint
        -- so the spine curves instead of kinking
        -- (Terrarium: not while turning; with nothing pushing back it would
        -- gather the body into a lump instead of letting it fold)
        for i = 2, self.turning and 0 or #self.points - 1 do
            local a, p, b = self.points[i - 1], self.points[i], self.points[i + 1]
            local mx, my = (a.x + b.x) * 0.5, (a.y + b.y) * 0.5
            local k = ((i == 2) and 0.22 or 0.12) * (air and 1 or 1.6) * self.bend
            p.x, p.y = p.x + (mx - p.x) * k, p.y + (my - p.y) * k
        end
        -- Muscle tone (ground only): each segment leans toward carrying on
        -- the line of the two before it, strongest near the head, so a body
        -- over a ledge holds a drooping curve instead of hanging plumb.
        -- Terrarium: it holds the body up, never a tail up in the air: a line
        -- that rises is only half carried on, so a tail left raised by a jump
        -- settles back down instead of standing propped against the glass.
        if not air then
            for i = 3, #self.points do
                local a, b, p = self.points[i - 2], self.points[i - 1], self.points[i]
                local rise = b.y - a.y
                local ex, ey = b.x + (b.x - a.x), b.y + (rise < 0 and rise * 0.5 or rise)
                local k = 0.09 * self.tone * (1 - (i - 3) / #self.points) ^ self.reach
                if self.turning then k = k * 0.25 end -- Terrarium: let the fold bend
                p.x, p.y = p.x + (ex - p.x) * k, p.y + (ey - p.y) * k
            end
        end
        -- Collide body with the world; grounded segments grip
        for i = 2, #self.points do
            local p = self.points[i]
            local s, nx, ny = level:resolve_point(p, self.radii[i] * 0.85, air and 0.95 or 0.55, 0)
            p.contact = s and ny == -1
        end
    end

    -- Follow the leader: however fast the head moved, no segment may trail
    -- more than a little past its rest length (stops the body stretching
    -- like elastic on long drops)
    for i = 2, #self.points do
        local a, b = self.points[i - 1], self.points[i]
        local dx, dy = b.x - a.x, b.y - a.y
        local d = sqrt(dx * dx + dy * dy)
        local limit = SEG_LEN * 1.12
        if d > limit then
            local k = limit / d
            local nx, ny = a.x + dx * k, a.y + dy * k
            -- keep the velocity consistent with the correction
            b.px, b.py = b.px + (nx - b.x), b.py + (ny - b.y)
            b.x, b.y = nx, ny
        end
    end

    -- Face
    local tx, ty = ctx.look_at and ctx.look_at.x, ctx.look_at and ctx.look_at.y
    local lx, ly = m.facing, 0
    if tx then
        local dx, dy = tx - head.x, ty - head.y
        local d = sqrt(dx * dx + dy * dy)
        if d > 1 then lx, ly = dx / d, dy / d end
    end
    self.face:update(dt, lx, ly, idle and not tx)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- Catmull-Rom smoothed spine: returns arrays of x, y, radius
local function spine(points, radii, steps)
    local xs, ys, rs = {}, {}, {}
    local n = #points
    for i = 1, n - 1 do
        local p0 = points[max(1, i - 1)]
        local p1, p2 = points[i], points[i + 1]
        local p3 = points[min(n, i + 2)]
        for s = 0, steps - 1 do
            local t = s / steps
            local t2, t3 = t * t, t * t * t
            xs[#xs + 1] = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            ys[#ys + 1] = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            rs[#rs + 1] = radii[i] + (radii[i + 1] - radii[i]) * t
        end
    end
    xs[#xs + 1], ys[#ys + 1], rs[#rs + 1] = points[n].x, points[n].y, radii[n]
    return xs, ys, rs
end

-- Shade a vertex on the body surface by which way its normal faces.
-- Terrarium: in the worm's own skin, with `w` of its mark colour laid over.
local function shade(sk, nx, ny, lx, ly, band, w)
    local up = (-ny + 1) * 0.5                     -- 1 = faces sky, 0 = faces floor
    local r, g, b = Base.mix(sk.belly, band and sk.band or sk.back, up ^ 0.8)
    if w and w > 0 then
        local m = sk.mark
        r, g, b = r + (m[1] - r) * w, g + (m[2] - g) * w, b + (m[3] - b) * w
    end
    local rim = max(0, nx * lx + ny * ly)
    rim = rim * rim * 0.55
    return min(1, r + (COLORS.rim[1] - r) * rim), min(1, g + (COLORS.rim[2] - g) * rim),
           min(1, b + (COLORS.rim[3] - b) * rim)
end

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

-- Terrarium: how much of the mark colour the skin wears `t` segments back
-- from the head, for the patterns laid into the body itself (#15). Bands are
-- about a segment wide, two and a bit apart, and leave the clitellum bare.
local function mark_at(pattern, t, band)
    if pattern == 'capped' then return clamp01((2.2 - t) / 0.8) end
    if pattern == 'banded' and not band and t > 1.6 then
        local f = (t / 2.2) % 1
        return clamp01((0.2 - abs(f - 0.5)) / 0.06 + 0.5)
    end
    return 0
end

function Worm:draw(ctx)
    local sk = self.skin
    local xs, ys, rs = spine(self.points, self.radii, 4)
    local n = #xs
    local lx, ly = ctx.light_dir(xs[1], ys[1])
    local marks = {} -- Terrarium: what glows, for draw_emissive

    -- Squash on landing: fatten the head end briefly
    local sq = self.squash
    if sq > 0 then
        for i = 1, min(n, 16) do
            rs[i] = rs[i] * (1 + sq * 0.35 * (1 - i / 16))
        end
    end

    -- Per-sample normals
    local nxs, nys = {}, {}
    for i = 1, n do
        local a, b = max(1, i - 1), min(n, i + 1)
        local tx, ty = xs[b] - xs[a], ys[b] - ys[a]
        local d = sqrt(tx * tx + ty * ty)
        if d < 1e-5 then tx, ty, d = 1, 0, 1 end
        nxs[i], nys[i] = -ty / d, tx / d
    end

    -- Outline silhouette: a union of discs can't fold over itself
    love.graphics.setColor(sk.outline)
    for i = 1, n do
        love.graphics.circle('fill', xs[i], ys[i], rs[i] + 1.4)
    end
    -- Body underlay in the mid tone (covers any fold in the mesh's inner edge)
    for i = 1, n, 2 do
        love.graphics.setColor(shade(sk, 0, 0.2, lx, ly, false, mark_at(sk.pattern, (i - 1) / 4, false)))
        love.graphics.circle('fill', xs[i], ys[i], rs[i] * 0.98)
    end

    -- Body mesh: three vertices per sample (edge, spine, edge)
    local verts, glow = {}, {}
    local band_lo, band_hi = (self.band - 1) * 4, (self.band + 1) * 4
    for i = 1, n do
        local band = i >= band_lo and i <= band_hi
        local w = mark_at(sk.pattern, (i - 1) / 4, band)
        local x, y, r = xs[i], ys[i], rs[i]
        local nx, ny = nxs[i], nys[i]
        local ar, ag, ab = shade(sk, nx, ny, lx, ly, band, w)
        local cr, cg, cb = shade(sk, 0, -0.35, lx, ly, band, w)
        local br, bg, bb = shade(sk, -nx, -ny, lx, ly, band, w)
        verts[#verts + 1] = {x + nx * r, y + ny * r, 0, 0, ar, ag, ab, 1}
        verts[#verts + 1] = {x, y, 0, 0, cr * 1.04, cg * 1.04, cb * 1.04, 1}
        verts[#verts + 1] = {x - nx * r, y - ny * r, 0, 0, br, bg, bb, 1}
        -- Terrarium: the same strip, lit only where it's marked, for the glow
        glow[#glow + 1] = {x + nx * r * 0.8, y + ny * r * 0.8, 0, 0, 1, 1, 1, w * 0.4}
        glow[#glow + 1] = {x, y, 0, 0, 1, 1, 1, w}
        glow[#glow + 1] = {x - nx * r * 0.8, y - ny * r * 0.8, 0, 0, 1, 1, 1, w * 0.4}
    end
    local map = {}
    for i = 0, n - 2 do
        local a = i * 3 + 1
        local b = a + 3
        map[#map + 1] = a;     map[#map + 1] = a + 1; map[#map + 1] = b
        map[#map + 1] = a + 1; map[#map + 1] = b + 1; map[#map + 1] = b
        map[#map + 1] = a + 1; map[#map + 1] = a + 2; map[#map + 1] = b + 1
        map[#map + 1] = a + 2; map[#map + 1] = b + 2; map[#map + 1] = b + 1
    end
    if not self.mesh or self.mesh:getVertexCount() ~= #verts then
        self.mesh = love.graphics.newMesh(#verts, 'triangles', 'stream')
    end
    self.mesh:setVertices(verts)
    self.mesh:setVertexMap(map)
    if sk.pattern == 'capped' or sk.pattern == 'banded' then
        if not self.glow_mesh or self.glow_mesh:getVertexCount() ~= #glow then
            self.glow_mesh = love.graphics.newMesh(#glow, 'triangles', 'stream')
        end
        self.glow_mesh:setVertices(glow)
        self.glow_mesh:setVertexMap(map)
        marks[#marks + 1] = {'mesh', self.glow_mesh}
        -- and a soft light round each band, or round the head
        local prev = 0
        for i = 1, n do
            local w = glow[i * 3 - 1][8]
            if w >= 1 and prev < 1 then marks[#marks + 1] = {'halo', xs[i], ys[i], rs[i] * 3.5} end
            prev = w
        end
    end

    -- Rounded caps (head and tail) in the edge colours, then the mesh over them
    love.graphics.setColor(shade(sk, -lx, -ly, lx, ly, false))
    love.graphics.circle('fill', xs[n], ys[n], rs[n])
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.mesh)

    -- Head dome: radial shading
    local hr = rs[1]
    local capped = sk.pattern == 'capped' and 1 or 0
    for k = 3, 1, -1 do
        local t = k / 3
        local r, g, b = shade(sk, -0.2 * t, -0.9 * t, lx, ly, false, capped)
        love.graphics.setColor(r, g, b)
        love.graphics.circle('fill', xs[1] + lx * (1 - t) * 1.5, ys[1] + ly * (1 - t) * 1.5 - (1 - t), hr * (0.55 + 0.45 * t))
    end

    -- Terrarium: spots and the stripe run along the back, on whichever side
    -- of the spine faces up
    local function back(i, f)
        local side = nys[i] < 0 and 1 or -1
        return xs[i] + nxs[i] * side * rs[i] * f, ys[i] + nys[i] * side * rs[i] * f
    end
    if sk.pattern == 'spotted' then
        love.graphics.setColor(sk.mark)
        local j = 1
        for seg = 1.3, self.n - 1.5, 1.4 do
            local i = math.floor(seg * 4) + 1
            local x, y = back(i, 0.3 + 0.3 * Skin.hash(sk.seed, j))
            local r = rs[i] * (0.28 + 0.12 * Skin.hash(j, sk.seed))
            love.graphics.circle('fill', x, y, r)
            marks[#marks + 1] = {'disc', x, y, r}
            j = j + 1
        end
    elseif sk.pattern == 'striped' then
        local pts = {}
        for i = 3, math.floor(n * 0.92) do
            local x, y = back(i, 0.42)
            pts[#pts + 1] = x
            pts[#pts + 1] = y
        end
        if #pts >= 4 then
            love.graphics.setColor(sk.mark)
            love.graphics.setLineWidth(2.4)
            love.graphics.setLineJoin('bevel')
            love.graphics.line(pts)
            love.graphics.setLineWidth(1)
            marks[#marks + 1] = {'line', pts, 2.4}
        end
    end

    -- Segment rings
    love.graphics.setColor(sk.outline[1], sk.outline[2], sk.outline[3], 0.22)
    love.graphics.setLineWidth(1)
    for i = 6, n - 2, 3 do
        local r = rs[i] * 0.9
        love.graphics.line(xs[i] + nxs[i] * r, ys[i] + nys[i] * r, xs[i] - nxs[i] * r, ys[i] - nys[i] * r)
    end

    -- Wet highlight along the back
    love.graphics.setColor(1, 0.95, 0.85, 0.35)
    love.graphics.setLineWidth(1.4)
    local hl = {}
    for i = 2, math.floor(n * 0.7) do
        local side = nys[i] < 0 and 1 or -1
        hl[#hl + 1] = xs[i] + nxs[i] * side * rs[i] * 0.55
        hl[#hl + 1] = ys[i] + nys[i] * side * rs[i] * 0.55
    end
    if #hl >= 4 then love.graphics.line(hl) end
    love.graphics.setLineWidth(1)

    -- Eyes: look along the head's direction, far eye tucked behind
    local dx, dy = xs[1] - xs[3], ys[1] - ys[3]
    local d = sqrt(dx * dx + dy * dy)
    if d < 1e-4 then dx, dy, d = self.mover.facing, 0, 1 end
    dx, dy = dx / d, dy / d
    local ux, uy = dy, -dx             -- perpendicular, pick the upward one
    if uy > 0 then ux, uy = -ux, -uy end
    local ex, ey = xs[1] + dx * hr * 0.35 + ux * hr * 0.42, ys[1] + dy * hr * 0.35 + uy * hr * 0.42
    Base.draw_eye(self.face, ex - dx * 3.2 + ux * 0.8, ey - dy * 3.2 + uy * 0.8, 2.5, 1, 1, sk, true)
    Base.draw_eye(self.face, ex, ey, 3.1, 1, 1 - sq * 0.3, sk, false)

    self.marks = marks
end

-- Terrarium: the markings, shining as the lamp dims (#15)
function Worm:draw_emissive(ctx)
    Skin.paint_glow(self.marks, self.skin, Skin.shine(self.skin, ctx and ctx.light, self.flush))
end

-- X-ray: the body as the simulation sees it (drawn additively, after lighting)
function Worm:draw_xray(ctx)
    local c = self.color_name
    local xs, ys = spine(self.points, self.radii, 4)
    local line = {}
    for i = 1, #xs do line[#line + 1] = xs[i]; line[#line + 1] = ys[i] end
    love.graphics.setLineWidth(1.4)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.line(line)
    for i, p in ipairs(self.points) do
        local r = self.radii[i] * 0.85
        love.graphics.setColor(c[1], c[2], c[3], 0.35)
        love.graphics.setLineWidth(1)
        love.graphics.circle('line', p.x, p.y, r)
        love.graphics.setColor(1, 0.95, 0.88, 0.95)
        love.graphics.circle('fill', p.x, p.y, i == 1 and 2.2 or 1.4)
    end
    -- The anchor the head rides on
    local m = self.mover
    love.graphics.setColor(1, 0.95, 0.88, 0.6)
    love.graphics.line(self.points[1].x, self.points[1].y, m.x, m.y)
    love.graphics.line(m.x - 3, m.y, m.x + 3, m.y)
    love.graphics.setLineWidth(1)
end

function Worm:draw_debug()
    love.graphics.setColor(1, 1, 1, 0.5)
    for i, p in ipairs(self.points) do
        love.graphics.circle('line', p.x, p.y, self.radii[i] * 0.85)
    end
    local m = self.mover
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.circle('fill', m.x, m.y, 2.5)
end

--------------------------------------------------------------------------------
-- Terrarium: what the self-test knows of a worm (#73), so it never has to ask
-- which plan a body is. LIMITS are how far a body may come apart before the
-- ranges test (#17) fails it: each of the measures health() keeps, the most it
-- may reach, and how a fault reads (`scale` times the measure).
Worm.LIMITS = {
    {measure = 'torn', most = 2, says = 'tore a segment to %.1fx its length'}, -- longest segment over its rest length
    {measure = 'knot', most = 2, says = 'stayed knotted %.1fs'}, -- s knotted (three sharp bends): a dropped tail shakes out
}

-- Fold a look at worm `c`, `dt` seconds after the last, into `m`, the worst
-- it has been (a fresh `m` and dt 0 is a single look). How far its longest
-- segment is stretched, and how long it has been knotted: a hairpin turn bends
-- one or two joints back on themselves, a knot three or more.
function Worm.health(c, m, dt)
    local pts, most, sharp = c.points, 0, 0
    for k = 2, #pts do
        local a, b, q = pts[k - 1], pts[k], pts[k + 1]
        local ux, uy = b.x - a.x, b.y - a.y
        most = max(most, sqrt(ux * ux + uy * uy))
        if q then
            local vx, vy = q.x - b.x, q.y - b.y
            local d = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            if d > 0 and (ux * vx + uy * vy) / d < -0.17 then sharp = sharp + 1 end
        end
    end
    m.torn = max(m.torn or 0, most / SEG_LEN)
    m.knotted = sharp >= 3 and (m.knotted or 0) + dt or 0
    m.knot = max(m.knot or 0, m.knotted)
    return m
end

-- How big worm `c` is built now: its segments
function Worm.grown_size(c) return #c.points end

-- `genome` with the body the sim works hardest for: the longest
function Worm.heaviest(genome)
    genome.segments = Genome.worm.by_name.segments.int[2]
    return genome
end

-- How far a worm of `genome` lies out behind its head, lying down (a segment
-- settles a little shorter than its rest length)
function Worm.length(genome) return genome.segments * 7.5 end

-- How far either side of its anchor it lies, as a token (bodies/token.lua): half its length
function Worm.half(t) return t.n * 8.5 / 2 end

return Worm
