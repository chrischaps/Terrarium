-- Terrarium: the jar's view on a screen of another shape (#90). The view is
-- C.W x C.H (16:10); a screen that isn't gets the view scaled to cover it,
-- losing at most CROP of its height or width (half from each edge), and thin
-- bars for whatever is left. The frame's 1280 x 720 loses 40 px from the top
-- and bottom: the room's ceiling and the desk's near edge go, the lamp's glow
-- and the jar's base stay, and the jar is drawn a pixel to a pixel.

local Screen = {}

Screen.CROP = 0.1

-- How to draw a vw x vh view on a w x h screen: scale k, then offset x, y
function Screen.fit(w, h, vw, vh)
    local contain = math.min(w / vw, h / vh)
    local cover = math.max(w / vw, h / vh)
    local k = math.min(cover, contain / (1 - Screen.CROP))
    return { k = k, x = math.floor((w - vw * k) / 2 + 0.5), y = math.floor((h - vh * k) / 2 + 0.5) }
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
