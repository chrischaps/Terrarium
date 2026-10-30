-- Springtail: a fleck of cobalt on the moss that crouches and is suddenly
-- somewhere else (#76).
--
-- A plump capsule of three verlet points (head, thorax, abdomen) carried by
-- the anchor on six tiny two-bone legs (bodies/fabrik.lua), with two
-- segmented antennae and a furcula, the spring, folded forward under its
-- belly. It walks only to line up a leap: its nav profile `hops`, so its graph
-- joins the nodes along a span with leaps as well as the spans to each other,
-- and walking costs it more than leaping (navgraph.lua's `walk_cost` and
-- `jump_flat`). Each hop it crouches, the furcula snaps down and back, and it
-- tumbles in the air, half a turn on a slow hop and a whole one on a fast one
-- (set by how fast it's thrown, never by chance), and lands upright, the
-- rest of the turn rolled out as it squashes down.
--
-- Its genes: `spring` is how hard the furcula throws it, so how far it hops
-- along a span (hop_max) and how high and far it can leap; graphs come in
-- Springtail.BUCKETS stretches of it, each built for its weakest. `antennae`
-- is how long they are, and nothing else.
--
-- Coloured from its genes (#15, #75, bodies/skin.lua): cobalt, with a frost of
-- pale scales in its markings. A hatchling is small and pale, and grows in
-- its sleep (Springtail:grow).
--
-- Courting (#22), a pair face each other, reach their antennae out to touch,
-- and hop in place together on the beat they share, the markings flushing as
-- they rise. Asleep it sits low on the moss with its legs tucked and its
-- antennae laid back, and dying it curls on its side.

local sq = require('core.fmath').sq -- Terrarium: x ^ 2 isn't one number in LuaJIT (#94)
local Base = require('bodies.base')
local Skin = require('bodies.skin')
local fabrik = require('bodies.fabrik')
local Genome = require('genome')

local Springtail = {}
Springtail.__index = Springtail

local sqrt, sin, cos, abs, min, max, pi, atan2 = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max, math.pi, math.atan2
local floor, ceil = math.floor, math.ceil
local TAU = 2 * pi

-- Every leap goes at least `loft` over the higher end (ballistics.solve_jump),
-- so a hop is a real arc, and a hop along a span asks for at most about a
-- quarter of its spring: a hop of hop_max at that lowest arc takes 0.53 s,
-- thrown at about 0.22 of jump_vx, so even a timid one hops (mind.lua's DARE
-- floor is 0.35). Both scale with the spring, so that holds for every
-- springtail.
Springtail.profile = {
    name = 'springtail',
    radius = 6, height = 12, step = 6,
    walk_speed = 40, walk_accel = 1400,
    jump_vx = 820, jump_vy = 680, air_accel = 900,
    anticipation = 0.14,
    hops = true, hop_max = 96, walk_cost = 2.5, jump_flat = 4, loft = 34,
    spring = 1,
}

-- One profile per spring, so springtails with the same spring share it
local profiles = {}
function Springtail.profile_for(spring)
    if spring == 1 then return Springtail.profile end
    local p = profiles[spring]
    if p then return p end
    local b = Springtail.profile
    p = {}
    for k, v in pairs(b) do p[k] = v end
    p.spring = spring
    p.jump_vx, p.jump_vy = b.jump_vx * spring, b.jump_vy * spring
    p.hop_max = b.hop_max * spring
    profiles[spring] = p
    return p
end

-- The profile a springtail's nav graph is built from (#16): springs come in
-- BUCKETS stretches sharing a graph, built for the weakest in the stretch, so
-- every hop and leap in it is one each of them can make
Springtail.BUCKETS = 8
Springtail.BUCKET_GENE = 'spring'
local navs = {}
function Springtail.nav_profile(genome)
    local k, lo, hi = Genome.bucket('springtail', 'spring', genome and genome.spring or 1, Springtail.BUCKETS)
    if navs[k] then return navs[k] end
    local p = {}
    for key, v in pairs(Springtail.profile_for(lo)) do p[key] = v end
    p.spring, p.springs, p.bucket = nil, {lo, hi}, k
    p.bucket_label = string.format('springs %.3f-%.3f', lo, hi)
    navs[k] = p
    return p
end

-- The body, at full size: each point's place along it (forward, and up, from
-- the thorax), its radius, and how high the thorax rides over its feet
local POSE = {{5.6, -0.5}, {0, 0}, {-6.0, 0.9}}
local CURL = {{4.6, -1.6}, {0, 0}, {-3.4, -3.6}} -- dying, the abdomen curled under
local RADII = {3.2, 3.9, 5.0}
local RIDE = 5.2
local BONES = {3.4, 3.6}
local ANTENNA = 8 -- its length at antennae 1
local ANTENNA_SEGS = 4

-- Legs: where each hip is along the thorax, where its foot stands (forward of
-- the anchor), which side and which of the two tripods it steps with
local LEGS = {
    {along = 2.4, rest = 5.2, near = true, group = 1},
    {along = 0.6, rest = 1.2, near = true, group = 2},
    {along = -1.4, rest = -3.2, near = true, group = 1},
    {along = 2.0, rest = 4.2, near = false, group = 2},
    {along = 0.2, rest = 0.2, near = false, group = 1},
    {along = -1.8, rest = -4.2, near = false, group = 2},
}
local STEP_DIST = 2.6 -- a foot this far behind where it would stand lifts
local STEP_TIME = 0.07

local TUMBLE_VX = 160   -- thrown faster than this, it turns a whole somersault
local RIGHT = 20        -- radians a second it rolls the rest of its turn on landing
local SETTLE = 0.15     -- seconds its legs stay folded as it squashes down, before they unfold
local HOP_BEAT = 0.7    -- seconds between a courting pair's hops (#22)
Springtail.HOP_BEAT = HOP_BEAT -- (each is heard, core/synth.lua)
local HOP_UP = 0.42     -- of each beat it spends in the air
local HOP_HIGH = 5      -- how high it hops in place

local COLORS = {
    eye = {0.07, 0.07, 0.12},
}

-- The parts of a springtail its genes make. `young` (0..1) is how pale it is
-- (#23), and a hatchling is small too: two thirds of its grown size.
function Springtail:take(genome, young)
    if genome then Genome.clamp(genome) end
    local spring = genome and genome.spring or 1
    self.genome = genome
    self.spring = spring
    self.profile = Springtail.profile_for(spring)
    self.nav = Springtail.nav_profile(genome)
    self.s = 1 - 0.35 * (young or 0)
    self.antenna = ANTENNA * (genome and genome.antennae or 1) * self.s
    self.court_gap = 9 * self.s + 2 -- its half of the gap to a partner (#22)
    self.skin = Skin.of('springtail', genome, young)
    self.skin.eye = COLORS.eye
    self.color_name = self.skin.name
end

function Springtail.new(x, y, world, genome, young)
    local self = setmetatable({}, Springtail)
    self:take(genome, young)
    self.world = world
    self.mover = Base.Mover.new(x, y, self.profile)
    self.face = Base.Face.new()
    self.clock = 0
    self.angle, self.spin = 0, nil   -- its somersault, radians, and the hop it's in
    self.crouch, self.squash, self.snap, self.settle = 0, 0, 0, 0
    self.sleep, self.curl, self.lift, self.tap = 0, 0, 0, 0
    self.ardour, self.flush = 0, 0
    self.points = {}
    for i = 1, 3 do self.points[i] = {x = x, y = y, px = x, py = y} end
    self:layout()
    self.legs = {}
    for i, def in ipairs(LEGS) do
        self.legs[i] = {def = def, chain = fabrik.chain(x, y - 3, self:bones(), 0, 1),
            foot = {x = x, y = y}, from = {x = 0, y = 0}, t = 1, stepping = false, grounded = true}
    end
    self:plant_all()
    return self
end

function Springtail:bones() return {BONES[1] * self.s, BONES[2] * self.s} end

-- Grow into `genome` where it sits (#23): the body swells about its feet and
-- every foot is set down again for legs that long
function Springtail:grow(genome, young)
    self:take(genome, young)
    self.mover.profile = self.profile
    for _, leg in ipairs(self.legs) do
        local j = leg.chain.joints
        leg.chain = fabrik.chain(j[1].x, j[1].y, self:bones(), 0, 1)
    end
    self:plant_all()
end

function Springtail:get_name() return "Springtail" end
function Springtail:get_description() return "A capsule on six legs that gets about by leaping" end

function Springtail:anchor() return self.mover.x, self.mover.y end

function Springtail:interp_points()
    local pts = {self.points[1], self.points[2], self.points[3]}
    for _, leg in ipairs(self.legs) do
        for _, j in ipairs(leg.chain.joints) do pts[#pts + 1] = j end
    end
    return pts
end

-- Where its three points want to be now: about its thorax, turned by its
-- somersault, curled if it's dying, low if it's asleep or crouching
function Springtail:pose()
    local m, s = self.mover, self.s
    local f = m.facing
    local ride = RIDE * s * (1 - 0.35 * self.crouch - 0.3 * self.sleep - 0.35 * self.curl) + self.lift
    local cx, cy = m.x, m.y - ride
    local a = f * self.angle
    local ca, sa = cos(a), sin(a)
    local out = {}
    for i = 1, 3 do
        local p, q = POSE[i], CURL[i]
        local lx = (p[1] + (q[1] - p[1]) * self.curl) * s
        local ly = (p[2] + (q[2] - p[2]) * self.curl) * s
        local vx, vy = f * lx, -ly
        out[i] = {cx + vx * ca - vy * sa, cy + vx * sa + vy * ca}
    end
    return out
end

-- Every point straight to its pose
function Springtail:layout()
    for i, t in ipairs(self:pose()) do
        local p = self.points[i]
        p.x, p.y, p.px, p.py = t[1], t[2], t[1], t[2]
    end
end

function Springtail:reset(x, y)
    self.mover = Base.Mover.new(x, y, self.profile)
    self.angle, self.spin, self.crouch, self.squash, self.lift = 0, nil, 0, 0, 0
    self:layout()
    self:plant_all()
end

-- Its frame from its points: forward along the body (head end), and up
function Springtail:frame()
    local h, a = self.points[1], self.points[3]
    local ux, uy = h.x - a.x, h.y - a.y
    local d = sqrt(ux * ux + uy * uy)
    if d < 1e-6 then ux, uy, d = self.mover.facing, 0, 1 end
    ux, uy = ux / d, uy / d
    local f = self.mover.facing
    return ux, uy, f * uy, -f * ux
end

function Springtail:hip(def)
    local ux, uy, nx, ny = self:frame()
    local t = self.points[2]
    local s = self.s
    return t.x + ux * def.along * s - nx * 1.6 * s, t.y + uy * def.along * s - ny * 1.6 * s
end

-- Where a foot stands on the ground under it, `lead` further on
function Springtail:rest_spot(def, level, lead)
    local m = self.mover
    local x = m.x + m.facing * def.rest * self.s + (lead or 0)
    local y = level and level:surface_below(x, m.y - 4, 10)
    if y then return x, y, true end
    -- (off the edge of what it stands on, the foot stays under it)
    y = level and level:surface_below(m.x, m.y - 4, 10)
    return m.x, y or m.y, y ~= nil
end

function Springtail:plant_all()
    local level = self.world and self.world.level
    for _, leg in ipairs(self.legs) do
        leg.foot.x, leg.foot.y, leg.grounded = self:rest_spot(leg.def, level)
        leg.t, leg.stepping = 1, false
        local hx, hy = self:hip(leg.def)
        for _ = 1, 3 do fabrik.solve(leg.chain, hx, hy, leg.foot.x, leg.foot.y, hx, hy - 4 * self.s) end
    end
end

function Springtail:influencers(out)
    local t = self.points[2]
    out[#out + 1] = {x = t.x, y = t.y, r = 9, vx = self.mover.vx, vy = self.mover.vy}
end

function Springtail:light()
    local t = self.points[2]
    return t.x, t.y, 0, 0, 0, 0
end

--------------------------------------------------------------------------------
-- Simulation
--------------------------------------------------------------------------------

function Springtail:update(dt, level, ctx)
    self.clock = self.clock + dt
    local m, s = self.mover, self.s
    m:update(level, dt)
    for _, ev in ipairs(m:drain()) do
        if ev.kind == 'jump' then
            -- The furcula snaps, and it's thrown into a somersault: a half
            -- turn on a slow hop and a whole one on a fast one, timed to
            -- about the flight back down to where it left
            self.snap = 1
            local from = self.spin and self.spin.right and self.angle - self.spin.right or 0
            self.spin = {from = from, turns = abs(ev.vx) > TUMBLE_VX and 1 or 0.5,
                T = max(0.2, 2 * abs(ev.vy) / 980), t = 0}
            ctx.events:emit('jump', {x = m.x, y = m.y, vx = ev.vx, vy = ev.vy, who = self})
        elseif ev.kind == 'land' then
            -- It sticks the landing and squashes, and rolls the rest of its
            -- turn out onto its feet
            m.vx = 0
            self.squash, self.settle = min(1, ev.impact / 500), SETTLE
            for _, p in ipairs(self.points) do p.py = p.py - min(ev.impact, 600) * 0.3 * dt end
            if self.spin then self.spin.right = TAU * ceil(self.angle / TAU - 1e-6) end
            self:plant_all()
            ctx.events:emit('land', {x = m.x, y = m.y, impact = ev.impact, who = self})
        end
    end

    -- The somersault: round in the air, then rolled upright on the ground
    local sp = self.spin
    if sp then
        if m.state == 'air' then
            sp.t = sp.t + dt
            self.angle = sp.from + sp.turns * TAU * min(1, sp.t / sp.T)
        elseif sp.right then
            self.angle = min(sp.right, self.angle + RIGHT * dt)
            if self.angle >= sp.right then self.angle, self.spin = 0, nil end
        end
    end
    local ease = min(1, dt * 14)
    self.crouch = self.crouch + ((m.state == 'anticipate' and 1 or 0) - self.crouch) * ease
    self.squash = self.squash * max(0, 1 - dt * 7)
    self.settle = max(0, self.settle - dt)
    self.snap = max(0, self.snap - dt / 0.35)
    self.sleep = self.sleep + ((ctx.rest and m.state == 'ground' and 1 or 0) - self.sleep) * min(1, dt * 2)
    if self.face.closing then self.curl = min(1, self.curl + dt / 6) end

    -- Courting, it faces its partner and hops in place on the beat, antennae
    -- reaching out to touch (#22)
    local court = ctx.court
    if court then self.court = court end
    self.ardour = self.ardour + ((court and 1 or 0) - self.ardour) * min(1, dt * 1.5)
    if self.ardour < 0.005 then self.ardour, self.court = 0, nil end
    self.lift, self.tap, self.flush = 0, 0, 0
    if self.court and m.state == 'ground' then
        local c, k = self.court, self.ardour
        if court and abs(c.x - m.x) > 1 then m.facing = c.x > m.x and 1 or -1 end
        local u = (c.beat / HOP_BEAT) % 1
        local up = u < HOP_UP and 4 * (u / HOP_UP) * (1 - u / HOP_UP) or 0
        self.lift = HOP_HIGH * s * k * up
        self.tap = k * max(0, sin((u - HOP_UP) / (1 - HOP_UP) * pi))
        self.flush = k * up
    end

    -- The body: its points carried toward the pose, held their lengths apart
    -- and out of the scenery
    local pose = self:pose()
    local air = m.state ~= 'ground'
    local pull = air and 0.55 or 0.3
    for i, p in ipairs(self.points) do
        local vx, vy = (p.x - p.px) * 0.86, (p.y - p.py) * 0.86
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx, p.y + vy
        p.x, p.y = p.x + (pose[i][1] - p.x) * pull, p.y + (pose[i][2] - p.y) * pull
    end
    local pts = self.points
    for _ = 1, 2 do
        for i = 1, 2 do
            local a, b = pts[i], pts[i + 1]
            local rest = sqrt(sq(pose[i + 1][1] - pose[i][1]) + sq(pose[i + 1][2] - pose[i][2]))
            local ex, ey = b.x - a.x, b.y - a.y
            local d = sqrt(ex * ex + ey * ey)
            if d > 1e-5 then
                local c = (d - rest) / d * 0.5
                a.x, a.y = a.x + ex * c, a.y + ey * c
                b.x, b.y = b.x - ex * c, b.y - ey * c
            end
        end
        for i = 1, 3 do level:resolve_point(pts[i], RADII[i] * s * 0.6, 0.6, 0) end
    end

    self:step_legs(dt, level)

    -- Eyes
    local t = pts[2]
    local lx, ly = m.facing * 0.6, 0.2
    if ctx.look_at then
        local ddx, ddy = ctx.look_at.x - t.x, ctx.look_at.y - t.y
        local d = sqrt(ddx * ddx + ddy * ddy)
        if d > 1 then lx, ly = ddx / d, ddy / d end
    end
    self.face:update(dt, lx, ly, m.state == 'ground' and abs(m.vx) < 5 and not ctx.look_at)
end

-- Six legs: on the ground two tripods take turns stepping; crouched they hold
-- where they stand; tumbling, asleep or dying they fold in under it
function Springtail:step_legs(dt, level)
    local m, s = self.mover, self.s
    local ux, uy, nx, ny = self:frame()
    -- (and while it rolls the rest of a somersault out, or squashes down
    -- landing, its legs stay folded)
    local tucked = m.state == 'air' or self.spin ~= nil or self.settle > 0 or self.sleep > 0.5 or self.curl > 0
    local walking = m.state == 'ground' and not tucked
    local lead = max(-3, min(3, m.vx * 0.06)) * s
    if walking and self.tucked then
        -- waking: every foot unfolds from under it to where it stands
        for _, leg in ipairs(self.legs) do
            leg.stepping, leg.t = true, 0
            leg.from.x, leg.from.y = leg.foot.x, leg.foot.y
        end
    end
    self.tucked = tucked and m.state ~= 'air' -- (landing sets them down itself)
    if walking then
        local stepping, need = false, {0, 0}
        for _, leg in ipairs(self.legs) do
            if leg.stepping then stepping = true end
            local rx = self:rest_spot(leg.def, level, lead)
            local g = leg.def.group
            need[g] = max(need[g], abs(rx - leg.foot.x) / (STEP_DIST * s))
        end
        local go = need[1] >= need[2] and 1 or 2
        if not stepping and need[go] > 1 then
            for _, leg in ipairs(self.legs) do
                if leg.def.group == go then
                    leg.stepping, leg.t = true, 0
                    leg.from.x, leg.from.y = leg.foot.x, leg.foot.y
                end
            end
        end
    end
    for _, leg in ipairs(self.legs) do
        local def = leg.def
        local hx, hy = self:hip(def)
        local fx, fy
        if tucked then
            -- drawn in under the belly, a little toward where it stands
            local k = def.rest * 0.35 * s
            fx, fy = hx + ux * k - nx * 0.8 * s, hy + uy * k - ny * 0.8 * s
            leg.stepping, leg.t, leg.grounded = false, 1, false
            leg.foot.x, leg.foot.y = fx, fy
        else
            if leg.stepping then
                local tx, ty, found = self:rest_spot(def, level, lead)
                leg.t = min(1, leg.t + dt / STEP_TIME)
                local e = leg.t * leg.t * (3 - 2 * leg.t)
                fx = leg.from.x + (tx - leg.from.x) * e
                fy = leg.from.y + (ty - leg.from.y) * e - sin(leg.t * pi) * 1.6 * s
                if leg.t >= 1 then
                    leg.stepping, leg.grounded = false, found
                    leg.foot.x, leg.foot.y = tx, ty
                end
            else
                fx, fy = leg.foot.x, leg.foot.y
            end
            -- (hopping in place, its feet leave the ground with it)
            fy = fy - self.lift * 0.85
        end
        local px, py = hx + nx * 4 * s + ux * (def.rest >= 0 and 1 or -1) * 2 * s, hy + ny * 4 * s
        fabrik.solve(leg.chain, hx, hy, fx, fy, px, py, 4, 0.4)
        fabrik.solve(leg.chain, hx, hy, fx, fy, nil, nil, 6)
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function set(c, a) love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

local function draw_leg(leg, far, sk)
    local j = leg.chain.joints
    set(sk.outline, far and 0.7 or 1)
    love.graphics.setLineWidth(far and 1.4 or 1.8)
    love.graphics.line(j[1].x, j[1].y, j[2].x, j[2].y, j[3].x, j[3].y)
    set(far and sk.furca or sk.antenna)
    love.graphics.setLineWidth(far and 0.7 or 1)
    love.graphics.line(j[1].x, j[1].y, j[2].x, j[2].y, j[3].x, j[3].y)
    love.graphics.setLineWidth(1)
end

-- An antenna in the body's frame (+x forward, -y up), from (x, y): ANTENNA_SEGS
-- beads, each segment bending a little more, as the moment asks
function Springtail:antenna_points(x, y, far)
    local len = self.antenna / ANTENNA_SEGS
    local a = far and -0.95 or -0.7          -- up and forward
    local bend = 0.16
    local sway = sin(self.clock * 1.9 + (far and 1.3 or 0) + (self.skin.seed or 0)) * 0.12
    -- courting: out level toward its partner, dipping to touch on the beat
    local k = self.ardour
    a = a + (-0.12 - a) * k
    bend = bend + k * (0.05 + 0.35 * self.tap)
    -- asleep, laid back along its body; dying, drooped
    a = a + ((far and -2.75 or -2.6) - a) * self.sleep * (1 - self.curl)
    bend = bend * (1 - self.sleep) + 0.45 * self.curl
    local pts = {x, y}
    for i = 1, ANTENNA_SEGS do
        a = a + bend + sway * 0.5
        x, y = x + cos(a) * len, y + sin(a) * len
        pts[#pts + 1], pts[#pts + 2] = x, y
    end
    return pts
end

function Springtail:draw(ctx)
    local sk, pattern = self.skin, self.skin.pattern
    local s, pts = self.s, self.points
    local ux, uy, nx, ny = self:frame()
    local f = self.mover.facing
    local t = pts[2]
    local angle = atan2(uy, ux)
    local lx, ly = ctx.light_dir(t.x, t.y)
    -- (the light, the head and the abdomen in the body's own frame)
    local function here(x, y)
        local dx, dy = x - t.x, y - t.y
        return dx * ux + dy * uy, -(dx * nx + dy * ny)
    end
    local hx, hy = here(pts[1].x, pts[1].y)
    local ax, ay = here(pts[3].x, pts[3].y)
    local llx, lly = lx * ux + ly * uy, -(lx * nx + ly * ny)
    local r1, r2, r3 = RADII[1] * s, RADII[2] * s, RADII[3] * s
    local sq = self.squash
    local sx, sy = 1 + 0.22 * sq, 1 - 0.28 * sq
    local local_marks = {}

    for _, leg in ipairs(self.legs) do
        if not leg.def.near then draw_leg(leg, true, sk) end
    end

    love.graphics.push()
    love.graphics.translate(t.x, t.y)
    love.graphics.rotate(angle)
    love.graphics.scale(1, f)
    -- (squashed about its feet)
    local base = RIDE * s
    love.graphics.translate(0, base)
    love.graphics.scale(sx, sy)
    love.graphics.translate(0, -base)

    -- the far antenna, behind the head
    local head_x, head_y = hx + r1 * 0.55, hy - r1 * 0.55
    set(sk.outline, 0.8)
    love.graphics.setLineWidth(0.9)
    love.graphics.line(self:antenna_points(head_x - 0.6, head_y, true))

    -- The capsule: outline, then belly, then the cobalt back over it
    local body = {{hx, hy, r1}, {0, 0, r2}, {ax, ay, r3}}
    local function capsule(grow, dy, shrink)
        for i, b in ipairs(body) do
            love.graphics.circle('fill', b[1], b[2] + dy * b[3], b[3] * shrink + grow)
            local n = body[i + 1]
            if n then
                love.graphics.setLineWidth((min(b[3], n[3]) * shrink + grow) * 2)
                love.graphics.line(b[1], b[2] + dy * b[3], n[1], n[2] + dy * n[3])
            end
        end
    end
    set(sk.outline)
    capsule(0.8, 0, 1)
    set(sk.belly)
    capsule(0, 0, 1)
    set(sk.body)
    capsule(0, -0.16, 0.9)
    love.graphics.setLineWidth(1)
    -- the light on its back
    set(sk.belly, 0.45)
    love.graphics.ellipse('fill', ax * 0.55 + llx * 1.5, ay * 0.55 - r2 * 0.55 + lly * 1.2, r3 * 0.6, r3 * 0.28)
    -- segments across the abdomen
    set(sk.outline, 0.35)
    love.graphics.setLineWidth(0.5)
    for k = 1, 3 do
        local x = ax * (0.22 + 0.22 * k)
        local y = ay * (0.22 + 0.22 * k)
        local r = r2 + (r3 - r2) * (0.22 + 0.22 * k)
        love.graphics.arc('line', 'open', x, y, r * 0.95, -pi * 0.9, -pi * 0.55)
    end
    -- a frost of pale scales
    set(sk.mark, 0.35)
    for k = 1, 7 do
        local u = Skin.hash(sk.seed, k)
        local x = ax + (hx - ax) * u
        local r = r3 + (r1 - r3) * u
        love.graphics.circle('fill', x, ay + (hy - ay) * u - r * (0.25 + 0.55 * Skin.hash(k, sk.seed)), 0.35 * s)
    end

    -- Markings
    set(sk.mark, 0.9)
    if pattern == 'capped' then
        love.graphics.circle('fill', hx, hy - 0.2, r1 * 0.82)
        local_marks[#local_marks + 1] = {'disc', hx, hy - 0.2, r1 * 0.82}
    elseif pattern == 'banded' then
        love.graphics.setLineWidth(1.1 * s)
        for _, u in ipairs({0.08, 0.5, 0.82}) do
            local x, y = ax * u, ay * u
            local r = r2 + (r3 - r2) * u
            local band = {x - 0.5, y - r * 0.92, x + 0.4, y - r * 0.2}
            love.graphics.line(band)
            local_marks[#local_marks + 1] = {'line', band, 1.1 * s}
        end
    elseif pattern == 'spotted' then
        for k, u in ipairs({-0.45, 0.1, 0.45, 0.8}) do
            local x, y, r = ax * u, ay * u, r2 + (r3 - r2) * u
            if u < 0 then x, y, r = -hx * u, -hy * u, r2 + (r1 - r2) * -u end
            local d = (0.75 + 0.35 * Skin.hash(sk.seed, k)) * s
            love.graphics.circle('fill', x, y - r * 0.55, d)
            local_marks[#local_marks + 1] = {'disc', x, y - r * 0.55, d}
        end
    elseif pattern == 'striped' then
        local line = {hx * 0.7, hy - r1 * 0.68, 0, -r2 * 0.74, ax * 0.55, ay * 0.55 - (r2 + r3) * 0.38, ax * 0.95, ay - r3 * 0.62}
        love.graphics.setLineWidth(1.2 * s)
        love.graphics.line(line)
        local_marks[#local_marks + 1] = {'line', line, 1.2 * s}
    end
    love.graphics.setLineWidth(1)

    -- The furcula under its belly: folded forward, cocked as it crouches,
    -- and snapped down and back as it leaps
    local fx, fy = ax * 0.8, ay + r3 * 0.7
    local fa = 0.1 - 0.12 * self.crouch + pi * 0.7 * sqrt(self.snap)
    local flen = 5.5 * s
    local kx, ky = fx + cos(fa) * flen * 0.4, fy + sin(fa) * flen * 0.4
    local ex, ey = kx + cos(fa - 0.3) * flen * 0.6, ky + sin(fa - 0.3) * flen * 0.6
    set(sk.outline)
    love.graphics.setLineWidth(1.5 * s)
    love.graphics.line(fx, fy, kx, ky, ex, ey)
    set(sk.furca)
    love.graphics.setLineWidth(0.7 * s)
    love.graphics.line(fx, fy, kx, ky, ex, ey)

    -- Its eye patch, blinking, and the near antenna
    local open = self.face:openness()
    set(COLORS.eye)
    love.graphics.ellipse('fill', hx + r1 * 0.25, hy - r1 * 0.3, r1 * 0.32, r1 * 0.32 * max(0.12, open))
    if open > 0.3 then
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle('fill', hx + r1 * 0.32 + self.face.gaze_x * 0.2, hy - r1 * 0.42, 0.35 * s)
    end
    set(sk.outline)
    love.graphics.setLineWidth(1.3)
    local near = self:antenna_points(head_x, head_y, false)
    love.graphics.line(near)
    set(sk.antenna)
    love.graphics.setLineWidth(0.7)
    love.graphics.line(near)
    for i = 3, #near - 1, 2 do love.graphics.circle('fill', near[i], near[i + 1], 0.4 * s) end
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    for _, leg in ipairs(self.legs) do
        if leg.def.near then draw_leg(leg, false, sk) end
    end
    self.local_marks = local_marks
    self.mark_frame = {t.x, t.y, angle, f, sx, sy, base}
end

-- The markings, shining as the lamp dims (#15) and flushing as it hops on the beat (#22)
function Springtail:draw_emissive(ctx)
    local k = Skin.shine(self.skin, ctx and ctx.light, self.flush)
    local f = self.mark_frame
    if k > 0.01 and f then
        love.graphics.push()
        love.graphics.translate(f[1], f[2])
        love.graphics.rotate(f[3])
        love.graphics.scale(1, f[4])
        love.graphics.translate(0, f[7])
        love.graphics.scale(f[5], f[6])
        love.graphics.translate(0, -f[7])
        Skin.paint_glow(self.local_marks, self.skin, k)
        love.graphics.pop()
    end
end

-- X-ray: the three points and their rests, the legs, and the anchor
function Springtail:draw_xray(ctx)
    local c = self.color_name
    local pts = self.points
    love.graphics.setLineWidth(1.2)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.line(pts[1].x, pts[1].y, pts[2].x, pts[2].y, pts[3].x, pts[3].y)
    for i, p in ipairs(pts) do love.graphics.circle('line', p.x, p.y, RADII[i] * self.s) end
    for _, leg in ipairs(self.legs) do
        local j = leg.chain.joints
        love.graphics.setColor(c[1], c[2], c[3], leg.def.near and 0.9 or 0.45)
        love.graphics.line(j[1].x, j[1].y, j[2].x, j[2].y, j[3].x, j[3].y)
    end
    love.graphics.setColor(1, 0.96, 0.88, 0.6)
    love.graphics.circle('fill', self.mover.x, self.mover.y, 1.4)
    love.graphics.setLineWidth(1)
end

function Springtail:draw_debug()
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.circle('fill', self.mover.x, self.mover.y, 2)
end

--------------------------------------------------------------------------------
-- What the self-test knows of a springtail (#73); see Worm.LIMITS
Springtail.LIMITS = {
    -- of its rest length, the most a joint of its body has been pulled apart
    {measure = 'torn', most = 0.5, says = 'pulled a joint of its body %.0f%% past its length', scale = 100},
    -- of its feet standing on the ground, the ones its legs don't reach
    {measure = 'slip', most = 0.03, says = "stood on feet it can't reach %.1f%% of the time", scale = 100},
}

-- Fold a look at springtail `c` into `m`: how far its body's joints are from
-- their lengths, and of its feet standing on the ground (not stepping, tucked
-- or hopping in place), how many its legs don't reach or that stand on nothing
-- (#76: it's so seldom on its feet that every look counts)
function Springtail.health(c, m, dt)
    local pose, torn = c:pose(), 0
    for i = 1, 2 do
        local a, b = c.points[i], c.points[i + 1]
        local rest = sqrt(sq(pose[i + 1][1] - pose[i][1]) + sq(pose[i + 1][2] - pose[i][2]))
        local d = sqrt(sq(b.x - a.x) + sq(b.y - a.y))
        torn = max(torn, abs(d - rest) / rest)
    end
    m.torn = max(m.torn or 0, torn)
    local bad, planted = 0, 0
    if c.mover.state == 'ground' and not c.tucked and c.lift < 0.3 then
        for _, leg in ipairs(c.legs) do
            if not leg.stepping then
                planted = planted + 1
                local tip = leg.chain.joints[3]
                if sq(tip.x - leg.foot.x) + sq(tip.y - leg.foot.y) > 1 or not leg.grounded then bad = bad + 1 end
            end
        end
    end
    m.slips, m.planted = (m.slips or 0) + bad, (m.planted or 0) + planted
    m.slip = m.slips / max(1, m.planted)
    return m
end

-- How springy springtail `c` is built now
function Springtail.grown_size(c) return c.spring end

-- `genome` with the body the sim works hardest for: the strongest spring
function Springtail.heaviest(genome)
    genome.spring = Genome.springtail.by_name.spring.real[2]
    return genome
end

-- How far its body lies out behind its anchor
function Springtail.length(genome) return 8 end

-- How far either side of its anchor it lies, as a token (bodies/token.lua)
function Springtail.half(t) return 8 * t.s end

return Springtail
