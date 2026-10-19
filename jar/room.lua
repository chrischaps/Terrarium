-- The jar's room: soil, a cork-bark arch, a twig bridge over a water dish, a
-- stone cairn and a slate shelf on the right-hand glass.
--
-- Same format as Character's world/levels/cave.lua, sized to the jar (2000x780).
-- Solids are all physics and navigation see; jar/scenery.lua draws them. The
-- walls sit just outside the glass, with their inner faces 22px in, which is
-- where Level:top_spans expects them.
--
-- Tags on a solid:
--   moss      its exposed top is a moss surface (the moss grid covers it in M3)
--   material  how jar/scenery.lua draws it: cork, twig, stone, slate
--   part_of   drawn as one piece with that solid
--
-- Seen side-on, any roof that's grounded at both ends seals the floor beneath
-- it: nothing can walk in, jump out or climb round. So the arch stands on one
-- foot and stays open on its right, and the twig bridge is the only roof with
-- two ends down, over water nobody needs to reach. NavGraph:keep_home drops the
-- floor under it from every graph.
--
-- The climb, for the walkers: on the left, soil -> arch, standing stone or
-- cairn (a jump of 80-84) -> the twig joins the stone to the cairn. In the
-- middle, a flat stone basks under the lamp. On the right, soil -> the root or
-- the log (82) -> the tor between them (82) -> the shelf (84 off the tor).
-- Nothing reaches the shelf from the soil in one jump, so getting there is a
-- small journey. Spiders take the glass.
--
-- Terrarium: the jar is 2000 wide and drawn at C.S (jar/config.lua), so its
-- residents are small in it and there's room between the places they go.

return {
    width = 2000,
    height = 780,
    seed = 1,

    -- The lamp hangs above the lid. Bodies shade themselves away from it.
    lamp = {x = 1000, y = -40},

    solids = {
        -- The glass and the lid
        {id = 'glass_l', kind = 'wall',    x = -60,  y = -60, w = 82,   h = 1180},
        {id = 'glass_r', kind = 'wall',    x = 1978, y = -60, w = 82,   h = 1180},
        {id = 'lid',     kind = 'ceiling', x = -60,  y = -60, w = 2120, h = 92},

        -- Soil, mossed on top
        {id = 'soil',    kind = 'floor',   x = -60, y = 560, w = 2120, h = 280, moss = true},

        -- The cork-bark arch: a curl of bark standing on one foot, with room
        -- underneath for a blob to pass and a spider to hang
        {id = 'arch',      kind = 'ledge', x = 270, y = 480, w = 190, h = 18, moss = true, material = 'cork'},
        {id = 'arch_foot', kind = 'ledge', x = 280, y = 496, w = 28,  h = 68, material = 'cork', part_of = 'arch'},
        {id = 'arch_lip',  kind = 'ledge', x = 446, y = 496, w = 14,  h = 14, material = 'cork', part_of = 'arch'},

        -- A standing stone and a cairn of flat stones, a twig laid between them
        -- over the water dish
        {id = 'stone',   kind = 'ledge',   x = 640, y = 476, w = 46,  h = 88, moss = true, material = 'stone'},
        {id = 'twig',    kind = 'ledge',   x = 686, y = 476, w = 88,  h = 6,  moss = true, material = 'twig'},
        {id = 'cairn',   kind = 'ledge',   x = 774, y = 476, w = 60,  h = 88, moss = true, material = 'stone'},

        -- A flat stone in the lamp's pool, low enough to hop onto
        {id = 'flat',    kind = 'ledge',   x = 1060, y = 498, w = 160, h = 66, moss = true, material = 'stone'},

        -- The climb: a cork root and a cork log either side of a tor of stone
        {id = 'root',    kind = 'ledge',   x = 1520, y = 482, w = 70,  h = 82,  moss = true, material = 'cork'},
        {id = 'tor',     kind = 'ledge',   x = 1590, y = 400, w = 68,  h = 164, moss = true, material = 'stone'},
        {id = 'log',     kind = 'ledge',   x = 1658, y = 482, w = 100, h = 82,  moss = true, material = 'cork'},

        -- The shelf: a slate wedged against the right-hand glass, over the log
        {id = 'shelf',   kind = 'ledge',   x = 1690, y = 316, w = 288, h = 22, moss = true, material = 'slate'},
    },

    -- Decoration only: the water dish sunk into the soil under the twig
    water = {x0 = 686, x1 = 774, y = 560},

    -- Terrarium: who lives here and where each starts (solid id, surface x).
    -- The names are placeholders until naming (#29); a jar's own come from its book.
    residents = {
        {key = 'worm',   name = 'Loam',  solid = 'soil',  x = 160},
        {key = 'worm',   name = 'Rill',  solid = 'arch',  x = 370},
        {key = 'blob',   name = 'Dew',   solid = 'soil',  x = 960},
        {key = 'blob',   name = 'Bead',  solid = 'cairn', x = 800},
        {key = 'spider', name = 'Wick',  solid = 'soil',  x = 1860},
        {key = 'spider', name = 'Tansy', solid = 'shelf', x = 1880},
    },
}
