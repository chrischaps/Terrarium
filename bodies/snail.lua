-- Snail: a slow climber that carries its house (#77).
--
-- A flat foot of verlet points rides whatever it's on, floor, glass or the
-- underside of a ledge, along the surface's normal: ahead of the anchor each
-- point finds the surface for itself (bodies/climb.lua's Climb.along), and
-- behind it each follows the track the anchor has laid, so the foot wraps a
-- corner the way it went round it. Waves run forward along the sole as it
-- goes, and the shell on its back rocks a little with each one. Two eye stalks
-- reach up from its head and two short feelers below them; the stalks pull in
-- when something comes near and slowly reach out again.
--
-- The shell is a logarithmic spiral of `whorls` turns, seen side-on: few
-- whorls are a loose, flaring coil, many a tight, rounded one. Its markings
-- are its pattern: honey flames across the whorls (banded), one band along
-- them (striped), a row of spots (spotted), or the inner whorls in the honey
-- colour (capped).
--
-- It's a climber with nowhere to leap to (its profile `climbs` and doesn't
-- `leap`), so it gets about on the spider's surface graph and the
-- controller's climber branch (bodies/climb.lua), only slowly. `size` sets
-- how big it is and how fast it goes (graphs in Snail.BUCKETS stretches of
-- it, each built for the biggest's clearance and the smallest's span), and a
-- hatchling's shell has fewer whorls than it will grow.
--
-- It lays a ribbon of slime from its anchor (`slime`, drawing only: statehash
-- skips it), wet and shining in the lamp's pool and faintly holding the night
-- glow, that dries over a few minutes.
--
-- Asleep it seals itself into its shell where it lies, on the glass or under
-- a ledge (Snail.rest, mind.lua's beds), behind a pale film over the opening.
-- Courting (#22), a pair turn to each other and reach out until the fronts of
-- their feet meet, then rear up and sway together, feelers touching on the
-- beat. When it dies the body goes back to the moss, but the shell stays
-- (Snail.keeps, World.KEPT) while the moss grows over it.
--
-- Coloured from its genes (#15, #75): a shell of dark amber to bronze and a
-- grey-fawn foot. A hatchling is small and pale.

local sq = require('core.fmath').sq -- Terrarium: x ^ 2 isn't one number in LuaJIT (#94)
local Base = require('bodies.base')
local Climb = require('bodies.climb')
local Skin = require('bodies.skin')
local Genome = require('genome')
local DayCycle = require('jar.daycycle')

local Snail = {}
Snail.__index = Snail

local sqrt, sin, cos, abs, min, max, pi, atan2, exp, log = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max,
    math.pi, math.atan2, math.exp, math.log
local floor = math.floor
local TAU = 2 * pi

-- A climber on any surface, with no leaps: no ballistic edges in its graph, so
-- it never needs its mover's jump (but every body carries one, #73)
Snail.profile = {
    name = 'snail',
    radius = 11, height = 22, step = 8,
    walk_speed = 26, walk_accel = 200,
    jump_vx = 0, jump_vy = 0, air_accel = 0,
    anticipation = 0.2,
    climbs = true, leaps = false,
    crawl_speed = 26,
    size = 1, span = 13,
}

-- One profile per size, so snails of a size share it
local profiles = {}
Snail.profiles = profiles -- (a cache: the book, #30, puts it back as it was)
function Snail.profile_for(size)
    if size == 1 then return Snail.profile end
    local p = profiles[size]
    if p then return p end
    local b = Snail.profile
    p = {}
    for k, v in pairs(b) do p[k] = v end
    p.size = size
    p.radius, p.height, p.span = b.radius * size, b.height * size, b.span * size
    p.crawl_speed = b.crawl_speed * size ^ 0.5 -- a longer foot, a longer wave
    p.walk_speed = p.crawl_speed
    profiles[size] = p
    return p
end

-- The profile a snail's graph is built from (#16): sizes in BUCKETS stretches,
-- each built for the biggest's clearance (the most it needs to fit) and the
-- smallest's span (the least gap it can bridge)
Snail.BUCKETS = 8
Snail.BUCKET_GENE = 'size'
local navs = {}
Snail.navs = navs -- (so does this one)
function Snail.nav_profile(genome)
    local k, lo, hi = Genome.bucket('snail', 'size', genome and genome.size or 1, Snail.BUCKETS)
    if navs[k] then return navs[k] end
    local p = {}
    for key, v in pairs(Snail.profile_for(lo)) do p[key] = v end
    p.radius, p.min_radius = Snail.profile_for(hi).radius, p.radius
    p.size, p.sizes, p.bucket = nil, {lo, hi}, k
    p.bucket_label = string.format('sizes %.3f-%.3f', lo, hi)
    navs[k] = p
    return p
end

-- A slow body burns slowly: hunger rises at this much of the others' rate
-- (mind.lua), or a snail would spend its whole day crawling to dinner and
-- never be fed enough, at the same time as another, to court
Snail.APPETITE = 0.25

-- How big its body is at size 1, against the numbers below (it's drawn and
-- built `k` = size * BODY big, so it reads at the jar's scale beside a spider)
local BODY = 1.35

-- The foot, at k = 1: FOOT points, the first its head, HEAD ahead of the
-- anchor and SEG apart, each THICK high over the sole (its hump under the shell)
local FOOT = 9
local HEAD, SEG = 12, 3.2
local THICK = {4.0, 4.1, 4.4, 4.8, 5.0, 4.6, 3.6, 2.4, 1.2}
local LIFT = 0.6        -- how far the sole rides off the surface
local TRACK_GAP = 1.5   -- the anchor's track is a point this far apart
local WAVE = 9          -- length of a wave along the sole
local SHELL_R = 8       -- the shell's outer radius
local SHELL_AT = -3     -- its centre, along the foot from the anchor
local APEX = 0.07       -- the spiral's innermost radius, of its outermost
local AWAKE_AP = 1.25   -- the opening's angle in the body's frame (forward, then down)
local STALK = 7         -- the eye stalks' length
local FEELER = 2.8
local STARTLE = {r = 30, from = 10, hold = 2.5} -- within r * size + from, it pulls its eyes in, for `hold` s
local CREEP = 4         -- seconds courting before their feet have met
local SWAY_BEAT = 1.5   -- seconds of a courting sway (#22)
Snail.SWAY_BEAT = SWAY_BEAT -- (each is heard, core/synth.lua)
local SLIME_GAP = 4     -- a slime point this far apart
local DRY = 240         -- seconds a ribbon of slime takes to dry
local WET = 70          -- and of those, how long it still shines

local SLIME = {0.86, 0.9, 0.92}
local EYE = {0.12, 0.09, 0.07}

-- The parts of a snail its genes make. `young` (0..1) is how pale it is (#23);
-- a hatchling's genome is small (Genome.young), so it's small with few whorls.
function Snail:take(genome, young)
    if genome then Genome.clamp(genome) end
    local size = genome and genome.size or 1
    self.genome = genome
    self.size = size
    self.whorls = genome and genome.whorls or 3.25
    self.profile = Snail.profile_for(size)
    self.nav = Snail.nav_profile(genome)
    self.k = size * BODY
    self.court_gap = 12 * self.k + 2 -- its half of the gap to a partner (#22)
    self.skin = Skin.of('snail', genome, young)
    self.skin.eye = EYE
    self.color_name = self.skin.name
end

function Snail.new(x, y, world, genome, young)
    local self = setmetatable({}, Snail)
    self:take(genome, young)
    self.world = world
    self.a = {x = x, y = y}       -- anchor on the surface
    self.nx, self.ny = 0, -1      -- smoothed surface normal
    self.tnx, self.tny = 0, -1    -- target normal
    self.facing = 1
    self.turn = 1                 -- the shell turning round to its facing, -1..1
    self.mode = 'attached'
    self.mover = Base.Mover.new(x, y, self.profile)
    self.solid = nil
    self.face = Base.Face.new()
    self.clock = 0
    self.speed, self.pace, self.crawled, self.gait = 0, 0, false, 1
    self.wave = 0                 -- how far its pedal waves have run, in waves
    self.retract = 0              -- 0 out, 1 sealed in its shell
    self.stalks = 1               -- how far its eye stalks reach
    self.startle, self.crowded = 0, false
    self.ardour, self.flush, self.lean, self.rear, self.touch, self.sway = 0, 0, 0, 0, 0, 0
    self.track = {}               -- where its anchor has been, newest first
    self.slime = {}               -- the ribbon it lays, oldest first
    self.foot = {}
    for k = 1, FOOT do self.foot[k] = {x = x, y = y, px = x, py = y} end
    self:plant_all()
    return self
end

-- Grow into `genome` where it lies (#23): a bigger foot and one more turn of
-- shell, set down again on the surface
function Snail:grow(genome, young)
    self:take(genome, young)
    self.mover.profile = self.profile
    self:plant_all()
end

function Snail:get_name() return "Snail" end
function Snail:get_description() return "A foot that rides any surface, under a coiled shell" end

function Snail:anchor() return self.a.x, self.a.y end

function Snail:interp_points()
    local pts = {self.a}
    for k = 1, FOOT do pts[#pts + 1] = self.foot[k] end
    return pts
end

function Snail:reset(x, y)
    self.a.x, self.a.y = x, y
    self.nx, self.ny, self.tnx, self.tny = 0, -1, 0, -1
    self.mode = 'attached'
    self.mover = Base.Mover.new(x, y, self.profile)
    self.gait, self.pace = 1, 0
    self:plant_all()
end

-- Its anchor brought down onto the surface under it: across a corner the
-- anchor cuts through the air, and its track and slime go round it instead
-- (and the normal of the surface it found there, not the one it's easing round)
function Snail:find_sole(level)
    local x, y, nx, ny = self.a.x, self.a.y, self.nx, self.ny
    local h, hx, hy
    -- (as its normal turns, the spot under it sweeps round the corner from one
    -- face to the next, so it reaches as far as a join between them is long)
    if level then h, hx, hy = level:raycast(x + nx * 2, y + ny * 2, -nx, -ny, 44) end
    if h then x, y, nx, ny = x + nx * (2 - h), y + ny * (2 - h), hx, hy end
    local sole = self.sole or {}
    sole.x, sole.y, sole.nx, sole.ny = x, y, nx, ny
    self.sole = sole
    return x, y
end

-- Where the k'th point of its foot is along it from the anchor (ahead > 0):
-- drawn in under its shell as it retracts, and reaching out courting
function Snail:reach_of(k)
    local s = self.k
    local d = (HEAD - (k - 1) * SEG) * s
    local c = SHELL_AT * s
    d = c + (d - c) * (1 - 0.5 * self.retract)
    return d + self.lean * max(0, 1 - (k - 1) / 4)
end

-- Where the k'th point of its foot wants to be: ahead of the anchor on the
-- surface it'll come to, behind it on the track it has laid. Turning round,
-- it draws its foot in under its shell and reaches it out the other way (by
-- `turn`, as its shell turns edge-on). Returns the point and the surface's
-- normal there.
function Snail:target(k, level)
    local s = self.k
    local sole = self.sole or {x = self.a.x, y = self.a.y, nx = self.nx, ny = self.ny}
    local nx, ny = sole.nx, sole.ny
    local tx, ty = -ny, nx -- (facing right)
    local d = self:reach_of(k) * self.turn
    local x, y
    if not level then
        x, y = self.a.x + tx * d, self.a.y + ty * d
    elseif d * self.facing >= 0 or #self.track == 0 then
        x, y, nx, ny = Climb.along(level, sole.x, sole.y, tx, ty, nx, ny, d, s)
    else
        -- back along the track, and past its end along the surface
        local left, px, py = abs(d), sole.x, sole.y
        local found = false
        for _, q in ipairs(self.track) do
            local seg = sqrt(sq(q.x - px) + sq(q.y - py))
            if seg >= left and seg > 1e-6 then
                local u = left / seg
                x, y = px + (q.x - px) * u, py + (q.y - py) * u
                nx, ny = q.nx, q.ny
                found = true
                break
            end
            left, px, py = left - seg, q.x, q.y
        end
        if not found then
            x, y, nx, ny = Climb.along(level, px, py, -ny, nx, nx, ny, left * (d < 0 and -1 or 1), s)
        end
    end
    local lift = LIFT * s
    -- (courting, its head rears up off the surface)
    if k <= 3 then lift = lift + self.rear * sq(1 - (k - 1) / 3) end
    return x + nx * lift, y + ny * lift, nx, ny
end

-- Set itself down where it is: no track behind it yet, every point of its
-- foot on its spot
function Snail:plant_all()
    self.track = {}
    self.mover.x, self.mover.y = self.a.x, self.a.y
    local level = self.world and self.world.level
    self:find_sole(level)
    for k, p in ipairs(self.foot) do
        local x, y = self:target(k, level)
        p.x, p.y, p.px, p.py = x, y, x, y
    end
end

function Snail:influencers(out)
    local cx, cy = self:shell_centre()
    out[#out + 1] = {x = cx, y = cy, r = 10 * self.k, vx = 0, vy = 0}
end

function Snail:light()
    local cx, cy = self:shell_centre()
    return cx, cy, 0, 0, 0, 0
end

Climb.into(Snail)

--------------------------------------------------------------------------------
-- The shell's geometry
--------------------------------------------------------------------------------

-- The spiral of `whorls` turns at unit size (its outermost radius 1), with
-- its opening along +x: r(θ) = e^(-b(Θ - θ)) at angle θ - Θ, so its apex is
-- APEX across. One turn in from any point is `q` times as far out, so the
-- shell scaled by q is all of it but its last whorl. Kept per whorls.
local spirals = {}
local function spiral(whorls)
    local sp = spirals[whorls]
    if sp then return sp end
    local T = whorls * TAU
    local b = -log(APEX) / T
    local q = exp(-b * TAU)
    sp = {whorls = whorls, b = b, q = q, T = T}
    -- (where on the shell a point θ of the coil is)
    function sp.at(theta, f)
        local r = exp(-b * (T - theta)) * (f or 1)
        local a = theta - T
        return r * cos(a), r * sin(a), r
    end
    -- its outline: the last whorl, from one turn in at the opening round to it
    local outline = {}
    local n = 72
    for i = 0, n do
        local x, y = sp.at(T - TAU + TAU * i / n)
        outline[#outline + 1], outline[#outline + 2] = x, y
    end
    sp.outline = outline
    -- the suture: the coil itself, from the apex out
    local suture = {}
    local steps = floor(whorls * 40)
    for i = 0, steps do
        local x, y = sp.at(T * i / steps)
        suture[#suture + 1], suture[#suture + 2] = x, y
    end
    sp.suture = suture
    spirals[whorls] = sp
    return sp
end
Snail.spiral = spiral

-- A fan mesh of a spiral's outline (white: drawing tints it), once per whorls
local meshes = {}
local function mesh_of(sp)
    local m = meshes[sp.whorls]
    if m then return m end
    local v = {{0, 0, 0, 0, 1, 1, 1, 1}}
    for i = 1, #sp.outline, 2 do v[#v + 1] = {sp.outline[i], sp.outline[i + 1], 0, 0, 1, 1, 1, 1} end
    m = love.graphics.newMesh(v, 'fan', 'static')
    meshes[sp.whorls] = m
    return m
end

local function set(c, a) love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

-- The shell `sk` of `whorls` turns, radius R, centred at (cx, cy): the body
-- frame turned by `angle` (its forward), mirrored by `turn` (-1..1, edge-on
-- at 0 as it turns round), its opening at `ap` radians round from forward.
-- `lx, ly` is the light's direction. `hollow` (0..1) is how empty it is: a
-- dark opening where the body was; `seal` (0..1) how far a pale film has
-- closed it. Returns its markings, in its own frame, and the frame (for the glow).
local function draw_shell(sk, whorls, R, cx, cy, angle, turn, ap, lx, ly, hollow, seal)
    local sp = spiral(whorls)
    local mesh = mesh_of(sp)
    local mx = turn >= 0 and max(0.18, turn) or min(-0.18, turn)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(angle)
    love.graphics.scale(mx * R, R)
    love.graphics.rotate(ap)
    -- the light, in the shell's own frame
    local c, s = cos(-(angle + ap)), sin(-(angle + ap))
    local llx, lly = (lx * c - ly * s) * (mx < 0 and -1 or 1), lx * s + ly * c
    local marks = {}

    set(sk.outline)
    love.graphics.draw(mesh, 0, 0, 0, 1 + 0.9 / R, 1 + 0.9 / R)
    set(sk.whorl)
    love.graphics.draw(mesh)
    -- the light along its back, and the shadow of each whorl under the next
    set(sk.whorl_hi, 0.55)
    love.graphics.draw(mesh, llx * 0.18, lly * 0.18, 0, 0.62, 0.62)
    set(sk.outline, 0.22)
    love.graphics.draw(mesh, -llx * 0.05, -lly * 0.05, 0, sp.q * 1.04, sp.q * 1.04)
    set(sk.whorl, 1)
    love.graphics.draw(mesh, 0, 0, 0, sp.q, sp.q)

    -- Markings
    local pattern = sk.pattern
    set(sk.mark, 0.85)
    if pattern == 'capped' then
        love.graphics.draw(mesh, 0, 0, 0, sp.q, sp.q)
        marks[#marks + 1] = {'halo', 0, 0, sp.q * 1.3}
    elseif pattern == 'banded' then
        -- honey flames across the last whorl and a half
        local w = 0.07
        love.graphics.setLineWidth(w)
        for k = 1, floor(1.5 * TAU / 0.55) do
            local th = sp.T - 0.25 - k * 0.55
            local x0, y0 = sp.at(th, sp.q * 1.05)
            local x1, y1 = sp.at(th + 0.22, 0.94)
            local mx_, my_ = sp.at(th + 0.08, (1 + sp.q) / 2)
            local pts = {x0, y0, mx_, my_, x1, y1}
            love.graphics.line(pts)
            marks[#marks + 1] = {'line', pts, w}
        end
    elseif pattern == 'striped' then
        -- one band along the coil, midway across each whorl
        local pts = {}
        local n = 60
        for i = 0, n do
            local x, y = sp.at(sp.T - 1.8 * TAU * (1 - i / n), (1 + sp.q) / 2)
            pts[#pts + 1], pts[#pts + 2] = x, y
        end
        love.graphics.setLineWidth(0.09)
        love.graphics.line(pts)
        marks[#marks + 1] = {'line', pts, 0.09}
    elseif pattern == 'spotted' then
        for k = 1, 9 do
            local th = sp.T - 0.35 - k * 0.62
            local x, y, r = sp.at(th, (1 + sp.q) / 2)
            local d = r * (1 - sp.q) * 0.16 * (0.85 + 0.3 * Skin.hash(sk.seed, k))
            love.graphics.circle('fill', x, y, d, 10)
            marks[#marks + 1] = {'disc', x, y, d}
        end
    end
    -- the coil and its growth lines
    set(sk.outline, 0.6)
    love.graphics.setLineWidth(0.05)
    love.graphics.line(sp.suture)
    set(sk.outline, 0.2)
    love.graphics.setLineWidth(0.03)
    for k = 1, 22 do
        local th = sp.T - k * 0.3
        local x0, y0 = sp.at(th, sp.q * 1.02)
        local x1, y1 = sp.at(th, 0.98)
        love.graphics.line(x0, y0, x1, y1)
    end
    -- the opening, seen edge-on: a pale lip round the dark inside, filled
    -- with its body while it lives
    local ox, orx, ory = (1 + sp.q) / 2, (1 - sp.q) * 0.52, (1 - sp.q) * 0.2 + 0.03
    set(sk.whorl_hi)
    love.graphics.ellipse('fill', ox, 0, orx + 0.05, ory + 0.04, 18)
    set(sk.outline, 0.9)
    love.graphics.ellipse('fill', ox, 0.01, orx * 0.9, ory * 0.8, 18)
    if hollow < 1 then
        set(sk.foot, 1 - hollow)
        love.graphics.ellipse('fill', ox, 0.03, orx * 0.72, ory * 0.55, 18)
    end
    if (seal or 0) > 0 then
        set(Skin.families.snail.shell, seal)
        love.graphics.ellipse('fill', ox, 0.01, orx * 0.9, ory * 0.8, 18)
    end
    -- a gloss
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.circle('fill', llx * 0.5, lly * 0.5, 0.09, 8)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    return marks, {cx, cy, angle, mx * R, R, ap}
end

--------------------------------------------------------------------------------
-- Simulation
--------------------------------------------------------------------------------

-- The frame with facing right: the shell turns round in it as it faces about
function Snail:frame_right()
    return -self.ny, self.nx, self.nx, self.ny
end

-- How high its shell rides, where its opening faces, and its centre now
function Snail:shell_pose()
    local s, r = self.k, self.retract
    local R = SHELL_R * s
    -- (sealed, it sits on the lip of its opening, turned to the surface)
    local ap = AWAKE_AP + (pi / 2 - AWAKE_AP) * r
    local high = (R * 0.78 + 3 * s) * (1 - r) + (R + 0.3 * s) * r
    return R, ap, high, SHELL_AT * s * (1 - r)
end

function Snail:shell_centre()
    local _, _, high, along = self:shell_pose()
    local tx, ty, nx, ny = self:frame_right()
    return self.a.x + tx * along * self.turn + nx * high, self.a.y + ty * along * self.turn + ny * high
end

-- Something comes near (another creature, or a crumb falling by): it pulls its
-- eyes in, once each time, and looks again after a while
function Snail:alarmed(ctx, hx, hy)
    local w = self.world
    if not w or not w.creatures then return false end
    local r = STARTLE.r * self.k + STARTLE.from
    local partner = ctx.court
    for _, o in ipairs(w.creatures) do
        if o ~= self then
            local ox, oy = o:anchor()
            if sq(ox - hx) + sq(oy - hy) < r * r and not (partner and abs(ox - partner.x) < 1 and abs(oy - partner.y) < 1) then
                return true
            end
        end
    end
    for _, f in ipairs(w.food and w.food.crumbs or {}) do
        if not f.down and sq(f.x - hx) + sq(f.y - hy) < r * r then return true end
    end
    return false
end

function Snail:update(dt, level, ctx)
    self.clock = self.clock + dt
    local s = self.k
    self:turn_normal(dt, 12)
    self.mover.x, self.mover.y = self.a.x, self.a.y

    -- Sealed in its shell asleep and dying; out again slowly when it wakes
    local sealed = ctx.rest or self.face.closing
    self.retract = sealed and min(1, self.retract + dt * 0.5) or max(0, self.retract - dt * 0.25)
    local head = self.foot[1]
    local near = not sealed and self:alarmed(ctx, head.x, head.y)
    if near and not self.crowded then
        self.startle = STARTLE.hold
        ctx.events:emit('withdraw', {x = head.x, y = head.y, who = self})
    end
    self.crowded = near
    self.startle = max(0, self.startle - dt)
    local want = (sealed or self.startle > 0) and 0 or 1
    self.stalks = self.stalks + (want - self.stalks) * min(1, dt * (want < self.stalks and 9 or 0.8))
    -- (in its shell it can't go, and pulled in it goes carefully)
    self.gait = sq(1 - self.retract) * (self.startle > 0 and 0.4 or 1)

    -- Courting, it turns to its partner and reaches out to it, and once their
    -- feet have met they rear up and sway together, feelers touching (#22)
    local court = ctx.court
    if court then self.court = court end
    self.ardour = self.ardour + ((court and 1 or 0) - self.ardour) * min(1, dt * 1.5)
    if self.ardour < 0.005 then self.ardour, self.court = 0, nil end
    local lean, rear, touch, sway, flush = 0, 0, 0, 0, 0
    if self.court then
        local c, k = self.court, self.ardour
        if court then
            local tx, ty = self:frame()
            if (c.x - self.a.x) * tx + (c.y - self.a.y) * ty < -1 then self.facing = -self.facing end
        end
        local met = min(1, (c.t or 0) / CREEP)
        local up = sin((c.beat / SWAY_BEAT) * pi)
        lean = k * 2.2 * s * met * met
        rear = k * met * (2.5 + 2 * up) * s
        sway = k * met * up
        touch = k * met * max(0, up) ^ 3
        flush = k * met * max(0, up)
    end
    local ease = min(1, dt * 3)
    self.lean = self.lean + (lean - self.lean) * ease
    self.rear = self.rear + (rear - self.rear) * ease
    self.sway, self.touch, self.flush = sway, touch, flush

    -- Its track, newest first, as long as its foot behind it; it's a new one
    -- each time it turns round
    if self.facing ~= self.track_facing then self.track, self.track_facing = {}, self.facing end
    local sx, sy = self:find_sole(level)
    local last = self.track[1]
    if not last or sq(sx - last.x) + sq(sy - last.y) > sq(TRACK_GAP * s) then
        local moved = last and sqrt(sq(sx - last.x) + sq(sy - last.y)) or 0
        self.wave = self.wave + moved / (WAVE * s)
        table.insert(self.track, 1, {x = sx, y = sy, nx = self.sole.nx, ny = self.sole.ny})
        local behind = ((FOOT - 1) * SEG - HEAD + 4) * s
        local len, px, py = 0, sx, sy
        for i, q in ipairs(self.track) do
            len = len + sqrt(sq(q.x - px) + sq(q.y - py))
            px, py = q.x, q.y
            if len > behind then
                for j = #self.track, i + 1, -1 do self.track[j] = nil end
                break
            end
        end
    end
    self.turn = self.turn + (self.facing - self.turn) * min(1, dt * 2.5)

    -- The foot: each point carried toward where it wants to be, kept its
    -- length from the next, and out of the scenery
    local foot = self.foot
    local want_at = {}
    for k = 1, FOOT do
        local x, y = self:target(k, level)
        want_at[k] = {x, y}
    end
    for k, p in ipairs(foot) do
        local vx, vy = (p.x - p.px) * 0.7, (p.y - p.py) * 0.7
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx, p.y + vy
        p.x, p.y = p.x + (want_at[k][1] - p.x) * 0.3, p.y + (want_at[k][2] - p.y) * 0.3
    end
    for k = 1, FOOT - 1 do
        local a, b = foot[k], foot[k + 1]
        local rest = sqrt(sq(want_at[k + 1][1] - want_at[k][1]) + sq(want_at[k + 1][2] - want_at[k][2]))
        local ex, ey = b.x - a.x, b.y - a.y
        local d = sqrt(ex * ex + ey * ey)
        if d > 1e-5 then
            local c = (d - rest) / d * 0.5
            a.x, a.y = a.x + ex * c, a.y + ey * c
            b.x, b.y = b.x - ex * c, b.y - ey * c
        end
    end
    for _, p in ipairs(foot) do level:resolve_point(p, 0.5 * s, 0.5, 0) end

    -- Slime from its anchor, as it goes
    local slime = self.slime
    local tip = slime[#slime]
    if self.pace > 0.5 and (not tip or sq(sx - tip.x) + sq(sy - tip.y) > sq(SLIME_GAP * s)) then
        local gap = tip and sq(sx - tip.x) + sq(sy - tip.y) > sq(SLIME_GAP * s * 4)
        slime[#slime + 1] = {x = sx, y = sy, nx = self.sole.nx, ny = self.sole.ny, t = self.clock, w = s, gap = gap or nil}
    end
    while slime[1] and self.clock - slime[1].t > DRY do table.remove(slime, 1) end

    if not self.crawled then self.pace = self.pace * max(0, 1 - dt * 10) end
    self.crawled = false
    self:halt(dt)

    -- Its eyes look where it's going, or at what it's after
    local lx, ly = self:frame()
    if ctx.look_at then
        local ddx, ddy = ctx.look_at.x - head.x, ctx.look_at.y - head.y
        local d = sqrt(ddx * ddx + ddy * ddy)
        if d > 1 then lx, ly = ddx / d, ddy / d end
    end
    self.face:update(dt, lx, ly, not ctx.look_at)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- A smooth spine through its foot: points along the sole, each with the way
-- up from it and how thick the foot is there
function Snail:spine()
    local foot, s = self.foot, self.k
    local out = {}
    local SUB = 3
    for k = 1, FOOT - 1 do
        local p0, p1, p2, p3 = foot[max(1, k - 1)], foot[k], foot[k + 1], foot[min(FOOT, k + 2)]
        for j = 0, (k == FOOT - 1) and SUB or SUB - 1 do
            local t = j / SUB
            local t2, t3 = t * t, t * t * t
            local x = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            local y = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            local u = (k - 1 + t)
            local th = THICK[floor(u) + 1] + (THICK[min(FOOT, floor(u) + 2)] - THICK[floor(u) + 1]) * (u - floor(u))
            out[#out + 1] = {x = x, y = y, th = th * s, u = u / (FOOT - 1)}
        end
    end
    -- each one's way up: across the spine, on the side the surface faces
    for i, p in ipairs(out) do
        local a, b = out[max(1, i - 1)], out[min(#out, i + 1)]
        local dx, dy = a.x - b.x, a.y - b.y
        local d = sqrt(dx * dx + dy * dy)
        if d < 1e-6 then dx, dy, d = -self.ny, self.nx, 1 end
        local ux, uy = dy / d, -dx / d
        if ux * self.nx + uy * self.ny < 0 then ux, uy = -ux, -uy end
        p.ux, p.uy = ux, uy
    end
    return out
end

-- The ribbon it has laid, under every body (main.lua draws trails first): wet
-- and shining where it's fresh, with glints in the lamp's pool, drying to a
-- faint dull mark
function Snail:draw_trail()
    local slime = self.slime
    if #slime < 2 then return end
    local w = self.world
    local lamp = w and w.hour and DayCycle.lampAt(w:hour()) or 1
    local now = self.clock
    local CHUNK = 6
    love.graphics.setLineJoin('none')
    for i = 1, #slime - 1, CHUNK do
        local q = slime[i]
        local age = now - q.t
        local dry = 1 - age / DRY
        local wet = max(0, 1 - age / WET)
        if dry > 0 then
            local pts = {}
            for k = i, min(#slime, i + CHUNK) do
                local p = slime[k]
                if k > i and p.gap then break end
                pts[#pts + 1], pts[#pts + 2] = p.x + p.nx * 0.8, p.y + p.ny * 0.8
            end
            if #pts >= 4 then
                love.graphics.setColor(SLIME[1], SLIME[2], SLIME[3], 0.1 + 0.22 * wet * dry)
                love.graphics.setLineWidth(1.8 * q.w)
                love.graphics.line(pts)
                -- the lamp catching it, most in its pool
                local lit = 0
                if w and w.light_dir then
                    local _, ly = w.light_dir(q.x, q.y)
                    lit = lamp * max(0, -ly) ^ 4
                end
                if wet > 0 and lit > 0.02 then
                    love.graphics.setColor(1, 1, 1, 0.5 * wet * lit)
                    love.graphics.setLineWidth(0.6 * q.w)
                    love.graphics.line(pts)
                    local g = Skin.hash(q.t, i)
                    local glint = max(0, sin(now * 1.7 + g * 30)) ^ 8
                    love.graphics.setColor(1, 1, 1, 0.9 * wet * lit * glint)
                    love.graphics.circle('fill', pts[1], pts[2], 0.7 * q.w, 6)
                end
            end
        end
    end
    love.graphics.setLineWidth(1)
end

-- One of its tentacles: from (x, y) `len` along `a` (radians), bending by
-- `bend`; an eye at its tip if `eye`
local function tentacle(x, y, a, len, bend, width, col, out, eye, open)
    local pts = {x, y}
    local px, py = x, y
    for i = 1, 4 do
        a = a + bend
        px, py = px + cos(a) * len / 4, py + sin(a) * len / 4
        pts[#pts + 1], pts[#pts + 2] = px, py
    end
    set(out)
    love.graphics.setLineWidth(width + 0.9)
    love.graphics.line(pts)
    set(col)
    love.graphics.setLineWidth(width)
    love.graphics.line(pts)
    if eye then
        love.graphics.circle('fill', px, py, width * 0.75, 8)
        set(EYE, 0.9)
        love.graphics.circle('fill', px + cos(a) * 0.25, py + sin(a) * 0.25, width * 0.5 * max(0.25, open), 8)
    end
    return px, py
end

function Snail:draw(ctx)
    local sk, s = self.skin, self.k
    local tx, ty, nx, ny = self:frame()
    local lx, ly = ctx.light_dir(self.a.x, self.a.y)
    local r = self.retract
    local spine = self:spine()

    -- The far feelers and eye stalk, behind the head
    local head = spine[1]
    local fwd, up = atan2(ty, tx), atan2(ny, nx) -- (forward, and up from the surface, as angles)
    local out_ = 1 - r
    if out_ > 0.05 then
        local hx, hy = head.x + head.ux * head.th * 0.9, head.y + head.uy * head.th * 0.9
        local lean = self.facing * (0.55 - 0.3 * self.sway)
        local len = STALK * s * self.stalks * out_
        local gaze = self.face.gaze_x * 0.15
        tentacle(hx - tx * 0.8 * s, hy - ty * 0.8 * s, up + lean * 0.8 + gaze, len * 0.92, 0.04 * self.facing, 1.1 * s,
            sk.foot_far, sk.outline, true, self.face:openness())
        local fx, fy = head.x + tx * head.th * 0.4, head.y + ty * head.th * 0.4
        tentacle(fx - tx * 0.6 * s, fy - ty * 0.6 * s, fwd + self.facing * 0.25, FEELER * s * out_ * (1 + 0.6 * self.touch),
            -0.05 * self.facing, 0.8 * s, sk.foot_far, sk.outline)
    end

    -- The foot: a run of discs along its spine, outline, then flesh, then the
    -- sole's paler fringe and the waves running forward along it
    if out_ > 0.02 then
        local function discs(grow, col, a)
            set(col, a)
            for _, p in ipairs(spine) do
                local th = p.th * (0.4 + 0.6 * out_)
                local rr = th * 0.5 + grow
                love.graphics.circle('fill', p.x + p.ux * th * 0.5, p.y + p.uy * th * 0.5, max(0.3, rr), 12)
            end
        end
        discs(0.8, sk.outline, 1)
        discs(0, sk.foot, 1)
        -- the light along its back
        set({1, 1, 1}, 0.12)
        for _, p in ipairs(spine) do
            local th = p.th * (0.4 + 0.6 * out_)
            love.graphics.circle('fill', p.x + p.ux * th * 0.72 + lx * 0.4, p.y + p.uy * th * 0.72 + ly * 0.4, th * 0.22, 8)
        end
        -- tubercles: little darker flecks over its skin
        set(sk.outline, 0.25)
        for i, p in ipairs(spine) do
            if i % 2 == 0 then
                local th = p.th * (0.4 + 0.6 * out_)
                local h = Skin.hash(sk.seed + i, 3)
                love.graphics.circle('fill', p.x + p.ux * th * (0.3 + 0.5 * h), p.y + p.uy * th * (0.3 + 0.5 * h), 0.35 * s, 5)
            end
        end
        -- the sole's fringe, and the dark bands of its waves running forward
        local pts = {}
        for _, p in ipairs(spine) do pts[#pts + 1], pts[#pts + 2] = p.x + p.ux * 0.5, p.y + p.uy * 0.5 end
        set({Base.mix(sk.foot, {1, 1, 1}, 0.35)}, 0.8)
        love.graphics.setLineWidth(0.7 * s)
        love.graphics.line(pts)
        local moving = min(1, self.pace / max(1, self.profile.crawl_speed))
        if moving > 0.05 then
            set(sk.outline, 0.3 * moving)
            for j = 0, 2 do
                local u = 1 - ((self.wave + j / 3) % 1) -- (from tail to head)
                local p = spine[max(1, min(#spine, floor(u * (#spine - 1)) + 1))]
                love.graphics.circle('fill', p.x + p.ux * 0.8, p.y + p.uy * 0.8, 0.9 * s, 8)
            end
        end
        love.graphics.setLineWidth(1)
    end

    -- The shell
    if not ctx.parted then
        local marks, frame = self:draw_kept(ctx)
        self.local_marks, self.mark_frame = marks, frame
    end

    -- Sealed, a pale film over its opening
    if r > 0.3 then
        local R = self:shell_pose()
        local cx, cy = self:shell_centre()
        local sp = spiral(self.whorls)
        -- (where its lip meets the surface, a thin film along it)
        local ox, oy = cx - nx * (R - 0.2 * s), cy - ny * (R - 0.2 * s)
        local a = (r - 0.3) / 0.7
        local film = Skin.families.snail.shell
        local len = R * (1 - sp.q) * 0.6 + s
        love.graphics.push()
        love.graphics.translate(ox, oy)
        love.graphics.rotate(atan2(ty, tx))
        set(sk.outline, 0.4 * a)
        love.graphics.ellipse('fill', 0, 0, len + 0.4, 0.75 * s + 0.4, 16)
        set(film, 0.6 * a)
        love.graphics.ellipse('fill', 0, 0, len, 0.75 * s, 16)
        love.graphics.setColor(1, 1, 1, 0.4 * a)
        love.graphics.ellipse('fill', -len * 0.2, -0.2 * s, len * 0.45, 0.2 * s, 10)
        love.graphics.pop()
    end

    -- The near eye stalk and feeler, in front
    if out_ > 0.05 then
        local hx, hy = head.x + head.ux * head.th * 0.9, head.y + head.uy * head.th * 0.9
        local lean = self.facing * (0.45 - 0.3 * self.sway)
        local len = STALK * s * self.stalks * out_
        local gaze = self.face.gaze_x * 0.15
        tentacle(hx, hy, up + lean + gaze, len, 0.05 * self.facing, 1.25 * s, sk.foot, sk.outline, true, self.face:openness())
        local fx, fy = head.x + tx * head.th * 0.45, head.y + ty * head.th * 0.45
        tentacle(fx, fy, fwd + self.facing * 0.4, FEELER * s * out_ * (1 + 0.6 * self.touch), -0.06 * self.facing, 0.9 * s,
            sk.foot, sk.outline)
    end
    love.graphics.setLineWidth(1)
end

-- What it keeps when it dies, drawn as it is (Remains.through fades the rest):
-- its shell. Returns its markings and their frame, for the glow.
function Snail:draw_kept(ctx)
    local R, ap, high, along = self:shell_pose()
    local cx, cy = self:shell_centre()
    local tx, ty = self:frame_right()
    local lx, ly = ctx.light_dir(cx, cy)
    -- (it rocks a little with each wave of its foot, and sways courting)
    local moving = min(1, self.pace / max(1, self.profile.crawl_speed))
    local rock = 0.05 * moving * sin(self.wave * TAU) + 0.1 * self.sway
    -- (dying, the body it drew into its shell is gone from it)
    local hollow = (self.face.closing and 1 or 0) * self.retract
    return draw_shell(self.skin, self.whorls, R, cx, cy, atan2(ty, tx) + rock * self.facing, self.turn, ap, lx, ly,
        hollow, max(0, self.retract - 0.3) / 0.7 * (1 - hollow))
end

-- Its markings, shining as the lamp dims (#15) and flushing as it sways (#22),
-- and the night glow its fresh slime still holds
function Snail:draw_emissive(ctx)
    local k = Skin.shine(self.skin, ctx and ctx.light, self.flush)
    local f = self.mark_frame
    if k > 0.01 and f then
        love.graphics.push()
        love.graphics.translate(f[1], f[2])
        love.graphics.rotate(f[3])
        love.graphics.scale(f[4], f[5])
        love.graphics.rotate(f[6])
        Skin.paint_glow(self.local_marks, self.skin, k)
        love.graphics.pop()
    end
    local night = ctx and ctx.light and ctx.light.glow or 0
    local slime = self.slime
    if night > 0.05 and #slime > 1 then
        local pts = {}
        for i = #slime, max(1, #slime - 24), -3 do
            local q = slime[i]
            pts[#pts + 1], pts[#pts + 2] = q.x + q.nx * 0.8, q.y + q.ny * 0.8
        end
        if #pts >= 4 then Skin.paint_glow({{'line', pts, 0.8 * self.k}}, self.skin, 0.12 * night * self.skin.glow) end
    end
end

-- X-ray: its foot and the targets it reaches for, the anchor and its normal
function Snail:draw_xray(ctx)
    local c = self.color_name
    local level = self.world and self.world.level
    love.graphics.setLineWidth(1.2)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    local pts = {}
    for _, p in ipairs(self.foot) do pts[#pts + 1], pts[#pts + 2] = p.x, p.y end
    love.graphics.line(pts)
    for k, p in ipairs(self.foot) do
        love.graphics.circle('line', p.x, p.y, 1.4)
        if level then
            local x, y = self:target(k, level)
            love.graphics.setColor(c[1], c[2], c[3], 0.35)
            love.graphics.circle('line', x, y, 2.2)
            love.graphics.setColor(c[1], c[2], c[3], 0.9)
        end
    end
    love.graphics.setColor(1, 0.96, 0.88, 0.6)
    love.graphics.line(self.a.x, self.a.y, self.a.x + self.nx * 18, self.a.y + self.ny * 18)
    love.graphics.circle('fill', self.a.x, self.a.y, 1.6)
    love.graphics.setLineWidth(1)
end

function Snail:draw_debug()
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.circle('fill', self.a.x, self.a.y, 2.5)
end

--------------------------------------------------------------------------------
-- What it leaves

-- Asleep, it seals itself in on the glass or under a ledge (mind.lua's beds):
-- a node of its graph it would sleep on
function Snail.rest(n)
    if n.kind ~= 'face' then return false end
    return n.solid.kind == 'wall' or (n.solid.kind == 'ledge' and n.ny > 0.5)
end

-- When it goes back to the moss its shell stays where it lay (World.KEPT):
-- what's needed to draw it, or nil if it didn't die lying on a top
function Snail.keeps(c)
    if not c.foot or c.ny > -0.9 then return nil end
    local R, ap = c:shell_pose()
    local cx, cy = c:shell_centre()
    local g = c.genome or {}
    return {x = cx, y = cy, R = R, ap = ap, turn = c.turn >= 0 and 1 or -1, whorls = c.whorls, ground = c.a.y,
        hue = g.hue, pattern = g.pattern, glow = g.glow, old = c.skin.old or 0}
end

local kept_skins = {}

-- An empty shell in the moss, `u` (0..1) of the way through the time it's
-- kept: bleaching toward the moss's colours as the moss grows up over it, and
-- at the end sinking out of sight
function Snail.draw_left(r, world, u, light_dir)
    local k = r.kept
    local earth = floor((0.15 + 0.55 * u) * 12) / 12
    local key = string.format('%s:%s:%s:%s', tostring(k.hue), tostring(k.pattern), tostring(k.old), earth)
    local sk = kept_skins[key]
    if not sk then
        sk = Skin.of('snail', {hue = k.hue, pattern = k.pattern, glow = k.glow}, 0, k.old, earth)
        kept_skins[key] = sk
    end
    local gone = max(0, (u - 0.85) / 0.15)
    local sink = gone * k.R * 1.2
    local lx, ly = 0, -1
    if light_dir then lx, ly = light_dir(k.x, k.y) end
    love.graphics.push('all')
    love.graphics.setColor(1, 1, 1, 1 - gone)
    draw_shell(sk, k.whorls, k.R, k.x, k.y + sink, 0, k.turn, k.ap, lx, ly, 1)
    -- the moss growing up over it, a tuft at a time
    local seed = (r.born or 0) % 97
    for t = 1, 16 do
        local h = Skin.hash(seed, t)
        if u > h * 0.7 then
            local x = k.x + (Skin.hash(t, seed) - 0.5) * k.R * 2.4
            local grown = min(1, (u - h * 0.7) / 0.3)
            local tall = k.R * (0.5 + 1.1 * Skin.hash(seed + 1, t)) * grown
            local c = h < 0.5 and world.moss.LUSH or world.moss.RICH -- (jar/moss.lua's greens)
            love.graphics.setColor(c[1], c[2], c[3], 0.95)
            love.graphics.setLineWidth(1.1)
            local bend = (Skin.hash(seed + 2, t) - 0.5) * 3
            love.graphics.line(x, k.ground, x + bend * 0.5, k.ground - tall * 0.6, x + bend, k.ground - tall)
            love.graphics.circle('fill', x + bend, k.ground - tall, 0.8, 6)
        end
    end
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- What the self-test knows of a snail (#73); see Worm.LIMITS
Snail.LIMITS = {
    -- of the length between them, the most two points of its foot have been
    -- pulled apart or pushed together (a corner squeezes the sole a little)
    {measure = 'torn', most = 1, says = 'pulled or pushed its foot %.0f%% out of its length', scale = 100},
    -- of its foot's points behind its head, over every look, the ones off the surface
    {measure = 'lifted', most = 0.04, says = 'had its foot off the surface %.1f%% of the time', scale = 100},
}

-- Fold a look at snail `c` into `m`: how far its foot's points are from the
-- spacing they want, and of those behind its head (which rears courting),
-- how many have nothing within reach of the sole
function Snail.health(c, m, dt)
    local level = c.world and c.world.level
    local torn, off, looked = 0, 0, 0
    for k = 1, FOOT - 1 do
        local a, b = c.foot[k], c.foot[k + 1]
        local rest = abs(c:reach_of(k) - c:reach_of(k + 1)) * abs(c.turn)
        local d = sqrt(sq(b.x - a.x) + sq(b.y - a.y))
        torn = max(torn, abs(d - rest) / max(rest, 0.5))
    end
    m.torn = max(m.torn or 0, torn)
    if level then
        for k = 3, FOOT do
            local p = c.foot[k]
            looked = looked + 1
            if level:circle_clear(p.x, p.y, (LIFT + 1.8) * c.k) then off = off + 1 end
        end
    end
    m.offs, m.looks = (m.offs or 0) + off, (m.looks or 0) + looked
    m.lifted = m.offs / max(1, m.looks)
    return m
end

-- How big snail `c` is built now
function Snail.grown_size(c) return c.size end

-- `genome` with the body the sim works hardest for: the biggest, most whorled
function Snail.heaviest(genome)
    genome.size = Genome.snail.by_name.size.real[2]
    genome.whorls = Genome.snail.by_name.whorls.real[2]
    return genome
end

-- How far its foot lies out behind its anchor
function Snail.length(genome) return 14 * BODY * (genome and genome.size or 1) end

-- How far either side of its anchor it lies, as a token (bodies/token.lua)
function Snail.half(t) return 13 * t.k end

return Snail
