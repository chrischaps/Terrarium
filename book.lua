-- book.lua: the jar remembers (#30).
--
-- A jar is its seed plus its history, so its book keeps both: the seed the
-- jar was composed from, and everything its life since has made of it. That's
-- every creature's genome, body, mind and name, the moss grid, the crumbs and
-- the eggs, the hour, the sim stream, and the family's log (world.history,
-- which the family book, #32, reads). Quitting writes it, and so does every
-- EVERY seconds of jar, and reopening reads it back. The jar goes on as if it
-- had never been closed: it opens with the state hash it was saved with.
--
-- The World is written whole, as the graph of tables it is, so nothing it
-- remembers has to be listed here. Each table is a record, and a table seen
-- twice is written once and pointed at, so a graph's nodes are still the ones
-- a controller's path runs through. Three kinds of table aren't data:
--   a class (a body's metatable, a Mover's, a Mind's) is written by its
--     module's name and found again by requiring it;
--   a module's own table (a profile, a nav profile, the room's level) is
--     written by its path from the module, and is the same table when read,
--     so a bucket's graph is still found by its nav profile. A cache that's
--     empty in a new process gets the saved table put back where it was;
--   a nav graph still being built a slice at a time (NavGraph.Builder) is a
--     coroutine, so it's written as how many slices it had done, and read by
--     building that many again. The work is counted, so it ends up the same.
-- What's only drawn (meshes, the marks a body glowed, the render snapshots)
-- isn't kept, and is made again the first time it's drawn. What listens to
-- the World (its closures) listens again: World:revive.
--
-- Some of what the jar remembers lives beside the World: the flora's fronds
-- (jar/plants.lua) and the motes in the air (jar/motes.lua, which draw from
-- rng.look as the creatures' eyes do). They're passed in as `around`, each a
-- module with state() and restore(), and a resumed jar composes them again
-- from the seed and then restores them. The scape, glass and scenery are the
-- seed's alone, and are only composed again.
--
-- The format is text, one record a line: `#<id>;` then `t` (a table: its
-- class or `-`, then its keys and values), `p` (a module's table: the module,
-- the path's length and keys, then `c` and its contents if a cache may need
-- them, else `.`) or `k` (a table a codec packed: its class, then the packed
-- keys and values). Values are `n<number>;`, `s<length>:<bytes>`, `T`, `F` or
-- `@<id>;`. A table's pairs end with `.`. The first line names the format and
-- its VERSION: a book of another version isn't read, and is kept aside. A
-- change that would leave an old book's World wrong in the new code (a field
-- renamed, a meaning changed) moves VERSION on, so the jar starts over instead.

local statehash = require('core.statehash')
local rng = require('core.rng')
local log = require('core.log')

local Book = {}

Book.VERSION = 1
Book.FILE = 'jar.book'
Book.EVERY = 300 -- seconds of jar between saves, so a power cut loses no more
local MAGIC = 'terrarium book '

-- Fields that are drawn and drawn again, never remembered, and the World's
-- closures, which World:revive makes again
local DROP = {
    mesh = true, glow_mesh = true,                       -- draw buffers
    marks = true, local_marks = true, mark_frame = true, -- what a body drew last, for its glow
    listeners = true,                                    -- who hears the World's events
    light_dir = true,                                    -- the lamp's direction, a closure
}
-- and the World's render interpolation (a springtail's `snap` is its furcula's)
local DROP_WORLD = {snap = true, saved = true}

-- The standard libraries and LÖVE's own: never the jar's
local function foreign(name, m)
    return _G[name] == m or name:match('^love') or name:match('^jit') or name == 'ffi' or name == '_G'
end

local TYPE_ORDER = {boolean = 1, number = 2, string = 3}
local function key_less(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return TYPE_ORDER[ta] < TYPE_ORDER[tb] end
    if ta == 'boolean' then return (not a) and b end
    return a < b
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        if TYPE_ORDER[type(k)] then keys[#keys + 1] = k end
    end
    table.sort(keys, key_less)
    return keys
end

-- What the loaded modules hold, as names: `classes` (a module, or a field of
-- one with an __index, by `module` or `module:field`) and `paths` (every
-- table reachable from a module through tables with no metatable, by
-- {module, key, ...})
local function registry()
    local names = {}
    for name, m in pairs(package.loaded) do
        if type(m) == 'table' and not foreign(name, m) then names[#names + 1] = name end
    end
    table.sort(names)
    local classes, paths = {}, {}
    for _, name in ipairs(names) do
        local m = package.loaded[name]
        classes[m] = classes[m] or name
        for _, k in ipairs(sorted_keys(m)) do
            local v = rawget(m, k)
            if type(k) == 'string' and type(v) == 'table' and rawget(v, '__index') ~= nil then
                classes[v] = classes[v] or (name .. ':' .. k)
            end
        end
    end
    local function visit(t, path)
        for _, k in ipairs(sorted_keys(t)) do
            local v = rawget(t, k)
            if type(v) == 'table' and not paths[v] and getmetatable(v) == nil then
                local p = {unpack(path)}
                p[#p + 1] = k
                paths[v] = p
                visit(v, p)
            end
        end
    end
    for _, name in ipairs(names) do
        local m = package.loaded[name]
        paths[m] = paths[m] or {name}
    end
    for _, name in ipairs(names) do
        local m = package.loaded[name]
        if paths[m][1] == name then visit(m, {name}) end
    end
    return classes, paths
end

-- The class called `name`, requiring its module if it isn't loaded yet
local function class_named(name)
    local mod, field = name:match('^([^:]+):?(.*)$')
    local ok, m = pcall(require, mod)
    if not ok or type(m) ~= 'table' then return nil end
    if field == '' then return m end
    return rawget(m, field)
end

-- The live table at `path`, or nil
local function at_path(path)
    local ok, t = pcall(require, path[1])
    if not ok then return nil end
    for i = 2, #path do
        if type(t) ~= 'table' then return nil end
        t = rawget(t, path[i])
    end
    return type(t) == 'table' and t or nil
end

-- Tables written as what made them, and made again when read
local CODECS = {
    ['nav.navgraph:Builder'] = {
        pack = function(b)
            return {level = b.graph.level, profile = b.graph.profile, slice = b.slice, slices = b.slices,
                nav = b.nav, key = b.key}
        end,
        unpack = function(t)
            local NavGraph = require('nav.navgraph')
            local b = NavGraph.builder(t.level, t.profile, t.slice)
            for _ = 1, t.slices do assert(not b:step(), 'book: a graph finished sooner than it did') end
            local nav, key = t.nav, t.key
            for k in pairs(t) do t[k] = nil end
            for k, v in pairs(b) do t[k] = v end
            t.nav, t.key = nav, key
            return setmetatable(t, getmetatable(b))
        end,
    },
}

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

local function number(v)
    if v ~= v then return 'nnan;' end
    if v == math.huge then return 'ninf;' end
    if v == -math.huge then return 'n-inf;' end
    return 'n' .. string.format('%.17g', v) .. ';'
end

-- `root` (a table) as a book's text
function Book.encode(root)
    local classes, paths = registry()
    local ids, order = {}, {}
    local from = {} -- table -> {parent, key}, to say where something unwritable was
    local out = {MAGIC .. Book.VERSION .. '\n'}

    local function where(t, key)
        local parts = {tostring(key)}
        while from[t] do
            local f = from[t]
            table.insert(parts, 1, tostring(f[2]))
            t = f[1]
        end
        return table.concat(parts, '.')
    end

    local function id_of(t, parent, key)
        local id = ids[t]
        if not id then
            id = #order + 1
            ids[t], order[id] = id, t
            from[t] = parent and {parent, key} or nil
        end
        return id
    end

    local function value(v, parent, key)
        local ty = type(v)
        if ty == 'number' then return number(v) end
        if ty == 'string' then return 's' .. #v .. ':' .. v end
        if ty == 'boolean' then return v and 'T' or 'F' end
        if ty == 'table' then return '@' .. id_of(v, parent, key) .. ';' end
        return nil
    end

    -- t's pairs, without the dropped and the unwritable (which are errors)
    local World = require('jar.world')
    -- t's keys: its plain ones in order, then those that are tables (the
    -- World's graphs by nav profile) in the order they were first written
    local function keys_of(t)
        local keys, tables = sorted_keys(t), {}
        for k in pairs(t) do
            if type(k) == 'table' then
                id_of(k, t, '(a key)')
                tables[#tables + 1] = k
            end
        end
        table.sort(tables, function(a, b) return ids[a] < ids[b] end)
        for _, k in ipairs(tables) do keys[#keys + 1] = k end
        return keys
    end

    local function pairs_of(t, buf, owner)
        local world = getmetatable(t) == World
        for _, k in ipairs(keys_of(t)) do
            local v = rawget(t, k)
            if not (DROP[k] or (world and DROP_WORLD[k])) then
                local kv, vv = value(k, owner, k), value(v, owner, k)
                if not vv then
                    error(string.format('book: %s is a %s, which a book can\'t keep', where(owner, k), type(v)), 0)
                end
                buf[#buf + 1] = kv
                buf[#buf + 1] = vv
            end
        end
        buf[#buf + 1] = '.'
    end

    local function has_function(t)
        for _, v in pairs(t) do
            if type(v) == 'function' then return true end
        end
        return false
    end

    id_of(root)
    local i = 1
    while order[i] do
        local t = order[i]
        local buf = {'#', i, ';'}
        local path, mt = paths[t], getmetatable(t)
        if path then
            buf[#buf + 1] = 'p'
            buf[#buf + 1] = number(#path)
            for _, k in ipairs(path) do buf[#buf + 1] = value(k) end
            if mt == nil and not has_function(t) then
                buf[#buf + 1] = 'c'
                pairs_of(t, buf, t)
            else
                buf[#buf + 1] = '.'
            end
        else
            local name = mt and classes[mt]
            if mt and not name then
                error(string.format('book: %s has a metatable no module holds', where(t, '')), 0)
            end
            local codec = name and CODECS[name]
            if codec then
                buf[#buf + 1] = 'k'
                buf[#buf + 1] = value(name)
                pairs_of(codec.pack(t), buf, t)
            else
                buf[#buf + 1] = 't'
                buf[#buf + 1] = name and value(name) or '-'
                pairs_of(t, buf, t)
            end
        end
        buf[#buf + 1] = '\n'
        out[#out + 1] = table.concat(buf)
        i = i + 1
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local byte, sub, find = string.byte, string.sub, string.find
local N, S, AT, T, F, DOT = byte('n'), byte('s'), byte('@'), byte('T'), byte('F'), byte('.')

-- The token at s[i]: its value (a ref as its id, with `true` second) and
-- where the next one starts
local function token(s, i)
    local c = byte(s, i)
    if not c then error('book: it ends too soon', 0) end
    if c == N then
        local j = find(s, ';', i, true)
        if not j then error('book: it ends too soon', 0) end
        local x = sub(s, i + 1, j - 1)
        local v = tonumber(x)
        if not v then
            if x == 'inf' then v = math.huge elseif x == '-inf' then v = -math.huge elseif x == 'nan' then v = 0 / 0
            else error('book: a bad number at ' .. i, 0) end
        end
        return v, false, j + 1
    elseif c == S then
        local j = find(s, ':', i, true)
        local len = j and tonumber(sub(s, i + 1, j - 1))
        if not len or j + len > #s then error('book: it ends too soon', 0) end
        return sub(s, j + 1, j + len), false, j + len + 1
    elseif c == AT then
        local j = find(s, ';', i, true)
        if not j then error('book: it ends too soon', 0) end
        return tonumber(sub(s, i + 1, j - 1)), true, j + 1
    elseif c == T then
        return true, false, i + 1
    elseif c == F then
        return false, false, i + 1
    end
    error('book: unreadable at ' .. i, 0)
end

-- Step over pairs from s[i] to their `.`; where the next record starts
local function skip_pairs(s, i)
    while byte(s, i) ~= DOT do
        local _
        _, _, i = token(s, i)
    end
    return i + 1
end

-- The root table from a book's text, or nil and why it can't be read
function Book.decode(s)
    local first = s:match('^[^\n]*')
    local version = tonumber(first:match('^' .. MAGIC .. '(%d+)$') or '')
    if not version then return nil, 'not a book' end
    if version ~= Book.VERSION then return nil, 'a book of version ' .. version .. ', not ' .. Book.VERSION end

    local recs, objs = {}, {}
    local _
    local i = #first + 2
    -- 1: every record's table, found (a module's) or new
    while i <= #s do
        local c = byte(s, i)
        if c == 10 or c == 13 then
            i = i + 1
        else
            local j = find(s, ';', i, true)
            local id = tonumber(sub(s, i + 1, j - 1))
            local kind = sub(s, j + 1, j + 1)
            local r = {kind = kind}
            i = j + 2
            if kind == 'p' then
                local n
                n, _, i = token(s, i)
                local path = {}
                for k = 1, n do path[k], _, i = token(s, i) end
                r.path = path
                local live = at_path(path)
                if byte(s, i) == byte('c') then
                    r.at = i + 1
                    i = skip_pairs(s, i + 1)
                else
                    i = i + 1
                end
                if live then
                    objs[id], r.at = live, nil
                elseif r.at then
                    objs[id], r.install = {}, true
                else
                    return nil, 'the book names ' .. table.concat(path, '.') .. ', which isn\'t here'
                end
            else
                if byte(s, i) == byte('-') then
                    i = i + 1
                else
                    r.class, _, i = token(s, i)
                end
                r.at = i
                i = skip_pairs(s, i)
                objs[id] = {}
            end
            recs[id] = r
        end
    end
    -- 2: their contents
    for id, r in ipairs(recs) do
        if r.at then
            local t, k, v, ref = objs[id], nil, nil, nil
            i = r.at
            while byte(s, i) ~= DOT do
                k, ref, i = token(s, i)
                if ref then k = objs[k] end
                v, ref, i = token(s, i)
                if ref then v = objs[v] end
                rawset(t, k, v)
            end
        end
    end
    -- 3: classes, and caches put back where they were, shortest path first
    local installs = {}
    for id, r in ipairs(recs) do
        if r.class and r.kind == 't' then
            local mt = class_named(r.class)
            if not mt then return nil, 'the book names a class ' .. r.class .. ', which isn\'t here' end
            setmetatable(objs[id], mt)
        elseif r.install then
            installs[#installs + 1] = id
        end
    end
    table.sort(installs, function(a, b) return #recs[a].path < #recs[b].path or (#recs[a].path == #recs[b].path and a < b) end)
    for _, id in ipairs(installs) do
        local path = recs[id].path
        local parent = at_path({unpack(path, 1, #path - 1)})
        if not parent then return nil, 'the book names ' .. table.concat(path, '.') .. ', which isn\'t here' end
        rawset(parent, path[#path], objs[id])
    end
    -- 4: what codecs packed, made again
    for id, r in ipairs(recs) do
        if r.kind == 'k' then
            local codec = CODECS[r.class]
            if not codec then return nil, 'the book names a codec ' .. r.class .. ', which isn\'t here' end
            codec.unpack(objs[id])
        end
    end
    return objs[1]
end

--------------------------------------------------------------------------------
-- The jar's book
--------------------------------------------------------------------------------

-- The flora's fronds, which the state hash takes beside the World
local function fronds(around)
    return around and around.flora and around.flora.all()
end

-- The book of `world` as text, with what's `around` it ({flora = Plants,
-- motes = Motes}: modules with state() and restore()). `extra` is kept beside
-- it as it is (main.lua keeps who the lantern follows).
function Book.write(world, around, extra)
    local kept = {}
    for name, m in pairs(around or {}) do kept[name] = m.state() end
    local root = {
        version = Book.VERSION,
        seed = rng.jar,
        saved = os.time(), -- the wall clock, for catching up on time away (#31)
        time = world.time,
        hash = statehash.of(world, fronds(around)).total,
        world = world,
        around = kept,
        streams = {sim = rng.sim:getState(), look = rng.look:getState()},
        extra = extra,
    }
    return Book.encode(root)
end

-- A book's text read back: {world, seed, hash, saved, extra, ...} with its
-- World revived, or nil and why. Call Book.resume once the jar around it is
-- composed again from its seed.
function Book.read(s)
    local ok, root, err = pcall(Book.decode, s)
    if not ok then return nil, tostring(root) end
    if not root then return nil, err end
    if type(root.world) ~= 'table' or type(root.around) ~= 'table' then return nil, 'a book with no jar in it' end
    root.world:revive()
    return root
end

-- The rest of a jar read back, once what's `around` it is composed again
-- from `book.seed` (which reseeds the streams): what's around it as it was,
-- then, last, the streams. Returns whether it hashes as it did, and its hash.
function Book.resume(book, around)
    for name, m in pairs(around or {}) do
        if book.around[name] then m.restore(book.around[name]) end
    end
    rng.sim:setState(book.streams.sim)
    rng.look:setState(book.streams.look)
    local now = statehash.of(book.world, fronds(around)).total
    return now == book.hash, now
end

-- Where the book is kept: beside Easel's other data for this jar if the frame
-- launched it ($EASEL_DATA), else in LÖVE's save directory
function Book.dir()
    local easel = os.getenv('EASEL_DATA')
    if easel and easel ~= '' then return easel end
    love.filesystem.createDirectory('') -- (LÖVE makes the save directory on its first write)
    return love.filesystem.getSaveDirectory()
end

local function slurp(file)
    local f = io.open(file, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

-- os.rename, tried again a little later if it's refused (on Windows a file
-- just written can be held a moment by whatever scans it)
local function rename(from, to)
    local ok, err
    for _ = 1, 5 do
        ok, err = os.rename(from, to)
        if ok then return true end
        love.timer.sleep(0.02)
    end
    return nil, err
end

-- Write `text` to the book at `file`. It's written beside it first (`.new`)
-- and moved into place, and the last book is kept as `file`.old, so a quit
-- in the middle of a write (a SIGTERM, a power cut) never leaves no book.
function Book.store(text, file)
    file = file or (Book.dir() .. '/' .. Book.FILE)
    local new = file .. '.new'
    local f, err = io.open(new, 'wb')
    if not f then return nil, err end
    local ok, werr = f:write(text)
    f:close()
    if not ok then return nil, werr end
    os.remove(file .. '.old')
    rename(file, file .. '.old')
    local moved, merr = rename(new, file)
    if not moved then return nil, merr end
    return true
end

-- Save `world`'s book to `file` (by default, Book.FILE in Book.dir()).
-- Returns the seconds it took, or nil and why.
function Book.save(world, around, extra, file)
    local t0 = love.timer.getTime()
    local ok, text = pcall(Book.write, world, around, extra)
    if not ok then return nil, text end
    local stored, err = Book.store(text, file)
    if not stored then return nil, err end
    return love.timer.getTime() - t0, #text
end

-- Open the book at `file`, or if that can't be read, one written but never
-- moved into place, or the one before it. A book that can't be read is moved
-- aside (to `.unread`), never deleted.
-- Returns the book (see Book.read), or nil and why.
function Book.open(file)
    file = file or (Book.dir() .. '/' .. Book.FILE)
    local why
    for _, f in ipairs({file, file .. '.new', file .. '.old'}) do
        local s = slurp(f)
        if s then
            local book, err = Book.read(s)
            if book then return book, f end
            log.info('book', '%s: %s; kept aside as %s.unread', f, err, f)
            os.remove(f .. '.unread')
            os.rename(f, f .. '.unread')
            why = why or err
        end
    end
    return nil, why or 'no book yet'
end

log.always.book = true

return Book
