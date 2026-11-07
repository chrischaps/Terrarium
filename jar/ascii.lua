-- Terrarium: ascii (#97), the jar as glyphs on a character grid, a moth-eaten
-- roguelike of moss and creatures. It's a style (jar/styles.lua) that takes
-- three passes where the others take one:
--
--   1. cells: the frame averaged down to one texel a cell (a 4 x 4 grid of
--      taps in each), and beside it how the light runs across the cell and
--      how much it's the moss's green (shaders/styles/ascii_cells.glsl);
--   2. the eye: the frame's mean light in one texel, so a night jar opens up
--      as an eye does in the dark (shaders/styles/ascii_eye.glsl);
--   3. glyphs: every pixel of the target finds its cell, picks a glyph by the
--      cell's light, by its edge where one runs through it (| / - \), or
--      grass (, ") where it's moss, and inks it in the cell's colour
--      (shaders/styles/ascii.glsl).
--
-- The glyphs come from LÖVE's own font, baked into an atlas canvas at the
-- first frame of each cell size, so there's no font file in the repo. Each is
-- squeezed to its cell and centred in it, so the proportional font sits on a
-- monospaced grid, and its ink is measured off the atlas to order the ramp.
--
-- A cell is CELL view pixels (8 x 12 to begin with; [ and ] in play, or
-- --cell 6x9), but it's drawn at the target's own pixels: at 1080p the
-- 1280 x 800 frame is scaled 1.5, so the style draws a 1920 x 1200 canvas of
-- 12 x 18 cells and composite draws it a pixel to a pixel, and the glyphs
-- stay sharp. Below the frame's size (Easel's thumb) it draws at the frame's.
-- Drawing only, like every style: it sees pixels, never the World.

local Render = require('jar.render')

local Ascii = {}

-- The ramp, light to dark ink. It's sorted by the ink each glyph really lays
-- down once baked, so the order here is only a first guess. (No '-': in
-- LÖVE's font it's the second lightest, and the jar's dark back drew as
-- scanlines.)
Ascii.RAMP = { ' ', '.', ':', ';', '+', '=', '*', '#', '%', '@' }
-- The edges, by the way the light runs across the cell: across (the edge
-- stands up), down-right, down, down-left
Ascii.EDGES = { '|', '/', '-', '\\' }
-- Moss, as a roguelike's grass: a cell the moss's green (between the
-- families' hues, so no creature's skin is ever taken for it) is sparse
-- grass, then thick. The creatures keep the ramp, and stand out of it.
Ascii.GRASS = { ',', '"' }
-- The cell sizes [ and ] step through, in view pixels, about 2 tall to 3 wide
Ascii.SIZES = { { 4, 6 }, { 5, 8 }, { 6, 9 }, { 7, 11 }, { 8, 12 }, { 9, 14 }, { 10, 15 },
    { 12, 18 }, { 14, 21 }, { 16, 24 } }
Ascii.CELL = { 8, 12 }

local cell = { Ascii.CELL[1], Ascii.CELL[2] }

-- Cells of w x h view pixels (h half as tall again, if it's not given)
function Ascii.size(w, h)
    w = math.max(3, math.floor(tonumber(w) or Ascii.CELL[1]))
    h = math.max(4, math.floor(tonumber(h) or w * 1.5 + 0.5))
    cell[1], cell[2] = w, h
    return w, h
end

function Ascii.cell() return cell[1], cell[2] end

-- The next size up (dir 1) or down (-1) the ladder from the one in use
function Ascii.step(dir)
    local at = 1
    for i, s in ipairs(Ascii.SIZES) do
        if s[1] * s[2] <= cell[1] * cell[2] then at = i end
    end
    if dir < 0 and Ascii.SIZES[at][1] * Ascii.SIZES[at][2] < cell[1] * cell[2] then at = at + 1 end
    local s = Ascii.SIZES[math.max(1, math.min(#Ascii.SIZES, at + dir))]
    return Ascii.size(s[1], s[2])
end

function Ascii.label(name) return ('%s %d x %d'):format(name or 'ascii', cell[1], cell[2]) end

-- The glyph atlas for cw x ch target pixels: the ramp, the edges and the
-- grass in a row, one cell each, white ink on clear, and the ramp's slots in
-- it in order of the ink they lay down
local atlases = {}
local function atlas(cw, ch)
    local key = cw .. 'x' .. ch
    if atlases[key] then return atlases[key] end
    local glyphs = {}
    for _, list in ipairs({ Ascii.RAMP, Ascii.EDGES, Ascii.GRASS }) do
        for _, g in ipairs(list) do glyphs[#glyphs + 1] = g end
    end

    local font = love.graphics.newFont(math.max(4, ch), 'normal', 1)
    local wide = 1
    for _, g in ipairs(glyphs) do wide = math.max(wide, font:getWidth(g)) end
    local sx = math.min(1, (cw - 1) / wide)
    local y = math.floor((ch - font:getHeight()) / 2 + 0.5)

    local canvas = love.graphics.newCanvas(cw * #glyphs, ch, { dpiscale = 1 })
    canvas:setFilter('nearest', 'nearest')
    love.graphics.push('all')
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.clear(1, 1, 1, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font)
    for i, g in ipairs(glyphs) do
        local x0 = (i - 1) * cw
        love.graphics.setScissor(x0, 0, cw, ch)
        local gw = font:getWidth(g) * sx
        love.graphics.print(g, math.floor(x0 + (cw - gw) / 2 + 0.5), y, 0, sx, 1)
    end
    love.graphics.pop()

    -- The ink each glyph on the ramp lays down. A canvas that can't be read
    -- back keeps the ramp's own order.
    local ink = {}
    local ok, data = pcall(canvas.newImageData, canvas)
    for i = 1, #Ascii.RAMP do
        local sum = i
        if ok then
            sum = 0
            for py = 0, ch - 1 do
                for px = (i - 1) * cw, i * cw - 1 do
                    local _, _, _, a = data:getPixel(px, py)
                    sum = sum + a
                end
            end
        end
        ink[i] = sum
    end

    -- The ramp in order of its ink, the blank first, then the edges and the
    -- grass where they lie; each slot is a cell of the atlas
    local slots = {}
    for i = 1, #Ascii.RAMP do slots[i] = i end
    table.sort(slots, function(a, b)
        if ink[a] ~= ink[b] then return ink[a] < ink[b] end
        return a < b
    end)
    for i = #Ascii.RAMP + 1, #glyphs do slots[i] = i end
    for i = 1, #slots do slots[i] = slots[i] - 1 end
    atlases[key] = { canvas = canvas, slots = slots, count = #glyphs }
    return atlases[key]
end

local canvases = {}
local function canvas(name, w, h, format)
    local key = name .. w .. 'x' .. h
    if not canvases[key] then
        canvases[key] = love.graphics.newCanvas(w, h, { format = format, dpiscale = 1 })
        canvases[key]:setFilter('nearest', 'nearest')
    end
    return canvases[key]
end

-- ascii-each (after pencil-each, #95): each thing in the jar is laid into the
-- frame as it is, and marked on a map the frame's size of what's where: r its
-- kind (KIND, over 7), g its own seed (over 127), so the cells pass can tell
-- one thing from another and set each cell by the thing it holds. The map
-- starts afresh with each frame or plate (`begin`, from Styles.begin), and
-- what's left unmarked is the ground.
Ascii.KIND = { far = 1, soil = 2, prop = 3, moss = 4, creature = 5 }
local maps = {}

function Ascii.begin(target)
    if not target then return end
    local w, h = target:getDimensions()
    local key = 'map' .. w .. 'x' .. h
    maps[target] = canvas(key, w, h, 'rgba8')
    love.graphics.push('all')
    love.graphics.setCanvas(maps[target])
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.pop()
end

-- One thing (Styles.body): `alone` holds it, drawn on its own, and `quad`
-- cuts it out at x0, y0. It goes into the canvas being drawn into as it is,
-- and onto that canvas's map as `kind` with its `seed`.
function Ascii.lay(alone, quad, x0, y0, kind, seed)
    local map = maps[love.graphics.getCanvas()]
    local mark = Render.shader('styles/ascii_mark')
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader()
    love.graphics.setColorMask(true, true, true, false)
    love.graphics.setBlendMode('alpha', 'premultiplied')
    love.graphics.draw(alone, quad, x0, y0)
    if map and mark then
        love.graphics.setCanvas(map)
        love.graphics.setColorMask(true, true, true, true)
        love.graphics.setBlendMode('replace')
        love.graphics.setShader(mark)
        mark:send('kind', (Ascii.KIND[kind] or Ascii.KIND.creature) / 7)
        mark:send('seed', (seed or 0) % 127 / 127)
        love.graphics.draw(alone, quad, x0, y0)
    end
    love.graphics.pop()
end

-- The frame as ascii-each sets it: by its map, if it has one
function Ascii.draw_each(frame, time, kx, ky)
    return Ascii.draw(frame, time, kx, ky, maps[frame])
end

-- The frame as glyphs. `kx`, `ky` are how many of the target's pixels a pixel
-- of the frame will cover, and `map` what's where in it (ascii-each). Returns
-- the canvas and the scale to draw it at, or the frame itself at 1 if a
-- shader didn't load.
function Ascii.draw(frame, time, kx, ky, map)
    local glyphs = Render.shader('styles/ascii')
    local cells = Render.shader(map and 'styles/ascii_each_cells' or 'styles/ascii_cells')
    local eye = Render.shader('styles/ascii_eye')
    if not (glyphs and cells and eye) then return frame, 1, 1 end
    kx, ky = math.max(1, kx or 1), math.max(1, ky or 1)
    local w, h = frame:getDimensions()
    local ow, oh = math.floor(w * kx + 0.5), math.floor(h * ky + 0.5)
    local cw = math.max(3, math.floor(cell[1] * kx + 0.5))
    local ch = math.max(4, math.floor(cell[2] * ky + 0.5))
    local cols, rows = math.ceil(ow / cw), math.ceil(oh / ch)
    local a = atlas(cw, ch)

    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)

    -- 1. a texel a cell: its colour, and how its light runs
    local colour, edge = canvas('cells', cols, rows, 'rgba16f'), canvas('edges', cols, rows, 'rgba16f')
    love.graphics.setCanvas(colour, edge)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode('replace') -- (the second canvas's alpha is the grass, not cover)
    love.graphics.setShader(cells)
    cells:send('grid', { cols, rows })
    cells:send('span', { cw / ow, ch / oh })
    cells:send('frame', frame)
    if map then cells:send('map', map) end
    love.graphics.draw(frame, 0, 0, 0, cols / w, rows / h)

    -- 2. the eye: the frame's mean light, in one texel
    local mean = canvas('eye', 1, 1, 'rgba16f')
    love.graphics.setCanvas(mean)
    love.graphics.setShader(eye)
    eye:send('cells', colour)
    love.graphics.draw(frame, 0, 0, 0, 1 / w, 1 / h)

    -- 3. the glyphs, at the target's pixels
    local out = canvas('glyphs', ow, oh, 'rgba16f')
    out:setFilter('linear', 'linear') -- (drawn a pixel to a pixel, but Easel's thumb is smaller)
    love.graphics.setCanvas(out)
    love.graphics.setBlendMode('alpha')
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(glyphs)
    glyphs:send('eye', mean)
    glyphs:send('cells', colour)
    glyphs:send('edges', edge)
    glyphs:send('atlas', a.canvas)
    glyphs:send('grid', { cols, rows })
    glyphs:send('cellPx', { cw, ch })
    glyphs:send('outPx', { ow, oh })
    glyphs:send('glyphCount', a.count)
    glyphs:send('ramp', #Ascii.RAMP)
    glyphs:send('slot', unpack(a.slots))
    love.graphics.draw(frame, 0, 0, 0, ow / w, oh / h)
    love.graphics.pop()
    return out, w / ow, h / oh
end

return Ascii
