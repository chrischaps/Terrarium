-- The family book (#32): a week in one jar, read back. The jar is opened at
-- lamp-on with 900-second days and left a week, sitting everyone for their
-- portraits as live play does. You last closed the book at dawn on the last
-- day but one, so what happened after is what happened while you were away.
-- Then the book is opened and every spread saved: book_01.png (its title and
-- while you were away), book_02.png on (two creatures a page each, in the
-- order they came), and book_desk.png, the jar with the book closed beside it
-- and a slip of paper in it. The whole book is printed as text too, so a week
-- of it can be read as a family history.
--
--   lovec . --script scripts/book.lua                 (about ten minutes)
--   BOOK_DAYS=2 lovec . --script scripts/book.lua     (fewer days)

return {run = function(api)
    local days = tonumber(os.getenv('BOOK_DAYS')) or 7
    local DAY = api.args.day or 900
    local w = api.open(api.args.seed or 20261018, 'lampon', nil, DAY, api.World.CLASSIC)
    local book = api.book()
    local Book = api.Book
    api.portraits()
    local away = (days - 1) * DAY - (7.2 - 6) / 24 * DAY -- (dawn on the last day but one)
    local hour = DAY / 24
    local t0 = love.timer.getTime()
    for h = 1, days * 24 do
        api.step(hour)
        api.portraits()
        if w.time >= away and book.seen == 0 then book:close() end
        if h % 24 == 0 then
            print(string.format('[book] day %d: %d in the book, %d alive (%.0fs)', h / 24, #book.entries,
                book:living(), love.timer.getTime() - t0))
        end
        api.yield()
    end
    api.save(api.render(1600, 1000), 'book_desk.png')

    -- The book as text
    print('\n== The Family Book\n')
    print('While you were away:')
    for _, h in ipairs(book:since(book.seen)) do
        local e = h.entry
        if h.kind == 'born' then
            print(string.format('  day %d: %s hatched', book:day_of(h.at), Book.named(e)))
        elseif h.kind == 'gone' then
            print(string.format('  day %d: %s went back to the moss, after %s', book:day_of(h.at), Book.named(e),
                Book.days(book:lived(e))))
        else
            print(string.format('  day %d: %s and %s laid %d', book:day_of(h.at),
                Book.named(book.entries[h.clutch.parents[1]]), Book.named(book.entries[h.clutch.parents[2]]), h.clutch.count))
        end
    end
    print('')
    for _, e in ipairs(book.entries) do
        local function names(ns)
            local out = {}
            for _, n in ipairs(ns or {}) do out[#out + 1] = Book.named(book.entries[n]) end
            return Book.list(out)
        end
        print(string.format('%s, a %s, %s.%s%s %s.', Book.named(e), e.key,
            e.founder and 'came with the jar' or 'hatched on the ' .. Book.ordinal(book:day_of(e.came)) .. ' day',
            e.parents and ' Child of ' .. names(e.parents) .. '.' or '',
            #e.children > 0 and ' Parent of ' .. names(e.children) .. '.' or '',
            e.gone and string.format('Lived %s, gone on the %s day', Book.days(book:lived(e)), Book.ordinal(book:day_of(e.gone)))
                or 'Has lived ' .. Book.days(book:lived(e))))
    end

    for s = 1, (#book.entries > 0 and 1 + math.ceil(#book.entries / 2) or 1) do
        api.page(s)
        api.save(api.render(1600, 1000), string.format('book_%02d.png', s))
    end
    -- (and a leaf of it turning over, the third spread to the fourth)
    api.page(3, 0.35)
    api.save(api.render(1600, 1000), 'book_turn.png')
    api.page(nil)
end}
