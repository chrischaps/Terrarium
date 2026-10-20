-- From chrischaps/Character @ 925c35b (core/synth.lua)
-- Procedural audio: every sound is synthesized at load, no files.
--
-- Each creature has a voice (the worm chirps and thumps, the blob squelches,
-- the spider ticks on every footfall) plus a movement loop whose volume and
-- pitch follow its speed. Sounds pan with where they happen; creatures you aren't
-- guiding are quieter, so the selected one stays in focus.
--
-- Terrarium: the jar, heard through its glass (#28). Every sound is baked
-- through two poles of low-pass and the jar's own small hollow ring, and it
-- all plays quieter than Character's cave. A body's genes, as they are now,
-- shape its voice (Synth.voice): a bigger body is lower and a little louder, a
-- hatchling is high and small and deepens as it moults, and an elder's voice
-- drops. The body's give picks one of three variants: a stiff worm chirps
-- crisply and a loose one warbles, a firm blob rings and a soft one squelches,
-- four legs knock and eight patter. Then there are the jar's own sounds: the
-- lamp's timer and its hum, a pinch through the lid and the crumbs coming
-- down, courtship kept on its beat (a worm sings at the top of each coil, a
-- blob hums as it swells, a spider's foot taps), a clutch laid, a hatching, a
-- moult, a last sigh, and the moss taking it back.
--
-- It only listens. It hears the World's events and reads its state, never
-- writes to either, and draws from rng.sound, so a jar heard is the same jar
-- unheard. With a tape (core/tape.lua) it records instead of playing, for
-- scripts/listen.lua.

local Synth = {}
Synth.__index = Synth

local SAMPLE_RATE = 44100
Synth.SAMPLE_RATE = SAMPLE_RATE
local rng = require('core.rng')
local C = require('jar.config')
local DayCycle = require('jar.daycycle')
local Genome = require('genome')
local sin, cos, exp, pi, min, max, abs, floor = math.sin, math.cos, math.exp, math.pi, math.min, math.max, math.abs, math.floor
-- Terrarium: sound draws from its own stream, so it never touches the sim or the look of the jar
local function random(a, b)
    if a then return rng.sound:random(a, b) end
    return rng.sound:random()
end
local TAU = 2 * pi

-- Terrarium: the glass between you and the jar (#28)
local GLASS = {
    cut = 1700,              -- Hz, where the low-pass starts to bite (two poles of it)
    rings = {0.0029, 0.0041}, -- s, the jar's hollow: two short combs
    ring = 0.3,              -- how much each comb feeds back
    tail = 0.04,             -- s of ring after a sound ends
}
local QUIET = 0.6      -- everything, against Character's levels
local LAMP_ON = 0.05   -- the lamp's brightness its timer clicks at
Synth.LAMP_ON = LAMP_ON
local HUM = 0.03       -- the lamp's hum at full brightness
local MOVE = 0.2       -- jumps, landings and footfalls, under the jar's events
local STIR = 0.4       -- the worms' and blobs' movement loops, under those

local function clamp(v) return max(-1, min(1, v)) end

local function to_data(samples, n)
    local data = love.sound.newSoundData(n, SAMPLE_RATE, 16, 1)
    for i = 0, n - 1 do data:setSample(i, clamp(samples[i])) end
    return data
end

-- Terrarium: muffled by the glass and ringing a little in the jar's hollow
local function through_glass(raw, n)
    local a = 1 - exp(-TAU * GLASS.cut / SAMPLE_RATE)
    local d1, d2 = floor(GLASS.rings[1] * SAMPLE_RATE), floor(GLASS.rings[2] * SAMPLE_RATE)
    local y1, y2, c1, c2, out = 0, 0, {}, {}, {}
    for i = 0, n - 1 do
        y1 = y1 + ((raw[i] or 0) - y1) * a
        y2 = y2 + (y1 - y2) * a
        c1[i] = y2 + (c1[i - d1] or 0) * GLASS.ring
        c2[i] = y2 + (c2[i - d2] or 0) * GLASS.ring
        out[i] = (y2 + c1[i] + c2[i]) * 0.4
    end
    return out
end

-- Render a sound by sample function f(t, i) -> sample
-- (Terrarium: through the glass, and every one to the same peak, so how loud
-- it plays is only ever its `vol` in Synth:play)
local PEAK = 0.7
local function render(duration, f)
    local n = floor(SAMPLE_RATE * duration)
    local raw = {}
    for i = 0, n - 1 do raw[i] = f(i / SAMPLE_RATE, i) end
    local total = n + floor(GLASS.tail * SAMPLE_RATE)
    local out, peak = through_glass(raw, total), 1e-6
    for i = 0, total - 1 do peak = max(peak, abs(out[i])) end
    for i = 0, total - 1 do out[i] = out[i] * PEAK / peak end
    return to_data(out, total)
end

-- One-pole low-pass filtered noise generator
local function lp_noise(amount)
    local y = 0
    return function()
        y = y + ((random() * 2 - 1) - y) * amount
        return y
    end
end

-- Terrarium: a crackle, `count` dry grains scattered over `dur`
local function grains(count, dur)
    local at = {}
    for k = 1, count do at[k] = random() * dur end
    table.sort(at)
    return function(t)
        local v = 0
        for _, g in ipairs(at) do
            local dt = t - g
            if dt >= 0 and dt < 0.012 then v = v + (random() * 2 - 1) * exp(-dt * 500) end
        end
        return v
    end
end

function Synth.new(tape)
    local self = setmetatable({}, Synth)
    self.tape = tape -- Terrarium: record onto this instead of playing (#28)
    if not tape then love.audio.setDistanceModel('none') end
    self.data = {}
    self:generate()
    self.loops = {}
    self.tick_budget = 0
    self.muted = false
    -- Terrarium
    self.clock = 0      -- seconds it has heard, for sounds that come a moment later
    self.later = {}     -- those sounds, soonest first
    self.beats = {}     -- creature -> the last courtship beat it sounded
    self.down = {}      -- crumb id -> it has been heard to land
    return self
end

-- Terrarium: three of a sound, from one end of a gene's travel to the other
local function three(f)
    return {f(0), f(0.5), f(1)}
end

function Synth:generate()
    local D = self.data

    -- Worm: rising chirp (Terrarium: loose ones warble, stiff ones are crisp
    -- and bright), soft thump
    D.chirp = three(function(k)
        return render(0.16 + 0.06 * (1 - k), function(t)
            local dur = 0.16 + 0.06 * (1 - k)
            local p = t / dur
            local f = 300 + p * 320 + sin(t * (45 - 15 * k)) * (34 - 26 * k) * (1 - p)
            local env = min(1, t / (0.02 - 0.014 * k)) * (1 - p) ^ 1.5
            return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 1.5 * t) * (0.05 + 0.2 * k)
                + sin(TAU * f * 2 * t) * 0.12 * k) * env * 0.5
        end)
    end)
    local nz = lp_noise(0.3)
    D.thump = render(0.2, function(t)
        local f = 120 - t * 300
        local env = min(1, t / 0.004) * exp(-t * 22)
        return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 0.5 * t) * 0.3 + nz() * 0.3 * exp(-t * 40)) * env * 0.7
    end)

    -- Blob: wet squelch and a rubbery boing (Terrarium: a soft blob is wetter
    -- and wobbles longer, a firm one rings tighter)
    D.squelch = three(function(k)
        local nz2 = lp_noise(0.08)
        return render(0.26, function(t)
            local p = t / 0.26
            local f = 170 - p * 90 + sin(t * 190) * 28 * (1 - p)
            local env = min(1, t / 0.01) * (1 - p) ^ 2
            local body = sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.02 * t)
            return (body * (0.3 + 0.5 * k) + nz2() * (1.2 - 0.7 * k)) * env * 0.55
        end)
    end)
    D.boing = three(function(k)
        local dur = 0.36 - 0.1 * k
        return render(dur, function(t)
            local p = t / dur
            local f = 180 + 260 * (1 - exp(-t * (12 + 12 * k))) + sin(t * (50 + 40 * k)) * (30 - 20 * k) * (1 - p)
            local env = min(1, t / 0.006) * (1 - p) ^ 1.8
            return (sin(TAU * f * t) * 0.8 + sin(TAU * f * 0.5 * t) * 0.25) * env * 0.42
        end)
    end)

    -- Spider: a dry little tick, several variants for variety (Terrarium: four
    -- legs knock lower and longer, eight patter light)
    D.ticks = three(function(k)
        local set = {}
        for v = 1, 4 do
            local nz3 = lp_noise(0.9)
            local freq = 900 + 700 * k + v * (200 + 180 * k)
            local decay = 140 + 160 * k
            set[v] = render(0.05 - 0.015 * k, function(t)
                local env = exp(-t * decay)
                return (nz3() * 0.6 + sin(TAU * freq * t) * 0.5) * env * 0.5
            end)
        end
        return set
    end)
    D.skitter = render(0.12, function(t)
        local env = exp(-t * 30) * (0.5 + 0.5 * sin(TAU * 38 * t))
        return (random() * 2 - 1) * env * 0.3 + sin(TAU * 900 * t) * env * 0.15
    end)

    -- Spore puff: breathy band of noise
    local nz4 = lp_noise(0.25)
    D.spores = render(0.45, function(t)
        local env = sin(min(1, t / 0.45) * pi) ^ 2
        return nz4() * env * 0.35
    end)

    -- Soft plucks for UI: a pentatonic bell (Terrarium: the lantern's)
    local function bell(freq, dur)
        return render(dur, function(t)
            local env = min(1, t / 0.004) * exp(-t * 6)
            return (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.76 * t) * 0.15 * exp(-t * 12)
                + sin(TAU * freq * 5.4 * t) * 0.05 * exp(-t * 20)) * env * 0.35
        end)
    end
    D.bells = {bell(523.25, 1.2), bell(587.33, 1.2), bell(659.25, 1.2), bell(783.99, 1.2), bell(880.0, 1.2)}

    -- Movement loops: worm slither (wet, low) and blob roll (burbly)
    local nz5 = lp_noise(0.12)
    D.slither = self:loop(0.6, function(t)
        local g = sin(TAU * 140 * t + sin(TAU * 7 * t) * 0.6) * 0.12
        return g + nz5() * 0.5
    end)
    local nz6 = lp_noise(0.05)
    D.roll = self:loop(0.5, function(t)
        local wob = 0.5 + 0.5 * sin(TAU * 8 * t)
        return (sin(TAU * 90 * t) * 0.25 + nz6() * 0.9) * (0.4 + 0.6 * wob)
    end)

    -- Terrarium: courtship (#22), each on its body's beat. A worm sings a
    -- little rising warble at the top of each coil, a blob hums as it swells,
    -- a spider's front foot taps.
    D.trill = render(0.42, function(t)
        local p = t / 0.42
        local f = (p < 0.45 and 520 or 690) * (1 + 0.012 * sin(TAU * 17 * t))
        local env = min(1, t / 0.03) * (1 - p) ^ 1.2 * (0.75 + 0.25 * sin(TAU * 17 * t))
        return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2 * t) * 0.12) * env * 0.4
    end)
    D.hum = render(1.0, function(t)
        local f = 150 + 18 * t
        local env = sin(min(1, t) * pi) ^ 2
        return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2 * t) * 0.25 + sin(TAU * f * 3 * t) * 0.08) * env * 0.5
    end)
    local nz7 = lp_noise(0.6)
    D.tap = render(0.08, function(t)
        local f = 720 - t * 2400
        local env = min(1, t / 0.001) * exp(-t * 90)
        return (sin(TAU * f * t) * 0.7 + nz7() * 0.4 * exp(-t * 300)) * env * 0.55
    end)
    -- They've courted: a soft glassy tone, sounded as a rising arpeggio
    D.tone = render(1.8, function(t)
        local f = 392
        local env = min(1, t / 0.04) * exp(-t * 2.4)
        return (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2 * t) * 0.18 * exp(-t * 3)
            + sin(TAU * f * 3 * t) * 0.06 * exp(-t * 5)) * env * 0.4
    end)

    -- Terrarium: eggs (#23). A clutch laid is a few soft wet plips; a hatching
    -- is a dry crack, then a small peep (the plan's voice, high); a moult is a
    -- papery rustle.
    D.plip = render(0.1, function(t)
        local f = 380 + 700 * (1 - exp(-t * 40))
        local env = min(1, t / 0.003) * exp(-t * 45)
        return sin(TAU * f * t) * env * 0.5
    end)
    local crack = grains(7, 0.13)
    D.crack = render(0.16, function(t)
        return crack(t) * 0.45
    end)
    local nz8 = lp_noise(0.5)
    local crinkle = grains(24, 0.6)
    D.rustle = render(0.65, function(t)
        local env = sin(min(1, t / 0.65) * pi)
        return (nz8() * 0.25 + crinkle(t) * 0.3) * env * 0.5
    end)

    -- Terrarium: going back to the moss (#24). A last long sigh as it lies
    -- down; when it's gone, a hush like air over moss under a warm low chord,
    -- and its spores.
    local nz9 = lp_noise(0.06)
    D.sigh = render(2.4, function(t)
        local env = min(1, t / 0.7) ^ 2 * exp(-max(0, t - 0.7) * 1.8)
        local f = 220 - 60 * min(1, t / 2.4)
        return (nz9() * 0.9 + sin(TAU * f * t) * 0.18) * env * 0.5
    end)
    local nz10 = lp_noise(0.03)
    D.hush = render(4.0, function(t)
        local env = sin(min(1, t / 4.0) * pi) ^ 2
        local chord = sin(TAU * 110 * t) * 0.3 + sin(TAU * 164.8 * t) * 0.2 + sin(TAU * 220.5 * t) * 0.14
        return (nz10() * 1.2 + chord * (0.6 + 0.4 * sin(TAU * 0.4 * t))) * env * 0.4
    end)

    -- Terrarium: a pinch (#25). The lid's glass knocked as it's lifted, the
    -- crumbs pattering in, each one landing soft, and nibbling.
    D.lid = render(1.0, function(t)
        local env = min(1, t / 0.002) * exp(-t * 5)
        return (sin(TAU * 1180 * t) * 0.5 + sin(TAU * 2950 * t) * 0.2 * exp(-t * 6)
            + sin(TAU * 4700 * t) * 0.1 * exp(-t * 12)) * env * 0.4
    end)
    local patter = grains(16, 0.8)
    D.sprinkle = render(0.9, function(t)
        return patter(t) * 0.3 * (1 - t / 0.9)
    end)
    D.pat = render(0.04, function(t)
        local env = exp(-t * 160)
        return (random() * 2 - 1) * env * 0.35 + sin(TAU * 600 * t) * env * 0.2
    end)
    local bites = grains(3, 0.16)
    D.nibble = render(0.2, function(t)
        return bites(t) * 0.5
    end)

    -- Terrarium: the lamp (#3). Its timer clicks as it comes on and goes off,
    -- and it hums faintly while it burns.
    D.click = render(0.06, function(t)
        local env = min(1, t / 0.0005) * exp(-t * 120)
        return (sin(TAU * 140 * t) * 0.6 + (random() * 2 - 1) * 0.5 * exp(-t * 600)) * env * 0.6
    end)
    D.buzz = self:loop(1.0, function(t)
        return sin(TAU * 100 * t) * 0.5 + sin(TAU * 200 * t) * 0.2 + sin(TAU * 300 * t) * 0.08
    end)
end

-- Seamless loop: render, then crossfade the tail into the head
-- (Terrarium: through the glass before the crossfade, so the seam is too)
function Synth:loop(duration, f)
    local fade = 0.08
    local n = floor(SAMPLE_RATE * duration)
    local fn = floor(SAMPLE_RATE * fade)
    local raw = {}
    for i = 0, n + fn - 1 do raw[i] = f(i / SAMPLE_RATE) end
    raw = through_glass(raw, n + fn)
    local out = {}
    for i = 0, n - 1 do
        local v = raw[i]
        if i < fn then
            local w = i / fn
            v = v * w + raw[i + n] * (1 - w)
        end
        out[i] = v * 0.5
    end
    return to_data(out, n)
end

-- Terrarium: where across the jar x is, from -0.8 (left) to 0.8
local function pan_of(x)
    return ((x - C.GLASS_L) / (C.GLASS_R - C.GLASS_L) - 0.5) * 1.6
end

-- Play a one-shot: x in level units for panning, vol, pitch
-- (Terrarium: `delay` seconds from now; onto the tape if there is one)
function Synth:play(data, x, vol, pitch, delay)
    if self.muted or not data then return end
    if delay and delay > 0 then
        local at = self.clock + delay
        local k = #self.later + 1
        while k > 1 and self.later[k - 1].at > at do k = k - 1 end
        table.insert(self.later, k, {at = at, data = data, x = x, vol = vol, pitch = pitch})
        return
    end
    vol = (vol or 1) * QUIET
    local pan = x and pan_of(x) or 0
    if self.tape then
        self.tape:add(self.clock, data, vol, pitch or 1, pan)
        return
    end
    local src = love.audio.newSource(data, 'static')
    src:setVolume(vol)
    src:setPitch(pitch or 1)
    src:setPosition(pan, 0, -1)
    src:play()
    return src
end

-- Terrarium: how far along its range a gene is, 0 to 1
local function along(key, genome, name)
    local gene = Genome[key].by_name[name]
    local r = gene.real or gene.int or {gene.pick[1], gene.pick[#gene.pick]}
    local v = genome and genome[name]
    if not v then return 0.5 end
    return max(0, min(1, (v - r[1]) / (r[2] - r[1])))
end

-- Terrarium: a body's voice (#28), from its genes as they are now (a
-- hatchling's are the bottom of their ranges) and how old it is (0 until
-- it's an elder, 1 at its end). Its pitch spans about an octave across the
-- size gene's range, and an elder's falls a fifth of one; a bigger body is a
-- little louder; `kind` (1 to 3) is the variant its give speaks with.
local SIZE = {worm = {'segments', 1.0}, blob = {'size', 1.2}, spider = {'reach', 0.9}}
local GIVE = {worm = 'stiffness', blob = 'pressure', spider = 'legs'}
function Synth.voice(c, old)
    local size, octaves = SIZE[c.key][1], SIZE[c.key][2]
    local t = along(c.key, c.genome, size)
    local pitch = 2 ^ (octaves * (0.5 - t) - 0.2 * (old or 0))
    local kind = 1 + floor(along(c.key, c.genome, GIVE[c.key]) * 2.999)
    return {pitch = pitch, gain = 0.85 + 0.3 * t, kind = kind}
end

-- Terrarium: the voice of creature `c` in `world` now
local function voice_of(world, c)
    local i = world and world:index_of(c)
    local old = 0
    if i and world.lives[i] then old = select(2, world:age_of(i)) end
    return Synth.voice(c, old)
end

-- Terrarium: how loud one creature is against the rest. The one the lantern
-- follows stands out; with nobody followed, everyone is heard alike.
local function heed(who, focus)
    if not who or not focus then return 1 end
    return who == focus and 1.2 or 0.5
end

-- Terrarium: a plan's voice, the sound it jumps with
local function call_of(D, key, v)
    if key == 'worm' then return D.chirp[v.kind]
    elseif key == 'blob' then return D.boing[v.kind] end
    return D.skitter
end

-- React to world events
-- (Terrarium: `world` to read voices from, and `focus`, the creature the lantern follows)
function Synth:on_event(ev, world, focus)
    local who = ev.who
    local near = heed(who, focus)
    local D = self.data
    local key = who and who.key
    local v = who and voice_of(world, who)
    if ev.kind == 'jump' then
        local k = min(1, abs(ev.vy or 300) / 500)
        near = near * MOVE
        local vol, p = (0.35 + k * 0.2) * near * v.gain, v.pitch
        if key == 'worm' then self:play(D.chirp[v.kind], ev.x, vol, p * (0.95 + k * 0.15 + random() * 0.05))
        elseif key == 'blob' then self:play(D.boing[v.kind], ev.x, vol, p * (0.9 + k * 0.2))
        elseif key == 'spider' then self:play(D.skitter, ev.x, 0.4 * near * v.gain, p * (1.2 + random() * 0.2)) end
    elseif ev.kind == 'land' then
        local k = min(1, (ev.impact or 0) / 600)
        local p = v.pitch
        near = near * MOVE
        if key == 'worm' then self:play(D.thump, ev.x, (0.25 + k * 0.45) * near * v.gain, p * (1.15 - k * 0.3))
        elseif key == 'blob' then
            self:play(D.squelch[v.kind], ev.x, (0.3 + k * 0.5) * near * v.gain, p * (1.2 - k * 0.45 + random() * 0.08))
        elseif key == 'spider' then self:play(D.skitter, ev.x, (0.2 + k * 0.3) * near * v.gain, p * 0.9) end
    elseif ev.kind == 'step' then
        if self.tick_budget > 0 then
            self.tick_budget = self.tick_budget - 1
            local set = D.ticks[v.kind]
            self:play(set[random(1, #set)], ev.x, (ev.near and 0.16 or 0.09) * near * MOVE * v.gain,
                v.pitch * (0.85 + random() * 0.3))
        end
    elseif ev.kind == 'courted' then
        -- a rising arpeggio from the pair, one note each and then both
        local o = voice_of(world, ev.with)
        local ox = ev.with:anchor()
        local p = v.pitch
        self:play(D.tone, ev.x, 0.32 * near, p)
        self:play(D.tone, ox, 0.28 * near, p * 1.5, 0.22)
        self:play(D.tone, (ev.x + ox) / 2, 0.22 * near, p * 2, 0.44)
        self:play(D.tone, (ev.x + ox) / 2, 0.12 * near, o.pitch * 1.5, 0.44)
    elseif ev.kind == 'laid' then
        for k = 1, #ev.eggs do
            self:play(D.plip, ev.eggs[k].x or ev.x, 0.25, 0.9 + random() * 0.25, 1.2 + (k - 1) * 0.18)
        end
    elseif ev.kind == 'hatched' then
        self:play(D.crack, ev.x, 0.3, 0.9 + random() * 0.2)
        self:play(call_of(D, key, v), ev.x, 0.3 * near, v.pitch * 1.2, 0.2)
    elseif ev.kind == 'moulted' then
        self:play(D.rustle, ev.x, 0.3 * near, 0.9 + random() * 0.2)
        self:play(call_of(D, key, v), ev.x, 0.3 * near, v.pitch, 0.6)
    elseif ev.kind == 'dying' then
        self:play(D.sigh, ev.x, 0.35 * near, v.pitch * 0.9)
    elseif ev.kind == 'returned' then
        self:play(D.hush, ev.x, 0.4, 1)
        self:play(D.spores, ev.x, 0.3, 0.9 + random() * 0.3, 1.2)
        self:play(D.spores, ev.x, 0.2, 0.8 + random() * 0.3, 2.2)
    elseif ev.kind == 'nibbled' then
        self:play(D.nibble, ev.x, 0.2 * near, 0.85 + random() * 0.35)
    elseif ev.kind == 'pinch' then
        self:play(D.lid, ev.x, 0.3, 1)
        self:play(D.sprinkle, ev.x, 0.25, 0.95 + random() * 0.1, 0.3)
    end
end

-- Terrarium: the lantern lifted to someone
function Synth:chime(x)
    self:play(self.data.bells[random(1, #self.data.bells)], x, 0.18, 1)
end

-- Terrarium: silence, or not
function Synth:mute(on)
    self.muted = on
    if on then self.later = {} end
end

-- Terrarium: a looping source (or its stand-in on the tape), silent until set
function Synth:start(data)
    if self.tape then return {tape = true, data = data, vol = 0, pitch = 1, pan = 0} end
    local src = love.audio.newSource(data, 'static')
    src:setLooping(true)
    src:setVolume(0)
    src:play()
    return {src = src, vol = 0}
end

function Synth:set(L, vol, pitch, pan)
    L.vol, L.pitch, L.pan = vol, pitch, pan
    if L.tape then
        self.tape:loop(L, self.clock, vol * QUIET, pitch, pan)
    else
        L.src:setVolume(vol * QUIET)
        L.src:setPitch(pitch)
        L.src:setPosition(pan, 0, -1)
    end
end

function Synth:stop(L)
    if L.src then L.src:stop() else self:set(L, 0, L.pitch, L.pan) end
end

-- Terrarium: a courting body sounds on its beat (#22), louder as it warms to it
function Synth:court(world, i, c, near)
    local m = world.minds[i]
    if m.doing ~= 'court' or not m.with or (c.ardour or 0) < 0.3 then
        self.beats[c] = nil
        return
    end
    local D, v, t = self.data, voice_of(world, c), world.time
    local beat, data, vol, pitch
    if c.key == 'worm' then
        -- at the top of each turn of its coil, half a turn from its partner's
        local a = t * c.COIL_SPIN + (i < m.with and 0 or pi) - pi / 2
        beat, data, vol, pitch = floor(a / TAU), D.trill, 0.24, v.pitch
    elseif c.key == 'blob' then
        beat, data, vol, pitch = floor(t / c.PULSE), D.hum, 0.2, v.pitch
    else
        -- as each front foot comes down, the near and then the far
        beat = floor(t / c.TAP_BEAT)
        data, vol, pitch = D.tap, 0.16, v.pitch * (beat % 2 == 0 and 1 or 0.84)
    end
    local last = self.beats[c]
    self.beats[c] = beat
    if last and beat ~= last then
        local x = c:anchor()
        self:play(data, x, vol * c.ardour * near * v.gain, pitch)
    end
end

-- Movement loops follow each creature's speed
-- (Terrarium: and the jar's own sounds, courtship, and the sounds that come a
-- moment later. `focus` is the creature the lantern follows.)
function Synth:update(dt, world, focus)
    self.clock = self.clock + dt
    while self.later[1] and self.later[1].at <= self.clock do
        local s = table.remove(self.later, 1)
        self:play(s.data, s.x, s.vol, s.pitch)
    end
    self.tick_budget = math.min(14, self.tick_budget + dt * 14)

    -- The lamp: its timer clicks as it comes on or goes off, and it hums
    local lamp = DayCycle.lampAt(world:hour())
    local lit = lamp > LAMP_ON
    if self.lit ~= nil and lit ~= self.lit then self:play(self.data.click, C.GLASS_R, 0.3, lit and 1 or 0.85) end
    self.lit = lit
    self.hum = self.hum or self:start(self.data.buzz)
    self:set(self.hum, self.muted and 0 or lamp * HUM, 1, 0)

    -- Each crumb, as it lands
    local down = {}
    for _, f in ipairs(world.food.crumbs) do
        if f.down then
            if not self.down[f.id] and world.time - f.at < 1 then
                self:play(self.data.pat, f.x, 0.12, 0.8 + random() * 0.5)
            end
            down[f.id] = true
        end
    end
    self.down = down

    local live = {}
    for i, c in ipairs(world.creatures) do
        live[c] = true
        local near = heed(c, focus)
        self:court(world, i, c, near)
        local loop_data = (c.key == 'worm' and self.data.slither) or (c.key == 'blob' and self.data.roll) or nil
        if loop_data and c.mover then
            local L = self.loops[c]
            if not L then
                L = self:start(loop_data)
                self.loops[c] = L
            end
            local m = c.mover
            local speed = (m.state == 'ground') and math.abs(m.vx) / c.profile.walk_speed or 0
            local v = voice_of(world, c)
            local target = self.muted and 0 or min(1, speed) * 0.22 * STIR * near * v.gain * (1 - world:fading(i))
            L.vol = L.vol + (target - L.vol) * min(1, dt * 8)
            self:set(L, L.vol, (0.8 + min(1, speed) * 0.35) * v.pitch, pan_of(m.x))
        end
    end
    -- (and the ones gone back to the moss go quiet)
    for c, L in pairs(self.loops) do
        if not live[c] then
            self:stop(L)
            self.loops[c], self.beats[c] = nil, nil
        end
    end
end

return Synth
