-- Terrarium: the sim's sines and cosines (#94). In LÖVE 11.5's LuaJIT, the
-- interpreter's math.sin and the compiled one don't agree to the last bit, so
-- a body's step came out different depending on whether its code had been
-- compiled yet, and that depends on what else the process has run: drawing the
-- jar (with no window, the jar was never drawn, so the order was always the
-- same). These are the C library's, called through the FFI, the same function
-- either way. Anything the sim steps with uses them; drawing can keep math's.

local ffi = require('ffi')

ffi.cdef [[
double sin(double);
double cos(double);
double atan2(double, double);
double exp(double);
double log(double);
]]

local C = ffi.C

return {
    sin = C.sin,
    cos = C.cos,
    atan2 = C.atan2,
    exp = C.exp,
    log = C.log,
}
