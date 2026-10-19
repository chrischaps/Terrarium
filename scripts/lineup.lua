-- The M2 gate (#19): eight random genomes of each plan, lined up on three
-- shelves in the jar's own light, by day and by night. Nobody is chosen: the
-- genomes are the seed's first draws from rng.sim, so a lineup is a fair look
-- at what the genes make.
--
--   love . --script scripts/lineup.lua [--seed <n>]
--
-- Saves lineup_day.png and lineup_night.png to the save directory (copy them
-- to renders/, which git ignores, to keep them), and prints
-- each creature's genome, left to right.

local SEED = 19
local PER_PLAN = 8
local W, H = 2400, 660 -- the plate, in pixels

-- Worms on a cork log, blobs on a stone ledge, spiders on a slate shelf above
local ROWS = {
    { plan = 'spider', y = 330, material = 'slate', h = 20 },
    { plan = 'blob', y = 440, material = 'stone', h = 26 },
    { plan = 'worm', y = 545, material = 'cork', h = 24 },
}
local X0, X1 = 400, 1600 -- under the lamp
local WORM_SEGMENT = 7.5 -- about how much worm one segment makes, lying down
local VIEW = { 340, 248, 1660, 248 + (1660 - 340) * H / W } -- level units on the plate

local function lineup(seed)
    local rng = require('core.rng')
    rng.seed(seed)
    local level = {
        width = 2000, height = 780, seed = 1,
        lamp = { x = 1000, y = -40 },
        solids = {
            { id = 'glass_l', kind = 'wall', x = -60, y = -60, w = 82, h = 1180 },
            { id = 'glass_r', kind = 'wall', x = 1978, y = -60, w = 82, h = 1180 },
            { id = 'lid', kind = 'ceiling', x = -60, y = -60, w = 2120, h = 92 },
            { id = 'soil', kind = 'floor', x = -60, y = 560, w = 2120, h = 280 },
        },
        residents = {},
    }
    local genomes = {}
    for _, row in ipairs(ROWS) do
        local id = row.plan .. '_row'
        table.insert(level.solids, {
            id = id, kind = 'ledge', material = row.material,
            x = X0 - 40, y = row.y, w = X1 - X0 + 80, h = row.h,
        })
        -- A worm stands at its head and trails its body behind it, so worms
        -- are spaced by their lengths; everyone else evenly
        local row_genomes, length = {}, 0
        for k = 1, PER_PLAN do
            row_genomes[k] = require('genome').random(row.plan, rng.sim)
            length = length + (row.plan == 'worm' and row_genomes[k].segments * WORM_SEGMENT or 0)
        end
        local gap = (X1 - X0 - length) / PER_PLAN
        local x = X0 + gap / 2
        for k, g in ipairs(row_genomes) do
            genomes[#genomes + 1] = g
            x = x + (row.plan == 'worm' and g.segments * WORM_SEGMENT or 0)
            table.insert(level.residents, {
                key = row.plan, name = row.plan .. ' ' .. k, solid = id, genome = g, x = x,
            })
            x = x + gap
        end
    end
    return level, genomes
end

return {
    run = function(api)
        local seed = api.args.seed or SEED
        local level, genomes = lineup(seed)
        for _, g in ipairs(genomes) do print('[lineup] ' .. api.Genome.serialise(g)) end
        for _, shot in ipairs({ { 'midday', 'lineup_day.png' }, { 23, 'lineup_night.png' } }) do
            api.open(seed, shot[1], level).wander = false
            api.step(3) -- long enough to settle onto the shelves
            api.save(api.render(W, H, { view = VIEW }), shot[2])
            api.yield()
        end
    end,
}
