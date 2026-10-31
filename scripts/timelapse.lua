-- A month in one jar (#33): the jar from its seed, watched from where you'd
-- stand, for 30 jar days. It opens at dawn just before the lamp comes on, eases
-- from fifteen times life to a jar day every couple of seconds, and slows again
-- for the last night so it ends as it began, with the lamp coming on over a
-- jar whose founders are all back in the moss. Nobody is chosen and nothing is
-- staged: it's the seed's jar, its own month.
--
--   lovec . --script scripts/timelapse.lua [--seed <n>] [--day <sec>] [--cast a,b,c]
--   lovec . --headless --script scripts/timelapse.lua   (the chronicle alone)
--
-- Days are 900 s unless --day says otherwise, long enough that a jar day is
-- a whole day to its creatures (the `day` and `court` tests' length). The
-- cast is the classic one unless --cast gives another.
--
-- In the save directory it leaves:
--   timelapse_<seed>.mp4            the month, 1920 x 1080 at 30 fps (needs ffmpeg on the PATH)
--   timelapse_<seed>.txt            its chronicle: every clutch, hatching, moult and return
--
-- Each frame is SUB renders spread over the jar time it stands for, so a body
-- that crossed the jar meanwhile leaves a trail, as a long shutter would. The
-- tally in the corner gains a stroke each dawn.

local DayCycle = require('jar.daycycle')

local DAYS = 30
local DAY = 900 -- seconds in a jar day, unless --day
local FPS = 30
local SLOW = 0.5 -- jar seconds a frame at the ends: fifteen times life
local FILM_DAY = 2 -- seconds of film a jar day takes at full speed
local EASE = 0.25 -- of a day, to come up to speed and down again
local TAIL = 50 -- jar seconds after the month, at SLOW, for the lamp to come on
local SUB = 4 -- renders a frame
local RW, RH = 2560, 1600 -- rendered, the jar's own 16:10
local OUT = 'crop=2560:1440:0:80,scale=1920:1080:flags=lanczos' -- the frame's cut (core/screen.lua)

-- Jar seconds a frame stands for, `t` seconds into the month: SLOW at either
-- end, eased up to full speed and back on a log scale, as a time-lapse's
-- shutter interval ramps
local function interval(t, day)
    local fast = day / (FILM_DAY * FPS)
    local month = DAYS * day
    local u = math.min(1, t / (EASE * day), (month - t) / (EASE * day))
    if u <= 0 then return SLOW end
    u = u * u * (3 - 2 * u)
    return SLOW * (fast / SLOW) ^ u
end

-- Tally marks, a stroke a day in gates of five, low on the left over the desk
local function tally(days, h)
    local s = h / 1600
    local x0, y0, len, gap = 150 * s, h - 150 * s, 34 * s, 11 * s
    love.graphics.setLineWidth(3 * s)
    love.graphics.setLineStyle('smooth')
    love.graphics.setColor(0.96, 0.9, 0.78, 0.5)
    for d = 1, days do
        local gate, k = math.floor((d - 1) / 5), (d - 1) % 5
        local x = x0 + gate * (5 * gap + 16 * s)
        if k < 4 then
            local lean = (k % 2 == 0) and 1.5 * s or -1 * s -- (by hand)
            love.graphics.line(x + k * gap, y0, x + k * gap + lean, y0 - len)
        else
            love.graphics.line(x - 6 * s, y0 - len * 0.2, x + 3 * gap + 6 * s, y0 - len * 0.8)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function each(t, f)
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = f(v) end
    return table.concat(out, ' ')
end

return {
    run = function(api)
        local seed = api.args.seed or 20261018
        local day = api.args.day or DAY
        local cast = api.args.cast or api.World.CLASSIC
        local headless = require('core.headless').active()
        local w = api.open(seed, 'dawn', nil, day, cast)
        local start = DayCycle.presets.dawn
        local save = love.filesystem.getSaveDirectory()
        local name = 'timelapse_' .. seed

        -- The chronicle, and each one's generation as the month test counts
        -- it: the founders' 0, a child's one more than its elder parent's
        local lines, gen, laid, deepest, founders = {}, {}, {}, 0, 0
        local hatched, returned = 0, 0
        for _, c in ipairs(w.creatures) do gen[c], founders = 0, founders + 1 end
        local function note(fmt, ...)
            local hour = DayCycle.hourAt(start, w.time, day)
            lines[#lines + 1] = string.format('day %2d %02d:%02d  ', math.floor(w.time / day) + 1, math.floor(hour),
                math.floor(hour % 1 * 60)) .. string.format(fmt, ...)
        end
        local function who(c)
            return c.key .. (c.name and (' ' .. c.name) or '') .. ' (gen ' .. (gen[c] or '?') .. ')'
        end
        w.events:on(function(ev)
            if ev.kind == 'laid' then
                for _, egg in ipairs(ev.eggs) do
                    laid[#laid + 1] = { egg = egg, gen = math.max(gen[ev.who] or 0, gen[ev.with] or 0) + 1 }
                end
                note('%s and %s laid %d', who(ev.who), who(ev.with), #ev.eggs)
            elseif ev.kind == 'hatched' then
                for k, l in ipairs(laid) do
                    if l.egg.key == ev.who.key and l.egg.x == ev.x then
                        gen[ev.who], deepest = l.gen, math.max(deepest, l.gen)
                        table.remove(laid, k)
                        break
                    end
                end
                hatched = hatched + 1
                note('a %s hatched', who(ev.who))
            elseif ev.kind == 'moulted' then
                note('a %s moulted%s', who(ev.who), ev.grown and ', grown' or '')
            elseif ev.kind == 'dying' then
                note('a %s lay down for the last time', who(ev.who))
            elseif ev.kind == 'returned' then
                returned = returned + 1
                note('a %s went back to the moss', who(ev.who))
            end
        end)

        -- The film: raw frames into ffmpeg, which cuts and scales them
        local film, accum, out
        if not headless then
            local file = save .. '/' .. name .. '.mp4'
            local cmd = string.format('ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - '
                .. '-vf "%s,format=yuv420p" -c:v libx264 -preset slow -crf 14 -movflags +faststart "%s"',
                RW, RH, FPS, OUT, file)
            if love.system.getOS() == 'Windows' then cmd = '"' .. cmd .. '"' end -- (cmd.exe strips the outer pair)
            film = assert(io.popen(cmd, 'wb'), 'no ffmpeg')
            accum = love.graphics.newCanvas(RW, RH, { format = 'rgba16f' })
            out = love.graphics.newCanvas(RW, RH)
            print('[timelapse] filming to ' .. file)
        end

        local function to(at)
            local n = math.floor((at - w.time) / api.STEP + 0.5)
            if n > 0 then api.step(n * api.STEP) end
        end

        local function frame(t, span)
            if headless then return to(t) end
            love.graphics.setCanvas(accum)
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.setCanvas()
            for k = 1, SUB do
                to(t - span * (SUB - k) / SUB)
                local c = api.render(RW, RH)
                love.graphics.setCanvas(accum)
                love.graphics.setBlendMode('add')
                love.graphics.setColor(1, 1, 1, 1 / SUB)
                love.graphics.draw(c)
                love.graphics.setBlendMode('alpha')
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.setCanvas(out)
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.setBlendMode('alpha', 'premultiplied')
            love.graphics.draw(accum)
            love.graphics.setBlendMode('alpha')
            tally(math.floor(w.time / day), RH)
            love.graphics.setCanvas()
            local data = out:newImageData()
            film:write(data:getString())
            data:release()
            collectgarbage() -- (each frame's copy is 16 MB, more than LuaJIT's heap can let pile up)
            api.yield() -- (and LÖVE presents, or the driver queues every frame it's sent)
        end

        local month, t, frames, t0 = DAYS * day, 0, 0, os.clock()
        local mark = 0
        while t < month + TAIL do
            local span = t < month and interval(t, day) or SLOW
            t = t + span
            frame(t, span)
            frames = frames + 1
            if t >= mark then
                mark = mark + day
                local n = {}
                for _, c in ipairs(w.creatures) do n[c.key] = (n[c.key] or 0) + 1 end
                print(string.format('[timelapse] day %2d: %s, %d eggs (%d frames, %.0fs)', math.floor(t / day) + 1,
                    each(cast, function(key) return (n[key] or 0) .. ' ' .. key .. 's' end), #w.eggs, frames,
                    os.clock() - t0))
            end
        end

        local left = 0
        for _, c in ipairs(w.creatures) do if gen[c] == 0 then left = left + 1 end end
        local summary = string.format('seed %d, %d days of %ds: %d hatched, %d went back to the moss, %d founders '
            .. 'left, %d generations deep; %d frames, %.1fs of film', seed, DAYS, day, hatched, returned, left,
            deepest, frames, frames / FPS)
        table.insert(lines, 1, summary)
        love.filesystem.write(name .. '.txt', table.concat(lines, '\n') .. '\n')
        print('[timelapse] ' .. summary)
        print('[timelapse] chronicle in ' .. save .. '/' .. name .. '.txt')

        if film then film:close() end
    end,
}
