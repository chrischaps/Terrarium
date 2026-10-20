-- Terrarium: a tape for the synth (#28). Given one, the synth plays nothing:
-- it writes each sound onto the tape with the moment it was heard, and each
-- loop's volume, pitch and pan as they change. `bounce` mixes chosen
-- stretches of the tape into a stereo WAV in the save directory, one after
-- another with a breath of silence between, so a jar can be listened to with
-- your eyes closed (scripts/listen.lua). Pitch is a resample and pan is equal
-- power, near enough to what OpenAL does live.

local ffi = require('ffi')

local Tape = {}
Tape.__index = Tape

local floor, min, max, cos, sin, pi = math.floor, math.min, math.max, math.cos, math.sin, math.pi
local RATE = 44100
local EVERY = 1 / 30 -- s between the points a loop keeps
local FADE = 0.02    -- s each scene fades in over

function Tape.new()
    return setmetatable({shots = {}, tracks = {}, by_loop = {}}, Tape)
end

function Tape:add(at, data, vol, pitch, pan)
    self.shots[#self.shots + 1] = {at = at, data = data, vol = vol, pitch = pitch, pan = pan}
end

-- A loop's level at `at`. Kept in flat lists, about thirty points a second
-- while it's heard and one when it falls silent.
function Tape:loop(L, at, vol, pitch, pan)
    local tr = self.by_loop[L]
    if not tr then
        tr = {data = L.data, at = {}, vol = {}, pitch = {}, pan = {}, n = 0}
        self.by_loop[L] = tr
        self.tracks[#self.tracks + 1] = tr
    end
    local n = tr.n
    if n > 0 then
        local quiet = vol < 1e-4 and tr.vol[n] < 1e-4
        if quiet or at - tr.at[n] < EVERY then return end
    end
    n = n + 1
    tr.at[n], tr.vol[n], tr.pitch[n], tr.pan[n], tr.n = at, vol, pitch, pan, n
end

-- A sound's samples as a list, read from its SoundData once
local cache = setmetatable({}, {__mode = 'k'})
local function samples(data)
    local s = cache[data]
    if s then return s end
    s = {}
    local n = data:getSampleCount()
    for i = 0, n - 1 do s[i] = data:getSample(i) end
    s.n = n
    cache[data] = s
    return s
end

local function gains(pan)
    local a = (max(-1, min(1, pan)) + 1) * pi / 4
    return cos(a), sin(a)
end

-- Mix `src` into `mix` from frame j0 (not past `stop`), stepping through it at
-- `pitch` (and from `pos` in it, for a loop, which wraps)
local function mix_in(mix, src, j0, stop, vol0, vol1, pitch, pan, pos, wrap)
    local gl, gr = gains(pan)
    local n, len = src.n, stop - j0
    for j = j0, stop - 1 do
        local i = floor(pos)
        if i >= n - 1 then
            if not wrap then break end
            pos = pos - (n - 1)
            i = floor(pos)
        end
        local f = pos - i
        local v = (src[i] + (src[i + 1] - src[i]) * f) * (vol0 + (vol1 - vol0) * (j - j0) / len)
        if j >= 0 then
            mix[2 * j] = mix[2 * j] + v * gl
            mix[2 * j + 1] = mix[2 * j + 1] + v * gr
        end
        pos = pos + pitch
    end
    return pos
end

local function le(v, bytes)
    local out = {}
    for k = 1, bytes do
        out[k] = string.char(v % 256)
        v = floor(v / 256)
    end
    return table.concat(out)
end

-- Mix `scenes` ({title, from, to} in tape seconds) into `file`, each followed
-- by `gap` seconds that its last sounds ring into. Normalised to just under
-- full scale. Returns where each scene starts in the file, and the gain.
function Tape:bounce(scenes, file, gap)
    gap = gap or 1.5
    local total = 0
    for _, s in ipairs(scenes) do total = total + (s.to - s.from) + gap end
    local frames = floor(total * RATE)
    local mix = ffi.new('float[?]', frames * 2)
    local cues, offset = {}, 0
    for _, s in ipairs(scenes) do
        local o = floor(offset * RATE)
        local len = floor((s.to - s.from) * RATE)
        local stop = min(frames, o + len + floor(gap * RATE))
        cues[#cues + 1] = {at = offset, title = s.title}
        -- what was heard in the scene, ringing on into the gap
        for _, shot in ipairs(self.shots) do
            if shot.at >= s.from and shot.at < s.to then
                local j0 = o + floor((shot.at - s.from) * RATE)
                mix_in(mix, samples(shot.data), j0, stop, shot.vol, shot.vol, shot.pitch, shot.pan, 0, false)
            end
        end
        -- and the loops, only within it
        for _, tr in ipairs(self.tracks) do
            local src, pos = samples(tr.data), 0
            for k = 1, tr.n do
                local t0, t1 = tr.at[k], tr.at[k + 1] or (tr.at[k] + EVERY)
                local v0, v1 = tr.vol[k], tr.vol[k + 1] or tr.vol[k]
                if t1 > s.from and t0 < s.to and (v0 > 1e-4 or v1 > 1e-4) then
                    local a, b = max(t0, s.from), min(t1, s.to)
                    local va = v0 + (v1 - v0) * (a - t0) / (t1 - t0)
                    local vb = v0 + (v1 - v0) * (b - t0) / (t1 - t0)
                    local j0, j1 = o + floor((a - s.from) * RATE), o + floor((b - s.from) * RATE)
                    if j1 > j0 then pos = mix_in(mix, src, j0, j1, va, vb, tr.pitch[k], tr.pan[k], pos, true) end
                end
            end
        end
        -- in softly, and out to silence by the end of the gap
        local fade = floor(FADE * RATE)
        for j = o, stop - 1 do
            local k = 1
            if j - o < fade then k = (j - o) / fade end
            if j >= o + len then k = k * (1 - (j - o - len) / (stop - o - len)) end
            mix[2 * j], mix[2 * j + 1] = mix[2 * j] * k, mix[2 * j + 1] * k
        end
        offset = offset + (s.to - s.from) + gap
    end

    local peak = 1e-6
    for j = 0, frames * 2 - 1 do peak = max(peak, math.abs(mix[j])) end
    local gain = 0.89 / peak
    local pcm = ffi.new('int16_t[?]', frames * 2)
    for j = 0, frames * 2 - 1 do pcm[j] = floor(max(-1, min(1, mix[j] * gain)) * 32767 + 0.5) end
    local bytes = frames * 4
    local header = 'RIFF' .. le(36 + bytes, 4) .. 'WAVE' .. 'fmt ' .. le(16, 4) .. le(1, 2) .. le(2, 2)
        .. le(RATE, 4) .. le(RATE * 4, 4) .. le(4, 2) .. le(16, 2) .. 'data' .. le(bytes, 4)
    assert(love.filesystem.write(file, header .. ffi.string(pcm, bytes)))
    return cues, gain
end

return Tape
