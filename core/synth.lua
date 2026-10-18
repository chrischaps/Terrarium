-- From chrischaps/Character @ 925c35b (core/synth.lua)
-- Procedural audio: every sound is synthesized at load, no files.
--
-- Each creature has a voice (the worm chirps and thumps, the blob squelches,
-- the spider ticks on every footfall) plus a movement loop whose volume and
-- pitch follow its speed. Drips carry their own baked echo, because a cave is
-- mostly echo. Sounds pan with where they happen; creatures you aren't
-- guiding are quieter, so the selected one stays in focus.

local Synth = {}
Synth.__index = Synth

local SAMPLE_RATE = 44100
local rng = require('core.rng')
local sin, exp, pi, min, max, abs = math.sin, math.exp, math.pi, math.min, math.max, math.abs
-- Terrarium: sound draws from the look stream instead of math.random, so audio never touches the sim
local function random(a, b)
    if a then return rng.look:random(a, b) end
    return rng.look:random()
end
local TAU = 2 * pi

local function new_data(duration)
    local n = math.floor(SAMPLE_RATE * duration)
    return love.sound.newSoundData(n, SAMPLE_RATE, 16, 1), n
end

local function clamp(v) return max(-1, min(1, v)) end

-- Render a sound by sample function f(t, i) -> sample
local function render(duration, f)
    local data, n = new_data(duration)
    for i = 0, n - 1 do
        data:setSample(i, clamp(f(i / SAMPLE_RATE, i)))
    end
    return data
end

-- Bake echo taps into a buffer: {delay seconds, gain}
local function with_echo(data, taps)
    local n = data:getSampleCount()
    local extra = 0
    for _, tp in ipairs(taps) do extra = max(extra, tp[1]) end
    local out, total = new_data(n / SAMPLE_RATE + extra + 0.05)
    for i = 0, total - 1 do
        local v = i < n and data:getSample(i) or 0
        for _, tp in ipairs(taps) do
            local j = i - math.floor(tp[1] * SAMPLE_RATE)
            if j >= 0 and j < n then v = v + data:getSample(j) * tp[2] end
        end
        out:setSample(i, clamp(v))
    end
    return out
end

-- One-pole low-pass filtered noise generator
local function lp_noise(amount)
    local y = 0
    return function()
        y = y + ((random() * 2 - 1) - y) * amount
        return y
    end
end

function Synth.new()
    local self = setmetatable({}, Synth)
    love.audio.setDistanceModel('none')
    self.data = {}
    self:generate()
    self.loops = {}
    self.tick_budget = 0
    self.muted = false
    return self
end

function Synth:generate()
    local D = self.data

    -- Worm: rising chirp, soft thump
    D.chirp = render(0.16, function(t)
        local p = t / 0.16
        local f = 300 + p * 320 + sin(t * 45) * 14 * (1 - p)
        local env = min(1, t / 0.008) * (1 - p) ^ 1.5
        return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 1.5 * t) * 0.15) * env * 0.5
    end)
    local nz = lp_noise(0.3)
    D.thump = render(0.2, function(t)
        local f = 120 - t * 300
        local env = min(1, t / 0.004) * exp(-t * 22)
        return (sin(TAU * f * t) * 0.7 + sin(TAU * f * 0.5 * t) * 0.3 + nz() * 0.3 * exp(-t * 40)) * env * 0.7
    end)

    -- Blob: wet squelch and a rubbery boing
    local nz2 = lp_noise(0.08)
    D.squelch = render(0.26, function(t)
        local p = t / 0.26
        local f = 170 - p * 90 + sin(t * 190) * 28 * (1 - p)
        local env = min(1, t / 0.01) * (1 - p) ^ 2
        local body = sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.02 * t)
        return (body * 0.5 + nz2() * 0.9) * env * 0.55
    end)
    D.boing = render(0.3, function(t)
        local p = t / 0.3
        local f = 180 + 260 * (1 - exp(-t * 18)) + sin(t * 70) * 18 * (1 - p)
        local env = min(1, t / 0.006) * (1 - p) ^ 1.8
        return (sin(TAU * f * t) * 0.8 + sin(TAU * f * 0.5 * t) * 0.25) * env * 0.42
    end)

    -- Spider: a dry little tick (several variants for variety)
    D.ticks = {}
    for v = 1, 4 do
        local nz3 = lp_noise(0.9)
        local freq = 1700 + v * 380
        D.ticks[v] = render(0.035, function(t)
            local env = exp(-t * 260)
            return (nz3() * 0.6 + sin(TAU * freq * t) * 0.5) * env * 0.5
        end)
    end
    D.skitter = render(0.12, function(t)
        local env = exp(-t * 30) * (0.5 + 0.5 * sin(TAU * 38 * t))
        return (random() * 2 - 1) * env * 0.3 + sin(TAU * 900 * t) * env * 0.15
    end)

    -- Cave drip with baked echoes
    local drip = render(0.09, function(t)
        local f = 1450 * exp(-t * 9) + 520
        local env = min(1, t / 0.002) * exp(-t * 38)
        return sin(TAU * f * t) * env * 0.55
    end)
    D.drip = with_echo(drip, {{0.11, 0.42}, {0.23, 0.26}, {0.37, 0.15}, {0.55, 0.08}})

    -- Spore puff: breathy band of noise
    local nz4 = lp_noise(0.25)
    D.spores = render(0.45, function(t)
        local env = sin(min(1, t / 0.45) * pi) ^ 2
        return nz4() * env * 0.35
    end)

    -- Soft plucks for UI: a pentatonic bell and a low "nope"
    local function bell(freq, dur)
        return render(dur, function(t)
            local env = min(1, t / 0.004) * exp(-t * 6)
            return (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.76 * t) * 0.15 * exp(-t * 12)
                + sin(TAU * freq * 5.4 * t) * 0.05 * exp(-t * 20)) * env * 0.35
        end)
    end
    D.bells = {bell(523.25, 1.2), bell(587.33, 1.2), bell(659.25, 1.2), bell(783.99, 1.2), bell(880.0, 1.2)}
    D.nope = render(0.22, function(t)
        local env = min(1, t / 0.005) * exp(-t * 14)
        return (sin(TAU * 196 * t) * 0.6 + sin(TAU * 185 * t) * 0.4) * env * 0.32
    end)

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
end

