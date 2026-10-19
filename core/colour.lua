-- colour: OKLCH, a colour space where equal steps look equal.
--
-- Lightness L (0..1), chroma C (0 grey .. about 0.3) and hue h in degrees. Two
-- colours with the same L read as equally bright whatever their hue, which is
-- what lets a family keep one lightness and chroma and let only its hue wander.
-- The conversions are Björn Ottosson's (https://bottosson.github.io/posts/oklab/).

local colour = {}

local cos, sin, rad, deg, atan2, sqrt = math.cos, math.sin, math.rad, math.deg, math.atan2, math.sqrt

local function encode(x) -- linear light to sRGB
    if x <= 0.0031308 then return 12.92 * x end
    return 1.055 * x ^ (1 / 2.4) - 0.055
end

local function decode(x) -- sRGB to linear light
    if x <= 0.04045 then return x / 12.92 end
    return ((x + 0.055) / 1.055) ^ 2.4
end

local function lab_to_linear(L, a, b)
    local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
    local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
    local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
    return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
          -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
          -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function inside(r, g, b)
    local e = 1e-4
    return r >= -e and r <= 1 + e and g >= -e and g <= 1 + e and b >= -e and b <= 1 + e
end

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

-- sRGB (0..1) for an OKLCH colour. One the screen can't show keeps its
-- lightness and hue and gives up chroma until it fits.
function colour.oklch(L, C, h)
    local hr = rad(h)
    local ca, sa = cos(hr), sin(hr)
    local r, g, b = lab_to_linear(L, C * ca, C * sa)
    if not inside(r, g, b) then
        local lo, hi = 0, C
        for _ = 1, 20 do
            local mid = (lo + hi) / 2
            r, g, b = lab_to_linear(L, mid * ca, mid * sa)
            if inside(r, g, b) then lo = mid else hi = mid end
        end
        r, g, b = lab_to_linear(L, lo * ca, lo * sa)
    end
    return clamp01(encode(r)), clamp01(encode(g)), clamp01(encode(b))
end

-- The other way: OKLab L, a, b for an sRGB colour
function colour.oklab(r, g, b)
    r, g, b = decode(r), decode(g), decode(b)
    local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
    local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
    local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
           1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
           0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

-- OKLCH for an sRGB colour (hue in degrees, 0..360)
function colour.lch(r, g, b)
    local L, a, bb = colour.oklab(r, g, b)
    return L, sqrt(a * a + bb * bb), deg(atan2(bb, a)) % 360
end

-- How different two sRGB colours look (distance in OKLab; 0.02 is about the
-- smallest difference you'd notice side by side)
function colour.distance(r1, g1, b1, r2, g2, b2)
    local L1, a1, c1 = colour.oklab(r1, g1, b1)
    local L2, a2, c2 = colour.oklab(r2, g2, b2)
    return sqrt((L1 - L2) ^ 2 + (a1 - a2) ^ 2 + (c1 - c2) ^ 2)
end

return colour
