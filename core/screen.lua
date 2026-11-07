-- Terrarium: the jar's view on a screen of another shape (#90). The view is
-- C.W x C.H (16:10). In a window, a screen that isn't gets the view scaled to
-- cover it, losing at most CROP of its height or width (half from each edge),
-- and thin bars for whatever is left: 1280 x 720 loses 40 px from the top and
-- bottom, the room's ceiling and the desk's near edge, and keeps the room round
-- the jar. On the frame (#110) the jar is the whole picture: the inside of its
-- glass covers the screen and nothing round it shows, not even its own frame.

local Glass = require('jar.glass')

local Screen = {}

Screen.CROP = 0.1
-- How far the frame's fit stays inside the glass, in the view's pixels: the
-- front glass's colour fringes (composite.glsl) reach a pixel or two past the
-- pane, and a frame scaled by a fraction blends in the pixel beyond its edge
Screen.INSET = 3

-- How to draw a vw x vh view on a w x h screen: scale k, then offset x, y
function Screen.fit(w, h, vw, vh)
    local contain = math.min(w / vw, h / vh)
    local cover = math.max(w / vw, h / vh)
    local k = math.min(cover, contain / (1 - Screen.CROP))
    return { k = k, x = math.floor((w - vw * k) / 2 + 0.5), y = math.floor((h - vh * k) / 2 + 0.5) }
end

-- A stretch of the view (x0, y0, x1, y1, in its pixels) scaled to cover the
-- w x h screen and centred on it, so nothing round it shows. Whichever way
-- the stretch is longer than the screen gives way, half from each side. No
-- rounding: the scale isn't whole, and a rounded offset could open a sliver
-- of what's outside at one edge.
function Screen.cover(w, h, x0, y0, x1, y1)
    local k = math.max(w / (x1 - x0), h / (y1 - y0))
    return { k = k, x = w / 2 - (x0 + x1) / 2 * k, y = h / 2 - (y0 + y1) / 2 * k }
end

-- The frame's fit: the glass's inside, taken in by INSET, covers the screen.
-- The tank is wider than 16:9, so at 1280 x 720 it's scaled by about 1.17 and
-- loses its sides, about 40 px of screen from each; lid to base all shows.
function Screen.tank(w, h)
    local x0, y0, x1, y1 = Glass.innerRect()
    local i = Screen.INSET
    return Screen.cover(w, h, x0 + i, y0 + i, x1 - i, y1 - i)
end

-- A point on the screen, in the view's own pixels
function Screen.toView(f, sx, sy)
    return (sx - f.x) / f.k, (sy - f.y) / f.k
end

-- Draw in the view's pixels until love.graphics.pop()
function Screen.push(f)
    love.graphics.push()
    love.graphics.translate(f.x, f.y)
    love.graphics.scale(f.k)
end

return Screen
