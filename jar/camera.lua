-- Terrarium: a closer look (#120, #122). A tap on a creature opens a loupe on
-- it, whoever the lantern is following, and a tap on nothing lets go. The jar
-- stays whole and where it was: a small ring on the creature, a round inset up
-- in a corner showing what's in that ring, enlarged, and two lines joining them.
-- It lives beside the lantern, outside the World: it only reads where a body's
-- points are, and its easing runs on the frame clock, which is fine for
-- something the simulation never sees.
--
-- The view never moves, so a point on the screen means the same thing in the
-- jar however far open it is: only a tap on the inset itself needs asking about
-- (`over`). The small ring holds exactly the stretch the inset shows, so at no
-- way open the two are the same picture in the same place, and the inset grows
-- out of the ring.
--
-- `inset` is all of it, as numbers; jar/loupe.lua and main.lua's drawClose draw
-- what it says. Holds no canvas and draws nothing itself, so the self-test reads
-- it with no window.

local C = require('jar.config')
local Tank = require('jar.tank')

local Camera = {}
Camera.__index = Camera

Camera.EASE = 0.5     -- seconds to open, or to close
Camera.SWING = 0.9    -- seconds to cross to the other corner
Camera.SIZE = 1 / 3   -- the inset's diameter, as a share of the picture's shorter side...
Camera.MARGIN = 0.035 -- ...and how far it keeps from the picture's edges
Camera.CROSS = 0.05   -- how far past the middle (a share of the view) before it crosses: one
                      -- pottering about in the middle doesn't send it back and forth
Camera.FILL = 1.5     -- the stretch is this many times the creature's size...
Camera.ROOM = 30      -- ...and this much more, in level units
Camera.LEAST = 40     -- no one is framed as smaller than this, so a hatchling isn't a blur of moss
Camera.POWER = 2.5    -- and the inset always shows at least this many times the jar's own size
                      -- (a long worm laid out fills it and runs off its edge)
Camera.TRACK = 12     -- how quickly it catches up with where they've gone (per second)
Camera.BREATHE = 1.5  -- how quickly the framing takes a new size (a worm uncoiling doesn't pump it)

-- View px to a level unit, on the creatures' plane
local PLANE = C.S * Tank.k(C.PLANE_D)

local function clamp(v, lo, hi)
    return v < lo and lo or v > hi and hi or v
end

-- A curve that starts and ends still
local function smoother(z)
    return z * z * z * (z * (z * 6 - 15) + 10)
end

function Camera.new()
    return setmetatable({ on = false, z = 0, side = 1, swing = 1 }, Camera)
end

--- Open on (or stay with) whoever the lantern is following
function Camera:hold() self.on = true end

--- Let go, and ease shut
function Camera:letGo() self.on = false end

--- Put it back where it starts, shut: a new jar
function Camera:reset()
    self.on, self.z, self.x, self.y, self.bw, self.bh = false, 0, nil, nil, nil, nil
    self.side, self.swing = 1, 1
end

--- Ease toward creature `c`, the one the lantern follows (frame dt, render only).
-- With no one to look at it lets go, and shuts on where it last was.
function Camera:update(dt, c)
    if not c then self.on = false end
    if self.on then
        -- (it goes to the middle of their points, as the lantern does; the middle of
        -- their bounds would jump each time a spider sets a foot down. The bounds
        -- are only for how much room to give them)
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        local sx, sy, n = 0, 0, 0
        for _, p in ipairs(c:interp_points()) do
            x0, y0 = math.min(x0, p.x), math.min(y0, p.y)
            x1, y1 = math.max(x1, p.x), math.max(y1, p.y)
            sx, sy, n = sx + p.x, sy + p.y, n + 1
        end
        if n > 0 then
            local cx, cy, bw, bh = sx / n, sy / n, x1 - x0, y1 - y0
            -- (every fit is centred, so the view's middle is the picture's)
            local off = (Tank.level(cx, cy) - C.W / 2) / C.W
            if self.z <= 0 or not self.x then
                self.x, self.y, self.bw, self.bh = cx, cy, bw, bh
                self.side = off > 0 and 0 or 1
                self.swing = self.side
            else
                local k = 1 - math.exp(-Camera.TRACK * dt)
                self.x, self.y = self.x + (cx - self.x) * k, self.y + (cy - self.y) * k
                k = 1 - math.exp(-Camera.BREATHE * dt)
                self.bw, self.bh = self.bw + (bw - self.bw) * k, self.bh + (bh - self.bh) * k
                if off > Camera.CROSS then self.side = 0 elseif off < -Camera.CROSS then self.side = 1 end
            end
        end
    end
    local step = dt / Camera.EASE
    self.z = clamp(self.z + (self.on and step or -step), 0, 1)
    step = dt / Camera.SWING
    self.swing = clamp(self.swing + clamp(self.side - self.swing, -step, step), 0, 1)
end

--- How far open it is, 0 (just the jar) to 1, on a curve that starts and ends still
function Camera:amount()
    return self.x and smoother(self.z) or 0
end

--- The inset, on a w x h screen shown through `base` (a fit, core/screen.lua), in
-- the screen's pixels: `ring`, on the creature, and `lens`, at its size and place
-- as far open as it is, each {x, y, r}; `corner`, where the lens is going; `R`,
-- the radius it opens to, a whole number, so `size` (2R) can be its plate's
-- canvas; and `view`, the stretch of the creatures' plane {x0, y0, x1, y1} in
-- level units that both rings hold. It sits in the top corners, where the jar is
-- only air and the lid, across the middle from the creature, and inside what the
-- screen shows of the picture: the frame's cropped edges and a window's bars are
-- outside that. The closed book and its ribbon lie along the bottom, so it's
-- never on them.
function Camera:inset(base, w, h)
    local px0, py0 = math.max(0, base.x), math.max(0, base.y)
    local px1, py1 = math.min(w, base.x + C.W * base.k), math.min(h, base.y + C.H * base.k)
    local short = math.min(px1 - px0, py1 - py0)
    local R = math.floor(short * Camera.SIZE / 2 + 0.5)
    local gap = short * Camera.MARGIN
    local u = smoother(self.swing)
    local corner = { x = px0 + gap + R + (px1 - px0 - 2 * (gap + R)) * u, y = py0 + gap + R }

    -- (px of the screen to a level unit, on the plane)
    local scale = PLANE * base.k
    local span = math.max(self.bw, self.bh, Camera.LEAST) * Camera.FILL + Camera.ROOM
    span = math.min(span, 2 * R / (Camera.POWER * scale))
    local vx, vy = Tank.level(self.x, self.y)
    local ring = { x = vx * base.k + base.x, y = vy * base.k + base.y, r = span / 2 * scale }

    local o = self:amount()
    return {
        amount = o,
        ring = ring,
        lens = {
            x = ring.x + (corner.x - ring.x) * o,
            y = ring.y + (corner.y - ring.y) * o,
            r = ring.r + (R - ring.r) * o,
        },
        corner = corner,
        R = R,
        size = 2 * R,
        view = { self.x - span / 2, self.y - span / 2, self.x + span / 2, self.y + span / 2 },
    }
end

--- Is a point on the screen on the inset? A tap there lets go, and never picks
-- whoever happens to be behind it.
function Camera:over(base, w, h, sx, sy)
    if self:amount() <= 0 then return false end
    local lens = self:inset(base, w, h).lens
    return (sx - lens.x) ^ 2 + (sy - lens.y) ^ 2 <= lens.r ^ 2
end

--- The two lines between two circles {x, y, r}, each touching both on the same
-- side, as a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y (1 on the first circle, 2 on the
-- second). Nil if one is inside the other, and there are no such lines.
function Camera.tangents(p, q)
    local dx, dy = q.x - p.x, q.y - p.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= math.abs(p.r - q.r) or d <= 0 then return nil end
    local at = math.atan2(dy, dx)
    local turn = math.acos((p.r - q.r) / d)
    local ax, ay = math.cos(at + turn), math.sin(at + turn)
    local bx, by = math.cos(at - turn), math.sin(at - turn)
    return p.x + ax * p.r, p.y + ay * p.r, q.x + ax * q.r, q.y + ay * q.r,
        p.x + bx * p.r, p.y + by * p.r, q.x + bx * q.r, q.y + by * q.r
end

return Camera
