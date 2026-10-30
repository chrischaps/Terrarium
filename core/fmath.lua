-- Terrarium: the sim's squares (#94). In the LuaJIT LÖVE 11.5 ships, `x ^ 2`
-- isn't one number: the interpreter calls the C library's pow, the compiler
-- turns it into x * x, and about one square in 500 comes out a bit apart.
-- Which one a step gets depends on what the process had compiled by then, so
-- two processes could run the same jar to different hashes (tests/ci.sh's
-- replay across processes, and its --interpret check). A square in sim code is
-- sq(x), or x * x, never x ^ 2. (The rest of math, and every other power, came
-- out the same both ways when this was measured.)

local fmath = {}

function fmath.sq(x) return x * x end

return fmath
