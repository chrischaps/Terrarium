-- Terrarium: condensation on the inside of the front glass (#5).
-- After the lamp goes off the jar cools, and the moss's breath gathers on the
-- glass: first a fine mist low down and at the cold edges, then beads, then a
-- few heavy drops that let go and run, leaving a clear trail that slowly fogs
-- over again. When the lamp comes on it warms the lid first, so the glass
-- clears from the top down through the morning and is dry by midday.
--
-- How damp the glass is comes from the day cycle (env.damp); where it fogs
-- first is a fixed field, composed from rng.scape like the rest of the jar.
-- The runs are timed by the hour too, so the glass is a pure function of the
-- jar's clock: the same jar at the same hour always looks the same, and none
-- of it touches the simulation.

local C = require("jar.config")
local Render = require("jar.render")

local Condensation = {}

local FIELD_CELL = 4      -- the fogging field is baked at 1/4 resolution
local SOFT = 0.09         -- how gradually a spot fogs past its threshold
local REFILL = 1.4        -- hours for a run's trail to fog over again
local NIGHT0 = 18         -- runs are timed in hours since six in the evening

local x0, y0 = C.OX + C.GLASS_L, C.OY + C.GLASS_T
local x1, y1 = C.OX + C.GLASS_R, C.OY + C.GLASS_B - C.GLASS_THICK
local soilY = C.OY + C.SOIL_Y

local mist, field, dry
local beads, runs = {}, {}
local noiseX, noiseY

local function smooth(e0, e1, x)
    local t = math.max(0, math.min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
end

-- How damp the glass must be before this spot fogs. The lamp warms the top
-- middle, the corners stay cold, and the glass in front of the soil is wettest.
local function threshold(x, y)
    if x < x0 or x > x1 or y < y0 or y > y1 then return 1 end
    local u, v = (x - x0) / (x1 - x0), (y - y0) / (y1 - y0)
    local lamp = math.exp(-((u - 0.5) / 0.30) ^ 2) * (1 - v) ^ 1.4
    local edge = math.max(0, 1 - math.min(u, 1 - u) / 0.10)
    local soil = smooth(soilY - 40, soilY + 30, y)
    local n = 0.65 * love.math.noise(u * 3.1 + noiseX, v * 3.7 + noiseY)
        + 0.35 * love.math.noise(u * 9.3 + noiseY, v * 8.1 + noiseX)
    local fine = love.math.noise(u * 48 + noiseX, v * 36 + noiseY)  -- a ragged edge
    local t = 0.10 + 0.48 * lamp + 0.20 * (1 - v) - 0.10 * edge - 0.08 * soil
        + 0.18 * (n - 0.5) + 0.07 * (fine - 0.5)
    return math.max(0.02, math.min(0.92, t))
end

local function bakeField()
    local fw, fh = C.W / FIELD_CELL, C.H / FIELD_CELL
    local data = love.image.newImageData(fw, fh)
    data:mapPixel(function(i, j)
        local t = threshold((i + 0.5) * FIELD_CELL, (j + 0.5) * FIELD_CELL)
        return t, t, t, 1
    end)
    field = love.graphics.newImage(data)
    field:setFilter("linear", "linear")
end

-- The mist itself: a faint even breath on the glass and a grain of droplets
-- too small to see one by one
local function bakeMist(gen)
    mist = love.graphics.newCanvas(C.W, C.H)
    love.graphics.push("all")
    love.graphics.setCanvas(mist)
    love.graphics.clear(1, 1, 1, 0)
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
    for _ = 1, 40000 do
        local x = x0 + gen:random() * (x1 - x0)
        local y = y0 + gen:random() * (y1 - y0)
        love.graphics.setColor(1, 1, 1, 0.04 + gen:random() * 0.14)
        love.graphics.circle("fill", x, y, 0.3 + gen:random() ^ 2 * 0.6, 5)
    end
    love.graphics.pop()
end

-- Beads: many small, a few large, the large ones lower where drops gather.
-- A bead forms a little after the mist under it, and big ones form last.
local function placeBeads(gen)
    for _ = 1, 520 do
        local x = x0 + 3 + gen:random() * (x1 - x0 - 6)
        local y = y0 + 4 + gen:random() ^ 0.8 * (y1 - y0 - 8)
        local v = (y - y0) / (y1 - y0)
        local r = 0.7 + gen:random() ^ 3.2 * (2.5 + 4.5 * v)
        beads[#beads + 1] = {
            x = x, y = y, r = r,
            thr = threshold(x, y) + 0.06 + 0.04 * r + gen:random() * 0.12,
        }
    end
end

-- Runs: a heavy drop lets go in the small hours and slides down in fits and
-- starts, gathering every bead in its way
local function placeRuns(gen)
    for _ = 1, 7 do
        local x = x0 + 30 + gen:random() * (x1 - x0 - 60)
        local top = y0 + 40 + gen:random() * (y1 - y0) * 0.45
        local run = {
            x = x, top = top,
            len = math.min(y1 - 6 - top, 140 + gen:random() * 260),
            at = 8 + gen:random() * 4.3,            -- 2am to half past six
            dur = 0.012 + gen:random() * 0.025,     -- about a minute, start to stop
            r = 2.8 + gen:random() * 2.0,
            fits = 3 + math.floor(gen:random() * 3),
            phase = gen:random() * 6.28,
            trail = {},
        }
        -- It leaves a line of tiny beads behind it
        local y = top + 4
        while y < top + run.len - 6 do
            run.trail[#run.trail + 1] = { dy = y - top, dx = (gen:random() - 0.5) * 2.4, r = 0.5 + gen:random() * 0.8 }
            y = y + 6 + gen:random() * 9
        end
        runs[#runs + 1] = run
    end
    for _, b in ipairs(beads) do
        for i, run in ipairs(runs) do
            if b.y > run.top and b.y < run.top + run.len and math.abs(b.x - run.x) < run.r * 1.6 + b.r then
                b.run = i
            end
        end
    end
end

function Condensation.init(gen)
    noiseX, noiseY = gen:random() * 100, gen:random() * 100
    bakeField()
    bakeMist(gen)
    placeBeads(gen)
    placeRuns(gen)
    dry = love.graphics.newCanvas(C.W / 2, C.H / 2)
    dry:setFilter("linear", "linear")
end

local function wobble(run, y)
    return run.x + 1.6 * math.sin(y * 0.045 + run.phase) + 0.8 * math.sin(y * 0.13 + run.phase * 2)
end

-- Where a run's drop is, and how clear its trail still is (0 = fogged over)
local function runState(run, night)
    local age = night - run.at
    if age < 0 then return nil end
    local p = math.min(1, age / run.dur)
    local k = 2 * math.pi * run.fits
    local f = p - 0.8 * math.sin(k * p) / k   -- slides, sticks, slides
    return run.top + run.len * f, 1 - smooth(run.dur, run.dur + REFILL, age)
end

-- Gather the mist around beads and along runs into the dry layer
local function drawDry(state)
    love.graphics.setCanvas(dry)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode("add")
    love.graphics.push()
    love.graphics.scale(0.5)
    for _, b in ipairs(beads) do
        if b.s > 0 and b.r > 1.4 then
            love.graphics.setColor(0.75 * b.s, 0, 0, 1)
            Render.drawBlob(b.x, b.y, b.r * 2.4)
        end
    end
    for i, run in ipairs(runs) do
        local head, clear = state[i][1], state[i][2]
        if head and clear > 0 then
            love.graphics.setColor(clear, 0, 0, 1)
            for y = run.top, head, 3 do
                Render.drawBlob(wobble(run, y), y, run.r * 1.7)
            end
        end
    end
    love.graphics.pop()
    love.graphics.setBlendMode("alpha")
end

--- Draw the condensation over the jar, under the front glass's dust and glare
function Condensation.draw(light)
    local damp = light.damp or 0
    local night = (light.hour - NIGHT0) % 24
    local state = {}
    local running = false
    for i, run in ipairs(runs) do
        local head, clear = runState(run, night)
        state[i] = { head, clear or 0 }
        if head then running = true end
    end
    if damp < 0.003 and not running then return end

    local canvas = love.graphics.getCanvas()
    love.graphics.push("all")

    -- How big each bead is now, and whether a run has swept it away
    for _, b in ipairs(beads) do
        local s = smooth(b.thr, b.thr + 0.30, damp)
        local run = b.run and state[b.run]
        if run and run[1] and run[1] > b.y then s = s * (1 - run[2]) end
        b.s = s
    end

    drawDry(state)
    love.graphics.setCanvas(canvas)

    -- The mist scatters whatever light is on the glass: the room's, the
    -- lamp's warmth from above, and the moon from the window
    local amb, lamp, moon = light.ambient, light.lamp, light.moon or 0
    local tint = {
        0.70 * amb[1] + 0.22 * lamp[1] + 0.22 * moon,
        0.76 * amb[2] + 0.22 * lamp[2] + 0.26 * moon,
        0.80 * amb[3] + 0.22 * lamp[3] + 0.36 * moon,
    }
    local sh = Render.shader("mist")
    if sh then
        sh:send("field", field)
        sh:send("dry", dry)
        sh:send("damp", damp)
        sh:send("soft", SOFT)
        sh:send("tint", tint)
        love.graphics.setShader(sh)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(mist)
        love.graphics.setShader()
    end

    -- Every drop, run or resting: beads, the runs' heads and their trails
    local drops = {}
    local function add(x, y, r, s)
        if s > 0.01 then drops[#drops + 1] = { x, y, r * s ^ 0.6, s } end
    end
    for _, b in ipairs(beads) do add(b.x, b.y, b.r, b.s) end
    for i, run in ipairs(runs) do
        local head, clear = state[i][1], state[i][2]
        if head then
            -- The drop lingers where it stopped until the morning dries it
            local rest = (head < run.top + run.len) and 1 or smooth(0.06, 0.45, damp)
            add(wobble(run, head), head, run.r, rest)
            for _, t in ipairs(run.trail) do
                if run.top + t.dy < head then
                    add(wobble(run, run.top + t.dy) + t.dx, run.top + t.dy, t.r, smooth(0.05, 0.4, damp) * (0.4 + 0.6 * clear))
                end
            end
        end
    end

    -- A drop darkens what's behind it a little, bends the light above it into a
    -- bright rim along its underside, and catches a point of the lamp (or the
    -- moon, from the upper left) near its top
    for _, d in ipairs(drops) do
        love.graphics.setColor(0.02, 0.035, 0.035, 0.14 * d[4])
        Render.drawBlob(d[1], d[2] + 0.15 * d[3], d[3] * 1.15, d[3] * 1.05)
    end
    love.graphics.setBlendMode("add")
    local rim = { 0.45 * amb[1] + 0.55 * lamp[1] + 0.15 * moon,
                  0.48 * amb[2] + 0.55 * lamp[2] + 0.18 * moon,
                  0.52 * amb[3] + 0.55 * lamp[3] + 0.25 * moon }
    local sx = -0.22 - 0.22 * moon
    for _, d in ipairs(drops) do
        local x, y, r, s = d[1], d[2], d[3], d[4]
        love.graphics.setColor(rim[1], rim[2], rim[3], 0.65 * s)
        Render.drawBlob(x, y + 0.45 * r, r * 0.80, r * 0.42)
        love.graphics.setColor(rim[1] * 2, rim[2] * 2, rim[3] * 2, s)
        Render.drawBlob(x + sx * r, y - 0.42 * r, math.max(0.7, 0.34 * r))
    end
    love.graphics.pop()
end

return Condensation
