-- Terrarium: the dev modes that only check the sim run with no window, so they
-- run in CI (see core/headless.lua). --window opens one anyway.
local WINDOWLESS = { ['--headless'] = true, ['--test'] = true, ['--selftest'] = true, ['--replay'] = true,
    ['--navdump'] = true, ['--keep'] = true, ['--resume'] = true }

local function windowless()
    local found = false
    for _, a in ipairs(arg or {}) do
        if a == '--window' then return false end
        if WINDOWLESS[a] then found = true end
    end
    return found
end

local function has(flag)
    for _, a in ipairs(arg or {}) do
        if a == flag then return true end
    end
    return false
end

function love.conf(t)
    t.identity = "terrarium"
    t.version = "11.5"
    if windowless() then
        t.window = false
        return
    end
    t.window.title = "Terrarium"
    t.window.width = 1280
    t.window.height = 800
    t.window.msaa = 4
    t.window.highdpi = true
    -- --frame (#90): the whole of whatever screen it's on, the Pi frame's 1280 x 720
    -- in landscape. main.lua fits the 1280 x 800 view to it (core/screen.lua).
    if has('--frame') then
        t.window.fullscreen = true
        t.window.fullscreentype = 'desktop'
        t.window.borderless = true
    end
end
