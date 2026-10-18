-- From chrischaps/Fishbowl @ b0624e4 (env/motes.lua)
-- Suspended particulate: tiny motes drifting in the air, sparkling when they
-- cross the light. Back motes sit behind the creatures, front motes drift
-- between them and the glass.
-- Terrarium: the jar's air is still, so there's no current to carry them, only
-- a slow wander and a little settling. They shine in the lamp's cone instead of
-- Fishbowl's light shafts, and catch the moon faintly at night. Stepped on the
-- fixed step and drawn from rng.look, so the same jar shows the same motes.
-- Positions are in level coordinates plus a depth d.

local C = require("jar.config")
local Tank = require("jar.tank")
local Render = require("jar.render")

local Motes = {}

local sin, abs = math.sin, math.abs

local gen
local list = {}
local time = 0

local function random() return gen:random() end

local function soilY(x, d) return Tank.floorY(x, d) - C.OY end

local function respawn(m)
    m.d = random()
    m.x = C.GLASS_L + 6 + random() * (C.GLASS_R - C.GLASS_L - 12)
    local floor = soilY(m.x, m.d)
    m.y = C.GLASS_T + 10 + random() * (floor - C.GLASS_T - 20)
    m.size = 0.5 + random() ^ 3 * 1.8
    m.base = 0.05 + random() * 0.10
    m.phase = random() * 10
    m.sink = (random() - 0.55) * 2.4
end

function Motes.init(generator, count)
    gen = generator
    list = {}
    time = 0
    for i = 1, count or 120 do
        local m = {}
        respawn(m)
        list[i] = m
    end
end

function Motes.update(dt)
    time = time + dt
    for _, m in ipairs(list) do
        m.x = m.x + sin(time * 0.21 + m.phase) * 2.2 * dt
        m.y = m.y + (m.sink + sin(time * 0.17 + m.phase * 1.7) * 1.2) * dt
        if m.y < C.GLASS_T + 4 or m.y > soilY(m.x, m.d) or m.x < C.GLASS_L or m.x > C.GLASS_R then
            respawn(m)
        end
    end
end

--- How much of the lamp's cone reaches (x, y): 1 on its axis, 0 outside it
-- Terrarium: in place of Water.rayLight
function Motes.coneLight(x, y)
    local t = Tank.clamp((y - C.GLASS_T) / (C.SOIL_Y - C.GLASS_T), 0, 1)
    local hw = Tank.lerp(C.LAMP_CONE.top, C.LAMP_CONE.bottom, t)
    local u = abs(x - C.LAMP_X) / hw
    return Tank.clamp(1 - u * u, 0, 1) * (1 - t * 0.5)
end

local function drawRange(env, dMin, dMax)
    local lc = env.lamp
    for _, m in ipairs(list) do
        if m.d >= dMin and m.d < dMax then
            local sx, sy, k = Tank.level(m.x, m.y, m.d)
            local lit = Motes.coneLight(m.x, m.y) * env.lamp_i
            local twinkle = 0.75 + 0.25 * sin(time * 1.3 + m.phase)
            local a = (m.base * (0.3 + 0.7 * env.lamp_i + 0.4 * env.moon) + lit * 0.5) * twinkle
            -- Lit by the lamp when it's on, by the moon when it isn't
            local r = lc[1] + 0.35 * env.moon
            local g = lc[2] + 0.42 * env.moon
            local b = lc[3] + 0.60 * env.moon
            local haze = Tank.haze(m.d) * 0.6
            love.graphics.setColor(
                r * (1 - haze) + env.fog[1] * haze,
                g * (1 - haze) + env.fog[2] * haze,
                b * (1 - haze) + env.fog[3] * haze, math.min(0.8, a))
            local rad = m.size * k * (m.d > 0.9 and 1.6 or 1)
            if rad > 1.2 then
                Render.drawBlob(sx, sy, rad * 1.8)
            else
                love.graphics.circle("fill", sx, sy, rad)
            end
        end
    end
end

function Motes.drawBack(env) drawRange(env, 0, C.PLANE_D) end
function Motes.drawFront(env) drawRange(env, C.PLANE_D, 1.01) end

return Motes
