-- Terrarium: the family book (#32). Everyone who has lived in the jar, in the
-- order they came: the founders who came with it, and each one hatched since,
-- with its parents, its children, the day it came and the day it went back to
-- the moss. It names them too (#29): a jar's own names come from its seed and
-- the order they came in, by a hash, so naming moves no stream.
--
-- It listens to what the World says happened (`laid`, `hatched`, `dying`,
-- `returned`) and never writes to it, so a jar with a book hashes the same as
-- one without. An entry is plain data (numbers, strings and lists of entry
-- numbers), so the book can be saved as it stands (#30); the living creature
-- each page belongs to is kept apart, in `alive`.
--
-- `seen` is the jar time you last closed the book. What came and went after it
-- happened while you were away.

local World = require('jar.world')
local Genome = require('genome')

local Book = {}
Book.__index = Book

-- Gentle names, for the jar to give out. One is chosen for each newcomer by a
-- hash of the jar's seed and its place in the book; a name already given goes
-- to the next one free, so a family has few twins. And now and then a child
-- of a family that has lost someone is named for them, and is the Second.
Book.NAMES = {
    'Alder', 'Aster', 'Barley', 'Bay', 'Birch', 'Bramble', 'Briar', 'Brook', 'Bryony', 'Burdock',
    'Calla', 'Campion', 'Cedar', 'Clary', 'Clover', 'Cobble', 'Cress', 'Dill', 'Dock', 'Dune',
    'Elder', 'Elm', 'Ember', 'Fennel', 'Fern', 'Finch', 'Flax', 'Furze', 'Gorse', 'Hazel',
    'Heath', 'Holly', 'Hops', 'Ivy', 'Juniper', 'Larch', 'Lark', 'Laurel', 'Lichen', 'Linden',
    'Lovage', 'Madder', 'Mallow', 'Maple', 'Marram', 'Meadow', 'Medlar', 'Mint', 'Moss', 'Mullein',
    'Myrtle', 'Nettle', 'Oak', 'Oat', 'Orris', 'Pebble', 'Peat', 'Pine', 'Poppy', 'Quince',
    'Rain', 'Reed', 'Robin', 'Rowan', 'Rue', 'Rush', 'Saffron', 'Sage', 'Sedge', 'Sloe',
    'Spruce', 'Starling', 'Tarn', 'Teasel', 'Thistle', 'Thyme', 'Tide', 'Tinder', 'Vale', 'Vetch',
    'Willow', 'Wren', 'Yarrow', 'Yew', 'Bracken', 'Catkin', 'Dapple', 'Drizzle', 'Eddy', 'Fallow',
    'Gale', 'Hollow', 'Kelp', 'Loam', 'Mire', 'Nook', 'Oriel', 'Puddle', 'Quill', 'Rill',
    'Shale', 'Sorrel', 'Tansy', 'Umber', 'Wick', 'Whorl', 'Dew', 'Bead', 'Fleck', 'Pip',
}
Book.NAMED_FOR = 4 -- one child in this many, of a family with someone gone, is named for them

local WORDS = {'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
    'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen',
    'nineteen', 'twenty'}
local ORDINALS = {'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth',
    'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth',
    'seventeenth', 'eighteenth', 'nineteenth', 'twentieth'}
local TENS = {[20] = 'twent', [30] = 'thirt', [40] = 'fort', [50] = 'fift'}

-- A count in words: "three", "twelve", and past twenty "twenty-three"
function Book.words(n)
    if n <= 20 then return WORDS[n] or 'no' end
    local tens = n - n % 10
    if n < 60 then return TENS[tens] .. 'y' .. (n % 10 > 0 and '-' .. WORDS[n % 10] or '') end
    return tostring(n)
end

-- An ordinal in words: "third", "twenty-first"
function Book.ordinal(n)
    if n <= 20 then return ORDINALS[n] end
    local tens = n - n % 10
    if n < 60 then return n % 10 == 0 and TENS[tens] .. 'ieth' or TENS[tens] .. 'y-' .. ORDINALS[n % 10] end
    local suffix = (n % 10 == 1 and 'st') or (n % 10 == 2 and 'nd') or (n % 10 == 3 and 'rd') or 'th'
    if n % 100 >= 11 and n % 100 <= 13 then suffix = 'th' end
    return n .. suffix
end

-- A list in words: "Fen", "Fen and Moss", "Fen, Moss and Ivo"
function Book.list(names)
    if #names <= 1 then return names[1] or '' end
    return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names]
end

-- So many days, in words: "less than a day", "a day", "four and a half days"
function Book.days(d)
    if d < 0.75 then return 'less than a day' end
    local whole = math.floor(d + 0.25)
    local half = d - whole >= 0.25
    if whole == 1 then return half and 'a day and a half' or 'a day' end
    return Book.words(whole) .. (half and ' and a half' or '') .. ' days'
end

function Book.new(world, seed)
    local self = setmetatable({}, Book)
    self.world = world
    self.seed = seed or 0
    self.entries = {} -- everyone, in the order they came
    self.clutches = {} -- {at, parents = {n, n}, count}, as they were laid
    self.seen = 0      -- the jar time the book was last closed
    self.alive = {}    -- entry number -> its creature, while it lives (never saved)
    self.of = setmetatable({}, {__mode = 'k'})    -- creature -> its entry
    self.laid = setmetatable({}, {__mode = 'k'})  -- egg -> its parents' entries
    for i, c in ipairs(world.creatures) do self:arrive(c, world.lives[i], nil, true) end
    world.events:on(function(ev) self:hear(ev) end)
    return self
end

-- Everyone's names so far, and how many have borne each
local function names_given(self)
    local given = {}
    for _, e in ipairs(self.entries) do given[e.name] = (given[e.name] or 0) + 1 end
    return given
end

-- The ancestors of entry numbers `parents` who have gone back to the moss, nearest first
local function gone_before(self, parents)
    local out, seen, gen = {}, {}, parents or {}
    for _ = 1, 2 do -- parents, then grandparents
        local next_gen = {}
        for _, n in ipairs(gen) do
            local e = self.entries[n]
            if e and not seen[n] then
                seen[n] = true
                if e.gone then out[#out + 1] = e end
                for _, p in ipairs(e.parents or {}) do next_gen[#next_gen + 1] = p end
            end
        end
        gen = next_gen
    end
    return out
end

-- A name for the `n`th to come, whose parents are `parents`
function Book:name_for(n, parents)
    local h = World.hash(tostring(self.seed) .. ':name:' .. n)
    local given = names_given(self)
    local forebears = gone_before(self, parents)
    if #forebears > 0 and h % Book.NAMED_FOR == 0 then
        local e = forebears[(math.floor(h / Book.NAMED_FOR) % #forebears) + 1]
        return e.name, (given[e.name] or 0) + 1, e.n
    end
    local count = #Book.NAMES
    local k = h % count
    for step = 0, count - 1 do
        local name = Book.NAMES[(k + step) % count + 1]
        if not given[name] then return name end
    end
    local name = Book.NAMES[k + 1]
    return name, given[name] + 1
end

-- A creature's page: `c` has come, living `life` (World.lives), a child of
-- entries `parents`, or with the jar
function Book:arrive(c, life, parents, founder)
    local n = #self.entries + 1
    local name, ordinal, named_for = self:name_for(n, parents)
    local e = {
        n = n, key = c.key, name = name, ordinal = ordinal, named_for = named_for,
        genome = Genome.serialise(c.genome),
        parents = parents, children = {},
        came = self.world.time, born = life.born, founder = founder or nil,
    }
    self.entries[n] = e
    self.alive[n], self.of[c] = c, e
    for _, p in ipairs(parents or {}) do
        local pe = self.entries[p]
        pe.children[#pe.children + 1] = n
    end
    return e
end

function Book:hear(ev)
    local world = self.world
    if ev.kind == 'laid' then
        local a, b = self.of[ev.who], self.of[ev.with]
        local parents = a and b and {a.n, b.n} or nil
        for _, egg in ipairs(ev.eggs) do self.laid[egg] = parents end
        if parents and #ev.eggs > 0 then
            self.clutches[#self.clutches + 1] = {at = world.time, parents = parents, count = #ev.eggs}
        end
    elseif ev.kind == 'hatched' then
        local i = world:index_of(ev.who)
        if i and not self.of[ev.who] then
            local parents = ev.egg and self.laid[ev.egg]
            self:arrive(ev.who, world.lives[i], parents, not parents)
        end
    elseif ev.kind == 'dying' then
        local e = self.of[ev.who]
        if e then e.dying = world.time end
    elseif ev.kind == 'became' then
        -- (catch-up, #31: a body became a token, or a token its body again)
        local e = self.of[ev.was]
        if e then self.alive[e.n], self.of[ev.who] = ev.who, e end
    elseif ev.kind == 'returned' then
        local e = self.of[ev.who]
        if e then
            e.gone = world.time
            self.alive[e.n] = nil
        end
    end
end

-- The entry of creature `c`, if the book knows it
function Book:entry_of(c)
    return self.of[c]
end

-- Entry `n`'s living creature and its index in the World, if it's alive
function Book:creature(n)
    local c = self.alive[n]
    return c, c and self.world:index_of(c)
end

-- A name as the book writes it: "Fen", or "Fen the Second"
function Book.named(e)
    if not e.ordinal or e.ordinal < 2 then return e.name end
    local ord = Book.ordinal(e.ordinal)
    return e.name .. ' the ' .. ord:sub(1, 1):upper() .. ord:sub(2)
end

-- The jar's day at jar time `t`: 1 on the day it was opened
function Book:day_of(t)
    local L = self.world:day_length()
    return math.floor((self.world.start_hour / 24 * L + t) / L) + 1
end

-- How many days entry `e` has lived (or had, if it's gone)
function Book:lived(e)
    return ((e.gone or self.world.time) - e.born) / self.world:day_length()
end

-- What happened after jar time `t`, oldest first: {at, kind = 'born'|'gone'|'laid', entry|clutch}
function Book:since(t)
    local out = {}
    for _, e in ipairs(self.entries) do
        if not e.founder and e.came > t then out[#out + 1] = {at = e.came, kind = 'born', entry = e} end
        if e.gone and e.gone > t then out[#out + 1] = {at = e.gone, kind = 'gone', entry = e} end
    end
    for _, k in ipairs(self.clutches) do
        if k.at > t then out[#out + 1] = {at = k.at, kind = 'laid', clutch = k} end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return (a.entry and a.entry.n or 0) < (b.entry and b.entry.n or 0)
    end)
    return out
end

-- Is there anything you haven't seen?
function Book:news()
    return #self:since(self.seen) > 0
end

-- You've read it, now: what's happened so far isn't news
function Book:close()
    self.seen = self.world.time
end

-- How many live in the jar now
function Book:living()
    local n = 0
    for _ in pairs(self.alive) do n = n + 1 end
    return n
end

return Book
