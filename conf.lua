-- Terrarium: the dev modes that only check the sim run with no window, so they
-- run in CI (see core/headless.lua). --window opens one anyway.
local WINDOWLESS = { ['--headless'] = true, ['--test'] = true, ['--selftest'] = true, ['--replay'] = true,
    ['--navdump'] = true, ['--styles'] = true }

local function windowless()
    local found = false
    for _, a in ipairs(arg or {}) do
        if a == '--window' then return false end
        if WINDOWLESS[a] then found = true end
    end
    return found
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
end
