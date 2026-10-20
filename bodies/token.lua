-- Token: a creature with no soft body, for the coarse step (#27, #31).
--
-- A token is a body's anchor and nothing hanging off it: no verlet chain, no
-- pressure ring, no legs. It takes its genes the way its own plan's body does
-- (the plan's `take`), so it has the same profile, nav profile, court gap and
-- skin, and it answers what the World and a mind ask of a body (where its
-- anchor is, whether it climbs, what it stands on, whether it's settled), so
-- the same minds, moss, eggs and deaths run over tokens as over bodies. A
-- Glide (nav/glide.lua) moves it along its own graph's edges, so the body
-- still never lies: a token only goes where its body could.
--
-- It's what a month in the jar runs on (the `month` test), and what catch-up
-- after time away will run on. Nothing draws a token.

local Token = {}
Token.__index = Token

-- A token of plan `key` (whose body class is `class`) at (x, y), from
-- `genome`; `young` as the plan's own body takes it
function Token.new(key, class, x, y, genome, young)
    local self = setmetatable({key = key, class = class, x = x, y = y}, Token)
    self:take(genome, young)
    self.mover = {state = 'ground'} -- (a climber's only says what it set off from)
    if self.profile.climbs then self.mode, self.nx, self.ny = 'attached', 0, -1 end
    self.face = {}
    return self
end

function Token:take(genome, young)
    self.class.take(self, genome, young)
    self.profile = self.profile or self.class.profile
    self.nav = self.nav or self.class.nav_profile(genome)
    self.court_gap = self.court_gap or 9 -- (a worm's, which only its new sets)
    -- (how far either side of its anchor its body lies, for where it goes back
    -- to the moss: its plan's `half`, #76)
    self.half = self.class.half(self)
end

function Token:anchor() return self.x, self.y end

-- Where it is, on the surface `solid` with the normal (nx, ny) (climbers only)
function Token:set(x, y, solid, nx, ny)
    self.x, self.y = x, y
    if self.profile.climbs then
        self.solid = solid or self.solid
        if nx then self.nx, self.ny = nx, ny end
    elseif solid then
        self.mover.solid = solid
    end
end

-- In flight, or settled on a surface
function Token:fly(air)
    if self.profile.climbs then self.mode = air and 'air' or 'attached' else self.mover.state = air and 'air' or 'ground' end
end

function Token:interp_points()
    return {{x = self.x - self.half, y = self.y}, {x = self.x + self.half, y = self.y}}
end

function Token:grow(genome, young) self:take(genome, young) end
function Token:plant_all() end
function Token:update() end
function Token:influencers() end

return Token
