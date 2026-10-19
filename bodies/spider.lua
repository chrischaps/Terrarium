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

local Base = require('bodies.base')
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
local navs = {}
function Spider.nav_profile(genome)
    local k, lo, hi = Genome.bucket('spider', 'reach', genome and genome.reach or 1, Spider.BUCKETS)
    if navs[k] then return navs[k] end
    local p = {}
    for key, v in pairs(Spider.profile_for(lo)) do p[key] = v end
    p.reach, p.reaches, p.bucket = nil, {lo, hi}, k
    navs[k] = p
    return p
end

local RIDE = 12
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

local COLORS = {
    body     = {0.26, 0.17, 0.27},
    body_hi  = {0.56, 0.38, 0.48},
    mark     = {0.96, 0.62, 0.30},
    leg      = {0.40, 0.27, 0.38},
    leg_far  = {0.20, 0.14, 0.22},
    joint    = {0.62, 0.42, 0.48},
    outline  = {0.07, 0.04, 0.08, 1},
    eye      = {1.00, 0.80, 0.45},
}

function Spider.new(x, y, world, genome)
    local self = setmetatable({}, Spider)
    -- Terrarium: the body from its genes
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
    self.world = world
    self.color_name = {1, 0.78, 0.5}
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

-- Body frame: tangent (along the surface, toward facing) and normal (up)
function Spider:frame()
    local nx, ny = self.nx, self.ny
    local tx, ty = -ny * self.facing, nx * self.facing
    return tx, ty, nx, ny
end

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
    -- Straight down onto the surface
    local d = level:raycast(ox, oy, -nx, -ny, 34 * k)
    if d then return ox - nx * d, oy - ny * d, true end
    -- Around a convex corner: back toward the body
    local s = reach >= 0 and -1 or 1
    local cx, cy = self.a.x + tx * reach - nx * 6 * k, self.a.y + ty * reach - ny * 6 * k
    d = level:raycast(cx, cy, tx * s, ty * s, abs(reach) + 6 * k)
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
-- Controller interface
--------------------------------------------------------------------------------

function Spider:ready() return self.mode == 'attached' end
function Spider:airborne() return self.mode == 'air' end
function Spider:support() return self.solid end
function Spider:normal() return self.nx, self.ny end

-- Crawl straight toward a node; blends the normal across the move.
-- Returns true on arrival.
function Spider:crawl_to(node, dt, speed_scale)
    if self.mode ~= 'attached' then return false end
    local dx, dy = node.x - self.a.x, node.y - self.a.y
    local d = sqrt(dx * dx + dy * dy)
    local speed = self.profile.crawl_speed * (speed_scale or 1) * self.gait -- Terrarium: held back by a straining leg
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

function Spider:halt(dt)
    self.speed = self.speed * max(0, 1 - dt * 10)
end

function Spider:launch(vx, vy)
    if self.mode ~= 'attached' then return false end
    self.mover = Base.Mover.new(self.a.x, self.a.y, self.profile)
    self.mover.solid = self.solid
    self.mover:launch(vx, vy)
    self.mode = 'anticipate'
    if vx ~= 0 then self.facing = vx > 0 and 1 or -1 end
    self.tnx, self.tny = 0, -1
    return true
end

function Spider:steer(tx, ty, dt)
    if self.mode == 'air' then self.mover:steer(tx, ty, dt) end
end

--------------------------------------------------------------------------------
-- Simulation
--------------------------------------------------------------------------------

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
        self.bob = self.bob + ((0.8 * sin(self.clock * 2.2)) - self.bob) * min(1, dt * 6)
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
    if self.mode == 'attached' and not moving then
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
            fx, fy = leg.foot.x, leg.foot.y
        else
            if leg.stepping then
                -- (aiming at where it will land, not where it would have)
                leg.to.x, leg.to.y, leg.grounded = leg.rx, leg.ry, leg.found
                leg.t = min(1, leg.t + dt / step_time)
                local e = leg.t * leg.t * (3 - 2 * leg.t)
                local lift = sin(leg.t * pi) * 7 * self.scale
                fx = leg.from.x + (leg.to.x - leg.from.x) * e + fnx * lift
                fy = leg.from.y + (leg.to.y - leg.from.y) * e + fny * lift
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

local function draw_leg(leg, far)
    local j = leg.chain.joints
    local widths = far and {1.8, 1.4, 0.9} or {2.6, 2.0, 1.2}
    local col = far and COLORS.leg_far or COLORS.leg
    for i = 1, #j - 1 do
        love.graphics.setColor(COLORS.outline)
        love.graphics.setLineWidth(widths[i] + 1.4)
        love.graphics.line(j[i].x, j[i].y, j[i + 1].x, j[i + 1].y)
    end
    for i = 1, #j - 1 do
        love.graphics.setColor(col)
        love.graphics.setLineWidth(widths[i])
        love.graphics.line(j[i].x, j[i].y, j[i + 1].x, j[i + 1].y)
    end
    if not far then
        love.graphics.setColor(COLORS.joint[1], COLORS.joint[2], COLORS.joint[3], 0.8)
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

    for _, leg in ipairs(self.legs) do
        if not leg.def.near then draw_leg(leg, true) end
    end

    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(angle)
    love.graphics.scale(1, self.facing)
    -- In the body's local frame: +x is forward, -y is "up" (the normal)
    -- Abdomen
    local ax, ay = -10, -3
    love.graphics.setColor(COLORS.outline)
    love.graphics.ellipse('fill', ax, ay, 11.5 * breathe, 9.2 * breathe)
    love.graphics.setColor(COLORS.body)
    love.graphics.ellipse('fill', ax, ay, 10.3 * breathe, 8 * breathe)
    -- Lit side of the abdomen: offset toward the light in local space
    local llx = lx * cos(-angle) - ly * sin(-angle)
    local lly = (lx * sin(-angle) + ly * cos(-angle)) * self.facing
    love.graphics.setColor(COLORS.body_hi[1], COLORS.body_hi[2], COLORS.body_hi[3], 0.85)
    love.graphics.ellipse('fill', ax + llx * 3, ay + lly * 3, 6.5 * breathe, 4.6 * breathe)
    -- Markings: amber chevrons
    love.graphics.setColor(COLORS.mark[1], COLORS.mark[2], COLORS.mark[3], 0.75)
    love.graphics.setLineWidth(1.3)
    for k = 0, 2 do
        local cx = ax - 5 + k * 3.6
        love.graphics.line(cx - 1.6, ay - 5.2 + k * 0.3, cx + 0.9, ay - 3.4, cx - 1.6, ay - 1.6 - k * 0.3)
    end
    love.graphics.setLineWidth(1)
    -- Thorax / head
    love.graphics.setColor(COLORS.outline)
    love.graphics.ellipse('fill', 4.5, -1, 7.4, 6)
    love.graphics.setColor(COLORS.body)
    love.graphics.ellipse('fill', 4.5, -1, 6.2, 4.9)
    love.graphics.setColor(COLORS.body_hi[1], COLORS.body_hi[2], COLORS.body_hi[3], 0.7)
    love.graphics.ellipse('fill', 4.5 + llx * 2, -1 + lly * 2, 3.4, 2.2)
    -- Pedipalps
    love.graphics.setColor(COLORS.leg)
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
        if leg.def.near then draw_leg(leg, false) end
    end
end

-- Emissive bits drawn after lighting so they stay bright
function Spider:draw_emissive()
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

return Spider
