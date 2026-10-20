-- The jar with your eyes closed (#28). One jar from just before lamp-on, its
-- days 900 seconds long, heard onto a tape (core/tape.lua) until it has done
-- everything once, and those moments mixed into listen.wav in the save
-- directory: the lamp coming on and the jar waking, a pinch of food, a
-- courtship and the clutch laid, a hatching, a moult, the lamp going off, a
-- last sigh and the moss taking it back. The first to lay has lived its life
-- by then, so it goes back to the moss in its next sleep; that's the only
-- thing the script does to the jar besides the pinch. Listen first, then read
-- the cue sheet it prints.
--
--   lovec . --headless --script scripts/listen.lua [--seed <n>]

local Synth = require('core.synth')
local Tape = require('core.tape')
local DayCycle = require('jar.daycycle')

local DAY = 900
local OPEN = 5.2   -- the hour it opens at, a little before the lamp's timer
local PINCH = 75   -- s in, a pinch beside the first blob
local LIMIT = 5    -- jar days, at most
local GAP = 2      -- s of quiet between scenes

local function clock(s) return string.format('%d:%02d', math.floor(s / 60), math.floor(s % 60)) end

return {run = function(api)
    local seed = api.args.seed or 20261018
    local w = api.open(seed, OPEN, nil, DAY)
    local tape = Tape.new()
    local synth = Synth.new(tape)
    local first, courts, elder = {}, {}, nil
    w.events:on(function(ev)
        synth:on_event(ev, w)
        local k = ev.kind
        if k == 'court' then courts[#courts + 1] = {at = w.time, who = ev.who, with = ev.with} end
        if k == 'hatched' and not w.young[w:index_of(ev.who)] then return end -- (only a hatchling's)
        if k == 'nibbled' and not first.pinch then return end
        if (k == 'dying' or k == 'returned') and ev.who ~= elder then return end
        if not first[k] then first[k] = {at = w.time, who = ev.who, with = ev.with} end
        -- the first to lay has lived its life
        if k == 'laid' and not elder then
            elder = ev.who
            local life = w.lives[w:index_of(elder)]
            life.born = w.time - life.spared - 0.98 * life.span
        end
    end)

    local lamp, lit = {}, nil
    local steps, done = 0, nil
    while w.time < LIMIT * DAY and not (done and w.time > done) do
        -- (and on a little after it's all happened, for the last scene's end)
        if not done and first.returned and first.moulted and lamp.off then done = w.time + 12 end
        if not first.pinch and w.time >= PINCH then w:pinch((w.creatures[w:first('blob')]:anchor())) end
        api.step(api.STEP)
        synth:update(api.STEP, w)
        local now = DayCycle.lampAt(w:hour()) > Synth.LAMP_ON
        if lit ~= nil and now ~= lit then
            local which = now and 'on' or 'off'
            lamp[which] = lamp[which] or w.time
        end
        lit = now
        steps = steps + 1
        if steps % math.floor(DAY / 4 / api.STEP) == 0 then
            print(string.format('[listen] day %.2f, %d in the jar, %d sounds so far', w.time / DAY, #w.creatures,
                #tape.shots))
        end
    end

    local scenes = {}
    local function scene(title, from, to)
        if from and to then scenes[#scenes + 1] = {title = title, from = math.max(0, from), to = to} end
    end
    if lamp.on then scene('The lamp\'s timer clicks on, it starts to hum, and the jar wakes', lamp.on - 3, lamp.on + 25) end
    if first.pinch then
        local p = first.pinch.at
        local nib = first.nibbled and first.nibbled.at + 5 or p + 25
        scene('A pinch of food: the lid, crumbs pattering down and landing, then nibbling', p - 1, math.min(nib, p + 40))
    end
    if first.courted then
        local start = first.courted.at - 18
        for _, c in ipairs(courts) do
            if c.at <= first.courted.at and (c.who == first.courted.who or c.with == first.courted.who) then start = c.at end
        end
        scene(string.format('Two %ss court on their beat, they\'ve courted, and a clutch is laid', first.courted.who.key),
            start - 3, first.courted.at + (first.laid and 4 or 3))
    end
    if first.hatched then
        scene(string.format('An egg cracks and a %s hatchling peeps', first.hatched.who.key), first.hatched.at - 3,
            first.hatched.at + 6)
    end
    if first.moulted then
        scene(string.format('A young %s moults in its sleep, its voice a little lower', first.moulted.who.key),
            first.moulted.at - 3, first.moulted.at + 5)
    end
    if lamp.off then scene('Evening: the timer clicks off, the hum goes, the jar settles', lamp.off - 6, lamp.off + 10) end
    if first.dying then
        scene(string.format('An old %s lies down for the last time', first.dying.who.key), first.dying.at - 3,
            first.dying.at + 6)
    end
    if first.returned then
        scene('It goes back to the moss', first.returned.at - 2, first.returned.at + 8)
    end
    table.sort(scenes, function(a, b) return a.from < b.from end)

    local cues, gain = tape:bounce(scenes, 'listen.wav', GAP)
    print(string.format('[listen] seed %d, %.2f jar days, %d sounds; mixed %d scenes at %+.1f dB', seed,
        w.time / DAY, #tape.shots, #scenes, 20 * math.log10(gain)))
    for k, c in ipairs(cues) do
        local s = scenes[k]
        print(string.format('[listen]   %s  %s   (day %.2f, hour %.1f)', clock(c.at), c.title, s.from / DAY,
            DayCycle.hourAt(OPEN, s.from, DAY)))
    end
    print('[listen] saved ' .. love.filesystem.getSaveDirectory() .. '/listen.wav')
end}
