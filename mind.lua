-- mind.lua: what a creature means to do next.
--
-- Needs and temperament choose goals (#21). Two needs drive the day: hunger,
-- which rises while it's awake and falls only on what it crops from the moss
-- (jar/moss.lua), and rest, which its own clock calls for. From them it picks
-- one of five goals: graze, wander, rest, follow another creature for a
-- while, or court.
--
-- Courting (#22) comes of meeting. Each time two awake creatures of the same
-- plan come near each other after time apart, both count it (Mind.meet, once a
-- step). When a fed one has met another of its kind often enough, and that
-- one is fed and free too, it walks over while the other waits, and the two
-- court for a while: worms coil together, blobs pulse in time, spiders tap.
-- The bodies read it from Mind:courting, and the beat is the jar's clock, so a
-- pair keeps time. Each courts at most once between one sleep and the next.
--
-- Its temperament is three genes, and they change when and where it does
-- those things, never what it can do:
--   boldness     how far from home it wanders, and how big a leap it will take
--                (a timid body walks the long way round, or doesn't go). Hunger
--                makes anyone brave: past DESPERATE it takes any leap its
--                body can make.
--   sociability  whether it goes where the others are, follows them about, and
--                sleeps in a pile; or keeps its distance and sleeps alone.
--   chronotype   when its day is: an early riser is up before the lamp and in
--                bed before it goes off, and a night owl wakes in the
--                afternoon and is about in the dark, against the lamp.
--
-- A mind only picks goals. The controller walks the path and the body moves,
-- so it can only ask for places its graph holds (the body never lies). It
-- reads nothing of a body but its anchor, whether it climbs, and (to stand
-- beside a partner) the surface it's on and its `court_gap`, and keeps
-- only numbers (another creature is an index), so it runs the same over the
-- anchors-only coarse step of catch-up (#31) as over the live one.

local rng = require('core.rng')
local DayCycle = require('jar.daycycle')

local Mind = {}
Mind.__index = Mind

local HUNGRY_AFTER = 150 -- seconds awake before moss starts to call
local DESPERATE = 1.6    -- hunger that takes any leap to reach moss
local GRAZE = {6, 12}    -- seconds spent at the moss
local FILL = 1.0         -- hunger a cell's worth of lush moss takes away
local LUSH = 0.4         -- moss this high is worth walking to
local PAUSE = {5, 14}    -- seconds idle between wanders
local LATE = 0.75        -- up to this many hours of each mind's own lateness

-- Temperament, from genes 0..1
local RANGE = {280, 2000}     -- how far from home it wanders, timid to bold (the jar is 2000 wide)
local DARE = {0.35, 1}        -- the biggest leap it takes (navgraph's edge.dare), timid to bold
local SHIFT = {-1.5, 9}       -- its day against the lamp's, in hours, early riser to night owl,
                              -- along the cube of the gene: most keep near the lamp's hours,
                              -- and only the far end lives by night
local FOLLOW = 0.5            -- chance the most sociable picks following over wandering
local FOLLOW_FOR = {12, 24}   -- seconds it keeps after one
local CLOSE = 40              -- nearer than this to another is as close as it gets
local FAR = 800               -- and farther than this is as far
local CHOICES = 6             -- places weighed for each wander or bed

-- Courting
local MEET = 70               -- two of a kind this near have met
local PART = 140              -- and must be this far apart before they can meet again
local MET = 3                 -- meetings before a pair will court
local FED = 0.5               -- hunger below this is fed enough to court
local COURT = {12, 18}        -- seconds a courtship lasts
local REACH = 30              -- seconds it gives the walk over
local BESIDE = 90             -- this near on arrival, they court
local FREE = {idle = true, wander = true, follow = true} -- what a partner leaves off to court

local function lerp(r, t) return r[1] + (r[2] - r[1]) * t end

-- A mind for a body grown from `genome` (any gene it lacks reads as the middle)
function Mind.new(genome)
    genome = genome or {}
    local self = setmetatable({
        doing = 'idle',          -- idle, wander, follow, to_graze, graze, to_rest, rest, to_court, await, court
        timer = rng.range(rng.sim, 2, 6),
        hunger = rng.range(rng.sim, 0, 0.6),
        late = rng.range(rng.sim, 0, LATE),
        met = {},                -- creature index -> times they've met
        near = {},               -- creature index -> true while they're together
        wooed = false,           -- it has courted since it last slept
        wanders = 0, grazes = 0, nights = 0, follows = 0, courts = 0, -- what it's done, for the self-tests
    }, Mind)
    self.boldness = genome.boldness or 0.5
    self.sociability = genome.sociability or 0.5
    self.chronotype = genome.chronotype or 0.5
    self.range = lerp(RANGE, self.boldness)
    self.dare = lerp(DARE, self.boldness)
    self.shift = lerp(SHIFT, self.chronotype ^ 3) + self.late
    return self
end

-- Awake through its own day: the lamp's hours, moved by its chronotype
function Mind:awake(hour)
    local h = (hour - self.shift) % 24
    return h >= DayCycle.presets.lampon and h < DayCycle.presets.lampoff
end

-- How big a leap it'll take now: its own, unless hunger has made it brave
function Mind:daring()
    return self.hunger >= DESPERATE and 1 or self.dare
end

-- Somewhere this body can rest the night
local function rest_spots(graph, climbs)
    local pool = {}
    for _, n in ipairs(graph.nodes) do
        local ok
        if climbs then
            ok = n.kind == 'face' and n.ny > 0.5 and n.solid.kind == 'ledge'
        else
            ok = n.kind == 'top' and n.solid.moss
        end
        if ok then pool[#pool + 1] = n end
    end
    return pool
end

-- Moss to graze, the lush first: a creature walks past what's been cropped
-- (any moss will do if there's none)
local function moss_spots(graph, moss)
    local pool, lush = {}, {}
    for _, n in ipairs(graph.nodes) do
        if n.kind == 'top' and n.solid.moss then
            pool[#pool + 1] = n
            local h = moss and moss:height_at(n.x, n.y)
            if h and h >= LUSH then lush[#lush + 1] = n end
        end
    end
    return #lush > 0 and lush or pool
end

local function pick(pool)
    return #pool > 0 and pool[rng.sim:random(1, #pool)] or nil
end

-- The places in `pool` within its range of home, or all of them if none are
function Mind:near_home(pool, home)
    local out = {}
    for _, n in ipairs(pool) do
        if math.abs(n.x - home.x) <= self.range then out[#out + 1] = n end
    end
    return #out > 0 and out or pool
end

-- Where the others are: each awake one's anchor, and a resting one's bed. With
-- `abed`, only those in or on their way to bed.
local function others(world, me, abed)
    local out = {}
    for j, c in ipairs(world.creatures) do
        local m = world.minds[j]
        local sleeping = m.doing == 'rest' or m.doing == 'to_rest'
        if j ~= me and (sleeping or not abed) then
            local goal = m.doing == 'to_rest' and world.controllers[j].goal
            if goal then
                out[#out + 1] = {goal.x, goal.y}
            else
                local x, y = c:anchor()
                out[#out + 1] = {x, y}
            end
        end
    end
    return out
end

-- Up to CHOICES places from `pool`, best first by its sociability: near the
-- others for a sociable one, far for a loner, and by chance between
function Mind:choose(pool, near)
    if #pool == 0 then return {} end
    local scored = {}
    for k = 1, math.min(CHOICES, #pool) do
        local n = pool[rng.sim:random(1, #pool)]
        local d = FAR
        for _, p in ipairs(near) do
            d = math.min(d, math.sqrt((n.x - p[1]) ^ 2 + (n.y - p[2]) ^ 2))
        end
        scored[k] = {n = n, score = (self.sociability - 0.5) * math.max(d, CLOSE), k = k}
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.k < b.k
    end)
    local out = {}
    for k, s in ipairs(scored) do out[k] = s.n end
    return out
end

-- Set off for the first of `goals` it dares the way to. With `brave`, it'll
-- take any leap for the first if none of them can be reached its own way.
function Mind:head(ctrl, goals, brave)
    local dare = self:daring()
    for _, n in ipairs(goals) do
        if ctrl:go_to(n, dare) then return true end
    end
    return brave and goals[1] ~= nil and ctrl:go_to(goals[1]) or false
end

function Mind:set(doing, timer)
    self.doing, self.timer = doing, timer or 0
end

-- The nearest awake creature to follow: its own kind first
local function companion(world, me)
    local c = world.creatures[me]
    local x, y = c:anchor()
    local best, best_d
    for j, o in ipairs(world.creatures) do
        local m = world.minds[j]
        if j ~= me and m.doing ~= 'rest' and m.doing ~= 'to_rest' then
            local ox, oy = o:anchor()
            local d = math.sqrt((ox - x) ^ 2 + (oy - y) ^ 2) + (o.key == c.key and 0 or FAR)
            if not best_d or d < best_d then best, best_d = j, d end
        end
    end
    return best
end

-- Head for wherever the one it follows is now
function Mind:after(ctrl, graph, world)
    local o = world.creatures[self.with]
    local x, y = o:anchor()
    return ctrl:go_to(graph:node_near(x, y), self:daring())
end

-- Something to do by day: follow someone, or wander off
function Mind:choose_errand(c, ctrl, graph, world, me)
    if rng.sim:random() < FOLLOW * self.sociability * self.sociability then
        local j = companion(world, me)
        if j then
            self.with = j
            if self:after(ctrl, graph, world) then
                self:set('follow', rng.range(rng.sim, FOLLOW_FOR[1], FOLLOW_FOR[2]))
                self.follows = self.follows + 1
                return
            end
            self.with = nil
        end
    end
    local pool = {}
    for _, n in ipairs(graph.nodes) do
        if c.profile.climbs or n.kind == 'top' then pool[#pool + 1] = n end
    end
    if self:head(ctrl, self:choose(self:near_home(pool, c.home), others(world, me))) then
        self:set('wander')
        self.wanders = self.wanders + 1
    else
        self:set('idle', rng.range(rng.sim, PAUSE[1], PAUSE[2]))
    end
end

-- Count meetings, once a step: two of a plan, both up, coming near after time
-- apart have met once more
function Mind.meet(world)
    local cs, ms = world.creatures, world.minds
    for i = 1, #cs do
        local a, ma = cs[i], ms[i]
        if ma.doing ~= 'rest' then
            local ax, ay = a:anchor()
            for j = i + 1, #cs do
                local b, mb = cs[j], ms[j]
                if b.key == a.key and mb.doing ~= 'rest' then
                    local bx, by = b:anchor()
                    local d2 = (bx - ax) ^ 2 + (by - ay) ^ 2
                    if not ma.near[j] and d2 < MEET * MEET then
                        ma.near[j], mb.near[i] = true, true
                        ma.met[j], mb.met[i] = (ma.met[j] or 0) + 1, (mb.met[i] or 0) + 1
                    elseif ma.near[j] and d2 > PART * PART then
                        ma.near[j], mb.near[i] = nil, nil
                    end
                end
            end
        end
    end
end

-- Fed, grown (a hatchling is `young` until its last moult, #23), and it
-- hasn't courted since it last slept
function Mind:ready()
    return self.hunger < FED and not self.wooed and not self.young
end

-- Whom it would court now: one of its kind it's met often, ready and free
-- (the one it's met most, and of those the first)
local function suitor(world, me)
    local best, most = nil, MET - 1
    for j = 1, #world.minds do
        local n, o = world.minds[me].met[j] or 0, world.minds[j]
        if n > most and j ~= world.selected and o:ready() and FREE[o.doing] then best, most = j, n end
    end
    return best
end

-- Where on `graph` creature `c` goes to court `p`: the place on the surface
-- `p` stands on that's nearest the two bodies' court gaps away from it, on
-- the side `c` comes from if there's room
local function beside(graph, c, p)
    local x, y = p:anchor()
    local cx, cy = c:anchor()
    local on, gap = p.solid or p.mover.solid, c.court_gap + p.court_gap
    local best, best_d
    for _, n in ipairs(graph.nodes) do
        if n.solid == on and (not p.nx or n.nx * p.nx + n.ny * p.ny > 0.5) then
            local dx, dy = n.x - x, n.y - y
            local d = math.abs(math.sqrt(dx * dx + dy * dy) - gap)
            if dx * (cx - x) + dy * (cy - y) < 0 then d = d + gap end
            if not best_d or d < best_d then best, best_d = n, d end
        end
    end
    return best
end

-- Go courting, if it's ready and there's one to court: it walks over, and the
-- other stops and waits for it
function Mind:court(ctrl, graph, world, me)
    if not self:ready() then return false end
    local j = suitor(world, me)
    if not j then return false end
    local spot = beside(graph, world.creatures[me], world.creatures[j])
    if not spot or not ctrl:go_to(spot, self:daring()) then return false end
    local o = world.minds[j]
    world.controllers[j]:clear()
    self.with, o.with, self.lead = j, me, true
    self:set('to_court', REACH)
    o:set('await', REACH)
    return true
end

-- Both leave off courting; `done`, they've courted
function Mind:part(world, me, done)
    for _, k in ipairs({me, self.with}) do
        local m = world.minds[k]
        if done then
            m.wooed, m.courts = true, m.courts + 1
            m.met[m.with] = 0
        end
        world.controllers[k]:clear()
        m.with, m.lead = nil, nil
        m:set('idle', rng.range(rng.sim, 2, 5))
    end
end

-- A step of courting: walking over, waiting, or the courtship itself. The one
-- that walked over says when it's over; the other waits on it, and gives up
-- if it goes off.
function Mind:woo(dt, world, me, arrived)
    local o = world.minds[self.with]
    if not o or o.with ~= me then
        self.with, self.lead = nil, nil
        self:set('idle', rng.range(rng.sim, 2, 5))
        return
    end
    self.timer = self.timer - dt
    if not self.lead then
        -- (its time runs with the other's, so this is only if that one stalls)
        if self.timer < -1 then self:part(world, me) end
        return
    end
    local c, p = world.creatures[me], world.creatures[self.with]
    if self.doing == 'to_court' then
        local x, y = c:anchor()
        local ox, oy = p:anchor()
        if self.timer <= 0 or (arrived and (ox - x) ^ 2 + (oy - y) ^ 2 > BESIDE * BESIDE) then
            self:part(world, me)
        elseif arrived then
            self:set('court', rng.range(rng.sim, COURT[1], COURT[2]))
            o:set('court', self.timer)
            self.since, o.since = world.time, world.time
            world.events:emit('court', {who = c, with = p, x = x, y = y})
        end
    elseif self.timer <= 0 then
        local x, y = c:anchor()
        world.events:emit('courted', {who = c, with = p, x = x, y = y})
        self:part(world, me, true)
    end
end

-- What a courting body is told: where its partner is, how long they've been
-- at it, and the beat they keep (the jar's clock, so the two share it). `side`
-- tells the two apart.
function Mind:courting(world, me)
    if self.doing ~= 'court' then return nil end
    local x, y = world.creatures[self.with]:anchor()
    return {x = x, y = y, t = world.time - self.since, beat = world.time, side = me < self.with and 1 or -1}
end

-- One fixed step for creature `me` of `world`, at the jar's `hour`
function Mind:update(dt, hour, world, me)
    local c, ctrl, graph, moss = world.creatures[me], world.controllers[me], world.graphs[me], world.moss
    local doing = self.doing
    local arrived = not ctrl:has_path()

    if not self:awake(hour) then
        self.with, self.lead = nil, nil
        self.wooed = false
        if doing == 'rest' then return end
        if doing == 'to_rest' then
            if arrived then
                self:set('rest')
                self.nights = self.nights + 1
            end
        elseif arrived or doing == 'follow' or doing == 'to_court' then
            -- Finish whatever trip it's on, then go to bed (or sleep where it is)
            local beds = self:choose(self:near_home(rest_spots(graph, c.profile.climbs), c.home), others(world, me, true))
            self:set(self:head(ctrl, beds, true) and 'to_rest' or 'rest')
            if self.doing == 'rest' then self.nights = self.nights + 1 end
        end
        return
    end

    self.hunger = self.hunger + dt / HUNGRY_AFTER
    if doing == 'rest' or doing == 'to_rest' then
        if arrived then self:set('idle', rng.range(rng.sim, 1, 4)) end
    elseif doing == 'wander' then
        if arrived then self:set('idle', rng.range(rng.sim, PAUSE[1], PAUSE[2])) end
    elseif doing == 'follow' then
        -- Keep after it a while, catching up whenever it's got ahead; let it go
        -- when the time's up, it's gone to bed, or hunger calls
        self.timer = self.timer - dt
        local m = world.minds[self.with]
        if self.timer <= 0 or self.hunger >= 1 or m.doing == 'rest' or m.doing == 'to_rest' then
            ctrl:clear()
            self.with = nil
            self:set('idle', rng.range(rng.sim, 1, 3))
        elseif arrived then
            local x, y = c:anchor()
            local ox, oy = world.creatures[self.with]:anchor()
            if (ox - x) ^ 2 + (oy - y) ^ 2 > CLOSE * CLOSE * 4 then self:after(ctrl, graph, world) end
        end
    elseif doing == 'to_court' or doing == 'await' or doing == 'court' then
        self:woo(dt, world, me, arrived)
    elseif doing == 'to_graze' then
        if arrived then
            self:set('graze', rng.range(rng.sim, GRAZE[1], GRAZE[2]))
            self.grazes = self.grazes + 1
        end
    elseif doing == 'graze' then
        -- It's fed by what it crops, so bare moss leaves it hungry
        local x, y = c:anchor()
        local eaten = moss and moss:graze(x, y, dt)
        self.hunger = math.max(0, self.hunger - (eaten and eaten * FILL or 2 * dt / GRAZE[1]))
        self.timer = self.timer - dt
        -- It stops when it's full, or when it gives up on what's left
        if self.timer <= 0 or self.hunger == 0 then self:set('idle', rng.range(rng.sim, 2, 5)) end
    elseif doing == 'idle' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            -- Hungry, it goes for moss near home if it can, then any it dares
            -- reach; desperate, it goes for any its body can
            local spots = moss_spots(graph, moss)
            if self.hunger >= 1 and self:head(ctrl, {pick(self:near_home(spots, c.home)), pick(spots)}, self.hunger >= DESPERATE) then
                self:set('to_graze')
            elseif not self:court(ctrl, graph, world, me) then
                self:choose_errand(c, ctrl, graph, world, me)
            end
        end
    end
end

-- Grazing heads look down at the moss, a follower watches who it follows, and
-- a courting one its partner
function Mind:look(c, world)
    if self.doing == 'graze' then
        local x, y = c:anchor()
        return {x = x, y = y + 14}
    end
    if self.with then
        local x, y = world.creatures[self.with]:anchor()
        return {x = x, y = y - 10}
    end
end

return Mind
