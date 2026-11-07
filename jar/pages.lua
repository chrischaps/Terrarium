-- Terrarium: the family book, drawn (#32). Closed, it's a small cloth-bound
-- book lying on the desk at the jar's right-hand corner, a red ribbon over its
-- edge, and a slip of paper in its pages when something has happened that you
-- haven't read. Click it and it opens over the jar: the first spread is its
-- title and what happened while you were away, and after that each creature
-- who has lived in the jar has a page of its own, in the order they came: a
-- portrait, its name, its parents and children, and how long it lived, all in
-- words. There are no numbers for genes; the portrait shows them.
--
-- Portraits come from the offscreen renderer (main.lua's `sit`, a plate of
-- the creature where it stands). Each sits once it comes, again at each moult,
-- and again now and then while it's awake, so the one kept after it has gone
-- is of its last waking days.
--
-- Like the lantern, it lives outside the World and only reads it; its clocks
-- are the frame's.

local C = require('jar.config')
local Tank = require('jar.tank')
local Render = require('jar.render')
local Book = require('book')

local Pages = {}
Pages.__index = Pages

-- The open book, in the view's pixels
local CX, CY = C.W / 2, 414
local PAGE_W, PAGE_H = 500, 620
local GUTTER = 6
-- Portraits: drawn into an oval this size on the page, rendered at twice it
Pages.PORTRAIT = {w = 232, h = 174}
local SITTING = 3      -- seconds between portraits, at the most
local REFRESH = 120    -- seconds before a living one's portrait is retaken
local PATIENCE = 40    -- seconds a newcomer waits to be in the clear before it sits anyway
local OPEN = 4         -- how quickly it opens and closes (per second)
local TURN = 0.55      -- seconds a page takes to turn
local AWAY_LINES = 13  -- what the while-you-were-away page holds before it says "and before that"

local INK = {0.20, 0.145, 0.10}
local RUBRIC = {0.46, 0.17, 0.11}
local FADED = {0.42, 0.36, 0.29}
local PAPER = {0.93, 0.885, 0.79}
local CLOTH = {0.16, 0.25, 0.17}
local GILT = {0.80, 0.64, 0.33}
local RIBBON = {0.58, 0.10, 0.09}

local KIND = {worm = 'a worm', blob = 'a blob', spider = 'a spider', springtail = 'a springtail', snail = 'a snail'}

local fonts = {}
local function font(face, size)
    local key = face .. size
    if not fonts[key] then
        local file = face == 'italic' and 'fonts/IMFeENit28P.ttf' or 'fonts/IMFeENrm28P.ttf'
        fonts[key] = love.graphics.newFont(file, size)
    end
    return fonts[key]
end

-- A page's paper: warm, with a grain and fibres, foxed toward its outer edge
-- and the head and foot, and toned toward the gutter. `side` is -1 for a left
-- page, 1 for a right. Baked once; noise is no draw from any stream.
local function bakePaper(side)
    local w, h = PAGE_W, PAGE_H
    local data = love.image.newImageData(w, h)
    local ox = side < 0 and 0 or 37.7
    data:mapPixel(function(x, y)
        local u, v = x / w, y / h
        local outer = side < 0 and 1 - u or u -- 1 at the fore-edge
        local grain = love.math.noise(x * 0.9 + ox, y * 0.9) - 0.5
        local fibre = love.math.noise(x * 0.04 + ox, y * 0.6) - 0.5
        local cloud = love.math.noise(x * 0.008 + ox, y * 0.008)
        local edge = math.max(0, outer - 0.82) / 0.18 + math.max(0, math.abs(v - 0.5) - 0.42) / 0.08
        local fox = love.math.noise(x * 0.05 + 91 + ox, y * 0.05) * edge
        local spot = love.math.noise(x * 0.11 + 13 + ox, y * 0.11 + 7)
        local dark = 0.035 * grain + 0.02 * fibre + 0.05 * (cloud - 0.5) + 0.07 * fox * fox
            + (spot > 0.86 and (spot - 0.86) * 0.9 * edge or 0)
        local inner = 1 - outer
        dark = dark + 0.05 * math.max(0, inner - 0.9) / 0.1
        return PAPER[1] - dark, PAPER[2] - dark * 1.15, PAPER[3] - dark * 1.5, 1
    end)
    return love.graphics.newImage(data)
end

function Pages.new(book)
    local self = setmetatable({}, Pages)
    self.book = book
    self.shown = 0         -- 0 closed, 1 open
    self.open = false
    self.spread = 1
    self.portraits = {}    -- entry number -> canvas
    self.sat = {}          -- entry number -> the frame clock when it last sat
    self.queue = {}        -- entry numbers waiting to sit, oldest first
    self.clock, self.last_sitting = 0, -math.huge
    self.links = {}
    self.away = {}
    for _, e in ipairs(book.entries) do self.queue[#self.queue + 1] = {n = e.n, at = 0} end
    book.world.events:on(function(ev) self:hear(ev) end)
    return self
end

function Pages:hear(ev)
    if ev.kind == 'hatched' or ev.kind == 'moulted' then
        local e = self.book:entry_of(ev.who)
        if e then self.queue[#self.queue + 1] = {n = e.n, at = self.clock} end
    end
end

-- Is creature `c` in the clear, with nobody in front of it or crowding it,
-- so that its portrait is of it?
local function clear(world, c)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(c:interp_points()) do
        x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
    end
    local pad = 0.35 * math.max(x1 - x0, y1 - y0) + 12
    for _, o in ipairs(world.creatures) do
        if o ~= c then
            for _, p in ipairs(o:interp_points()) do
                if p.x > x0 - pad and p.x < x1 + pad and p.y > y0 - pad and p.y < y1 + pad then return false end
            end
        end
    end
    return true
end

-- Who sits for a portrait now, if anyone: the first waiting who is in the
-- clear (or has waited PATIENCE), else the living one whose portrait is
-- oldest, if it's due, awake and in the clear. One every SITTING, unless
-- `now` (a capture script takes everyone due at once).
function Pages:sitting(now)
    if not now and self.clock - self.last_sitting < SITTING then return nil end
    local world = self.book.world
    local function ready(n)
        local c, i = self.book:creature(n)
        if not i or world.lives[i].dying then return nil end
        return c, i
    end
    for k, q in ipairs(self.queue) do
        local c = ready(q.n)
        if not c then
            table.remove(self.queue, k)
            return self:sitting(now)
        end
        if clear(world, c) or self.clock - q.at > PATIENCE then
            table.remove(self.queue, k)
            return q.n, c
        end
    end
    local best, best_at
    for n in pairs(self.book.alive) do
        local at = self.sat[n] or -math.huge
        local c, i = ready(n)
        if c and self.clock - at > REFRESH and world.minds[i].doing ~= 'rest' and (not best_at or at < best_at or (at == best_at and n < best))
            and clear(world, c) then
            best, best_at = n, at
        end
    end
    if best then return best, self.book.alive[best] end
end

-- Entry `n`'s portrait, just taken
function Pages:hang(n, canvas)
    self.portraits[n] = canvas
    self.sat[n] = self.clock
    self.last_sitting = self.clock
end

-- The spreads: the title and what happened while you were away, then two creatures a spread
function Pages:spreads()
    return 1 + math.ceil(#self.book.entries / 2)
end

function Pages:show(open)
    if open == self.open then return end
    self.open = open
    self.turn = nil
    if open then
        self.spread = 1
        self.away = self.book:since(self.book.seen)
    else
        self.book:close()
    end
end

function Pages:turn_to(spread)
    spread = math.max(1, math.min(self:spreads(), spread))
    if spread == self.spread or self.turn then return end
    self.turn = {from = self.spread, to = spread, t = 0}
    self.spread = spread
end

function Pages:update(dt)
    self.clock = self.clock + dt
    local target = self.open and 1 or 0
    if self.shown < target then self.shown = math.min(1, self.shown + OPEN * dt) end
    if self.shown > target then self.shown = math.max(0, self.shown - OPEN * dt) end
    if self.turn then
        self.turn.t = self.turn.t + dt / TURN
        if self.turn.t >= 1 then self.turn = nil end
    end
end

--------------------------------------------------------------------------------
-- The closed book on the desk
--------------------------------------------------------------------------------

local DESK_Y = Tank.wy(C.GLASS_B)
-- Its cover's corners, (world x, depth), far left round to near left
local COVER = {{1078, 1.07}, {1196, 1.04}, {1208, 1.30}, {1088, 1.33}}
local THICK = 9 -- world px, cover to cover

local function at(x, d, h)
    local sx, sy = Tank.project(x, DESK_Y - (h or 0), d)
    return sx, sy
end

local function lerp2(a, b, t) return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t end

-- Where the closed book is on the view, for a click: x0, y0, x1, y1
function Pages.closedRect()
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(COVER) do
        for _, h in ipairs({0, THICK}) do
            local x, y = at(p[1], p[2], h)
            x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
        end
    end
    return x0 - 14, y0 - 16, x1 + 14, y1 + 10
end

-- On the frame (#110) the desk is off the screen, so the book is found by its
-- ribbon, left hanging over the jar's foot at the screen's bottom edge.
-- `self.tab` is {x, y, k}: where on the view the ribbon meets that edge, and
-- the screen's scale, so it's the same size on any screen. Nil in a window.
-- (the frame's 7" panel is about 210 px to the inch, so the ribbon is some 6 mm
-- tall, and its touch room twice that)
local TAB = {w = 13, h = 54, notch = 9, lean = 5, x = 64} -- screen px

-- Where the ribbon is on the screen, from its bottom edge, for main.lua to place it
Pages.TAB_X = TAB.x

-- The ribbon's room for a fingertip, on the view: x0, y0, x1, y1
function Pages:tabRect()
    local t, s = self.tab, 1 / self.tab.k
    return t.x - 44 * s, t.y - 100 * s, t.x + 44 * s, t.y
end

function Pages:overClosed(vx, vy)
    local x0, y0, x1, y1
    if self.tab then x0, y0, x1, y1 = self:tabRect() else x0, y0, x1, y1 = Pages.closedRect() end
    return self.shown < 0.5 and vx >= x0 and vx <= x1 and vy >= y0 and vy <= y1
end

local function shade(c, k, a) love.graphics.setColor(c[1] * k[1], c[2] * k[2], c[3] * k[3], a or 1) end

-- Drawn into the scene, in front of the jar's glass, lit as the desk is
function Pages:drawClosed(light)
    local rm, l = light.room, light.lamp
    local k = {}
    for i = 1, 3 do k[i] = rm[i] * 0.85 + l[i] * 0.30 end
    if self.tab then
        self.tabLight = k -- (the ribbon is drawn over the glass, after it bends the view: drawTab)
        return
    end
    local function quad(a, b, c, d, h1, h2, h3, h4)
        local ax, ay = at(a[1], a[2], h1)
        local bx, by = at(b[1], b[2], h2)
        local cx, cy = at(c[1], c[2], h3)
        local dx, dy = at(d[1], d[2], h4)
        love.graphics.polygon('fill', ax, ay, bx, by, cx, cy, dx, dy)
    end
    local fl, fr, nr, nl = COVER[1], COVER[2], COVER[3], COVER[4]
    love.graphics.push('all')
    -- its shadow on the desk
    local sx, sy = at((fl[1] + nr[1]) / 2 + 6, (fl[2] + nr[2]) / 2 + 0.02)
    love.graphics.setColor(0, 0, 0, 0.30 + 0.25 * light.lamp_i)
    Render.drawBlob(sx, sy, 92, 16)
    -- the near edge: the back board, the page block, the front board
    shade(CLOTH, k)
    quad(nl, nr, nr, nl, 0, 0, THICK, THICK)
    shade(PAPER, k)
    quad(nl, nr, nr, nl, 1.6, 1.6, THICK - 1.6, THICK - 1.6)
    -- (the leaves' edges, a few fine lines)
    love.graphics.setLineWidth(0.6)
    for i = 1, 3 do
        local h = 1.6 + (THICK - 3.2) * i / 4
        local ax, ay = at(nl[1] + 3, nl[2], h)
        local bx, by = at(nr[1] - 2, nr[2], h)
        shade({0.6, 0.55, 0.47}, k, 0.6)
        love.graphics.line(ax, ay, bx, by)
    end
    -- the spine, on the left, rounded toward us
    shade(CLOTH, k)
    quad(fl, nl, nl, fl, 0, 0, THICK, THICK)
    shade({CLOTH[1] * 0.7, CLOTH[2] * 0.7, CLOTH[3] * 0.7}, k)
    quad(fl, nl, nl, fl, 0, 0, THICK * 0.45, THICK * 0.45)
    -- the cover, a tooled gilt rule inset, and a sprig in the middle
    shade(CLOTH, {k[1] * 1.15, k[2] * 1.15, k[3] * 1.15})
    quad(fl, fr, nr, nl, THICK, THICK, THICK, THICK)
    local inset = {}
    for i, p in ipairs(COVER) do
        local o = COVER[(i + 1) % 4 + 1]
        inset[i] = {lerp2(p, o, 0.12)}
    end
    shade(GILT, k, 0.55)
    love.graphics.setLineWidth(0.8)
    local pts = {}
    for _, p in ipairs(inset) do
        local x, y = at(p[1], p[2], THICK)
        pts[#pts + 1] = x
        pts[#pts + 1] = y
    end
    love.graphics.polygon('line', pts)
    local mx, my = at((fl[1] + nr[1]) / 2, (fl[2] + nr[2]) / 2, THICK)
    love.graphics.ellipse('fill', mx, my, 5, 1.6)
    love.graphics.line(mx - 9, my + 0.5, mx + 9, my - 0.5)
    -- the ribbon, out of the pages and over the near edge onto the desk
    local rx = nl[1] + (nr[1] - nl[1]) * 0.62
    local d = nl[2] - 0.012
    local ribbon = {}
    for _, p in ipairs({{0, 0, THICK * 0.6}, {0.5, 0.004, 0}, {5, 0.08, 0}, {13, 0.16, 0}, {10, 0.24, 0}}) do
        local x, y = at(rx + p[1], d + p[2], p[3])
        ribbon[#ribbon + 1] = x
        ribbon[#ribbon + 1] = y
    end
    shade(RIBBON, k)
    love.graphics.setLineWidth(2.6)
    love.graphics.setLineJoin('bevel')
    love.graphics.line(love.math.newBezierCurve(ribbon):render(3))
    -- something you haven't read: a slip of paper between the leaves
    if self.book:news() then
        local sx0 = nl[1] + (nr[1] - nl[1]) * 0.22
        local slip = {{0, 0, THICK * 0.55}, {16, 0, THICK * 0.55}, {18, 0.15, THICK * 0.2}, {1, 0.16, THICK * 0.2}}
        local pts = {}
        for _, p in ipairs(slip) do
            local x, y = at(sx0 + p[1], d + p[2], p[3])
            pts[#pts + 1] = x
            pts[#pts + 1] = y
        end
        shade({0.98, 0.95, 0.87}, k)
        love.graphics.polygon('fill', pts)
        shade({0.5, 0.42, 0.33}, k, 0.5)
        love.graphics.setLineWidth(0.7)
        love.graphics.polygon('line', pts)
    end
    love.graphics.pop()
end

-- On the frame: the ribbon's swallowtail end, up over the jar's foot from the
-- book below the screen, and a slip of paper beside it when there's news. Lit
-- as the desk is, but never quite lost, so a finger can find it at night. In
-- the view's pixels, over the finished frame, since it's in front of the
-- glass and isn't bent by it; it hides while the book is open.
function Pages:drawTab()
    local k = self.tabLight
    if not (self.tab and k) or self.shown >= 1 then return end
    local t, s = self.tab, 1 / self.tab.k
    local lit = {}
    -- (darkened as the room's vignette darkens the screen's corner, composite.glsl)
    for i = 1, 3 do lit[i] = math.max(k[i], 0.55) * 0.62 * (1 - self.shown) end
    local x, y = t.x, t.y + 4 * s -- (from just under the edge)
    local hw, h, notch, lean = TAB.w / 2 * s, (TAB.h + 4) * s, TAB.notch * s, TAB.lean * s
    love.graphics.push('all')
    if self.book:news() then
        -- the slip, standing up out of the leaves behind the ribbon
        love.graphics.push()
        love.graphics.translate(x - 18 * s, y)
        love.graphics.rotate(-0.10)
        shade({0, 0, 0}, lit, 0.25)
        love.graphics.rectangle('fill', -9 * s, -38 * s, 22 * s, 38 * s)
        shade({0.98, 0.95, 0.87}, lit)
        love.graphics.rectangle('fill', -11 * s, -40 * s, 22 * s, 40 * s)
        shade({0.5, 0.42, 0.33}, lit, 0.5)
        love.graphics.setLineWidth(s)
        love.graphics.rectangle('line', -11 * s, -40 * s, 22 * s, 40 * s)
        love.graphics.pop()
    end
    -- its shadow on the glass, then the silk in two halves (each convex), the
    -- notch between them
    shade({0, 0, 0}, lit, 0.30)
    love.graphics.polygon('fill', x - hw + 2 * s, y, x + hw + 2 * s, y, x + hw + lean + 2 * s, y - h + 2 * s,
        x - hw + lean + 2 * s, y - h + 2 * s)
    shade(RIBBON, lit)
    love.graphics.polygon('fill', x - hw, y, x, y, x + lean, y - h + notch, x - hw + lean, y - h)
    love.graphics.polygon('fill', x, y, x + hw, y, x + hw + lean, y - h, x + lean, y - h + notch)
    -- a sheen down the silk
    shade({RIBBON[1] * 1.7, RIBBON[2] * 2.2, RIBBON[3] * 2.2}, lit, 0.55)
    love.graphics.setLineWidth(1.6 * s)
    love.graphics.line(x - hw * 0.4, y, x - hw * 0.4 + lean, y - h + notch * 0.5)
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- The open book
--------------------------------------------------------------------------------

local function ink(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- Text centred in [x, x + w], and how tall it came out
local function para(text, face, size, x, y, w, colour, align)
    local f = font(face, size)
    love.graphics.setFont(f)
    ink(colour)
    love.graphics.printf(text, x, y, w, align or 'center')
    local _, lines = f:getWrap(text, w)
    return #lines * f:getHeight() * f:getLineHeight()
end

-- A sprig, drawn in ink: a stem bowed a little, and leaflets along it either
-- side, growing outward from the middle and smaller toward the tips
local function sprig(x, y, size, colour, a)
    ink(colour, a)
    love.graphics.setLineWidth(1)
    local function stem(t) return x + t * size, y - (1 - t * t) * size * 0.07 end
    local pts = {}
    for i = -8, 8 do
        local sx, sy = stem(i / 8)
        pts[#pts + 1] = sx
        pts[#pts + 1] = sy
    end
    love.graphics.line(pts)
    for i = -7, 7 do
        if i ~= 0 then
            local t = i / 8
            local sx, sy = stem(t)
            local s = size * 0.2 * (1 - math.abs(t) * 0.55)
            local out = t < 0 and math.pi or 0
            local side = i % 2 == 0 and 1 or -1
            local angle = out + side * (t < 0 and -0.75 or 0.75)
            love.graphics.push()
            love.graphics.translate(sx, sy)
            love.graphics.rotate(angle)
            love.graphics.ellipse('fill', s * 0.55, 0, s * 0.6, s * 0.17)
            love.graphics.pop()
        end
    end
    love.graphics.circle('fill', x, y - size * 0.07, 1.6)
end

-- The jar's whole family in a sentence or two, in words
local function census(book)
    local founders, hatched, gone = 0, 0, 0
    for _, e in ipairs(book.entries) do
        if e.founder then founders = founders + 1 else hatched = hatched + 1 end
        if e.gone then gone = gone + 1 end
    end
    local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end
    local out = cap(Book.words(founders)) .. ' came with the jar.'
    if hatched > 0 or gone > 0 then
        local parts = {}
        if hatched > 0 then parts[#parts + 1] = Book.words(hatched) .. (hatched == 1 and ' has hatched' or ' have hatched') end
        if gone > 0 then parts[#parts + 1] = Book.words(gone) .. (gone == 1 and ' has' or ' have') .. ' gone back to the moss' end
        out = out .. ' Since then ' .. table.concat(parts, ', and ') .. '.'
    end
    local living = book:living()
    out = out .. ' ' .. cap(Book.words(living)) .. (living == 1 and ' lives' or ' live') .. ' here now.'
    return out
end

function Pages:drawTitle(x, y)
    local w = PAGE_W - 120
    x = x + 60
    para('The Family Book', 'roman', 46, x, y + 150, w, INK)
    sprig(x + w / 2, y + 222, 26, FADED, 0.9)
    para(census(self.book), 'italic', 23, x + 10, y + 262, w - 20, INK)
    para('These pages remember everyone\nwho has lived in the jar.', 'italic', 19, x, y + PAGE_H - 150, w, FADED)
end

-- One thing that happened, as a line in the book, and who it's about
local function happened(book, h)
    if h.kind == 'born' then
        local e = h.entry
        local ps = {}
        for _, p in ipairs(e.parents or {}) do ps[#ps + 1] = Book.named(book.entries[p]) end
        return string.format('%s hatched, %s%s.', Book.named(e), KIND[e.key] or e.key,
            #ps > 0 and ', to ' .. Book.list(ps) or ''), e.n
    elseif h.kind == 'gone' then
        local e = h.entry
        return string.format('%s went back to the moss, after %s.', Book.named(e), Book.days(book:lived(e))), e.n
    else
        local k = h.clutch
        local a, b = book.entries[k.parents[1]], book.entries[k.parents[2]]
        return string.format('%s and %s laid %s in the moss.', Book.named(a), Book.named(b),
            k.count == 1 and 'an egg' or Book.words(k.count) .. ' eggs'), a.n
    end
end

function Pages:drawAway(x, y, links)
    local book = self.book
    local w = PAGE_W - 116
    x = x + 52
    local yy = y + 64
    yy = yy + para('While you were away', 'roman', 34, x, yy, w, RUBRIC)
    yy = yy + 18
    local away = self.away
    if #away == 0 then
        para('Nothing has changed since you last looked. Everyone is as you left them.', 'italic', 21,
            x + 16, yy + 30, w - 32, FADED)
        return
    end
    local first = math.max(1, #away - AWAY_LINES + 1)
    if first > 1 then
        local births, gone = 0, 0
        for k = 1, first - 1 do
            if away[k].kind == 'born' then births = births + 1 elseif away[k].kind == 'gone' then gone = gone + 1 end
        end
        local parts = {}
        if births > 0 then parts[#parts + 1] = Book.words(births) .. ' hatched' end
        if gone > 0 then parts[#parts + 1] = Book.words(gone) .. ' went back to the moss' end
        if #parts > 0 then
            yy = yy + para('Before this, ' .. table.concat(parts, ' and ') .. '. Their pages tell it.',
                'italic', 18, x, yy, w, FADED, 'left') + 8
        end
    end
    local day
    for k = first, #away do
        local h = away[k]
        local d = book:day_of(h.at)
        if d ~= day then
            day = d
            yy = yy + 8
            yy = yy + para('On the ' .. Book.ordinal(d) .. ' day', 'italic', 19, x, yy, w, RUBRIC, 'left') + 2
        end
        local text, n = happened(book, h)
        local f = font('roman', 20)
        local _, lines = f:getWrap(text, w - 18)
        local hgt = #lines * f:getHeight() * f:getLineHeight()
        if self.hover and self.hover.n == n and self.hover.y == yy then
            love.graphics.setColor(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.07)
            love.graphics.rectangle('fill', x + 6, yy - 1, w - 6, hgt + 2, 4)
        end
        para(text, 'roman', 20, x + 18, yy, w - 18, h.kind == 'gone' and FADED or INK, 'left')
        links[#links + 1] = {x = x, y = yy, w = w, h = hgt, n = n}
        yy = yy + hgt + 4
        if yy > y + PAGE_H - 70 then break end
    end
end

-- A portrait in its oval, with a fine ink rule round it
function Pages:drawPortrait(n, x, y, faded)
    local P = Pages.PORTRAIT
    local cx, cy = x + P.w / 2, y + P.h / 2
    local canvas = self.portraits[n]
    love.graphics.setColor(0, 0, 0, 0.10)
    love.graphics.ellipse('fill', cx + 2, cy + 3, P.w / 2 + 4, P.h / 2 + 4)
    if canvas then
        love.graphics.stencil(function() love.graphics.ellipse('fill', cx, cy, P.w / 2, P.h / 2, 64) end, 'replace', 1)
        love.graphics.setStencilTest('greater', 0)
        love.graphics.setColor(1, 0.97, 0.90, 1)
        local cw, ch = canvas:getDimensions()
        love.graphics.draw(canvas, x, y, 0, P.w / cw, P.h / ch)
        -- the gone are a little faded, as old pictures are
        if faded then
            love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], 0.28)
            love.graphics.rectangle('fill', x, y, P.w, P.h)
        end
        love.graphics.setStencilTest()
    else
        love.graphics.setColor(PAPER[1] * 0.94, PAPER[2] * 0.94, PAPER[3] * 0.94, 1)
        love.graphics.ellipse('fill', cx, cy, P.w / 2, P.h / 2, 64)
    end
    ink(INK, 0.75)
    love.graphics.setLineWidth(1.2)
    love.graphics.ellipse('line', cx, cy, P.w / 2, P.h / 2, 64)
    ink(INK, 0.35)
    love.graphics.setLineWidth(0.7)
    love.graphics.ellipse('line', cx, cy, P.w / 2 + 5, P.h / 2 + 5, 64)
end

-- Words that wrap, some of them names you can click to turn to their page:
-- `segs` is a list of {text, n}, where `n` is a page's entry. Centred in
-- [x, x + w]; returns how tall it came out.
local function flow(segs, face, size, x, y, w, colour, links, hover)
    local f = font(face, size)
    -- (a line breaks only after a space, and never inside a name)
    local words, word = {}, {}
    for _, s in ipairs(segs) do
        if s.n then
            word[#word + 1] = {text = s.text, n = s.n}
        else
            for piece in s.text:gmatch('[^%s]*%s*') do
                if piece ~= '' then
                    word[#word + 1] = {text = piece}
                    if piece:find('%s$') then words[#words + 1], word = word, {} end
                end
            end
        end
    end
    if #word > 0 then words[#words + 1] = word end
    local lines, line, lw = {}, {}, 0
    for _, wd in ipairs(words) do
        local ww = 0
        for _, p in ipairs(wd) do ww = ww + f:getWidth(p.text) end
        if #line > 0 and lw + ww - f:getWidth(' ') > w then
            lines[#lines + 1], line, lw = line, {}, 0
        end
        for _, p in ipairs(wd) do line[#line + 1] = p end
        lw = lw + ww
    end
    if #line > 0 then lines[#lines + 1] = line end
    love.graphics.setFont(f)
    local lh = f:getHeight() * f:getLineHeight()
    for k, ln in ipairs(lines) do
        local total = 0
        for _, p in ipairs(ln) do total = total + f:getWidth(p.text) end
        local last = ln[#ln].text
        total = total - f:getWidth(last) + f:getWidth((last:gsub('%s+$', '')))
        local px, py = x + (w - total) / 2, y + (k - 1) * lh
        for _, p in ipairs(ln) do
            if p.n then
                local tw = f:getWidth((p.text:gsub('%s+$', '')))
                ink(RUBRIC)
                love.graphics.print(p.text, px, py)
                ink(RUBRIC, hover and hover.n == p.n and hover.y == py and 0.8 or 0.25)
                love.graphics.setLineWidth(1)
                love.graphics.line(px, py + f:getBaseline() + 3, px + tw, py + f:getBaseline() + 3)
                links[#links + 1] = {x = px - 3, y = py, w = tw + 6, h = lh, n = p.n}
            else
                ink(colour)
                love.graphics.print(p.text, px, py)
            end
            px = px + f:getWidth(p.text)
        end
    end
    return #lines * lh
end

-- What the book says of entry `e`: lines of {text, n}, for flow
function Pages:lines(e)
    local book, world = self.book, self.book.world
    local out = {}
    local function names(ns, before, after)
        local segs = {{text = before}}
        for k, n in ipairs(ns) do
            if k > 1 then segs[#segs + 1] = {text = k == #ns and ' and ' or ', '} end
            segs[#segs + 1] = {text = Book.named(book.entries[n]), n = n}
        end
        segs[#segs + 1] = {text = after}
        return segs
    end
    if e.parents then out[#out + 1] = names(e.parents, 'Child of ', '.') end
    if e.named_for then out[#out + 1] = names({e.named_for}, 'Named for ', ', who went before.') end
    if #e.children > 0 then
        out[#out + 1] = names(e.children, 'Parent of ', '.')
    elseif e.gone then
        out[#out + 1] = {{text = 'Left no children, but the moss grew rich where it lay.'}}
    else
        out[#out + 1] = {{text = 'No children yet.'}}
    end
    local lived = Book.days(book:lived(e))
    if e.gone then
        out[#out + 1] = {{text = string.format('Lived %s, and went back to the moss on the %s day.', lived,
            Book.ordinal(book:day_of(e.gone)))}}
    else
        local _, i = book:creature(e.n)
        local how = ''
        if i then
            if world.lives[i].dying then
                how = ', and is fading into the moss'
            elseif world.young[i] then
                how = ', and is still growing'
            else
                local _, old = world:age_of(i)
                if old > 0 then how = ', and is growing old' end
            end
        end
        out[#out + 1] = {{text = 'Has lived ' .. lived .. how .. '.'}}
        if i and world.minds[i].doing == 'rest' and not world.lives[i].dying then
            out[#out + 1] = {{text = 'Asleep now.'}}
        end
    end
    return out
end

function Pages:drawCreature(n, x, y, links)
    local e = self.book.entries[n]
    if not e then return end
    local w = PAGE_W - 110
    local cx = x + 55
    local P = Pages.PORTRAIT
    self:drawPortrait(n, x + (PAGE_W - P.w) / 2, y + 56, e.gone)
    local yy = y + 56 + P.h + 22
    yy = yy + para(Book.named(e), 'roman', 38, cx, yy, w, e.gone and FADED or INK)
    local came = e.founder and 'who came with the jar' or ('hatched on the ' .. Book.ordinal(self.book:day_of(e.came)) .. ' day')
    yy = yy + para((KIND[e.key] or e.key) .. ', ' .. came, 'italic', 21, cx, yy, w, FADED)
    sprig(x + PAGE_W / 2, yy + 16, 18, FADED, 0.7)
    yy = yy + 36
    -- (parents and children are names to click, and turn to their own pages)
    for _, line in ipairs(self:lines(e)) do
        yy = yy + flow(line, 'roman', 21, cx + 6, yy, w - 12, INK, links, self.hover) + 6
    end
    para(Book.words(n + 2), 'italic', 16, x, y + PAGE_H - 46, PAGE_W, FADED)
end


-- What's on one side of spread `s`: 'title', 'away', or an entry number
local function side(s, right)
    if s == 1 then return right and 'away' or 'title' end
    return 2 * (s - 2) + (right and 2 or 1)
end

function Pages:drawPage(what, x, y, links)
    if what == 'title' then self:drawTitle(x, y)
    elseif what == 'away' then self:drawAway(x, y, links)
    else self:drawCreature(what, x, y, links) end
end

function Pages:drawSheet(paper, x, y, what, links, k)
    love.graphics.setColor(k, k, k, 1)
    love.graphics.draw(paper, x, y)
    self:drawPage(what, x, y, links)
end

-- The open book over the jar, in the view's pixels
function Pages:draw()
    if self.shown <= 0 then return end
    self.paper = self.paper or {bakePaper(-1), bakePaper(1)}
    local ease = self.shown * self.shown * (3 - 2 * self.shown)
    love.graphics.push('all')
    -- the jar behind goes quiet
    love.graphics.setColor(0.02, 0.015, 0.01, 0.55 * ease)
    love.graphics.rectangle('fill', -20, -20, C.W + 40, C.H + 40)
    love.graphics.translate(0, (1 - ease) * 40)
    local lx, rx, top = CX - PAGE_W - GUTTER / 2, CX + GUTTER / 2, CY - PAGE_H / 2
    local alpha = ease
    -- the boards, and the edges of the leaves beneath these
    love.graphics.setColor(0, 0, 0, 0.35 * alpha)
    Render.drawBlob(CX, top + PAGE_H + 16, PAGE_W * 1.15, 40)
    love.graphics.setColor(CLOTH[1] * 0.8, CLOTH[2] * 0.8, CLOTH[3] * 0.8, alpha)
    love.graphics.rectangle('fill', lx - 16, top - 12, 2 * PAGE_W + GUTTER + 32, PAGE_H + 26, 8)
    for i = 3, 1, -1 do
        local k = 0.80 - i * 0.05
        love.graphics.setColor(PAPER[1] * k, PAPER[2] * k, PAPER[3] * k, alpha)
        love.graphics.rectangle('fill', lx - 3 * i, top - 1 + i, 2 * PAGE_W + GUTTER + 6 * i, PAGE_H + i)
    end
    -- (a canvas would fade the whole spread together; opening is quick enough that
    -- the pages come in at full strength behind the veil)
    local links = {}
    local s, t = self.spread, self.turn
    if not t then
        self:drawSheet(self.paper[1], lx, top, side(s, false), links, 1)
        self:drawSheet(self.paper[2], rx, top, side(s, true), links, 1)
    else
        -- A leaf turning over: forward, the old right page folds in to the
        -- gutter and the new left page unfolds from it; back, the other way
        local fwd = t.to > t.from
        local u = t.t * t.t * (3 - 2 * t.t)
        local under_l = fwd and side(t.from, false) or side(t.to, false)
        local under_r = fwd and side(t.to, true) or side(t.from, true)
        self:drawSheet(self.paper[1], lx, top, under_l, {}, 1)
        self:drawSheet(self.paper[2], rx, top, under_r, {}, 1)
        local first = u < 0.5
        local squeeze = math.abs(math.cos(math.pi * u))
        local on_right = (fwd and first) or (not fwd and not first)
        local what
        if fwd then what = first and side(t.from, true) or side(t.to, false)
        else what = first and side(t.from, false) or side(t.to, true) end
        -- (squeezed toward the gutter, so it's edge-on halfway over)
        love.graphics.push()
        love.graphics.translate(CX, 0)
        love.graphics.scale(squeeze, 1)
        love.graphics.translate(-CX, 0)
        local dim = 1 - 0.25 * (1 - squeeze)
        if on_right then
            self:drawSheet(self.paper[2], rx, top, what, {}, dim)
        else
            self:drawSheet(self.paper[1], lx, top, what, {}, dim)
        end
        love.graphics.pop()
        love.graphics.setColor(0, 0, 0, 0.18 * (1 - squeeze))
        love.graphics.rectangle('fill', on_right and rx or CX - (CX - lx) * squeeze, top,
            PAGE_W * squeeze, PAGE_H)
    end
    -- the gutter's shadow, where the pages curve into the spine
    for i = 0, 11 do
        love.graphics.setColor(0.25, 0.18, 0.10, 0.045 * (12 - i) / 12)
        love.graphics.rectangle('fill', CX - GUTTER / 2 - 2 * i - 2, top, 4 * i + 4 + GUTTER, PAGE_H)
    end
    -- the corners you can turn by
    local more, less = s < self:spreads(), s > 1
    for _, corner in ipairs({{more, rx + PAGE_W, 1}, {less, lx, -1}}) do
        if corner[1] then
            local ex, ey, dir = corner[2], top + PAGE_H, corner[3]
            love.graphics.setColor(PAPER[1] * 0.80, PAPER[2] * 0.78, PAPER[3] * 0.72, alpha)
            love.graphics.polygon('fill', ex, ey - 26, ex - dir * 26, ey, ex - dir * 26, ey - 26)
            love.graphics.setColor(0, 0, 0, 0.12 * alpha)
            love.graphics.line(ex, ey - 26, ex - dir * 26, ey)
        end
    end
    love.graphics.pop()
    self.links = t and {} or links
    self.layout = {lx = lx, rx = rx, top = top}
end

--------------------------------------------------------------------------------
-- Hands on it
--------------------------------------------------------------------------------

-- Which spread entry `n`'s page is on
local function spread_of(n) return 2 + math.floor((n - 1) / 2) end

-- A click or tap at (vx, vy) on the view. Returns true if the book took it.
function Pages:press(vx, vy)
    if not self.open then
        if self:overClosed(vx, vy) then
            self:show(true)
            return true
        end
        return false
    end
    if self.shown < 0.6 then return true end
    local L = self.layout
    if not L or vy < L.top - 16 or vy > L.top + PAGE_H + 16 or vx < L.lx - 20 or vx > L.rx + PAGE_W + 20 then
        self:show(false)
        return true
    end
    for _, link in ipairs(self.links) do
        if link.x and vx >= link.x and vx <= link.x + link.w and vy >= link.y and vy <= link.y + link.h then
            self:turn_to(spread_of(link.n))
            return true
        end
    end
    if vx > CX then self:turn_to(self.spread + 1) else self:turn_to(self.spread - 1) end
    return true
end

-- The pointer at (vx, vy): is there something there to click?
function Pages:over(vx, vy)
    self.hover = nil
    if not self.open then return self:overClosed(vx, vy) end
    for _, link in ipairs(self.links) do
        if link.x and vx >= link.x and vx <= link.x + link.w and vy >= link.y and vy <= link.y + link.h then
            self.hover = link
            return true
        end
    end
    return true
end

function Pages:key(key)
    if not self.open then
        if key == 'b' then self:show(true) return true end
        return false
    end
    if key == 'escape' or key == 'b' then self:show(false)
    elseif key == 'right' or key == 'pagedown' or key == 'space' then self:turn_to(self.spread + 1)
    elseif key == 'left' or key == 'pageup' then self:turn_to(self.spread - 1)
    elseif key == 'home' then self:turn_to(1)
    elseif key == 'end' then self:turn_to(self:spreads())
    else return false -- (the jar's own keys, m and tab, still work with it open)
    end
    return true
end

return Pages
