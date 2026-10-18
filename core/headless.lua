-- Terrarium: a jar with nobody looking. With no window (conf.lua turns it off
-- for --headless, --test, --selftest, --replay and --navdump), love.graphics
-- can't make a canvas or a mesh, but composing the jar bakes both, and bakes
-- them from rng.scape. This swaps in a null graphics module that accepts every
-- call and draws nothing, so the bakes run their code (and their draws from
-- rng.scape) exactly as they do in a window.
--
-- It's also the rule "rendering never affects the simulation", tested: a
-- headless jar has to hash the same as one with a window.

local headless = {}

local null
local mt = {}
local function self() return null end
mt.__index = self
mt.__call = self
mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__mod, mt.__pow, mt.__unm = self, self, self, self, self, self, self
mt.__concat = function() return '' end
mt.__tostring = function() return 'null' end
null = setmetatable({}, mt)

function headless.active()
    return not (love.window and love.window.isOpen())
end

-- Call before requiring anything that draws
function headless.install()
    love.graphics = null
end

return headless
