-- From chrischaps/Fishbowl @ b0624e4 (env/daycycle.lua)
-- Day/night cycle: keyframed light palettes for the whole jar, blended from the
-- two keyframes either side of the hour and published as DayCycle.env.
-- Terrarium: the light is the lamp hung above the jar, on a timer. It warms up
-- at seven, burns all day, dims amber through the evening and clicks off; after
-- that the only light is the moon through the window. A jar day is a real day,
-- and the hour is a pure function of the jar's sim time, so the cycle is as
-- deterministic as everything else. Fishbowl's free-running phase, glide, speed
-- and live-clock toggle are gone (time-lapse is question #39).

local C = require("jar.config")

local DayCycle = {}

-- Keyframes, by hour. Colours are linear-ish RGB; numbers blend smoothly.
--   ambient : multiplier on everything lit in the jar
--   fog     : what the back of the jar fades into
--   haze    : how much the back of the jar fades
--   bulb    : the lamp's colour; lamp_i its brightness (0 = off)
--   room    : multiplier on the room and desk around the jar
--   moon    : moonlight through the window (0..1)
--   glow    : goblin's-gold moss and anything else that shows best in the dark
local keys = {
    { h = 0.0, name = "night",
      ambient = { 0.30, 0.35, 0.52 }, fog = { 0.03, 0.045, 0.08 }, haze = 0.65,
      bulb = { 1.00, 0.70, 0.42 }, lamp_i = 0.00, room = { 0.26, 0.31, 0.48 }, moon = 1.00, glow = 1.00 },
    { h = 5.5, name = "before dawn",
      ambient = { 0.33, 0.37, 0.50 }, fog = { 0.04, 0.05, 0.08 }, haze = 0.62,
      bulb = { 1.00, 0.70, 0.42 }, lamp_i = 0.00, room = { 0.32, 0.36, 0.50 }, moon = 0.55, glow = 0.80 },
    { h = 7.0, name = "lamp on",
      ambient = { 0.74, 0.62, 0.54 }, fog = { 0.10, 0.08, 0.08 }, haze = 0.58,
      bulb = { 1.00, 0.72, 0.44 }, lamp_i = 0.50, room = { 0.56, 0.50, 0.50 }, moon = 0.20, glow = 0.25 },
    { h = 8.5, name = "morning",
      ambient = { 0.94, 0.90, 0.84 }, fog = { 0.10, 0.10, 0.10 }, haze = 0.55,
      bulb = { 1.00, 0.88, 0.68 }, lamp_i = 0.90, room = { 0.84, 0.84, 0.88 }, moon = 0.00, glow = 0.00 },
    { h = 13.0, name = "midday",
      ambient = { 1.00, 0.98, 0.94 }, fog = { 0.11, 0.11, 0.11 }, haze = 0.52,
      bulb = { 1.00, 0.94, 0.82 }, lamp_i = 1.00, room = { 1.00, 1.00, 1.00 }, moon = 0.00, glow = 0.00 },
    { h = 17.0, name = "afternoon",
      ambient = { 0.98, 0.90, 0.78 }, fog = { 0.11, 0.10, 0.09 }, haze = 0.54,
      bulb = { 1.00, 0.84, 0.60 }, lamp_i = 0.95, room = { 0.90, 0.82, 0.74 }, moon = 0.00, glow = 0.00 },
    { h = 20.0, name = "evening",
      ambient = { 0.80, 0.62, 0.48 }, fog = { 0.10, 0.07, 0.06 }, haze = 0.58,
      bulb = { 1.00, 0.66, 0.38 }, lamp_i = 0.55, room = { 0.58, 0.46, 0.40 }, moon = 0.10, glow = 0.15 },
    { h = 21.5, name = "lamp off",
      ambient = { 0.36, 0.36, 0.50 }, fog = { 0.04, 0.04, 0.08 }, haze = 0.62,
      bulb = { 1.00, 0.66, 0.38 }, lamp_i = 0.00, room = { 0.30, 0.30, 0.45 }, moon = 0.70, glow = 0.70 },
}

-- Named hours for --hour
DayCycle.presets = {
    night = 2, dawn = 6.5, lampon = 7.2, morning = 9, midday = 13,
    afternoon = 16, evening = 20, lampoff = 21.6,
}

DayCycle.env = {}

local function lerp(a, b, t) return a + (b - a) * t end

local function blend(a, b, t, out)
    for k, va in pairs(a) do
        local vb = b[k]
        if type(va) == "number" then
            out[k] = lerp(va, vb, t)
        elseif type(va) == "table" then
            out[k] = out[k] or {}
            blend(va, vb, t, out[k])
        end
    end
    return out
end

--- Blend the light for an hour (0..24) into DayCycle.env
function DayCycle.evaluate(hour)
    hour = hour % 24
    local n = #keys
    local a, b, t = keys[n], keys[1], 0
    for i = 1, n do
        local h1 = keys[i].h
        local h2 = keys[i + 1] and keys[i + 1].h or 24 + keys[1].h
        local hh = hour
        if i == n and hh < h1 then hh = hh + 24 end
        if hh >= h1 and hh < h2 then
            a, b = keys[i], keys[i % n + 1]
            t = (hh - h1) / (h2 - h1)
            break
        end
    end
    t = t * t * (3 - 2 * t)  -- smoothstep: palettes ease in and out of each key
    local env = blend(a, b, t, DayCycle.env)
    env.name = (t < 0.5) and a.name or b.name
    env.hour = hour
    -- Terrarium: what everything else reads is the lamp as it shines
    env.lamp = env.lamp or {}
    for i = 1, 3 do env.lamp[i] = env.bulb[i] * env.lamp_i end
    return env
end

--- The jar's hour after `seconds` of sim time, starting at `startHour`.
-- A day is C.DAY_SECONDS long unless a dev run compresses it.
function DayCycle.hourAt(startHour, seconds, daySeconds)
    return (startHour + 24 * seconds / (daySeconds or C.DAY_SECONDS)) % 24
end

--- The local hour on the wall clock. Read once, when a jar is opened: it's an
-- input like the seed, never consulted again by the simulation.
function DayCycle.clockHour()
    local d = os.date("*t")
    return d.hour + d.min / 60 + d.sec / 3600
end

--- Parse --hour: a number of hours or one of the presets
function DayCycle.parseHour(s)
    if not s then return nil end
    return tonumber(s) or DayCycle.presets[s]
end

DayCycle.evaluate(13)

return DayCycle
