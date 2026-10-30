-- Terrarium: a finger on the frame's glass (#90). A tap is a click: it follows
-- whoever is under it. Holding still is a right-click: a pinch of food falls
-- there. One finger at a time; a second is ignored, and one that slides away
-- is neither. While it holds, a thin ring of lamplight closes round it, so you
-- can see the pinch coming and lift off before it does. It opens out as the
-- pinch falls, or, if the jar has none left to give, shrinks away.

local Touch = {}
Touch.__index = Touch

Touch.HOLD = 0.6  -- seconds held still before it's a pinch
Touch.STILL = 24  -- px a finger may drift and still be holding still
Touch.SHOW = 0.15 -- the ring stays hidden this long, so a tap never shows it
Touch.FADE = 0.5  -- the ring opens out and fades once the pinch falls
Touch.RING = 26   -- its radius, px

function Touch.new()
    return setmetatable({ rings = {} }, Touch)
end

function Touch:press(id, x, y)
    if self.down then return end
    self.down = { id = id, x = x, y = y, t = 0 }
end

function Touch:move(id, x, y)
    local d = self.down
    if not d or d.id ~= id then return end
    if (x - d.x) ^ 2 + (y - d.y) ^ 2 > Touch.STILL ^ 2 then self.down = nil end
end

-- 'tap', x, y if this lifts a finger that never held long enough
function Touch:release(id, x, y)
    local d = self.down
    if not d or d.id ~= id then return end
    self.down = nil
    if not d.held then return 'tap', d.x, d.y end
end

-- 'hold', x, y on the step a still finger becomes a pinch
function Touch:update(dt)
    for i = #self.rings, 1, -1 do
        local r = self.rings[i]
        r.t = r.t + dt
        if r.t >= Touch.FADE then table.remove(self.rings, i) end
    end
    local d = self.down
    if not d or d.held then return end
    d.t = d.t + dt
    if d.t >= Touch.HOLD then
        d.held = true
        self.rings[#self.rings + 1] = { x = d.x, y = d.y, t = 0 }
        return 'hold', d.x, d.y
    end
end

-- The hold that just fell found no pinch to drop (the jar gives a few a day)
function Touch:empty()
    local r = self.rings[#self.rings]
    if r then r.empty = true end
end

-- On the screen, over everything
function Touch:draw()
    if not self.down and #self.rings == 0 then return end
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    love.graphics.setLineWidth(2)
    local d = self.down
    if d and not d.held and d.t > Touch.SHOW then
        local p = (d.t - Touch.SHOW) / (Touch.HOLD - Touch.SHOW)
        love.graphics.setColor(1, 0.86, 0.62, 0.10)
        love.graphics.circle('line', d.x, d.y, Touch.RING, 48)
        love.graphics.setColor(1, 0.86, 0.62, 0.28 + 0.27 * p)
        love.graphics.arc('line', 'open', d.x, d.y, Touch.RING, -math.pi / 2, -math.pi / 2 + p * 2 * math.pi, 48)
    end
    for _, r in ipairs(self.rings) do
        local u = r.t / Touch.FADE
        if r.empty then
            love.graphics.setColor(1, 0.86, 0.62, 0.3 * (1 - u) ^ 2)
            love.graphics.circle('line', r.x, r.y, Touch.RING * (1 - 0.5 * u), 48)
        else
            love.graphics.setColor(1, 0.86, 0.62, 0.55 * (1 - u) ^ 2)
            love.graphics.circle('line', r.x, r.y, Touch.RING * (1 + 0.7 * math.sqrt(u)), 48)
        end
    end
    love.graphics.pop()
end

return Touch