-- Seamless loop: render, then crossfade the tail into the head
function Synth:loop(duration, f)
    local fade = 0.08
    local data, n = new_data(duration)
    local fn = math.floor(SAMPLE_RATE * fade)
    local raw = {}
    for i = 0, n + fn - 1 do raw[i] = f(i / SAMPLE_RATE) end
    for i = 0, n - 1 do
        local v = raw[i]
        if i < fn then
            local w = i / fn
            v = v * w + raw[i + n] * (1 - w)
        end
        data:setSample(i, clamp(v * 0.5))
    end
    return data
end

-- Play a one-shot: x in virtual px for panning, vol, pitch
function Synth:play(data, x, vol, pitch)
    if self.muted or not data then return end
    local src = love.audio.newSource(data, 'static')
    src:setVolume(vol or 1)
    src:setPitch(pitch or 1)
    if x then
        local pan = (x / 960 - 0.5) * 1.6
        src:setPosition(pan, 0, -1)
    end
    src:play()
    return src
end

-- React to world events
function Synth:on_event(ev, selected)
    local who = ev.who
    local focus = (who == nil or who == selected) and 1 or 0.45
    local D = self.data
    local key = who and who.key
    if ev.kind == 'jump' then
        local k = min(1, abs(ev.vy or 300) / 500)
        if key == 'worm' then self:play(D.chirp, ev.x, (0.35 + k * 0.2) * focus, 0.95 + k * 0.15 + random() * 0.05)
        elseif key == 'blob' then self:play(D.boing, ev.x, (0.35 + k * 0.2) * focus, 0.9 + k * 0.2)
        elseif key == 'spider' then self:play(D.skitter, ev.x, 0.4 * focus, 1.2 + random() * 0.2) end
    elseif ev.kind == 'land' then
        local k = min(1, (ev.impact or 0) / 600)
        if key == 'worm' then self:play(D.thump, ev.x, (0.25 + k * 0.45) * focus, 1.15 - k * 0.3)
        elseif key == 'blob' then self:play(D.squelch, ev.x, (0.3 + k * 0.5) * focus, 1.2 - k * 0.45 + random() * 0.08)
        elseif key == 'spider' then self:play(D.skitter, ev.x, (0.2 + k * 0.3) * focus, 0.9) end
    elseif ev.kind == 'step' then
        if self.tick_budget > 0 then
            self.tick_budget = self.tick_budget - 1
            local v = D.ticks[random(1, #D.ticks)]
            self:play(v, ev.x, (ev.near and 0.16 or 0.09) * focus, 0.85 + random() * 0.3)
        end
    elseif ev.kind == 'splash' then
        self:play(D.drip, ev.x, 0.32, 0.85 + random() * 0.35)
    elseif ev.kind == 'spores' then
        self:play(D.spores, ev.x, 0.22, 0.9 + random() * 0.3)
    elseif ev.kind == 'arrived' and who == selected then
        self:play(D.bells[3], ev.x, 0.18, 1)
    end
end

function Synth:chime(i, x)
    self:play(self.data.bells[((i - 1) % #self.data.bells) + 1], x, 0.22, 1)
end

function Synth:nope(x)
    self:play(self.data.nope, x, 0.5, 1)
end

-- Movement loops follow each creature's speed
function Synth:update(dt, world)
    self.tick_budget = math.min(14, self.tick_budget + dt * 14)
    local selected = world:selected_creature()
    for _, c in ipairs(world.creatures) do
        local loop_data = (c.key == 'worm' and self.data.slither) or (c.key == 'blob' and self.data.roll) or nil
        if loop_data then
            local L = self.loops[c]
            if not L then
                local src = love.audio.newSource(loop_data, 'static')
                src:setLooping(true)
                src:setVolume(0)
                src:play()
                L = {src = src, vol = 0}
                self.loops[c] = L
            end
            local m = c.mover
            local speed = (m.state == 'ground') and math.abs(m.vx) / c.profile.walk_speed or 0
            local focus = (c == selected) and 1 or 0.4
            local target = self.muted and 0 or min(1, speed) * 0.22 * focus
            L.vol = L.vol + (target - L.vol) * min(1, dt * 8)
            L.src:setVolume(L.vol)
            L.src:setPitch(0.8 + min(1, speed) * 0.35)
            L.src:setPosition((m.x / 960 - 0.5) * 1.6, 0, -1)
        end
    end
end

return Synth
