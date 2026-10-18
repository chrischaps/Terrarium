-- From chrischaps/Character @ 925c35b (core/log.lua)
-- Log: category-tagged console output that stays silent unless enabled.
-- Usage: log.info('nav', 'built %d nodes', n)   (prints "[nav] built 12 nodes")

local log = {}

log.enabled = false          -- master switch (debug mode turns this on)
log.always = {selftest = true, dev = true}

function log.info(category, fmt, ...)
    if not (log.enabled or log.always[category]) then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print("[" .. category .. "] " .. (ok and msg or fmt))
end

return log
