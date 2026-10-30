-- A week in one jar (#34): before v0.1.0 ships, one jar lived for seven jar
-- days on the live step, the one you watch, not the month's coarse one. It
-- opens just before lamp-on on 900 s days and is left alone. At the end of
-- each day it prints and logs who is alive, what happened, how long a step
-- took and how much memory Lua holds, to week_<seed>.csv in the save
-- directory. It fails if anything breaks the jar: a body that leaves it or
-- goes NaN, a kind gone, more than CAPACITY in it, steps that are often
-- slow, or memory that keeps climbing. A body past its plan's LIMITS for a
-- while is reported but doesn't fail the week, since a lived-in jar has
-- tangles the ranges test's clean tours never meet.
--
--   lovec . --headless --script scripts/week.lua [--seed <n>]

local DAY = 900  -- s
local DAYS = 7
local OPEN = 5.2 -- the hour it opens at, a little before the lamp's timer
local BUDGET = 1 / 240 -- s: 99 steps in 100 come in under this (the crowd's budget for two)
local GROWTH = 1.5 -- memory on the last day may be at most this many times the second's
local EVENTS = {'court', 'laid', 'hatched', 'moulted', 'dying', 'returned', 'nibbled'}

-- (flushed, so a long run shows its days as they end)
local function say(s) print(s); io.stdout:flush() end

local function class_of(World, key)
    for _, def in ipairs(World.CREATURES) do
        if def.key == key then return def.class end
    end
end

-- What `m` says is past `class`'s LIMITS, as its LIMITS word it
local function past(class, m)
    local out = {}
    for _, l in ipairs(class.LIMITS) do
        local v = m[l.measure] or 0
        if v > l.most then out[#out + 1] = string.format(l.says, v * (l.scale or 1)) end
    end
    return out
end

return {run = function(api)
    local seed = api.args.seed or 20261018
    local World, room = api.World, api.room
    local w = api.open(seed, OPEN, nil, DAY)
    local width, height = room.width, room.height
    local cast = w.cast
    say(string.format('[week] seed %d, cast %s, %d days of %d s', seed, table.concat(cast, ', '), DAYS, DAY))

    local counts, during = {}, {} -- the day's events, and the last step's
    w.events:on(function(ev)
        counts[ev.kind] = (counts[ev.kind] or 0) + 1
        during[#during + 1] = ev.kind
    end)

    local health = setmetatable({}, {__mode = 'k'}) -- creature -> the worst it has been
    local noted = setmetatable({}, {__mode = 'k'}) -- creature -> faults already reported
    local broke, faults = {}, 0
    local function fail(fmt, ...) broke[#broke + 1] = string.format(fmt, ...) end

    local csv = {'day,' .. table.concat(cast, ',') .. ',eggs,' .. table.concat(EVENTS, ',')
        .. ',step_p99_ms,step_worst_ms,lua_kb'}
    local memory = {}
    local few, most = math.huge, 0
    local every = 12 -- steps between looks at the bodies (a tenth of a second)
    local steps = math.floor(DAY / api.STEP + 0.5)

    for day = 1, DAYS do
        local times, slowest = {}, {took = 0}
        for s = 1, steps do
            during = {}
            local t0 = love.timer.getTime()
            api.step(api.STEP)
            times[s] = love.timer.getTime() - t0
            if times[s] > slowest.took then -- (when, and what happened in it)
                slowest = {took = times[s], hour = w:hour(), eggs = #w.eggs, what = table.concat(during, ' ')}
            end
            if s % every == 0 then
                local n = #w.eggs
                for i, c in ipairs(w.creatures) do
                    if not w.lives[i].dying then n = n + 1 end
                    for _, p in ipairs(c:interp_points()) do
                        if not (p.x >= 0 and p.x <= width and p.y >= 0 and p.y <= height) then -- (NaN too)
                            fail('day %d: a %s left the jar at (%.0f,%.0f)', day, c.key, p.x, p.y)
                            break
                        end
                    end
                    local class = class_of(World, c.key)
                    health[c] = health[c] or {}
                    class.health(c, health[c], every * api.STEP)
                    for _, f in ipairs(past(class, health[c])) do
                        noted[c] = noted[c] or {}
                        local kind = f:match('^%a+ %a+') -- (one report of each kind of fault a body has)
                        if not noted[c][kind] then
                            noted[c][kind] = true
                            faults = faults + 1
                            say(string.format('[week] day %d %s: a %s %s', day, string.format('%05.2fh', w:hour()), c.key, f))
                        end
                    end
                end
                few, most = math.min(few, n), math.max(most, n)
                if n > World.CAPACITY then fail('day %d: %d in a jar for %d', day, n, World.CAPACITY) end
            end
            if #broke > 0 then break end
        end

        -- The day's end: the living of each kind, and its eggs
        local by, laid = {}, {}
        for i, c in ipairs(w.creatures) do
            if not w.lives[i].dying then by[c.key] = (by[c.key] or 0) + 1 end
        end
        for _, egg in ipairs(w.eggs) do laid[egg.key] = (laid[egg.key] or 0) + 1 end
        for _, key in ipairs(cast) do
            if (by[key] or 0) + (laid[key] or 0) == 0 then fail('day %d: the last %s is gone', day, key) end
        end
        table.sort(times)
        local p99, worst = times[math.ceil(#times * 0.99)] * 1000, times[#times] * 1000
        if p99 > BUDGET * 1000 then fail('day %d: a step took %.2f ms or more one time in a hundred', day, p99) end
        collectgarbage('collect')
        memory[day] = collectgarbage('count')

        local row, said = {tostring(day)}, {}
        for _, key in ipairs(cast) do
            row[#row + 1] = tostring(by[key] or 0)
            said[#said + 1] = string.format('%d %s', by[key] or 0, key)
        end
        row[#row + 1] = tostring(#w.eggs)
        for _, k in ipairs(EVENTS) do row[#row + 1] = tostring(counts[k] or 0) end
        row[#row + 1] = string.format('%.3f', p99)
        row[#row + 1] = string.format('%.3f', worst)
        row[#row + 1] = string.format('%.0f', memory[day])
        csv[#csv + 1] = table.concat(row, ',')
        say(string.format('[week] day %d: %s, %d eggs; %d courted, %d laid, %d hatched, %d moulted, %d returned;'
            .. ' step p99 %.2f ms, worst %.2f ms; lua %.0f KB', day, table.concat(said, ', '), #w.eggs,
            counts.courted or 0, counts.laid or 0, counts.hatched or 0, counts.moulted or 0, counts.returned or 0,
            p99, worst, memory[day]))
        say(string.format('[week]   slowest step at %.2fh, %d eggs in the jar%s', slowest.hour, slowest.eggs,
            slowest.what ~= '' and ', during ' .. slowest.what or ''))
        counts = {}
        if #broke > 0 then break end
    end

    -- Memory that grows day after day is a leak; day 1 is still warming up
    -- (graphs built for the young, the first clutches)
    if #memory == DAYS and memory[DAYS] > GROWTH * memory[2] then
        fail('Lua memory grew from %.0f KB on day 2 to %.0f KB on day %d', memory[2], memory[DAYS], DAYS)
    end

    local file = string.format('week_%d.csv', seed)
    love.filesystem.write(file, table.concat(csv, '\n') .. '\n')
    say(string.format('[week] between %d and %d in the jar; %d bodies past their limits for a while; wrote %s',
        few, most, faults, file))
    if #broke > 0 then
        for _, b in ipairs(broke) do say('[week] FAIL ' .. b) end
        error('the week broke the jar', 0)
    end
    say('[week] a week, and the jar is whole')
end}
