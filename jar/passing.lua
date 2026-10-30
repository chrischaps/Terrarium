-- Passing: the moment on opening a jar that was left (#31). Not a loading bar.
--
-- While the time away is lived (jar/catchup.lua), the jar is behind glass that
-- has fogged over in the dark, the way a shut jar's does. Through it the days
-- go by as light: the lamp comes on and goes off again in the time it takes to
-- breathe, and the moss grows and is grazed. What lives there is only anchors
-- then, and it shows as only that: a long exposure, each one a thread of its
-- own colour where it went and a glow where it stayed. Each day lived, a
-- fingertip draws a tally mark in the mist, five-barred, at most a week of
-- them. The last hours slow into now, the bodies come back, and the glass
-- clears from the top down as it does on a warm morning.
--
-- It's drawing and pacing only. How much of the catch-up runs in a frame is
-- up to the frame's time, never the sim's: the jar comes back the same however
-- the steps fall (the `catchup` test splits them). It reads the World and
-- never writes to it, except to step it through Catchup.

local C = require('jar.config')
local Render = require('jar.render')
local Catchup = require('jar.catchup')

local Passing = {}
Passing.__index = Passing

Passing.QUIET = 15 * 60 -- jar seconds away that are lived at once, with no moment
Passing.BUDGET = 0.022  -- seconds of a frame the catch-up may take
Passing.SLOW = 0.45     -- seconds: how the last of the time away slows into now
Passing.CLEAR = 2.8     -- seconds the glass takes to clear once the jar is back
Passing.HOLD = 1.2      -- seconds the jar stays fogged at least, however short the time
Passing.EXPOSE = 0.4    -- seconds a trace on the long exposure takes to fade by e
Passing.LIGHT = 0.015   -- how much light an anchor leaves on it a jar second
Passing.MARK = 0.4      -- seconds a tally mark takes to draw

local exp, min, max, sin, floor = math.exp, math.min, math.max, math.sin, math.floor

-- Catch `world` up on `away` seconds. A short time is lived at once, and nil
-- comes back; a longer one is a moment, lived a frame at a time.
function Passing.begin(world, away)
    local span = Catchup.span(away, world:day_length())
    if span <= 0 then return nil end
    if span <= Passing.QUIET then
        Catchup.now(world, away)
        return nil
    end
    local self = setmetatable({}, Passing)
    self.world = world
    self.catchup = Catchup.new(world, away)
    self.t = 0        -- seconds the moment has lasted
    self.clearing = nil -- seconds since the jar came back
    self.marks = {}   -- the tally, each {at = when it began}
    self.dots = {}    -- creature -> where its anchor was at each step this frame
    self.colours = {} -- creature -> its colour on the exposure
    return self
end

-- Still living the time away: the creatures are tokens, and nothing but the moment draws them
function Passing:catching() return self.catchup ~= nil end

-- Every anchor where it is now, onto this frame's exposure: a thread from
-- where it was, or, if it hasn't moved, a little more glow where it is
function Passing:trace()
    for _, c in ipairs(self.world.creatures) do
        local d = self.dots[c]
        if not d then
            local k = c.skin and c.skin[c.skin.main] or {1, 1, 1}
            self.colours[c] = {k[1], k[2], k[3]}
            d = {line = {}, still = {}}
            self.dots[c] = d
        end
        local x, y = c:anchor()
        y = y - 4
        local line = d.line
        if line[#line - 1] == x and line[#line] == y then
            d.still[#line] = (d.still[#line] or 0) + 1
        else
            line[#line + 1], line[#line + 2] = x, y
        end
    end
end

-- A frame of the moment, `dt` long. The catch-up gets what's left of
-- Passing.BUDGET of the frame's time, or with `steps`, that many coarse steps
-- (a capture script's, so its frames are exact). Returns true once it's over.
function Passing:update(dt, steps)
    self.t, self.dt = self.t + dt, dt
    local cu = self.catchup
    if cu then
        -- (the last of the time away slows down into now)
        local left = cu:left()
        local allow = max(1, floor(left * (1 - exp(-dt / Passing.SLOW)) + 0.5))
        if steps then allow = min(allow, steps) end
        local t0, budget = love.timer.getTime(), Passing.BUDGET
        while allow > 0 and cu:left() > 0 do
            local n = min(allow, 8)
            for _ = 1, n do
                cu:run(1)
                self:trace()
                self.stepped = (self.stepped or 0) + 1
            end
            allow = allow - n
            if not steps and love.timer.getTime() - t0 > budget then break end
        end
        local _, days = cu:progress()
        while #self.marks < min(days, Catchup.CAP) do self.marks[#self.marks + 1] = {at = self.t} end
        if cu:left() == 0 and self.t >= Passing.HOLD then
            cu:finish()
            self.catchup = nil
            self.clearing = 0
        end
        return false
    end
    self.clearing = self.clearing + dt
    return self.clearing >= Passing.CLEAR
end

-- How fogged the glass is: wholly while the jar is away, then clearing
function Passing:veil()
    if self.catchup then return 1 end
    local u = min(1, self.clearing / Passing.CLEAR)
    return 1 - u * u * (3 - 2 * u)
end

-- (the film seen through a soft shoulder, so where many threads cross it
-- glows rather than burning out to white)
local TONE = [[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec3 v = Texel(tex, uv).rgb * color.rgb;
    return vec4(v / (1.0 + v), 1.0);
}
]]

-- How long a thread `line` is, and how many steps it took
local function measure(line)
    local len, moved = 0, 0
    for i = 3, #line, 2 do
        len, moved = len + math.sqrt((line[i] - line[i - 2]) ^ 2 + (line[i + 1] - line[i - 1]) ^ 2), moved + 1
    end
    return len, moved
end

-- The long exposure, on the creatures' plane (call inside Tank.pushPlane):
-- what each anchor traced this frame, over what it traced before, fading
function Passing:draw()
    if not self.film then
        -- (half floats where it can, so a faint thread still adds up)
        local hdr = love.graphics.getCanvasFormats()['rgba16f'] and {format = 'rgba16f'} or nil
        self.film = love.graphics.newCanvas(C.W, C.H, hdr)
        love.graphics.push('all')
        love.graphics.setCanvas(self.film)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.pop()
    end
    -- (once the jar is back, the exposure goes twice as fast)
    local film, fade = self.film, exp(-(self.dt or 0) / (self.catchup and Passing.EXPOSE or Passing.EXPOSE / 2))
    love.graphics.push('all')
    love.graphics.setCanvas(film)
    love.graphics.setShader()
    -- (what was traced before fades)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setBlendMode('multiply', 'premultiplied')
    love.graphics.setColor(fade, fade, fade, 1)
    love.graphics.rectangle('fill', 0, 0, C.W, C.H)
    love.graphics.pop()
    -- (and this frame's are laid on it: a faint thread where each went, and
    -- a glow where it stayed, brighter the longer)
    love.graphics.setBlendMode('add')
    love.graphics.setLineJoin('none')
    love.graphics.setLineWidth(2.4)
    -- (and like a camera it stops down when the jar is busy: by day, with
    -- everyone about, each thread is fainter than one alone in the night)
    local busy = 0
    for _, d in pairs(self.dots) do busy = busy + select(2, measure(d.line)) end
    local gain = min(1, 1.5 * max(1, self.stepped or 0) / max(1, busy))
    self.stepped = 0
    for c, d in pairs(self.dots) do
        local k, line = self.colours[c], d.line
        if #line >= 4 then
            -- (each step is a jar second, so a thread is fainter the faster it
            -- went: the light it leaves is the time it spent there)
            local len, moved = measure(line)
            local a = gain * min(0.08, Passing.LIGHT * 80 / max(1, len / moved))
            love.graphics.setColor(k[1] * a, k[2] * a, k[3] * a, 1)
            love.graphics.line(line)
        end
        for i, n in pairs(d.still) do
            local a = min(0.025, Passing.LIGHT * 0.05 * n)
            love.graphics.setColor(k[1] * a, k[2] * a, k[3] * a, 1)
            Render.drawBlob(line[i - 1], line[i], 5)
            love.graphics.setColor(k[1] * a * 0.25, k[2] * a * 0.25, k[3] * a * 0.25, 1)
            Render.drawBlob(line[i - 1], line[i], 12)
        end
        -- (the next frame's thread goes on from where this one stopped)
        local x, y = line[#line - 1], line[#line]
        self.dots[c] = {line = x and {x, y} or {}, still = {}}
    end
    love.graphics.pop()

    self.tone = self.tone or love.graphics.newShader(TONE)
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setShader(self.tone)
    love.graphics.setBlendMode('add')
    local v = self:veil() ^ 0.5
    love.graphics.setColor(v, v, v, 1)
    love.graphics.draw(film)
    love.graphics.pop()
end

-- (a number in [0, 1) from two, the same every time: where a mark wavers)
local function hash(a, b)
    local n = sin(a * 127.1 + b * 311.7) * 43758.5453
    return n - floor(n)
end

-- Tally mark `k` (1 to CAP) as a stroke from (ax, ay) to (bx, by), in the
-- glass's frame: four down, the fifth across them, then a new gate
local function stroke(k, x0, y0, x1, y1)
    local gap, tall = 19, 64
    local gate = floor((k - 1) / 5)
    local left = x0 + 0.14 * (x1 - x0) + gate * 6.2 * gap
    local top = y0 + 0.17 * (y1 - y0)
    local j = (k - 1) % 5
    if j == 4 then
        return left - 9, top + tall * 0.72, left + 3 * gap + 10, top + tall * 0.18
    end
    local x = left + j * gap + (hash(k, 1) - 0.5) * 5
    local lean = (hash(k, 2) - 0.3) * 9
    return x + lean * 0.5, top + (hash(k, 3) - 0.5) * 7, x - lean * 0.5, top + tall + (hash(k, 4) - 0.5) * 9
end

-- The tally, wiped into the condensation's dry layer (Condensation.draw calls
-- it, in the glass's own frame): each mark drawn with a fingertip over MARK
-- seconds, and filled in again by the fog as the glass clears
function Passing:wipe(x0, y0, x1, y1)
    local veil = self:veil()
    if veil <= 0 then return end
    for k, m in ipairs(self.marks) do
        local u = min(1, (self.t - m.at) / Passing.MARK)
        u = 1 - (1 - u) ^ 2
        local ax, ay, bx, by = stroke(k, x0, y0, x1, y1)
        local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local n = max(2, floor(len * u / 1.5))
        for i = 0, n do
            local t = i / n * u
            -- (a fingertip presses hardest where it lands, and lifts off at the end)
            local r = 8 + 2.5 * (1 - t) ^ 6 - 2.5 * t ^ 4 + (hash(k, i) - 0.5) * 1.2
            local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            x = x + sin(t * 3.1 + k) * 1.4
            love.graphics.setColor(min(1, veil * 1.5) * 0.35, 0, 0, 1)
            Render.drawBlob(x, y, r)
        end
    end
end

-- What Condensation.draw takes of it: how fogged, and the tally to wipe
function Passing:glass()
    return {veil = self:veil(), wipe = function(...) self:wipe(...) end}
end

return Passing
