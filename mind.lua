-- mind.lua: what a creature means to do next.
--
-- The M1 stub (#9): the lamp and a hunger counter choose among three things to
-- do. By day a creature wanders between places its body can reach, and when
-- it's hungry it goes to moss and grazes for a while. When the lamp goes out
-- it finds somewhere to rest and stays there until morning. Walkers rest on
-- moss and spiders hang under the arch or the shelf. Each mind keeps its own
-- hours, a little after the lamp's, so the jar doesn't all fall asleep at once.
-- #21 grows this into needs and temperament.
--
-- A mind only picks goals. The controller walks the path and the body moves,
-- so it can only ask for places its graph holds (the body never lies).

local rng = require('core.rng')
local DayCycle = require('jar.daycycle')

local Mind = {}
Mind.__index = Mind

local HUNGRY_AFTER = 80 -- seconds awake before moss starts to call
local GRAZE = {6, 12}   -- seconds spent at the moss
local PAUSE = {5, 14}   -- seconds idle between wanders
local LATE = 0.75       -- up to this many hours after the lamp to sleep and wake

function Mind.new()
    return setmetatable({
        doing = 'idle',          -- idle, wander, to_graze, graze, to_rest, rest
        timer = rng.range(rng.sim, 2, 6),
        hunger = rng.range(rng.sim, 0, 0.6),
        late = rng.range(rng.sim, 0, LATE),
        wanders = 0, grazes = 0, nights = 0,
    }, Mind)
end

-- Awake from a little after the lamp comes on to a little after it goes off
function Mind:awake(hour)
    local h = (hour - self.late) % 24
    return h >= DayCycle.presets.lampon and h < DayCycle.presets.lampoff
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

local function moss_spots(graph)
    local pool = {}
    for _, n in ipairs(graph.nodes) do
        if n.kind == 'top' and n.solid.moss then pool[#pool + 1] = n end
    end
    return pool
end

local function pick(pool)
    return #pool > 0 and pool[rng.sim:random(1, #pool)] or nil
end

function Mind:set(doing, timer)
    self.doing, self.timer = doing, timer or 0
end

-- One fixed step. `c` is the body, `ctrl` its controller and `graph` its nav graph
function Mind:update(dt, hour, c, ctrl, graph)
    local doing = self.doing
    local arrived = not ctrl:has_path()

    if not self:awake(hour) then
        if doing == 'rest' then return end
        if doing == 'to_rest' then
            if arrived then
                self:set('rest')
                self.nights = self.nights + 1
            end
        elseif arrived then
            -- Finish whatever trip it's on, then go to bed (or sleep where it is)
            self:set(ctrl:go_to(pick(rest_spots(graph, c.profile.climbs))) and 'to_rest' or 'rest')
            if self.doing == 'rest' then self.nights = self.nights + 1 end
        end
        return
    end

    self.hunger = self.hunger + dt / HUNGRY_AFTER
    if doing == 'rest' or doing == 'to_rest' then
        if arrived then self:set('idle', rng.range(rng.sim, 1, 4)) end
    elseif doing == 'wander' then
        if arrived then self:set('idle', rng.range(rng.sim, PAUSE[1], PAUSE[2])) end
    elseif doing == 'to_graze' then
        if arrived then
            self:set('graze', rng.range(rng.sim, GRAZE[1], GRAZE[2]))
            self.grazes = self.grazes + 1
        end
    elseif doing == 'graze' then
        self.hunger = math.max(0, self.hunger - 2 * dt / GRAZE[1])
        self.timer = self.timer - dt
        if self.timer <= 0 then self:set('idle', rng.range(rng.sim, 2, 5)) end
    elseif doing == 'idle' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            if self.hunger >= 1 and ctrl:go_to(pick(moss_spots(graph))) then
                self:set('to_graze')
            else
                local kinds = c.profile.climbs and nil or {top = true}
                if ctrl:go_to(graph:random_node(rng.sim, kinds)) then
                    self:set('wander')
                    self.wanders = self.wanders + 1
                else
                    self:set('idle', rng.range(rng.sim, PAUSE[1], PAUSE[2]))
                end
            end
        end
    end
end

-- Grazing heads look down at the moss
function Mind:look(c)
    if self.doing == 'graze' then
        local x, y = c:anchor()
        return {x = x, y = y + 14}
    end
end

return Mind
