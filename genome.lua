-- Genomes: a small table of numbers per creature, each held to a range the
-- body builders and the self-test have proven safe.
--
-- In the shape of Fishbowl's fish/species.lua: one table per body plan, plus
-- an order. A plan's genes are a list, never a set, so drawing a random genome
-- and writing one out always go in the same order (no pairs()).
--
-- A gene is one of
--   real  lo..hi, kept to thousandths (finer than anything you can see, and it
--         makes the string form round-trip exactly, so a saved jar resumes on
--         the same state hash)
--   int   lo..hi, whole numbers
--   pick  one of an ordered list of values; the order is what "a neighbouring
--         value" means when a gene mutates (see Genome.child)
--
-- The plan is fixed for life and never crosses: worms breed with worms.

local Genome = {}

local floor = math.floor

local SHARED = {
    {name = 'hue', real = {0, 1}},
    {name = 'pattern', pick = {1, 2, 3, 4}}, -- four kinds; #15 draws them
    {name = 'glow', real = {0, 1}},          -- how bright it shines in the dark
    {name = 'boldness', real = {0, 1}},
    {name = 'sociability', real = {0, 1}},
    {name = 'chronotype', real = {0, 1}},    -- 0 an early riser, 1 a night owl
}

local function plan(label, own)
    local genes = {}
    for _, g in ipairs(own) do genes[#genes + 1] = g end
    for _, g in ipairs(SHARED) do genes[#genes + 1] = g end
    return {label = label, genes = genes}
end

--------------------------------------------------------------------------------
Genome.worm = plan('worm', {
    {name = 'segments', int = {10, 24}},     -- length, and how many bunches crawl
    {name = 'stiffness', real = {0.2, 0.9}}, -- a stiff worm bridges, a loose one drapes
})

Genome.blob = plan('blob', {
    {name = 'size', real = {0.6, 1.4}},      -- times the standard blob
    {name = 'pressure', real = {0.5, 1.5}},  -- how firmly it holds its shape
})

Genome.spider = plan('spider', {
    {name = 'legs', pick = {4, 6, 8}},
    {name = 'reach', real = {0.7, 1.3}},     -- times the standard leg
})

Genome.order = {'worm', 'blob', 'spider'}

for _, key in ipairs(Genome.order) do
    local p = Genome[key]
    p.by_name = {}
    for _, g in ipairs(p.genes) do p.by_name[g.name] = g end
end

--------------------------------------------------------------------------------

local function plan_of(key)
    local p = Genome[key]
    if type(p) ~= 'table' or not p.genes then error(string.format('genome: no body plan %q', tostring(key)), 3) end
    return p
end

local function thousandths(v) return floor(v * 1000 + 0.5) / 1000 end

-- The middle of a gene's travel: what a missing or unreadable gene becomes
local function middle(g)
    if g.real then return thousandths((g.real[1] + g.real[2]) / 2) end
    if g.int then return floor((g.int[1] + g.int[2]) / 2) end
    return g.pick[floor((#g.pick + 1) / 2)]
end

-- One gene's value held to its range. Picks snap to the nearest value (the
-- lower one on a tie), so a 5-legged spider has 4 legs.
local function hold(g, v)
    if type(v) ~= 'number' or v ~= v then return middle(g) end
    if g.pick then
        local best, dist = g.pick[1], math.huge
        for _, p in ipairs(g.pick) do
            local d = math.abs(p - v)
            if d < dist then best, dist = p, d end
        end
        return best
    end
    local r = g.real or g.int
    v = math.max(r[1], math.min(r[2], v))
    if g.int then return floor(v + 0.5) end
    return thousandths(v)
end

-- A fresh genome for `key`, drawn from the generator `gen` (rng.sim in the jar)
function Genome.random(key, gen)
    local p = plan_of(key)
    local out = {plan = key}
    for _, g in ipairs(p.genes) do
        local v
        if g.real then v = g.real[1] + gen:random() * (g.real[2] - g.real[1])
        elseif g.int then v = gen:random(g.int[1], g.int[2])
        else v = g.pick[gen:random(#g.pick)] end
        out[g.name] = hold(g, v)
    end
    return out
end

-- Hold every gene in its range, in place; anything missing or not a number
-- comes back as the middle of its range. Genes the plan doesn't have are
-- dropped. Returns the genome.
function Genome.clamp(genome)
    local p = plan_of(genome.plan)
    for name in pairs(genome) do
        if name ~= 'plan' and not p.by_name[name] then genome[name] = nil end
    end
    for _, g in ipairs(p.genes) do genome[g.name] = hold(g, genome[g.name]) end
    return genome
end

-- Fresh copy of a genome
function Genome.copy(genome)
    local out = {}
    for k, v in pairs(genome) do out[k] = v end
    return out
end

local function write(v)
    if v == floor(v) then return string.format('%d', v) end
    return (string.format('%.3f', v):gsub('0+$', ''))
end

-- One line of text, plan first, then every gene in the plan's order:
--   worm segments=14 stiffness=0.512 hue=0.3 pattern=2 ...
function Genome.serialise(genome)
    local p = plan_of(genome.plan)
    local parts = {genome.plan}
    for _, g in ipairs(p.genes) do parts[#parts + 1] = g.name .. '=' .. write(hold(g, genome[g.name])) end
    return table.concat(parts, ' ')
end

-- The other way. Genes may come in any order; one that's missing takes the
-- middle of its range, and one this plan doesn't have is ignored, so an older
-- or newer string still reads. Returns nil and a reason for text that isn't a
-- genome at all.
function Genome.parse(s)
    if type(s) ~= 'string' then return nil, 'not a string' end
    local key, rest = s:match('^%s*(%a+)(.*)$')
    if not key or not (type(Genome[key]) == 'table' and Genome[key].genes) then
        return nil, string.format('no body plan in %q', s)
    end
    local out = {plan = key}
    for token in rest:gmatch('%S+') do
        local name, value = token:match('^(%a+)=(.+)$')
        local v = value and tonumber(value)
        if not v then return nil, string.format('cannot read %q', token) end
        if name ~= 'plan' then out[name] = v end
    end
    return Genome.clamp(out)
end

--------------------------------------------------------------------------------
-- Inheritance (#11). Each gene comes from one parent or the other, then takes
-- one small step: the Soba Mutate idea, a nudge along the gene's travel that
-- folds back at the ends instead of clamping, so values never pile up there.
-- One gene in twenty takes a bigger step.
--
-- Steps are triangular (the difference of two uniform draws), so small nudges
-- are common and the largest are rare. Reals step by a fraction of their range.
-- Ints and picks step in cells, and fold at the cells' outer edges, so a value
-- at the end of its range that steps outward lands back on itself. That keeps
-- an even spread even. A pick only ever reaches a neighbouring value (legs 4↔6↔8).

local STEP, BIG = 0.04, 0.25          -- reals: widest step, as a fraction of the range
local CELL_STEP, CELL_BIG = 0.6, 1.4  -- ints and picks: widest step, in cells (under 1.5, so picks move one at most)
local BIG_CHANCE = 1 / 20

Genome.STEP, Genome.BIG, Genome.BIG_CHANCE = STEP, BIG, BIG_CHANCE

-- x folded back into [a, b], like a ball between two walls
local function fold(x, a, b)
    local span = b - a
    local t = (x - a) % (2 * span)
    if t > span then t = 2 * span - t end
    return a + t
end

local function index_of(list, v)
    for i, p in ipairs(list) do if p == v then return i end end
    return 1
end

-- One gene's value after one step. Always draws three numbers from `gen`, so
-- the stream stays in step whatever kind of gene this is.
local function step(g, v, gen)
    local big = gen:random() < BIG_CHANCE
    local tri = gen:random() - gen:random()
    if g.real then
        local lo, hi = g.real[1], g.real[2]
        return hold(g, fold(v + tri * (big and BIG or STEP) * (hi - lo), lo, hi))
    end
    local d = tri * (big and CELL_BIG or CELL_STEP)
    if g.int then
        local lo, hi = g.int[1], g.int[2]
        return math.min(hi, floor(fold(v + d, lo - 0.5, hi + 0.5) + 0.5))
    end
    local n = #g.pick
    local i = math.min(n, floor(fold(index_of(g.pick, v) + d, 0.5, n + 0.5) + 0.5))
    return g.pick[i]
end

-- A copy of `genome` with every gene stepped once
function Genome.mutate(genome, gen)
    local p = plan_of(genome.plan)
    local out = {plan = genome.plan}
    for _, g in ipairs(p.genes) do out[g.name] = step(g, hold(g, genome[g.name]), gen) end
    return out
end

-- A child of `a` and `b`, drawn from `gen` (rng.sim in the jar). Both parents
-- must share a plan.
function Genome.child(a, b, gen)
    local p = plan_of(a.plan)
    if b.plan ~= a.plan then
        error(string.format('genome: a %s cannot breed with a %s', tostring(a.plan), tostring(b.plan)), 2)
    end
    local out = {plan = a.plan}
    for _, g in ipairs(p.genes) do
        local from = gen:random() < 0.5 and a or b
        out[g.name] = step(g, hold(g, from[g.name]), gen)
    end
    return out
end

-- Terrarium: which of `n` equal stretches of a real gene's range `v` falls in
-- (#16). Returns the stretch (0 to n-1) and its two ends. Worked in thousandths,
-- the way genes are kept, so a value on a boundary always lands on the same
-- side: the higher stretch, except at the top of the range.
function Genome.bucket(key, name, v, n)
    local g = plan_of(key).by_name[name]
    local lo, hi = floor(g.real[1] * 1000 + 0.5), floor(g.real[2] * 1000 + 0.5)
    local at = floor(hold(g, v) * 1000 + 0.5)
    local k = math.min(n - 1, floor((at - lo) * n / (hi - lo)))
    local function edge(i) return floor(lo + (hi - lo) * i / n + 0.5) / 1000 end
    return k, edge(k), edge(k + 1)
end

-- True when every gene the plan has is present and in range. A pick gene is
-- in range only if it's one of the plan's values; a real one only if it's on
-- the thousandths.
function Genome.valid(genome)
    local p = Genome[genome.plan]
    if type(p) ~= 'table' or not p.genes then return false, 'plan' end
    for _, g in ipairs(p.genes) do
        local v = genome[g.name]
        if type(v) ~= 'number' or hold(g, v) ~= v then return false, g.name end
    end
    return true
end

return Genome
