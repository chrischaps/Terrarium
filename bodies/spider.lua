-- From chrischaps/Character @ 925c35b (creatures/spider.lua)
-- Spider: eight FABRIK legs that find their own footing.
--
-- The body rides a point on any surface - floor, wall or ceiling - with the
-- surface normal telling it which way is "up". Each foot has a rest spot
-- relative to the body, projected onto real geometry with raycasts. When a
-- planted foot falls too far behind its rest spot, it lifts and arcs to the
-- new one; alternating leg groups keep it walking on four legs at a time.
-- Jumps hand the body to the shared ballistic mover; the legs tuck in flight.
--
-- Terrarium: built from a genome (#14). `legs` (4, 6 or 8) is half on each
-- side, and the gait is two alternating groups of half of them: a trot on
-- four, a tripod on six, Character's tetrapod on eight. `reach` is leg length,
-- and with it the stride, the body's height, how far a foot looks for ground,
-- and the gap between two solids it can step across (the profile's `span`,
-- which its nav graph is built with).
--
-- Terrarium: coloured from its genes (#15, bodies/skin.lua): indigo to plum,
-- and dark, with pale markings that glow at night.
--
-- Terrarium: courting (#22), two spiders face each other and tap: a front
-- foot lifts and reaches toward the other, then the other front foot, on a
-- beat they share (the jar's clock), and the body bobs and the markings
-- flush in time.
--
-- Terrarium: a hatchling (#23) has all its legs but they're short, and it's
-- pale; its legs lengthen in its sleep (Spider:grow).

local Base = require('bodies.base')
local Climb = require('bodies.climb')
local Skin = require('bodies.skin')
local fabrik = require('bodies.fabrik')
local rng = require('core.rng')
local Genome = require('genome')

local Spider = {}
Spider.__index = Spider

local sqrt, sin, cos, abs, min, max, pi, atan2 = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max, math.pi, math.atan2
local floor = math.floor

Spider.profile = {
    name = 'spider',
    radius = 9, height = 20, step = 20,
    walk_speed = 120, walk_accel = 900,
    jump_vx = 300, jump_vy = 470, air_accel = 650,
    anticipation = 0.15,
    climbs = true,
    crawl_speed = 115,
    reach = 1, span = 40, -- Terrarium
}

-- Terrarium: one profile per reach, so spiders with the same legs share a graph
local profiles = {}
function Spider.profile_for(reach)
    if reach == 1 then return Spider.profile end
    local p = profiles[reach]
    if p then return p end
    local b = Spider.profile
    p = {}
    for k, v in pairs(b) do p[k] = v end
    p.reach = reach
    p.span = b.span * reach
    p.crawl_speed = b.crawl_speed * reach ^ 0.5 -- a longer stride, a slower cadence
    profiles[reach] = p
    return p
end

-- Terrarium: the profile a spider's nav graph is built from (#16). Reaches
-- come in Spider.BUCKETS stretches that share a graph, built for the shortest
-- legs in the stretch: only the gaps those can step across.
Spider.BUCKETS = 8
Spider.BUCKET_GENE = 'reach' -- (#73: the gene the buckets divide, for the self-test)
local navs = {}
function Spider.nav_profile(genome)
    local k, lo, hi = Genome.bucket('spider', 'reach', genome and genome.reach or 1, Spider.BUCKETS)
    if navs[k] then return navs[k] end
    local p = {}
    for key, v in pairs(Spider.profile_for(lo)) do p[key] = v end
    p.reach, p.reaches, p.bucket = nil, {lo, hi}, k
    p.bucket_label = string.format('reaches %.3f-%.3f', lo, hi)
    navs[k] = p
    return p
end

local RIDE = 12
local TAP_BEAT = 0.42 -- Terrarium: seconds a courting tap takes (#22)
Spider.TAP_BEAT = TAP_BEAT -- (each tap is heard, core/synth.lua, #28)
local BONES = {14, 15, 11}
local STEP_DIST = 13
local STEP_TIME = 0.1
local FAN = {0.35, 0.8, 1.25, 1.7, -0.35} -- Terrarium: radians off straight down, toward the foot's side

-- Leg layout: reach along the body tangent (front positive), depth for near/far
local LEGS = {
    {reach = 30, hip = 4.5, near = true,  group = 1},
    {reach = 14, hip = 2.0, near = true,  group = 2},
    {reach = -6, hip = -0.5, near = true, group = 1},
    {reach = -24, hip = -2.5, near = true, group = 2},
    {reach = 24, hip = 3.5, near = false, group = 2},
    {reach = 7,  hip = 1.0, near = false, group = 1},
    {reach = -12, hip = -1.0, near = false, group = 2},
    {reach = -29, hip = -3.0, near = false, group = 1},
}

-- Terrarium: `count` legs, half a side, spread front to back along each side
-- of Character's eight (so eight is exactly it). Along a side the groups
-- alternate, and across the body they're opposite, so every group stands on
-- both sides at once. Reach and the knees scale with `scale`.
local function layout(count, scale)
    local per, out = count / 2, {}
    for side = 0, 1 do
        local near = side == 0
        for k = 0, per - 1 do
            local u = per > 1 and k / (per - 1) * 3 or 0 -- a place along LEGS 1..4
            local i0 = min(2, floor(u))
            local f = u - i0
            local a, b = LEGS[side * 4 + i0 + 1], LEGS[side * 4 + i0 + 2]
            out[#out + 1] = {
                reach = (a.reach + (b.reach - a.reach) * f) * scale,
                hip = a.hip + (b.hip - a.hip) * f,
                near = near,
                group = (k + side) % 2 + 1,
            }
        end
    end
    return out
end

-- Terrarium: the body's own colours come from its skin (Skin.of)
local COLORS = {
    eye      = {1.00, 0.80, 0.45},
}

-- Terrarium: the parts of a spider its genes make: its legs, how long they
-- are and the profile that goes with them. `young` (0..1) is how pale it is (#23).
function Spider:take(genome, young)
    if genome then Genome.clamp(genome) end
    local scale = genome and genome.reach or 1
    self.genome = genome
    self.scale = scale
    self.profile = Spider.profile_for(scale)
    self.nav = Spider.nav_profile(genome)
    self.layout = layout(genome and genome.legs or 8, scale)
    self.bones = {BONES[1] * scale, BONES[2] * scale, BONES[3] * scale}
    self.ride = RIDE * (0.6 + 0.4 * scale) -- long legs stand it taller
    self.step_dist = STEP_DIST * scale
    self.court_gap = 17 * scale + 4 -- Terrarium: its half of the gap to a partner (#22)
    self.skin = Skin.of('spider', genome, young)
    self.skin.eye = COLORS.eye
    self.color_name = self.skin.name
end

function Spider.new(x, y, world, genome, young)
    local self = setmetatable({}, Spider)
    -- Terrarium: the body from its genes
    self:take(genome, young)
    local scale = self.scale
    self.world = world
    self.a = {x = x, y = y}                 -- anchor on the surface
    self.nx, self.ny = 0, -1                -- smoothed surface normal
    self.tnx, self.tny = 0, -1              -- target normal
    self.facing = 1
    self.mode = 'attached'                  -- attached | anticipate | air
    self.mover = Base.Mover.new(x, y, self.profile)
    self.solid = nil
    self.face = Base.Face.new()
    self.clock = 0
    self.speed = 0
    self.gait = 1 -- Terrarium: how freely the legs let it go
    self.pace, self.crawled = 0, false -- Terrarium: how fast the body is really going
    self.bob = 0
    self.tap = nil
    self.next_tap = rng.range(rng.look, 3, 7)
    self.ardour, self.flush = 0, 0
    self.legs = {}
    for i, def in ipairs(self.layout) do
        local hx, hy = self:hip(def)
        local leg = {
            def = def,
            chain = fabrik.chain(hx, hy, self.bones, 0, 1),
            foot = {x = x + def.reach, y = y},
            from = {x = 0, y = 0}, to = {x = 0, y = 0},
            t = 1, stepping = false, planted = true,
        }
        self.legs[i] = leg
    end
    self:plant_all()
    return self
end

-- Terrarium: grow into `genome` where it stands or hangs (#23). Its legs
-- lengthen in place and every foot is set down again for legs that long.
function Spider:grow(genome, young)
    self:take(genome, young)
    self.mover.profile = self.profile
    for i, leg in ipairs(self.legs) do
        leg.def = self.layout[i]
        local hx, hy = self:hip(leg.def)
        leg.chain = fabrik.chain(hx, hy, self.bones, 0, 1)
    end
    -- (the new layout faces right, as a spider's does when it's built)
    self.legs_facing = 1
    if self.facing ~= 1 then self:turn_legs() end
    self:plant_all()
end

function Spider:get_name() return "Cave Spider" end
function Spider:get_description() return #self.legs .. " FABRIK legs that step to real footholds" end

function Spider:anchor() return self.a.x, self.a.y end

function Spider:interp_points()
    local pts = {self.a}
    for _, leg in ipairs(self.legs) do
        for _, j in ipairs(leg.chain.joints) do pts[#pts + 1] = j end
    end
    return pts
end

function Spider:reset(x, y)
    self.a.x, self.a.y = x, y
    self.nx, self.ny, self.tnx, self.tny = 0, -1, 0, -1
    self.mode = 'attached'
    self.mover = Base.Mover.new(x, y, self.profile)
    self.gait, self.pace = 1, 0 -- Terrarium
    self:plant_all()
end

-- (its frame, tangent and normal, is Climb.frame)

function Spider:body_center()
    local tx, ty, nx, ny = self:frame()
    local ride = self.ride + self.bob
    return self.a.x + nx * ride, self.a.y + ny * ride
end

function Spider:hip(def)
    local tx, ty, nx, ny = self:frame()
    local bx, by = self:body_center()
    return bx + tx * def.hip + nx * 1.5, by + ty * def.hip + ny * 1.5
end

-- Terrarium: how far ahead a foot reaches when moving, in step with the leg
function Spider:lead() return self.speed * 0.09 * self.scale ^ 0.5 end

-- Where this foot wants to stand, found on real geometry. Terrarium: `lead`
-- is how far ahead it reaches (by default as far as it's moving), 0 for
-- where it stands still.
function Spider:rest_spot(def, level, lead)
    local tx, ty, nx, ny = self:frame()
    local k = self.scale                                 -- Terrarium: footholds scale with reach
    lead = lead or self:lead()                           -- reach ahead when moving
    local reach = def.reach + lead + (def.near and 0 or 1.5)
    local ox, oy = self.a.x + tx * reach + nx * 14 * k, self.a.y + ty * reach + ny * 14 * k
    -- Terrarium: a ray cast from inside a stone passes through it, and the
    -- buried soil under a log is no foothold, so a probe that starts inside
    -- the scenery finds nothing (#17)
    local function cast(x, y, dx, dy, len)
        if level:solid_at(x, y) then return nil end
        return level:raycast(x, y, dx, dy, len)
    end
    -- Straight down onto the surface
    local d = cast(ox, oy, -nx, -ny, 34 * k)
    if d then return ox - nx * d, oy - ny * d, true end
    -- Around a convex corner: back toward the body
    local s = reach >= 0 and -1 or 1
    local cx, cy = self.a.x + tx * reach - nx * 6 * k, self.a.y + ty * reach - ny * 6 * k
    d = cast(cx, cy, tx * s, ty * s, abs(reach) + 6 * k)
    if d then return cx + tx * s * d, cy + ty * s * d, true end
    -- Into a concave corner: forward along the tangent
    d = level:raycast(self.a.x + nx * 4, self.a.y + ny * 4, tx * -s, ty * -s, abs(reach) + 8 * k)
    if d and d < abs(reach) + 8 * k then
        return self.a.x + nx * 4 - tx * s * d, self.a.y + ny * 4 - ty * s * d, true
    end
    -- Terrarium: across a gap, nothing is straight below: fan out from the
    -- body on the foot's own side for anything a leg this long can reach
    local len = (self.bones[1] + self.bones[2] + self.bones[3]) * 0.9
    for _, a in ipairs(FAN) do
        local c, sn = cos(a), sin(a) * -s
        local dx, dy = -nx * c + tx * sn, -ny * c + ty * sn
        d = level:raycast(self.a.x + nx * 4, self.a.y + ny * 4, dx, dy, len)
        if d then return self.a.x + nx * 4 + dx * d, self.a.y + ny * 4 + dy * d, true end
    end
    return self.a.x + tx * reach, self.a.y + ty * reach, false
end

-- Terrarium: turning round, the back legs become the front ones. Each side's
-- roles reverse so every foot stays where it stands, instead of the whole
-- stance mirroring at once and every leg reaching back across the body.
function Spider:turn_legs()
    self.legs_facing = self.facing
    local per = #self.legs / 2
    for side = 0, 1 do
        for k = 1, floor(per / 2) do
            local a, b = self.legs[side * per + k], self.legs[side * per + per + 1 - k]
            a.def, b.def = b.def, a.def
        end
    end
end

function Spider:plant_all()
    self.legs_facing = self.facing -- Terrarium
    local level = self.world and self.world.level
    for _, leg in ipairs(self.legs) do
        local fx, fy, found = self.a.x + leg.def.reach, self.a.y, true
        if level then fx, fy, found = self:rest_spot(leg.def, level) end
        leg.grounded = found
        leg.foot.x, leg.foot.y = fx, fy
        leg.t, leg.stepping, leg.planted = 1, false, true
        local hx, hy = self:hip(leg.def)
        local _, _, nx, ny = self:frame()
        for _ = 1, 3 do
            fabrik.solve(leg.chain, hx, hy, fx, fy, hx + nx * 18 * self.scale, hy + ny * 18 * self.scale)
        end
    end
end

function Spider:influencers(out)
    local bx, by = self:body_center()
    out[#out + 1] = {x = bx, y = by, r = 14, vx = 0, vy = 0}
    for i = 1, #self.legs, 2 do
        local j = self.legs[i].chain.joints[2]
        out[#out + 1] = {x = j.x, y = j.y, r = 6, vx = 0, vy = 0}
    end
end

function Spider:light()
    local bx, by = self:body_center()
    return bx, by, 0, 0, 0, 0
end

--------------------------------------------------------------------------------
-- Controller interface: bodies/climb.lua's (Terrarium, #77), and plant_all above
--------------------------------------------------------------------------------

Climb.into(Spider)

--------------------------------------------------------------------------------
-- Simulation
--------------------------------------------------------------------------------

-- Terrarium: a point inside the scenery, moved to the nearest clear spot
-- within 24px: rings of 16 directions, 1px apart. Faces alone won't do, since
-- a stone's foot is buried in the soil and the seam between them is inside
-- both (#17). Returns the point and whether it moved.
local AROUND = {}
for k = 0, 15 do AROUND[k + 1] = {cos(k * pi / 8), sin(k * pi / 8)} end
local function outside(level, x, y)
    if not level:solid_at(x, y) then return x, y, false end
    for r = 1, 24 do
        for _, d in ipairs(AROUND) do
            local qx, qy = x + d[1] * r, y + d[2] * r
            if not level:solid_at(qx, qy) then return qx, qy, true end
        end
    end
    return x, y, false
end

-- A leg's knee and ankle out of the scenery. True if either was inside.
local function clear_joints(j, level)
    local moved = false
    for i = 2, #j - 1 do
        local m
        j[i].x, j[i].y, m = outside(level, j[i].x, j[i].y)
        moved = moved or m
    end
    return moved
end

function Spider:update(dt, level, ctx)
    self.clock = self.clock + dt

    if self.mode ~= 'attached' then
        local m = self.mover
        m:update(level, dt)
        self.a.x, self.a.y = m.x, m.y
        for _, ev in ipairs(m:drain()) do
            if ev.kind == 'jump' then
                self.mode = 'air'
                ctx.events:emit('jump', {x = m.x, y = m.y, vx = ev.vx, vy = ev.vy, who = self})
            elseif ev.kind == 'land' then
                self.mode = 'attached'
                self.solid = m.solid
                self.nx, self.ny, self.tnx, self.tny = 0, -1, 0, -1
                self:plant_all()
                ctx.events:emit('land', {x = m.x, y = m.y, impact = ev.impact, who = self})
            end
        end
        if self.mode == 'anticipate' then
            self.bob = self.bob + (-4 - self.bob) * min(1, dt * 18)
        end
    else
        local bob = 0.8 * sin(self.clock * 2.2)
        if self.court then bob = bob + self.ardour * 1.6 * sin(self.court.beat / TAP_BEAT * pi) end -- Terrarium
        self.bob = self.bob + (bob - self.bob) * min(1, dt * 6)
    end

    -- Smooth the normal
    local k = min(1, dt * 12)
    local nx = self.nx + (self.tnx - self.nx) * k
    local ny = self.ny + (self.tny - self.ny) * k
    local d = sqrt(nx * nx + ny * ny)
    if d > 1e-4 then self.nx, self.ny = nx / d, ny / d end

    local _, _, fnx, fny = self:frame()
    local moving = self.speed > 10

    -- Idle tap: a front leg lifts and taps
    if self.mode == 'attached' and not moving and not self.court then
        self.next_tap = self.next_tap - dt
        if self.next_tap <= 0 and not self.tap then
            -- Terrarium: the front leg of a side, whichever leg that is since it turned
            local near, front, best = rng.look:random() < 0.5, nil, -math.huge
            for i, leg in ipairs(self.legs) do
                if leg.def.near == near and leg.def.reach > best then front, best = i, leg.def.reach end
            end
            self.tap = {leg = front, t = 0}
            self.next_tap = rng.range(rng.look, 4, 9)
        end
    end
    if self.tap then
        self.tap.t = self.tap.t + dt
        if self.tap.t > 0.7 or moving or self.mode ~= 'attached' then self.tap = nil end
    end

    -- Terrarium: courting, it faces its partner, and a front foot taps toward
    -- it on each beat, the near one and then the far (#22)
    local court = ctx.court
    if court then self.court = court end
    self.ardour = self.ardour + ((court and 1 or 0) - self.ardour) * min(1, dt * 1.5)
    if self.ardour < 0.005 then self.ardour, self.court = 0, nil end
    self.court_tap, self.flush = nil, 0
    if self.court and self.mode == 'attached' then
        local c, k = self.court, self.ardour
        if court then
            self.tap = nil
            local tx, ty = self:frame()
            if (c.x - self.a.x) * tx + (c.y - self.a.y) * ty < -1 then self.facing = -self.facing end
        end
        local b = c.beat / TAP_BEAT
        local near, front, best = math.floor(b) % 2 == 0, nil, -math.huge
        for i, leg in ipairs(self.legs) do
            if leg.def.near == near and leg.def.reach > best then front, best = i, leg.def.reach end
        end
        local up = sin((b % 1) * pi)
        self.court_tap = {leg = front, lift = up * 9 * self.scale * k}
        self.flush = k * up
    end

    -- Legs
    if self.facing ~= self.legs_facing then self:turn_legs() end
    local stepping = {false, false}
    for _, leg in ipairs(self.legs) do
        if leg.stepping then stepping[leg.def.group] = true end
    end
    -- Terrarium: a group steps as one. When any planted foot of a group has
    -- fallen a stride behind where it would stand still, or its leg is near
    -- full stretch, the whole group lifts together, but only while the other
    -- group stands (the one further behind goes first). Each foot swings to
    -- where it reaches ahead, so a stride is the lead plus the trigger, and a
    -- step is quick enough for both groups to keep up at this speed. The
    -- body is held back while a leg strains, and waits for one it can't
    -- reach, so it never goes ahead of its legs.
    local need, len = {0, 0}, self.bones[1] + self.bones[2] + self.bones[3]
    local lead = self:lead()
    local step_time = STEP_TIME * (moving and 1 or 1.6)
    if moving then step_time = max(0.05, min(step_time, (lead + self.step_dist) / (2.4 * self.speed))) end
    local ftx, fty = self:frame()
    local strained, stuck = false, false
    if self.mode ~= 'air' then
        for _, leg in ipairs(self.legs) do
            leg.rx, leg.ry, leg.found = self:rest_spot(leg.def, level, lead)
            leg.lift, leg.urgent = false, false
            if not leg.stepping then
                local sx, sy = self:rest_spot(leg.def, level, 0)
                local ddx, ddy = sx - leg.foot.x, sy - leg.foot.y
                local behind = sqrt(ddx * ddx + ddy * ddy) / self.step_dist
                local hx, hy = self:hip(leg.def)
                local stretch = sqrt((leg.foot.x - hx) ^ 2 + (leg.foot.y - hy) ^ 2) / len
                leg.urgent = stretch > 1
                -- (and how far it will be one step from now, if it waits on
                -- the other group: the hip goes on ahead)
                local ahead = self.speed * step_time
                hx, hy = hx + ftx * ahead, hy + fty * ahead
                local soon = sqrt((leg.foot.x - hx) ^ 2 + (leg.foot.y - hy) ^ 2) / len
                local g = leg.def.group
                need[g] = max(need[g], behind, soon > 0.97 and 1.01 or 0)
                if stretch > 0.97 then strained = true end
            end
        end
        -- (when both groups are falling behind together, as they do from a
        -- standing start or a turn, the further one goes early, half a
        -- stride in, so the two settle half a cycle apart)
        local go = need[1] >= need[2] and 1 or 2
        local due = need[go] > 1 or min(need[1], need[2]) > 0.5
        if not due or stepping[1] or stepping[2] then go = nil end
        for _, leg in ipairs(self.legs) do
            if leg.def.group == go and not leg.stepping then
                local ddx, ddy = leg.rx - leg.foot.x, leg.ry - leg.foot.y
                -- (a foot already where it wants to be stays put)
                if ddx * ddx + ddy * ddy > (self.step_dist * 0.25) ^ 2 then leg.lift = true end
            end
        end
        -- A foot the leg can no longer reach lifts out of turn, but never
        -- leaves fewer than half the legs down: then the body waits for it.
        local down = 0
        for _, leg in ipairs(self.legs) do
            if not leg.stepping and not leg.lift then down = down + 1 end
        end
        for _, leg in ipairs(self.legs) do
            if leg.urgent and not leg.lift and not leg.stepping then
                if down - 1 >= #self.legs / 2 then
                    leg.lift, down = true, down - 1
                else
                    stuck = true
                end
            end
        end
        -- A planted leg at full stretch that has to wait its turn holds the
        -- body back until the other group is down
        strained = strained and not go
    end
    for i, leg in ipairs(self.legs) do
        local def = leg.def
        local hx, hy = self:hip(def)
        local fx, fy

        if self.mode == 'air' then
            -- Tucked: feet drawn in under the body
            local tx, ty = self:frame()
            local tuck = self.mover.vy < 0 and 0.45 or 0.75
            fx = hx + tx * def.reach * tuck - fnx * 8
            fy = hy + ty * def.reach * tuck - fny * 8
            leg.foot.x = leg.foot.x + (fx - leg.foot.x) * min(1, dt * 14)
            leg.foot.y = leg.foot.y + (fy - leg.foot.y) * min(1, dt * 14)
            leg.stepping, leg.planted = false, false
            fx, fy = outside(level, leg.foot.x, leg.foot.y) -- Terrarium: tucked, not through a lip (#17)
        else
            if leg.stepping then
                -- (aiming at where it will land, not where it would have)
                leg.to.x, leg.to.y, leg.grounded = leg.rx, leg.ry, leg.found
                leg.t = min(1, leg.t + dt / step_time)
                local e = leg.t * leg.t * (3 - 2 * leg.t)
                local lift = sin(leg.t * pi) * 7 * self.scale
                fx = leg.from.x + (leg.to.x - leg.from.x) * e + fnx * lift
                fy = leg.from.y + (leg.to.y - leg.from.y) * e + fny * lift
                -- Terrarium: a step round a corner cuts across it; the foot
                -- goes round the stone instead (#17)
                fx, fy = outside(level, fx, fy)
                if leg.t >= 1 then
                    leg.stepping = false
                    leg.foot.x, leg.foot.y = leg.to.x, leg.to.y
                    ctx.events:emit('step', {x = leg.to.x, y = leg.to.y, who = self, near = def.near})
                end
            else
                if leg.lift then
                    leg.stepping, leg.t = true, 0
                    leg.from.x, leg.from.y = leg.foot.x, leg.foot.y
                    leg.to.x, leg.to.y = leg.rx, leg.ry
                    leg.grounded = leg.found -- Terrarium: whether the raycasts found ground there
                end
                fx, fy = leg.foot.x, leg.foot.y
            end
            -- Idle tap animation overrides a front foot
            if self.tap and self.tap.leg == i then
                local t = self.tap.t
                local lift = max(0, sin(t / 0.7 * pi * 2)) * 6
                fx, fy = fx + fnx * lift, fy + fny * lift
            end
            -- Terrarium: and so does a courting one, up and toward its partner
            if self.court_tap and self.court_tap.leg == i then
                local lift = self.court_tap.lift
                fx, fy = fx + fnx * lift + ftx * lift * 0.6, fy + fny * lift + fty * lift * 0.6
            end
        end

        -- Knees up and out: pole above the hip, pushed along the reach
        local tx, ty = self:frame()
        local s = def.reach >= 0 and 1 or -1
        local out = (def.near and 18 or 13) * self.scale
        local px, py = hx + fnx * 16 * self.scale + tx * s * out, hy + fny * 16 * self.scale + ty * s * out
        fabrik.solve(leg.chain, hx, hy, fx, fy, px, py, 6, 0.4)
        -- Terrarium: then close on the foot with the knee where the pole put
        -- it (the pole's nudge on every pass leaves a stretched leg short)
        fabrik.solve(leg.chain, hx, hy, fx, fy, nil, nil, 4)
        -- Terrarium: a knee or ankle the pole bent into the scenery (at the
        -- foot of a wall, the knee goes up and on into it) comes back out to the
        -- nearest clear spot, and the leg closes on the foot again from there
        -- (#17). Pushed rather than flipped, so the knee never pops.
        if clear_joints(leg.chain.joints, level) then
            fabrik.solve(leg.chain, hx, hy, fx, fy, nil, nil, 4)
            clear_joints(leg.chain.joints, level)
        end
        -- Terrarium: a foot out of reach leaves the leg pointing at it, and on
        -- a riser just under a corner that line cuts through the corner, so the
        -- tip comes out of the stone the same way
        local tip = leg.chain.joints[#leg.chain.joints]
        tip.x, tip.y = outside(level, tip.x, tip.y)
    end

    if stuck then
        self.gait, self.pace = 0, 0
    elseif strained then
        self.gait = self.gait + (0.3 - self.gait) * min(1, dt * 30)
    else
        self.gait = min(1, self.gait + dt * 4)
    end
    if not self.crawled then self.pace = self.pace * max(0, 1 - dt * 10) end
    self.crawled = false
    if self.mode == 'attached' and not moving then self:halt(dt) end
    self.speed = self.speed * 0.98

    -- Eyes follow the target
    local bx, by = self:body_center()
    local lx, ly = 0, 0
    if ctx.look_at then
        local ddx, ddy = ctx.look_at.x - bx, ctx.look_at.y - by
        local dd = sqrt(ddx * ddx + ddy * ddy)
        if dd > 1 then lx, ly = ddx / dd, ddy / dd end
    end
    self.face:update(dt, lx, ly, not ctx.look_at)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- Terrarium: a banded spider's near legs have the mark colour at each knee
local function draw_leg(leg, far, sk, marks)
    local j = leg.chain.joints
    local widths = far and {1.8, 1.4, 0.9} or {2.6, 2.0, 1.2}
    local col = far and sk.leg_far or sk.leg
    for i = 1, #j - 1 do
        love.graphics.setColor(sk.outline)
        love.graphics.setLineWidth(widths[i] + 1.4)
        love.graphics.line(j[i].x, j[i].y, j[i + 1].x, j[i + 1].y)
    end
    for i = 1, #j - 1 do
        love.graphics.setColor(col)
        love.graphics.setLineWidth(widths[i])
        love.graphics.line(j[i].x, j[i].y, j[i + 1].x, j[i + 1].y)
    end
    if not far and sk.pattern == 'banded' then
        love.graphics.setColor(sk.mark)
        for i = 2, #j - 1 do
            local a, b, k = j[i - 1], j[i + 1], j[i]
            local pts = {k.x + (a.x - k.x) * 0.25, k.y + (a.y - k.y) * 0.25, k.x, k.y,
                         k.x + (b.x - k.x) * 0.25, k.y + (b.y - k.y) * 0.25}
            love.graphics.setLineWidth(widths[i])
            love.graphics.line(pts)
            marks[#marks + 1] = {'line', pts, widths[i]}
        end
    elseif not far then
        love.graphics.setColor(sk.joint[1], sk.joint[2], sk.joint[3], 0.8)
        love.graphics.circle('fill', j[2].x, j[2].y, 1.3)
        love.graphics.circle('fill', j[3].x, j[3].y, 0.9)
    end
    love.graphics.setLineWidth(1)
end

function Spider:draw(ctx)
    local tx, ty, nx, ny = self:frame()
    local bx, by = self:body_center()
    local angle = atan2(ty, tx)
    local lx, ly = ctx.light_dir(bx, by)
    local breathe = 1 + 0.035 * sin(self.clock * 2.2)
    local sk = self.skin
    local pattern = sk.pattern
    local marks, local_marks = {}, {} -- Terrarium: what glows, in the jar and in the body's frame

    for _, leg in ipairs(self.legs) do
        if not leg.def.near then draw_leg(leg, true, sk, marks) end
    end

    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(angle)
    love.graphics.scale(1, self.facing)
    -- In the body's local frame: +x is forward, -y is "up" (the normal)
    -- Abdomen
    local ax, ay = -10, -3
    love.graphics.setColor(sk.outline)
    love.graphics.ellipse('fill', ax, ay, 11.5 * breathe, 9.2 * breathe)
    love.graphics.setColor(sk.body)
    love.graphics.ellipse('fill', ax, ay, 10.3 * breathe, 8 * breathe)
    -- Lit side of the abdomen: offset toward the light in local space
    local llx = lx * cos(-angle) - ly * sin(-angle)
    local lly = (lx * sin(-angle) + ly * cos(-angle)) * self.facing
    love.graphics.setColor(sk.body_hi[1], sk.body_hi[2], sk.body_hi[3], 0.85)
    love.graphics.ellipse('fill', ax + llx * 3, ay + lly * 3, 6.5 * breathe, 4.6 * breathe)
    -- Markings. Terrarium: Character's chevrons are the banded kind (#15).
    love.graphics.setColor(sk.mark[1], sk.mark[2], sk.mark[3], 0.85)
    if pattern == 'banded' then
        love.graphics.setLineWidth(1.4)
        for k = 0, 2 do
            local cx = ax - 5 + k * 3.6
            local pts = {cx - 1.6, ay - 5.2 + k * 0.3, cx + 0.9, ay - 3.4, cx - 1.6, ay - 1.6 - k * 0.3}
            love.graphics.line(pts)
            local_marks[#local_marks + 1] = {'line', pts, 1.4}
        end
    elseif pattern == 'spotted' then
        -- pairs down the back, smaller toward the spinnerets
        for k = 0, 2 do
            local x = ax + 4 - k * 4.4
            local r = (2.1 - k * 0.35) * breathe * (0.85 + 0.3 * Skin.hash(sk.seed, k))
            for _, y in ipairs({ay - 5.6 + k * 0.7, ay - 1.6 + k * 0.2}) do
                love.graphics.circle('fill', x, y, r)
                local_marks[#local_marks + 1] = {'disc', x, y, r}
            end
        end
    elseif pattern == 'striped' then
        -- along the top of the abdomen, following its curve
        local pts = {}
        for k = 0, 8 do
            local a = pi * (1.12 + 0.76 * k / 8)
            pts[#pts + 1] = ax + cos(a) * 7.4 * breathe
            pts[#pts + 1] = ay + sin(a) * 5.4 * breathe
        end
        love.graphics.setLineWidth(1.8)
        love.graphics.line(pts)
        local_marks[#local_marks + 1] = {'line', pts, 1.8}
    end
    love.graphics.setLineWidth(1)
    -- Thorax / head. Terrarium: a capped spider's is the mark colour.
    local capped = pattern == 'capped'
    love.graphics.setColor(sk.outline)
    love.graphics.ellipse('fill', 4.5, -1, 7.4, 6)
    love.graphics.setColor(capped and sk.mark or sk.body)
    love.graphics.ellipse('fill', 4.5, -1, 6.2, 4.9)
    love.graphics.setColor(sk.body_hi[1], sk.body_hi[2], sk.body_hi[3], capped and 0.3 or 0.7)
    love.graphics.ellipse('fill', 4.5 + llx * 2, -1 + lly * 2, 3.4, 2.2)
    if capped then local_marks[#local_marks + 1] = {'ellipse', 4.5, -1, 5.2, 4.0} end
    if pattern == 'striped' then
        local pts = {0, -4.4, 4.5, -5.2, 8.5, -4.2}
        love.graphics.setColor(sk.mark[1], sk.mark[2], sk.mark[3], 0.85)
        love.graphics.setLineWidth(1.6)
        love.graphics.line(pts)
        love.graphics.setLineWidth(1)
        local_marks[#local_marks + 1] = {'line', pts, 1.6}
    end
    -- Pedipalps
    love.graphics.setColor(sk.leg)
    love.graphics.setLineWidth(1.6)
    love.graphics.line(9.5, 1, 13, 3.5, 13.5, 5.5)
    love.graphics.line(9, 2.5, 11.5, 5, 11.5, 6.8)
    love.graphics.setLineWidth(1)
    -- Eyes: a cluster of amber glints, blinking together
    local open = self.face:openness()
    local gx, gy = self.face.gaze_x * 0.6, self.face.gaze_y * 0.6
    love.graphics.setColor(COLORS.eye[1], COLORS.eye[2], COLORS.eye[3], 0.95)
    love.graphics.ellipse('fill', 8.4 + gx, -3.2 + gy, 1.7, 1.7 * max(0.1, open))
    love.graphics.ellipse('fill', 6.0 + gx, -4.0 + gy, 1.3, 1.3 * max(0.1, open))
    love.graphics.circle('fill', 9.6 + gx, -1.4 + gy, 0.8)
    love.graphics.circle('fill', 4.4 + gx, -4.4 + gy, 0.7)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle('fill', 8.0 + gx, -3.7 + gy, 0.55)
    love.graphics.pop()

    for _, leg in ipairs(self.legs) do
        if leg.def.near then draw_leg(leg, false, sk, marks) end
    end
    self.marks, self.local_marks = marks, local_marks
    self.mark_frame = {bx, by, angle, self.facing}
end

-- Emissive bits drawn after lighting so they stay bright.
-- Terrarium: and the markings, shining as the lamp dims (#15)
function Spider:draw_emissive(ctx)
    local k = Skin.shine(self.skin, ctx and ctx.light, self.flush)
    local f = self.mark_frame
    if k > 0.01 and f then
        Skin.paint_glow(self.marks, self.skin, k)
        love.graphics.push()
        love.graphics.translate(f[1], f[2])
        love.graphics.rotate(f[3])
        love.graphics.scale(1, f[4])
        Skin.paint_glow(self.local_marks, self.skin, k)
        love.graphics.pop()
    end
    local bx, by = self:body_center()
    local tx, ty, nx, ny = self:frame()
    local ex, ey = bx + tx * 8 + nx * 3.4, by + ty * 8 + ny * 3.4
    love.graphics.setColor(1, 0.75, 0.4, 0.5 * self.face:openness())
    love.graphics.circle('fill', ex, ey, 2.2)
end

-- X-ray: bones, joints, footholds and the surface normal it rides
function Spider:draw_xray(ctx)
    local c = self.color_name
    local level = self.world.level
    love.graphics.setLineWidth(1.3)
    for _, leg in ipairs(self.legs) do
        local j = leg.chain.joints
        local a = leg.def.near and 0.9 or 0.45
        love.graphics.setColor(c[1], c[2], c[3], a)
        for i = 1, #j - 1 do love.graphics.line(j[i].x, j[i].y, j[i + 1].x, j[i + 1].y) end
        love.graphics.setColor(1, 0.96, 0.88, a)
        for i = 1, #j do love.graphics.circle('fill', j[i].x, j[i].y, i == 1 and 1.6 or 1.2) end
        if leg.def.near and self.mode == 'attached' then
            local rx, ry = self:rest_spot(leg.def, level)
            love.graphics.setColor(c[1], c[2], c[3], 0.35)
            love.graphics.circle('line', rx, ry, 2.4)
        end
    end
    local tx, ty, nx, ny = self:frame()
    local bx, by = self:body_center()
    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(math.atan2(ty, tx))
    love.graphics.scale(1, self.facing)
    love.graphics.setColor(c[1], c[2], c[3], 0.85)
    love.graphics.ellipse('line', -10, -3, 10.3, 8)
    love.graphics.ellipse('line', 4.5, -1, 6.2, 4.9)
    love.graphics.pop()
    love.graphics.setColor(1, 0.96, 0.88, 0.6)
    love.graphics.line(self.a.x, self.a.y, self.a.x + nx * 18, self.a.y + ny * 18)
    love.graphics.circle('fill', self.a.x, self.a.y, 1.6)
    love.graphics.setLineWidth(1)
end

function Spider:draw_debug()
    local level = self.world.level
    for _, leg in ipairs(self.legs) do
        local rx, ry = self:rest_spot(leg.def, level)
        love.graphics.setColor(1, 0.8, 0.3, 0.7)
        love.graphics.circle('line', rx, ry, 2.5)
        love.graphics.setColor(0.4, 1, 0.6, 0.6)
        love.graphics.line(leg.foot.x, leg.foot.y, rx, ry)
    end
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.circle('fill', self.a.x, self.a.y, 2.5)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.line(self.a.x, self.a.y, self.a.x + self.nx * 16, self.a.y + self.ny * 16)
end

--------------------------------------------------------------------------------
-- Terrarium: what the self-test knows of a spider (#73); see Worm.LIMITS
Spider.LIMITS = {
    -- of its planted feet, over every look, the ones its legs don't reach
    {measure = 'slip', most = 0.02, says = "stood on feet it can't reach %.1f%% of the time", scale = 100},
}

-- Fold a look at spider `c` into `m`: of the feet it has planted (not
-- stepping or tapping), how many its legs don't reach or that stand on
-- nothing, counted over every look while it's on a surface
function Spider.health(c, m, dt)
    local bad, planted = 0, 0
    if c.mode == 'attached' then
        for _, leg in ipairs(c.legs) do
            if not leg.stepping and not (c.tap and c.legs[c.tap.leg] == leg) then
                planted = planted + 1
                local tip = leg.chain.joints[#leg.chain.joints]
                if (tip.x - leg.foot.x) ^ 2 + (tip.y - leg.foot.y) ^ 2 > 4 or not leg.grounded then bad = bad + 1 end
            end
        end
    end
    m.slips, m.planted = (m.slips or 0) + bad, (m.planted or 0) + planted
    m.slip = m.slips / max(1, m.planted)
    return m
end

-- How big spider `c` is built now: its reach
function Spider.grown_size(c) return c.scale end

-- `genome` with the body the sim works hardest for: the most legs, the longest
function Spider.heaviest(genome)
    local legs = Genome.spider.by_name.legs.pick
    genome.legs, genome.reach = legs[#legs], Genome.spider.by_name.reach.real[2]
    return genome
end

-- How far either side of its anchor it lies, as a token (bodies/token.lua): its legs
function Spider.half(t) return 30 * t.scale end

return Spider
