-- Catchup: the time you were away, lived on the coarse step (#31).
--
-- A jar you leave doesn't stop. When it's opened again, the time it was shut
-- is lived out on the coarse step (#27): the bodies go to tokens where they
-- stand (World:coarsen), the minds, moss, eggs, ageing and the floor run
-- World.COARSE seconds at a time with no soft bodies and nothing drawn, and
-- then each token takes up its body again where it is (World:embody). A day
-- takes a few seconds.
--
-- It can't be what would have happened had the jar been watched: a token
-- glides where a body would crawl and stumble. The proposal accepts that drift,
-- since what comes back is deterministic and whole: the same jar, away the
-- same time, always comes back the same, and as a jar its own rules made.
--
-- At most CAP days are lived. Past that, whole days are let go, so the jar
-- comes back at the hour it was left plus the time away, and its lamp keeps
-- the room's hours. Nothing here reads a clock: how long it was away is an
-- input, like the seed.

local World = require('jar.world')

local Catchup = {}
Catchup.__index = Catchup

Catchup.CAP = 7 -- jar days lived at most

-- How long a jar away `away` seconds lives through, with days of `day`
-- seconds: all of it up to CAP days, and past that, the whole days over CAP
-- let go. A whole number of coarse steps.
function Catchup.span(away, day)
    if not (away and away > 0) then return 0 end
    local cap = Catchup.CAP * day
    if away > cap then away = away - math.ceil((away - cap) / day) * day end
    return math.floor(away / World.COARSE) * World.COARSE
end

-- Catching `world` up on `away` seconds. The world goes coarse now.
function Catchup.new(world, away)
    local self = setmetatable({world = world}, Catchup)
    self.from = world.time
    self.span = Catchup.span(away, world:day_length())
    self.steps = math.floor(self.span / World.COARSE + 0.5)
    self.done = 0
    world.catching = true -- (what listens to the World can tell; the sim never reads it)
    -- (the ferns sway on the fine step only, and wait where they are)
    self.flora, world.flora = world.flora, nil
    world:coarsen()
    return self
end

-- Live up to `n` more coarse steps. Returns how many are left.
function Catchup:run(n)
    local w = self.world
    for _ = 1, math.min(n, self.steps - self.done) do
        w:step(World.COARSE)
        self.done = self.done + 1
    end
    return self.steps - self.done
end

function Catchup:left() return self.steps - self.done end

-- How far through the time away it is (0 to 1), and how many whole days it has lived
function Catchup:progress()
    local day = self.world:day_length()
    return self.steps > 0 and self.done / self.steps or 1, math.floor(self.done * World.COARSE / day)
end

-- Done: every token takes up its body again. Returns the world.
function Catchup:finish()
    self:run(self.steps)
    local w = self.world
    w:embody()
    w.catching, w.flora = nil, self.flora
    return w
end

-- All of it at once
function Catchup.now(world, away)
    return Catchup.new(world, away):finish()
end

return Catchup
