-- Terrarium: a closer look (#120). A tap on a creature brings the view in on
-- it, whoever the lantern is following, and a tap on nothing lets go. It lives
-- beside the lantern, outside the World: it only reads where a body's points
-- are, and its easing runs on the frame clock, which is fine for something the
-- simulation never sees.
--
-- The camera is a fit (core/screen.lua): how the jar's view goes on a w x h
-- screen, at a scale and offset eased from the screen's own fit (`base`) to a
-- close one framed round the creature. So everything that turns a point on the
-- screen into a point in the jar comes through `toLevel`, and a tap or a pinch
-- lands under the finger however far in it is.
--
-- main.lua draws what it says two ways through the ease. Coming in, it's the
-- whole finished picture, scaled; from the fit's own numbers, so the two line
-- up exactly, a plate fades in over it (`sharp`), and once in it's only the
-- plate: the stretch of the plane this fit shows, drawn at the screen's own
-- pixels. Holds no canvas and draws nothing itself, so the self-test reads it
-- with no window.

local C = require('jar.config')
local Tank = require('jar.tank')
local Screen = require('core.screen')
local Lantern = require('jar.lantern')

local Camera = {}
Camera.__index = Camera

Camera.EASE = 0.5     -- seconds to come in, or to go out
Camera.FILL = 2.1     -- the stretch is this many times the creature's size (as a portrait's is)...
Camera.ROOM = 40      -- ...and this much more, in level units
Camera.LEAST = 40     -- no one is framed as smaller than this, so a hatchling isn't a blur of moss
Camera.LOW = 0.56     -- how far down the screen the creature stands: a little air over its back
Camera.TRACK = 12     -- how quickly it catches up with where they've gone (per second)
Camera.BREATHE = 1.5  -- how quickly the framing takes a new size (a worm uncoiling doesn't pump it)
Camera.FADE = { 0.15, 0.6 } -- the amount over which the plate comes up over the scaled picture

-- View px to a level unit, on the creatures' plane
local PLANE = C.S * Tank.k(C.PLANE_D)

local function clamp(v, lo, hi)
    return v < lo and lo or v > hi and hi or v
end

function Camera.new()
    return setmetatable({ on = false, z = 0 }, Camera)
end

--- Come in on (or stay with) whoever the lantern is following
function Camera:hold() self.on = true end

--- Let go, and ease back out to the whole jar
function Camera:letGo() self.on = false end

--- Put it back where it starts, all the way out: a new jar
function Camera:reset()
    self.on, self.z, self.x, self.y, self.bw, self.bh = false, 0, nil, nil, nil, nil
end

--- Ease toward creature `c`, the one the lantern follows (frame dt, render only).
-- With no one to look at it lets go, and goes out from where it last was.
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
            if self.z <= 0 or not self.x then
                self.x, self.y, self.bw, self.bh = cx, cy, bw, bh
            else
                local k = 1 - math.exp(-Camera.TRACK * dt)
                self.x, self.y = self.x + (cx - self.x) * k, self.y + (cy - self.y) * k
                k = 1 - math.exp(-Camera.BREATHE * dt)
                self.bw, self.bh = self.bw + (bw - self.bw) * k, self.bh + (bh - self.bh) * k
            end
        end
    end
    local step = dt / Camera.EASE
    self.z = clamp(self.z + (self.on and step or -step), 0, 1)
end

--- How far in it is, 0 (the whole jar) to 1, on a curve that starts and ends still
function Camera:amount()
    local z = self.z
    return z * z * z * (z * (z * 6 - 15) + 10)
end

--- How much of the picture is the plate, 0 to 1
function Camera:sharp()
    return Tank.smoothstep(Camera.FADE[1], Camera.FADE[2], self:amount())
end

-- The close fit: the creature's stretch of the plane, at the screen's own
-- aspect, centred on it. It's kept inside the frame, the whole C.W x C.H of it
-- and not only the glass: one climbing the wall or under the lid stays in the
-- middle, with the blurred glass and the room behind it, sooner than standing
-- off to one side of a view that won't look that way.
function Camera:close(base, w, h)
    local span = math.max(self.bw, self.bh * w / h, Camera.LEAST) * Camera.FILL + Camera.ROOM
    local k = math.max(w / (span * PLANE), w / C.W, h / C.H, base.k)
    local fx, fy = Tank.level(self.x, self.y)
    return {
        k = k,
        x = clamp(w / 2 - fx * k, w - C.W * k, 0),
        y = clamp(h * Camera.LOW - fy * k, h - C.H * k, 0),
    }
end

--- The jar's view on a w x h screen, as far in as it is: `base` itself when it's
-- all the way out. The scale eases by ratio, so it comes in at an even pace to
-- the eye, and the creature goes in a straight line from where it stood to where
-- it'll stand. While there's a picture being scaled, the screen stays covered by
-- it; once the plate has come up, which has the whole frame to look at, that
-- lets go, so it arrives where it's going.
function Camera:fit(base, w, h)
    local u = self:amount()
    if u <= 0 or not self.x then return base end
    local close = self:close(base, w, h)
    if u >= 1 then return close end
    local r = (close.k / base.k) ^ u
    local fx, fy = Tank.level(self.x, self.y)
    local px = fx * base.k + base.x
    local py = fy * base.k + base.y
    px = px + (fx * close.k + close.x - px) * u
    py = py + (fy * close.k + close.y - py) * u
    local k = base.k * r
    local x, y = px - fx * k, py - fy * k
    local free = self:sharp()
    return {
        k = k,
        x = x + (clamp(x - r * base.x, w * (1 - r), 0) + r * base.x - x) * (1 - free),
        y = y + (clamp(y - r * base.y, h * (1 - r), 0) + r * base.y - y) * (1 - free),
    }
end

--- The stretch of the creatures' plane a fit shows on a w x h screen: x0, y0,
-- x1, y1 in level units, as a plate wants it
function Camera.stretch(f, w, h)
    local x0, y0 = Tank.toLevel(Screen.toView(f, 0, 0))
    local x1, y1 = Tank.toLevel(Screen.toView(f, w, h))
    return { x0, y0, x1, y1 }
end

--- A point on the screen, on the creatures' plane. Every tap, pinch and hover
-- that wants the jar under the finger asks here.
function Camera:toLevel(base, w, h, sx, sy)
    return Tank.toLevel(Screen.toView(self:fit(base, w, h), sx, sy))
end

--- How near a body a tap must land, in level units, or nil all the way out
-- (Lantern.creatureAt's own): the same distance on the screen, so tapping
-- beside a creature close up is tapping away from it.
function Camera:reach(base, w, h)
    if self:amount() <= 0 then return nil end
    return Lantern.PICK * base.k / self:fit(base, w, h).k
end

return Camera
