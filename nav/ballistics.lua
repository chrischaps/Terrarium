-- From chrischaps/Character @ 925c35b (core/ballistics.lua)
-- Ballistics: the single source of truth for jumps.
--
-- The nav graph uses it to decide which jumps exist, the controller uses it to
-- launch them, and the creatures fly them with the same gravity. Because all
-- three agree, a jump edge in the graph is a jump the creature can make.
--
-- Positions are "anchor" points: where the creature's feet meet the surface.

local ballistics = {}

ballistics.GRAVITY = 980

local sqrt, abs = math.sqrt, math.abs

-- Apex clearances to try, in order: low and quick first, higher if needed
local CLEARANCES = {14, 22, 34, 50, 72}

-- Solve launch velocity from (x0, y0) to land at (x1, y1).
-- profile: {jump_vy = max upward speed, jump_vx = max horizontal speed}
-- Returns vx, vy, flight_time - or nil if out of reach.
-- Terrarium: given a level, the lowest arc a body of profile.radius flies
-- clear of it, so a jump that would clip a corner low goes over it higher
-- (the nav graph and the controller ask the same question, so they agree).
function ballistics.solve_jump(x0, y0, x1, y1, profile, level)
    local g = ballistics.GRAVITY
    local max_rise = profile.jump_vy * profile.jump_vy / (2 * g)
    for _, clearance in ipairs(CLEARANCES) do
        local apex = math.min(y0, y1) - clearance
        local rise = y0 - apex
        if rise > max_rise then break end
        local vy = -sqrt(2 * g * rise)
        local t_up = -vy / g
        local t_down = sqrt(2 * (y1 - apex) / g)
        local t = t_up + t_down
        local vx = (x1 - x0) / t
        if abs(vx) <= profile.jump_vx
           and (not level or ballistics.arc_clear(level, x0, y0, vx, vy, t, profile.radius, profile.min_radius)) then
            return vx, vy, t
        end
    end
    return nil
end

-- Solve a step-off fall: leave (x0, y0) moving horizontally, land at (x1, y1).
function ballistics.solve_fall(x0, y0, x1, y1, profile)
    if y1 <= y0 then return nil end
    local t = sqrt(2 * (y1 - y0) / ballistics.GRAVITY)
    local vx = (x1 - x0) / t
    if abs(vx) > profile.jump_vx then return nil end
    return vx, 0, t
end

-- Position along the arc at time t
function ballistics.at(x0, y0, vx, vy, t)
    return x0 + vx * t, y0 + vy * t + 0.5 * ballistics.GRAVITY * t * t
end

-- Sample n+1 points along the arc as a flat list {x1, y1, x2, y2, ...}
function ballistics.sample_arc(x0, y0, vx, vy, t_total, n)
    n = n or 24
    local pts = {}
    for i = 0, n do
        local x, y = ballistics.at(x0, y0, vx, vy, t_total * i / n)
        pts[#pts + 1] = x
        pts[#pts + 1] = y
    end
    return pts
end

-- Does a body of radius r (centred r above the anchor) fly the arc without
-- touching any solid? The first and last few pixels are exempt because the
-- body is resting on its takeoff and landing surfaces there.
-- Terrarium: with r0, for every body of radius r0 to r at once (a size
-- bucket's, #16). A smaller body flies lower, so neither end alone will do:
-- the check is one circle around all of theirs, and the smallest exemption.
function ballistics.arc_clear(level, x0, y0, vx, vy, t_total, r, r0)
    r0 = r0 or r
    local steps = math.max(12, math.floor(t_total * 90))
    local pad = r * 0.85 + (r - r0) / 2
    for i = 1, steps - 1 do
        local t = t_total * i / steps
        local x, y = ballistics.at(x0, y0, vx, vy, t)
        local cy = y - (r + r0) / 2
        local from_start = math.min(abs(x - x0), abs(y - y0))
        local from_end_y = abs(y - (y0 + vy * t_total + 0.5 * ballistics.GRAVITY * t_total * t_total))
        local near_end = from_end_y < 3 and abs(x - (x0 + vx * t_total)) < r0
        if not (from_start < 2 and i < 3) and not near_end then
            if level:solid_at(x, cy, pad) then
                return false
            end
        end
    end
    return true
end

-- Time to fall from height y (moving with vy) down to y_target, or nil.
function ballistics.time_to_y(y, vy, y_target)
    local g = ballistics.GRAVITY
    -- y + vy t + g t^2 / 2 = y_target, take the later root (descending)
    local a, b, c = 0.5 * g, vy, y - y_target
    local disc = b * b - 4 * a * c
    if disc < 0 then return nil end
    local t = (-b + sqrt(disc)) / (2 * a)
    if t < 0 then return nil end
    return t
end

return ballistics
