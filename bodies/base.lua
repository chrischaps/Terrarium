-- From chrischaps/Character @ 925c35b (creatures/base.lua)
-- Creature base: the kinematic "anchor" every creature rides on, plus shared
-- face behaviour.
--
-- The anchor is where the creature meets the world (its feet on a surface).
-- It is deliberately exact - integrated with the same closed-form gravity the
-- ballistics module assumes - so a planned jump lands where it was planned.
-- The soft, physical bodies (verlet worm, pressure blob, IK spider legs) hang
-- off the anchor and are free to be loose and expressive.
--
-- States: ground -> anticipate -> air -> ground

local ballistics = require('nav.ballistics')
local rng = require('core.rng')

local Base = {}

local G = ballistics.GRAVITY
local abs, min, max = math.abs, math.min, math.max

--------------------------------------------------------------------------------
-- Mover: the anchor
--------------------------------------------------------------------------------

local Mover = {}
Mover.__index = Mover
Base.Mover = Mover

function Mover.new(x, y, profile)
    return setmetatable({
        x = x, y = y, vx = 0, vy = 0,
        profile = profile,
        state = 'ground',
        solid = nil,
        facing = 1,
        timer = 0,
        air_time = 0,
        pending = nil,         -- launch velocity waiting out anticipation
        events = {},           -- 'jump', 'land', 'walkoff' (drained by owner)
        walking = false,
    }, Mover)
end

