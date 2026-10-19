-- statehash: a fingerprint of everything the simulation remembers.
--
-- A jar is its seed plus its history, so two runs of the same seed must agree
-- on every number after any number of steps. This walks the World (creatures,
-- controllers, graphs, the flora's chains, the sim RNG's state) in a fixed
-- order and folds it into a 32-bit FNV-1a hash. Each part also gets a hash of
-- its own, so a replay that drifts says where it drifted first.
--
-- Render state is left out on purpose: the interpolation buffers, meshes, and
-- the look stream all depend on how often the jar was drawn, never on the sim.

local bit = require('bit')
local rng = require('core.rng')

local statehash = {}

-- Fields that are drawing, not living
local SKIP = {
    snap = true, saved = true, -- World's render interpolation
    mesh = true,               -- a fern's draw buffer
    world = true,              -- a body's back-reference to the World walking it
    skin = true, color_name = true, -- a body's colours (#15), read only by drawing
    marks = true, local_marks = true, mark_frame = true, glow_mesh = true, -- what it drew, for its glow
}

local FNV_OFFSET = -2128831035 -- 2166136261 as a signed 32-bit int

local function fnv(h, s)
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        -- h * 16777619 without losing bits: the prime is 2^24 + 403
        h = bit.tobit(bit.lshift(h, 24) + h * 403)
    end
    return h
end

local TYPE_ORDER = {boolean = 1, number = 2, string = 3}

local function key_less(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return TYPE_ORDER[ta] < TYPE_ORDER[tb] end
    if ta == 'boolean' then return (not a) and b end
    return a < b
end

-- Append a canonical spelling of v to out. Tables are walked once; a second
-- visit writes the order it was first seen in, which is the same every run.
local function walk(v, out, seen)
    local t = type(v)
    if t == 'number' then
        out[#out + 1] = string.format('%.17g', v)
    elseif t == 'string' then
        out[#out + 1] = string.format('%q', v)
    elseif t == 'boolean' then
        out[#out + 1] = v and 'T' or 'F'
    elseif t == 'table' then
        if seen[v] then
            out[#out + 1] = '@' .. seen[v]
            return
        end
        seen.n = seen.n + 1
        seen[v] = seen.n
        local keys = {}
        for k in pairs(v) do
            if TYPE_ORDER[type(k)] and not SKIP[k] then keys[#keys + 1] = k end
        end
        table.sort(keys, key_less)
        out[#out + 1] = '{'
        for _, k in ipairs(keys) do
            local before = #out
            walk(k, out, seen)
            out[#out + 1] = '='
            local mark = #out
            walk(v[k], out, seen)
            if #out == mark then
                -- functions and other unwalkable values leave no trace
                for j = #out, before + 1, -1 do out[j] = nil end
            else
                out[#out + 1] = ','
            end
        end
        out[#out + 1] = '}'
    elseif t == 'userdata' and v.typeOf and v:typeOf('RandomGenerator') then
        out[#out + 1] = v:getState()
    end
end

-- The World's state as {total = 'xxxxxxxx', parts = {{name, hash}, ...}}.
-- Pass the flora's list (Plants.all()) to include the ferns and moss stalks.
function statehash.of(world, flora)
    local seen = {n = 0}
    local parts = {}
    local total = FNV_OFFSET
    local function part(name, v)
        local out = {}
        walk(v, out, seen)
        local s = table.concat(out)
        local h = fnv(FNV_OFFSET, s)
        total = fnv(total, name .. s)
        parts[#parts + 1] = {name, bit.tohex(h)}
    end
    part('time', world.time)
    part('rng.sim', rng.sim)
    part('level', world.level)
    for i, c in ipairs(world.creatures) do
        part(c.name and (c.key .. ' ' .. c.name) or c.key or ('creature' .. i), c)
    end
    part('moss', world.moss)
    part('graphs', world.graphs)
    part('controllers', world.controllers)
    part('minds', world.minds)
    if flora then part('flora', flora) end
    part('world', world) -- whatever else the World keeps, now that the rest is seen
    return {total = bit.tohex(total), parts = parts}
end

-- The first part where two hashes disagree, or nil if they match
function statehash.diverged(a, b)
    for i, p in ipairs(a.parts) do
        local q = b.parts[i]
        if not q or q[1] ~= p[1] or q[2] ~= p[2] then return p[1] end
    end
    if #b.parts ~= #a.parts then return '(parts)' end
    return nil
end

return statehash
