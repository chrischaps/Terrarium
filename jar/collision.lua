-- From chrischaps/Character @ 925c35b (world/collision.lua)
-- Collision: points and rays against axis-aligned solids.
--
-- Solids are plain tables {x, y, w, h}. Points are scalar verlet-style tables
-- {x, y, px, py} where (px, py) is the previous position, so velocity is
-- implicit (per fixed step). Resolution picks the face the point actually
-- entered through (swept by entry time), not the nearest face - that is what
-- stops points snapping out the wrong side at corners or at speed.

local collision = {}

local huge = math.huge
local min, max = math.min, math.max

-- First solid whose (padded) interior strictly contains (x, y), or nil.
function collision.solid_at(solids, x, y, pad)
    pad = pad or 0
    for i = 1, #solids do
        local s = solids[i]
        if x > s.x - pad and x < s.x + s.w + pad and y > s.y - pad and y < s.y + s.h + pad then
            return s
        end
    end
    return nil
end

-- Resolve a circle of radius r centred on point p out of every solid.
-- grip: fraction of tangential velocity kept on contact (1 = ice, 0 = glue)
-- bounce: fraction of normal velocity reflected
-- Returns the last solid touched and the contact normal (nx, ny).
function collision.resolve_point(solids, p, r, grip, bounce)
    grip = grip or 0.85
    bounce = bounce or 0
    local hit, hnx, hny
    for i = 1, #solids do
        local s = solids[i]
        local l, t = s.x - r, s.y - r
        local rt, b = s.x + s.w + r, s.y + s.h + r
        if p.x > l and p.x < rt and p.y > t and p.y < b then
            local px, py = p.px, p.py
            local vx, vy = p.x - px, p.y - py

            -- Entry time per axis (only for axes we were outside of last step)
            local tx, ty, nx, ny = -huge, -huge, 0, 0
            if px <= l and vx > 0 then tx, nx = (l - px) / vx, -1
            elseif px >= rt and vx < 0 then tx, nx = (rt - px) / vx, 1 end
            if py <= t and vy > 0 then ty, ny = (t - py) / vy, -1
            elseif py >= b and vy < 0 then ty, ny = (b - py) / vy, 1 end

            if tx == -huge and ty == -huge then
                -- Started inside (teleport or stacked push): nearest face
                local dl, dr, dt, db = p.x - l, rt - p.x, p.y - t, b - p.y
                local m = min(dl, dr, dt, db)
                if m == dt then nx, ny = 0, -1
                elseif m == db then nx, ny = 0, 1
                elseif m == dl then nx, ny = -1, 0
                else nx, ny = 1, 0 end
            elseif ty >= tx then
                nx = 0
            else
                ny = 0
            end

            if ny ~= 0 then
                p.y = ny < 0 and t or b
                if vy * ny < 0 then vy = -vy * bounce end
                vx = vx * grip
            else
                p.x = nx < 0 and l or rt
                if vx * nx < 0 then vx = -vx * bounce end
                vy = vy * grip
            end
            p.px, p.py = p.x - vx, p.y - vy
            hit, hnx, hny = s, nx, ny
        end
    end
    return hit, hnx, hny
end

-- Ray from (ox, oy) along unit direction (dx, dy) up to maxd.
-- Solids containing the origin are ignored (so rays can start on a surface).
-- Returns distance, normal x, normal y, solid - or nil.
function collision.raycast(solids, ox, oy, dx, dy, maxd, pad)
    pad = pad or 0
    local best, bnx, bny, bs = maxd or huge, nil, nil, nil
    for i = 1, #solids do
        local s = solids[i]
        local l, t = s.x - pad, s.y - pad
        local r, b = s.x + s.w + pad, s.y + s.h + pad
        local tmin, tmax = -huge, huge
        local nx, ny = 0, 0
        local miss = false

        if dx ~= 0 then
            local t1, t2 = (l - ox) / dx, (r - ox) / dx
            local n = -1
            if t1 > t2 then t1, t2, n = t2, t1, 1 end
            if t1 > tmin then tmin, nx, ny = t1, n, 0 end
            tmax = min(tmax, t2)
        elseif ox <= l or ox >= r then
            miss = true
        end

        if not miss then
            if dy ~= 0 then
                local t1, t2 = (t - oy) / dy, (b - oy) / dy
                local n = -1
                if t1 > t2 then t1, t2, n = t2, t1, 1 end
                if t1 > tmin then tmin, nx, ny = t1, 0, n end
                tmax = min(tmax, t2)
            elseif oy <= t or oy >= b then
                miss = true
            end
        end

        if not miss and tmin <= tmax and tmin >= 0 and tmin < best then
            best, bnx, bny, bs = tmin, nx, ny, s
        end
    end
    if bs then return best, bnx, bny, bs end
    return nil
end

-- True if a circle at (x, y) with radius r overlaps no solid.
function collision.circle_clear(solids, x, y, r)
    return collision.solid_at(solids, x, y, r) == nil
end

-- Clamp helper shared by callers
function collision.clamp(v, a, b)
    return max(a, min(b, v))
end

return collision