function Mover:emit(kind, data)
    data = data or {}
    data.kind = kind
    self.events[#self.events + 1] = data
end

function Mover:drain()
    local ev = self.events
    self.events = {}
    return ev
end

function Mover:grounded()
    return self.state == 'ground'
end

function Mover:airborne()
    return self.state == 'air'
end

-- Request ground movement this step: dir -1/0/1, speed px/s
function Mover:walk(dir, speed)
    self.want_dir = dir
    self.want_speed = speed or self.profile.walk_speed
end

function Mover:launch(vx, vy, anticipation)
    if self.state ~= 'ground' then return false end
    self.pending = {vx = vx, vy = vy}
    self.state = 'anticipate'
    self.timer = anticipation or self.profile.anticipation or 0.12
    self.vx = 0
    if vx ~= 0 then self.facing = vx > 0 and 1 or -1 end
    return true
end

-- Leave the ground immediately with this velocity (walk-off falls)
function Mover:release(vx, vy)
    self.state = 'air'
    self.vx, self.vy = vx, vy
    self.air_time = 0
    self.solid = nil
end

-- Air control: nudge vx so we come down on (tx, ty)
function Mover:steer(tx, ty, dt)
    if self.state ~= 'air' then return end
    local t = ballistics.time_to_y(self.y, self.vy, ty)
    if not t or t < 0.04 then return end
    local want = (tx - self.x) / t
    local limit = self.profile.jump_vx * 1.15
    want = max(-limit, min(limit, want))
    local accel = (self.profile.air_accel or 700) * dt
    if self.vx < want then self.vx = min(want, self.vx + accel)
    else self.vx = max(want, self.vx - accel) end
end

function Mover:update(level, dt)
    local p = self.profile
    local r = p.radius

    if self.state == 'anticipate' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            local v = self.pending
            self.pending = nil
            self:release(v.vx, v.vy)
            self:emit('jump', {vx = v.vx, vy = v.vy})
        end
        self.want_dir = nil
        return
    end

    if self.state == 'ground' then
        local dir = self.want_dir or 0
        local target = dir * (self.want_speed or p.walk_speed)
        local accel = (p.walk_accel or 900) * dt
        if self.vx < target then self.vx = min(target, self.vx + accel)
        else self.vx = max(target, self.vx - accel) end
        self.walking = dir ~= 0
        if dir ~= 0 then self.facing = dir end
        self.want_dir = nil

        if self.vx ~= 0 then
            local nx = self.x + self.vx * dt
            -- Blocked by a wall at body height?
            local side = self.vx > 0 and 1 or -1
            if level:solid_at(nx + side * r * 0.9, self.y - p.step - r * 0.5) then
                self.vx = 0
            else
                self.x = nx
            end
        end

        -- Follow the surface: snap up or down small steps, fall off big drops
        local sy, s = level:surface_below(self.x, self.y - p.step, p.step * 2)
        if sy then
            self.y, self.solid = sy, s
        else
            self:release(self.vx, 0)
            self:emit('walkoff')
        end
        return
    end

    -- Air: exact constant-gravity integration
    self.air_time = self.air_time + dt
    local nx = self.x + self.vx * dt
    local ny = self.y + self.vy * dt + 0.5 * G * dt * dt
    local nvy = self.vy + G * dt
    if nvy > (p.terminal or 900) then nvy = p.terminal or 900 end

    -- Head bump
    if nvy < 0 and level:solid_at(nx, ny - r * 2) then
        nvy = 0
        ny = self.y
    end
    -- Walls
    local side = self.vx >= 0 and 1 or -1
    if self.vx ~= 0 and level:solid_at(nx + side * r * 0.8, ny - r) then
        self.vx = 0
        nx = self.x
    end

    -- Landing: did the anchor cross a top surface this step?
    if nvy >= 0 then
        local sy, s = level:surface_below(nx, self.y, ny - self.y + 1)
        if sy and sy <= ny then
            self.x, self.y = nx, sy
            self.solid = s
            self.state = 'ground'
            self:emit('land', {impact = nvy, air_time = self.air_time})
            self.vy = 0
            self.vx = self.vx * 0.3
            return
        end
    end

    self.x, self.y, self.vy = nx, ny, nvy
    -- Never leave the cave
    self.x = max(24 + r, min(level.width - 24 - r, self.x))
end

--------------------------------------------------------------------------------
-- Face: blinking, gaze and idle glances, shared by everyone with eyes
--------------------------------------------------------------------------------

local Face = {}
Face.__index = Face
Base.Face = Face

function Face.new()
    return setmetatable({
        blink = 0,                                   -- 0 open .. 1 shut
        next_blink = rng.range(rng.look, 1.5, 4),
        gaze_x = 0, gaze_y = 0,                      -- smoothed look offset (-1..1)
        glance_x = 0, glance_y = 0,
        next_glance = rng.range(rng.look, 2, 5),
        shut = 0,                                    -- Terrarium: eyes closing for good (#24), 0..1
    }, Face)
end

-- look_x/look_y: unit-ish direction the creature wants to look
function Face:update(dt, look_x, look_y, idle)
    self.next_blink = self.next_blink - dt
    if self.next_blink <= 0 then
        self.blink = 1
        self.next_blink = rng.range(rng.look, 2.2, 5.5)
        if rng.look:random() < 0.2 then self.next_blink = 0.25 end -- double blink
    end
    self.blink = max(0, self.blink - dt * 7)
    -- Terrarium: a dying one's eyes close slowly, and stay closed (#24)
    if self.closing then self.shut = min(1, self.shut + dt / 4) end

    if idle then
        self.next_glance = self.next_glance - dt
        if self.next_glance <= 0 then
            self.glance_x = rng.range(rng.look, -1, 1)
            self.glance_y = rng.range(rng.look, -0.8, 0.4)
            self.next_glance = rng.range(rng.look, 1.2, 3.5)
        end
        look_x, look_y = self.glance_x, self.glance_y
    end
    local k = min(1, dt * 8)
    self.gaze_x = self.gaze_x + ((look_x or 0) - self.gaze_x) * k
    self.gaze_y = self.gaze_y + ((look_y or 0) - self.gaze_y) * k
end

-- Eyelid openness 0..1 (smooth close/open)
function Face:openness()
    local b = self.blink
    return min(1 - min(1, b * 2 - b * b), 1 - self.shut)
end

-- Draw one eye: white, pupil toward gaze, glint, lid. scale squishes it.
function Base.draw_eye(face, x, y, size, sx, sy, colors, far)
    sx, sy = sx or 1, sy or 1
    local open = face:openness()
    local ry = size * sy * max(0.08, open)
    local rx = size * sx
    love.graphics.setColor(colors.outline)
    love.graphics.ellipse('fill', x, y, rx + 1.2, ry + 1.2)
    love.graphics.setColor(far and colors.eye_far or colors.eye)
    love.graphics.ellipse('fill', x, y, rx, ry)
    if open > 0.25 then
        local px = x + face.gaze_x * rx * 0.38
        local py = y + face.gaze_y * ry * 0.38
        love.graphics.setColor(colors.pupil)
        love.graphics.ellipse('fill', px, py, rx * 0.55, ry * 0.6)
        if not far then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.circle('fill', px - rx * 0.2, py - ry * 0.25, max(0.8, size * 0.22))
        end
    end
end

-- Linear blend of two colours
function Base.mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
           (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t
end

return Base
