-- #98: what a style costs, the matte's probes most of all. One moment of the
-- classic jar drawn again and again in each style at the frame's size, each
-- frame waited for (a pixel read back, so the GPU's work is in the time, not
-- just the CPU's), the styles taken in turns so a busy machine slows them all
-- alike. Prints each style's median and 95th percentile ms a frame.
--
--   lovec . --probes --crowd 16 --script scripts/probe_bench.lua
--
-- BENCH_FRAMES (60) frames a turn, BENCH_ROUNDS (5) turns, BENCH_SIZE (1280x720,
-- the Pi frame's screen) the frame. A matte style's cost is its own time less
-- probe-matte's; the matte's is probe-matte's less none's.

return {run = function(api)
    local Styles = require('jar.styles')
    local names = {}
    for _, n in ipairs({ 'none', 'silver', 'probe-matte', 'probe-ink', 'probe-cut' }) do
        if Styles.get(n) then names[#names + 1] = n end
    end
    local frames = tonumber(os.getenv('BENCH_FRAMES')) or 60
    local rounds = tonumber(os.getenv('BENCH_ROUNDS')) or 5
    local w, h = (os.getenv('BENCH_SIZE') or '1280x720'):match('(%d+)x(%d+)')
    w, h = tonumber(w), tonumber(h)

    local world = api.open(20261018, 'midday', nil, nil, api.World.CLASSIC)
    -- (a --crowd's eggs hatch first, as --bench waits for them)
    for _ = 1, 240 do
        if #world.eggs == 0 then break end
        api.step(0.5)
    end
    api.step(5)

    local times = {}
    for _, n in ipairs(names) do times[n] = {} end
    for _ = 1, rounds do
        for _, n in ipairs(names) do
            api.style(n)
            api.render(w, h):newImageData(1, 1, 0, 0, 1, 1) -- (shaders compiled, canvases made)
            for _ = 1, frames do
                local t0 = love.timer.getTime()
                api.render(w, h, { frame = true }):newImageData(1, 1, 0, 0, 1, 1)
                local t = times[n]
                t[#t + 1] = love.timer.getTime() - t0
            end
            api.yield()
        end
    end

    print(string.format('[probe_bench] %d creatures, %dx%d, %d frames each, on %s', #world.creatures, w, h,
        frames * rounds, select(4, love.graphics.getRendererInfo())))
    local base
    for _, n in ipairs(names) do
        local t = times[n]
        table.sort(t)
        local med, p95 = t[math.ceil(#t * 0.5)] * 1000, t[math.ceil(#t * 0.95)] * 1000
        base = base or med
        print(string.format('[probe_bench] %-12s median %6.2f ms  p95 %6.2f ms  (%+.2f ms)', n, med, p95, med - base))
    end
end}
