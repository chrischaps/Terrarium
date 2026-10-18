-- From chrischaps/Character @ 925c35b (creatures/spider.lua)
-- Spider: eight FABRIK legs that find their own footing.
--
-- The body rides a point on any surface - floor, wall or ceiling - with the
-- surface normal telling it which way is "up". Each foot has a rest spot
-- relative to the body, projected onto real geometry with raycasts. When a
-- planted foot falls too far behind its rest spot, it lifts and arcs to the
-- new one; alternating leg groups keep it walking on four legs at a time.
-- Jumps hand the body to the shared ballistic mover; the legs tuck in flight.

local Base = require('bodies.base')
local fabrik = require('bodies.fabrik')
local rng = require('core.rng')

local Spider = {}
Spider.__index = Spider

local sqrt, sin, cos, abs, min, max, pi, atan2 = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max, math.pi, math.atan2

Spider.profile = {
    name = 'spider',
    radius = 9, height = 20, step = 20,
    walk_speed = 120, walk_accel = 900,
    jump_vx = 300, jump_vy = 470, air_accel = 650,
    anticipation = 0.15,
    climbs = true,
    crawl_speed = 115,
}

local RIDE = 12
local BONES = {14, 15, 11}
local STEP_DIST = 13
local STEP_TIME = 0.1

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

function Spider.new(x, y, world)
    local self = setmetatable({}, Spider)
    self.profile = Spider.profile
    self.world = world
    self.color_name = {1, 0.78, 0.5}
    self.a = {x = x, y = y}                 -- anchor on the surface
    self.nx, self.ny = 0, -1                -- smoothed surface normal
    self.tnx, self.tny = 0, -1              -- target normal
    self.facing = 1
    self.mode = 'attached'                  -- attached | anticipate | air
    self.mover = Base.Mover.new(x, y, Spider.profile)
    self.solid = nil
    self.face = Base.Face.new()
    self.clock = 0
    self.speed = 0
    self.bob = 0
    self.tap = nil
    self.next_tap = rng.range(rng.look, 3, 7)
    self.legs = {}
    for i, def in ipairs(LEGS) do
        local hx, hy = self:hip(def)
        local leg = {
            def = def,
            chain = fabrik.chain(hx, hy, BONES, 0, 1),
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
function Spider:get_description() return "Eight FABRIK legs that step to real footholds" end

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
    self.mover = Base.Mover.new(x, y, Spider.profile)
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
    local ride = RIDE + self.bob
    return self.a.x + nx * ride, self.a.y + ny * ride
end

function Spider:hip(def)
    local tx, ty, nx, ny = self:frame()
    local bx, by = self:body_center()
    return bx + tx * def.hip + nx * 1.5, by + ty * def.hip + ny * 1.5
end

-- Where this foot wants to stand, found on real geometry
function Spider:rest_spot(def, level)
    local tx, ty, nx, ny = self:frame()
    local lead = self.speed * 0.09                       -- reach ahead when moving
    local reach = def.reach + lead + (def.near and 0 or 1.5)
    local ox, oy = self.a.x + tx * reach + nx * 14, self.a.y + ty * reach + ny * 14
    -- Straight down onto the surface
    local d = level:raycast(ox, oy, -nx, -ny, 34)
    if d then return ox - nx * d, oy - ny * d, true end
    -- Around a convex corner: back toward the body
    local s = reach >= 0 and -1 or 1
    local cx, cy = self.a.x + tx * reach - nx * 6, self.a.y + ty * reach - ny * 6
    d = level:raycast(cx, cy, tx * s, ty * s, abs(reach) + 6)
    if d then return cx + tx * s * d, cy + ty * s * d, true end
    -- Into a concave corner: forward along the tangent
    d = level:raycast(self.a.x + nx * 4, self.a.y + ny * 4, tx * -s, ty * -s, abs(reach) + 8)
    if d and d < abs(reach) + 8 then
        return self.a.x + nx * 4 - tx * s * d, self.a.y + ny * 4 - ty * s * d, true
    end
    return self.a.x + tx * reach, self.a.y + ty * reach, false
end

function Spider:plant_all()
    local level = self.world and self.world.level
    for _, leg in ipairs(self.legs) do
        local fx, fy = self.a.x + leg.def.reach, self.a.y
        if level then fx, fy = self:rest_spot(leg.def, level) end
        leg.foot.x, leg.foot.y = fx, fy
        leg.t, leg.stepping, leg.planted = 1, false, true
        local hx, hy = self:hip(leg.def)
        local _, _, nx, ny = self:frame()
        for _ = 1, 3 do
            fabrik.solve(leg.chain, hx, hy, fx, fy, hx + nx * 18, hy + ny * 18)
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
    local speed = self.profile.crawl_speed * (speed_scale or 1)
    local step = min(d, speed * dt)
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
            self.tap = {leg = rng.look:random() < 0.5 and 1 or 5, t = 0}
            self.next_tap = rng.range(rng.look, 4, 9)
        end
    end
    if self.tap then
        self.tap.t = self.tap.t + dt
        if self.tap.t > 0.7 or moving or self.mode ~= 'attached' then self.tap = nil end
    end

    -- Legs
    local stepping = {false, false}
    for _, leg in ipairs(self.legs) do
        if leg.stepping then stepping[leg.def.group] = true end
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
            local rx, ry = self:rest_spot(def, level)
            if leg.stepping then
                leg.t = min(1, leg.t + dt / (STEP_TIME * (moving and 1 or 1.6)))
                local e = leg.t * leg.t * (3 - 2 * leg.t)
                local lift = sin(leg.t * pi) * 7
                fx = leg.from.x + (leg.to.x - leg.from.x) * e + fnx * lift
                fy = leg.from.y + (leg.to.y - leg.from.y) * e + fny * lift
                if leg.t >= 1 then
                    leg.stepping = false
                    leg.foot.x, leg.foot.y = leg.to.x, leg.to.y
                    ctx.events:emit('step', {x = leg.to.x, y = leg.to.y, who = self, near = def.near})
                end
            else
                local ddx, ddy = rx - leg.foot.x, ry - leg.foot.y
                local dist2 = ddx * ddx + ddy * ddy
                local other = def.group == 1 and 2 or 1
                local need = dist2 > STEP_DIST * STEP_DIST
                local urgent = dist2 > (STEP_DIST * 2.2) ^ 2
                if (need and not stepping[other]) or urgent then
                    leg.stepping, leg.t = true, 0
                    leg.from.x, leg.from.y = leg.foot.x, leg.foot.y
                    leg.to.x, leg.to.y = rx, ry
                    stepping[def.group] = true
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
        local out = def.near and 18 or 13
        local px, py = hx + fnx * 16 + tx * s * out, hy + fny * 16 + ty * s * out
        fabrik.solve(leg.chain, hx, hy, fx, fy, px, py, 6, 0.4)
    end

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
