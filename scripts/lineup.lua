-- The M2 gate (#19): eight random genomes of each plan, lined up on a shelf
-- each in the jar's own light, by day and by night. Nobody is chosen: the
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
local W = 2400 -- the plate's width in pixels; its height fits the shelves

local Genome = require('genome')
local World = require('jar.world')

-- A shelf per plan (#73), the first in Genome.order lowest: cork, stone and
-- slate in turn, each a shelf's height above the last (closer together when
-- there are more of them, so the top one stays clear of the lid). Rows are
-- filled from the top down.
local MATERIALS = { { 'cork', 24 }, { 'stone', 26 }, { 'slate', 20 } }
local LOWEST, HIGHEST, GAP = 545, 150, 107.5
local ROWS = {}
local gap = math.min(GAP, (LOWEST - HIGHEST) / math.max(1, #Genome.order - 1))
for k = #Genome.order, 1, -1 do
    local m = MATERIALS[(k - 1) % #MATERIALS + 1]
    ROWS[#ROWS + 1] = { plan = Genome.order[k], y = LOWEST - (k - 1) * gap, material = m[1], h = m[2] }
end
local X0, X1 = 400, 1600 -- under the lamp
-- Level units on the plate: from above the top shelf (room for what stands on
-- it) to below the lowest
local TOP, BOTTOM = ROWS[1].y - 82, 611
local VIEW = { 340, TOP, 1660, BOTTOM }
local H = math.floor(W * (BOTTOM - TOP) / (1660 - 340) + 0.5)

-- How far a body lies out behind where it stands (a worm trails its length)
local function length(g)
    for _, def in ipairs(World.CREATURES) do
        if def.key == g.plan then return def.class.length and def.class.length(g) or 0 end
    end
    return 0
end

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
        -- A worm stands at its head and trails its body behind it, so a row
        -- is spaced by its bodies' lengths
        local row_genomes, lengths = {}, 0
        for k = 1, PER_PLAN do
            row_genomes[k] = Genome.random(row.plan, rng.sim)
            lengths = lengths + length(row_genomes[k])
        end
        local gap = (X1 - X0 - lengths) / PER_PLAN
        local x = X0 + gap / 2
        for k, g in ipairs(row_genomes) do
            genomes[#genomes + 1] = g
            x = x + length(g)
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
