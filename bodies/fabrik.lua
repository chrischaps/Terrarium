-- From chrischaps/Character @ 925c35b (core/fabrik.lua)
-- FABRIK: Forward And Backward Reaching Inverse Kinematics (2D).
--
-- A chain is a list of joints {x, y} (root first) and bone lengths. Solving
-- moves the end toward a target while the root stays put. A pole point bends
-- the chain the way you want (knees up, elbows out) by nudging the inner
-- joints toward it before each pass. Starting from the previous solution keeps
-- motion smooth frame to frame.
--
--   local leg = fabrik.chain(hip_x, hip_y, {12, 14, 12})
--   fabrik.solve(leg, hip_x, hip_y, foot_x, foot_y, pole_x, pole_y)

local fabrik = {}

local sqrt = math.sqrt

function fabrik.chain(x, y, lengths, dir_x, dir_y)
    dir_x, dir_y = dir_x or 1, dir_y or 0
    local joints = {{x = x, y = y}}
    local total = 0
    for i, len in ipairs(lengths) do
        total = total + len
        joints[i + 1] = {x = x + dir_x * total, y = y + dir_y * total}
    end
    return {joints = joints, lengths = lengths, total = total}
end

local function place(from, to, len)
    -- Put `to` at distance len from `from`, keeping its direction
    local dx, dy = to.x - from.x, to.y - from.y
    local d = sqrt(dx * dx + dy * dy)
    if d < 1e-6 then dx, dy, d = 0, 1, 1 end
    to.x, to.y = from.x + dx / d * len, from.y + dy / d * len
end

function fabrik.solve(chain, root_x, root_y, tx, ty, pole_x, pole_y, iterations, pole_weight)
    local j, L = chain.joints, chain.lengths
    local n = #j
    iterations = iterations or 8
    pole_weight = pole_weight or 0.3

    -- Unreachable: point the chain straight at the target
    local dx, dy = tx - root_x, ty - root_y
    local d = sqrt(dx * dx + dy * dy)
    if d >= chain.total then
        j[1].x, j[1].y = root_x, root_y
        local ux, uy = dx / d, dy / d
        local acc = 0
        for i = 2, n do
            acc = acc + L[i - 1]
            -- slight sag toward the pole so a stretched leg still reads as a leg
            j[i].x, j[i].y = root_x + ux * acc, root_y + uy * acc
        end
        return false
    end

    for _ = 1, iterations do
        if pole_x then
            for i = 2, n - 1 do
                j[i].x = j[i].x + (pole_x - j[i].x) * pole_weight / (i - 1)
                j[i].y = j[i].y + (pole_y - j[i].y) * pole_weight / (i - 1)
            end
        end
        -- Backward: end to target, then pull each joint after it
        j[n].x, j[n].y = tx, ty
        for i = n - 1, 1, -1 do place(j[i + 1], j[i], L[i]) end
        -- Forward: root back home, push each joint along
        j[1].x, j[1].y = root_x, root_y
        for i = 2, n do place(j[i - 1], j[i], L[i - 1]) end

        local ex, ey = j[n].x - tx, j[n].y - ty
        if ex * ex + ey * ey < 0.01 then break end
    end
    return true
end

return fabrik
