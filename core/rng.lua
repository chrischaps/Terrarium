-- From chrischaps/Character @ 925c35b (core/rng.lua)
-- RNG: two seeded streams so the simulation stays deterministic.
--   rng.sim  - anything that changes physics or behaviour (selftest replays it exactly)
--   rng.look - purely visual variation (blinks, sparkles, leaf jitter)
--   rng.scape - the jar's fixed composition: stones, soil layers, the desk
--               (Terrarium: drawn from once at load, so it's the same every visit)

local rng = {}

function rng.seed(seed)
    seed = seed or 7
    rng.sim = love.math.newRandomGenerator(seed)
    rng.look = love.math.newRandomGenerator(seed * 31 + 11)
    rng.scape = love.math.newRandomGenerator(seed * 131 + 7) -- Terrarium: the scape seed
end

-- Uniform float in [a, b)
function rng.range(gen, a, b)
    return a + gen:random() * (b - a)
end

rng.seed()

return rng
