-- Remains: a creature going back to the moss (#24).
--
-- A death is drawn as a settling, never a body. Over World.FADE seconds the
-- one that died in its sleep sinks a little into the cushion, its colours
-- drift toward the moss's own green-brown, and it fades, as if the moss were
-- taking it in. As it goes, pale spores rise from where it lies, and keep
-- drifting up for a while after it's gone. What's left is in the moss
-- itself: that patch grows back greener (Moss:enrich).
--
-- Drawing only: it reads World.lives (through World:fading) and
-- World.remains, and changes nothing but a dying body's skin (statehash
-- skips `skin`).

local Skin = require('bodies.skin')
local Render = require('jar.render')

local Remains = {}

local sin, pi, max, min, floor = math.sin, math.pi, math.max, math.min, math.floor

local SINK = 4          -- level units a body settles into the moss
local SPORES = 9        -- spores in the air at once over a body
local SPORE_LIFE = 7    -- seconds each one drifts
local RISE = 7          -- units a second they rise
local SPORE = {0.86, 0.9, 0.62} -- pale, like the gold-green the moss gives back at night

local function smooth(t)
    t = max(0, min(1, t))
    return t * t * (3 - 2 * t)
end

local canvas

-- Draw creature `i` of `world` with its `method` (draw or draw_emissive,
-- given `ctx`): as it is, or if it's dying, sunk, earthed and faded. `blend`
-- is how its picture goes onto the scene ('alpha', or 'add' for its glow).
function Remains.through(world, i, method, ctx, blend)
    local c = world.creatures[i]
    local f = world:fading(i)
    if f <= 0 then return c[method](c, ctx) end
    -- (its skin goes back to the moss in steps, not every frame)
    local earth = floor(smooth(f * 1.6) * 16) / 16
    if c.skin.earth ~= earth then c.skin = Skin.age(c.key, c.genome, c.skin, c.skin.old, earth) end

    local target = love.graphics.getCanvas()
    local w, h
    if target then w, h = target:getDimensions() else w, h = love.graphics.getDimensions() end
    if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        canvas = love.graphics.newCanvas(w, h, target and {format = target:getFormat(), msaa = target:getMSAA()} or nil)
    end
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.push()
    love.graphics.translate(0, SINK * smooth(f))
    c[method](c, ctx)
    love.graphics.pop()
    love.graphics.setCanvas(target)

    local a = 1 - smooth(f)
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setBlendMode(blend or 'alpha', 'premultiplied')
    love.graphics.setColor(a, a, a, a)
    love.graphics.draw(canvas)
    love.graphics.pop()
end

-- Spores over x0..x1 at ground y, `t` seconds since they began, as strong as `k`
local function spores(x0, x1, y, seed, t, k)
    if k < 0.01 then return end
    for s = 1, SPORES do
        local u = Skin.hash(seed, s)
        local age = (t + u * SPORE_LIFE) % SPORE_LIFE
        local born = t - age -- (none from before it began)
        if born >= 0 then
            local p = age / SPORE_LIFE
            local x = x0 + (x1 - x0) * Skin.hash(s, seed) + sin(age * 1.3 + s) * 3 * p
            local sy = y - 2 - age * RISE * (0.7 + 0.6 * Skin.hash(seed + 3, s))
            local a = k * sin(pi * p) * 0.75
            love.graphics.setColor(SPORE[1], SPORE[2], SPORE[3], a * 0.25)
            Render.drawBlob(x, sy, 4.5)
            love.graphics.setColor(SPORE[1], SPORE[2], SPORE[3], a)
            love.graphics.circle('fill', x, sy, 0.9)
        end
    end
end

-- The spores over each dying body and each place one went back to the moss
function Remains.draw(world)
    if #world.remains == 0 then
        local any = false
        for i = 1, #world.creatures do any = any or world:fading(i) > 0 end
        if not any then return end
    end
    love.graphics.push('all')
    love.graphics.setShader()
    for i, c in ipairs(world.creatures) do
        local f = world:fading(i)
        if f > 0 then
            local x0, x1, y = math.huge, -math.huge, -math.huge
            for _, p in ipairs(c:interp_points()) do
                x0, x1, y = min(x0, p.x), max(x1, p.x), max(y, p.y)
            end
            local life = world.lives[i]
            spores(x0, x1, y, life.born % 97, world.time - life.dying, smooth(f * 3))
        end
    end
    for _, r in ipairs(world.remains) do
        local since = world.time - r.at
        local k = 1 - since / world.SPORES
        -- (the same spores as while it faded, carrying on)
        spores(r.x0, r.x1, r.y, r.born % 97, since + r.faded, k)
    end
    love.graphics.pop()
end

return Remains
