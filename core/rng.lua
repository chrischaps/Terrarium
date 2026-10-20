-- From chrischaps/Character @ 925c35b (core/rng.lua)
-- RNG: seeded streams so the simulation stays deterministic.
--   rng.sim  - anything that changes physics or behaviour (selftest replays it exactly)
--   rng.look - purely visual variation (blinks, sparkles, leaf jitter)
--   rng.scape - the jar's fixed composition: stones, soil layers, the desk
--               (Terrarium: drawn from once at load, so it's the same every visit)
--   rng.sound - Terrarium: the jar's voices (#28), so whether it's heard changes
--               nothing that's seen

local rng = {}

function rng.seed(seed)
    seed = seed or 7
    rng.jar = seed -- Terrarium: the jar's cast is drawn from it by a hash, not a stream (#74)
    rng.sim = love.math.newRandomGenerator(seed)
    rng.look = love.math.newRandomGenerator(seed * 31 + 11)
    rng.scape = love.math.newRandomGenerator(seed * 131 + 7) -- Terrarium: the scape seed
    rng.sound = love.math.newRandomGenerator(seed * 17 + 3) -- Terrarium: the voices (#28)
end

-- Uniform float in [a, b)
function rng.range(gen, a, b)
    return a + gen:random() * (b - a)
end

rng.seed()

return rng
