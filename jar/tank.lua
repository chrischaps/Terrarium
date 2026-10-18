-- From chrischaps/Fishbowl @ b0624e4 (world.lua)
-- Projection and jar geometry helpers.
-- Terrarium: renamed from world.lua (jar/world.lua is the simulation), and the
-- creatures' plane maps level coordinates into the box.

local C = require("jar.config")

local Tank = {}

local sin = math.sin

--- Projected scale at depth d
function Tank.k(d)
    return C.K_BACK + (1 - C.K_BACK) * d
end

--- World (x, y, d) -> screen x, y, scale
function Tank.project(x, y, d)
    local k = C.K_BACK + (1 - C.K_BACK) * d
    return C.CX + (x - C.CX) * k, C.CY + (y - C.CY) * k, k
end

--- Screen (sx, sy) at depth d -> world x, y
function Tank.unproject(sx, sy, d)
    local k = C.K_BACK + (1 - C.K_BACK) * d
    return C.CX + (sx - C.CX) / k, C.CY + (sy - C.CY) / k
end

-- Terrarium: level coordinates live on the creatures' plane
function Tank.level(lx, ly, d)
    return Tank.project(C.OX + lx, C.OY + ly, d or C.PLANE_D)
end

function Tank.toLevel(sx, sy)
    local x, y = Tank.unproject(sx, sy, C.PLANE_D)
    return x - C.OX, y - C.OY
end

-- Terrarium: draw in level coordinates on the creatures' plane
function Tank.pushPlane(d)
    local k = Tank.k(d or C.PLANE_D)
    love.graphics.push()
    love.graphics.translate(C.CX, C.CY)
    love.graphics.scale(k)
    love.graphics.translate(C.OX - C.CX, C.OY - C.CY)
end

--- World y of the soil top at (x, d), x in level coordinates.
-- Terrarium: exactly level.soil on the creatures' plane, so feet meet the ground;
-- it banks toward the back and ripples a little away from the plane.
function Tank.floorY(x, d)
    local back = math.max(0, C.PLANE_D - d) / C.PLANE_D
    local away = Tank.smoothstep(0, 0.3, math.abs(d - C.PLANE_D))
    return C.OY + C.SOIL_Y - C.SOIL_RISE * back ^ 1.3
        + away * (3 * sin(x * 0.0091 + d * 3.1) + 2 * sin(x * 0.0213 - d * 5.3 + 1.3))
end

--- How much distance-haze to apply at depth d (0..1, before light scaling)
function Tank.haze(d)
    return (1 - d) ^ 1.6
end

function Tank.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function Tank.lerp(a, b, t)
    return a + (b - a) * t
end

function Tank.smoothstep(e0, e1, x)
    local t = Tank.clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
end

return Tank
