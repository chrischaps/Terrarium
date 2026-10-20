-- The jar's room: soil, a cork-bark arch, a twig bridge over a water dish, a
-- stone cairn, a stair of basalt columns up the left-hand glass, and in the
-- right-hand corner an old stump with a slate shelf, a branch and a fungus.
--
-- Same format as Character's world/levels/cave.lua, sized to the jar (2000x1080).
-- Solids are all physics and navigation see; jar/scenery.lua draws them. The
-- walls sit just outside the glass, with their inner faces 22px in, which is
-- where Level:top_spans expects them.
--
-- Tags on a solid:
--   moss      its exposed top is a moss surface, covered by the moss grid (jar/moss.lua)
--   material  how jar/scenery.lua draws it: cork, twig, stone, slate, basalt
--   part_of   drawn as one piece with that solid
--
-- Seen side-on, any roof that's grounded at both ends seals the floor beneath
-- it: nothing can walk in, jump out or climb round. So the arch stands on one
-- foot and stays open on its right, and the twig bridge is the only roof with
-- two ends down, over water nobody needs to reach. NavGraph:keep_home drops the
-- floor under it from every graph.
--
-- The climb, for the walkers: on the left, soil -> arch, standing stone or
-- cairn (a jump of 80-84) -> the twig joins the stone to the cairn, and from the
-- arch the basalt stair goes up to the glass, 80 a column, to the highest top in
-- the jar, 440 over the soil. In the middle, a flat stone basks under the lamp.
-- On the right, soil -> the root or the log (78) -> the tor between them (82)
-- -> the shelf (84 off the tor) -> the stump's branch (80), its fungus and its
-- top (68 each), 460 over the soil. Nothing reaches the shelf from the soil
-- in one jump, so getting there is a small journey, and the tops of the stair
-- and the stump longer ones. Both stand against the glass: a tower out in the
-- jar would be a wall, with nothing over it for a walker. Spiders and snails
-- take the glass, and the air between the towers is theirs and the
-- springtails'.
--
-- Terrarium: the jar is 2000 wide and drawn at C.S (jar/config.lua), so its
-- residents are small in it and there's room between the places they go. It's
-- 1080 tall, so there's room above them too.

return {
    width = 2000,
    height = 1080,
    seed = 1,

    -- The lamp hangs above the lid. Bodies shade themselves away from it.
    lamp = {x = 1000, y = -40},

    solids = {
        -- The glass and the lid
        {id = 'glass_l', kind = 'wall',    x = -60,  y = -60, w = 82,   h = 1480},
        {id = 'glass_r', kind = 'wall',    x = 1978, y = -60, w = 82,   h = 1480},
        {id = 'lid',     kind = 'ceiling', x = -60,  y = -60, w = 2120, h = 92},

        -- Soil, mossed on top
        {id = 'soil',    kind = 'floor',   x = -60, y = 860, w = 2120, h = 280, moss = true},

        -- The basalt stair: five columns stood side by side, each 80 over the
        -- last, from the arch up to the left-hand glass, like a causeway set on
        -- end. The lowest is broad, a landing off the arch.
        {id = 'col_1',   kind = 'ledge',   x = 250, y = 740, w = 80, h = 124, moss = true, material = 'basalt'},
        {id = 'col_2',   kind = 'ledge',   x = 193, y = 660, w = 57, h = 204, moss = true, material = 'basalt'},
        {id = 'col_3',   kind = 'ledge',   x = 136, y = 580, w = 57, h = 284, moss = true, material = 'basalt'},
        {id = 'col_4',   kind = 'ledge',   x = 79,  y = 500, w = 57, h = 364, moss = true, material = 'basalt'},
        {id = 'col_5',   kind = 'ledge',   x = 22,  y = 420, w = 57, h = 444, moss = true, material = 'basalt'},

        -- The cork-bark arch: a curl of bark standing on one foot against the
        -- stair, with room underneath for a blob to pass and a spider to hang
        {id = 'arch',      kind = 'ledge', x = 330, y = 780, w = 190, h = 18, moss = true, material = 'cork'},
        {id = 'arch_foot', kind = 'ledge', x = 330, y = 796, w = 28,  h = 68, material = 'cork', part_of = 'arch'},
        {id = 'arch_lip',  kind = 'ledge', x = 506, y = 796, w = 14,  h = 14, material = 'cork', part_of = 'arch'},

        -- A standing stone and a cairn of flat stones, a twig laid between them
        -- over the water dish
        {id = 'stone',   kind = 'ledge',   x = 640, y = 776, w = 46,  h = 88, moss = true, material = 'stone'},
        {id = 'twig',    kind = 'ledge',   x = 686, y = 776, w = 88,  h = 6,  moss = true, material = 'twig'},
        {id = 'cairn',   kind = 'ledge',   x = 774, y = 776, w = 60,  h = 88, moss = true, material = 'stone'},

        -- A flat stone in the lamp's pool, low enough to hop onto
        {id = 'flat',    kind = 'ledge',   x = 1060, y = 798, w = 160, h = 66, moss = true, material = 'stone'},

        -- The climb: a cork root and a cork log either side of a tor of stone
        {id = 'root',    kind = 'ledge',   x = 1460, y = 782, w = 70,  h = 82,  moss = true, material = 'cork'},
        {id = 'tor',     kind = 'ledge',   x = 1530, y = 700, w = 68,  h = 164, moss = true, material = 'stone'},
        {id = 'log',     kind = 'ledge',   x = 1598, y = 782, w = 100, h = 82,  moss = true, material = 'cork'},

        -- An old stump stood on end in the corner, against the right-hand
        -- glass. The shelf, a slate, is wedged against it over the log; above
        -- that a branch broke off short, and above the branch a bracket of
        -- fungus has grown out of it, so they step up to its top.
        {id = 'stump',   kind = 'ledge',   x = 1918, y = 400, w = 60,  h = 464, moss = true, material = 'cork'},
        {id = 'shelf',   kind = 'ledge',   x = 1630, y = 616, w = 288, h = 22,  moss = true, material = 'slate'},
        {id = 'branch',  kind = 'ledge',   x = 1800, y = 536, w = 118, h = 12,  moss = true, material = 'twig'},
        {id = 'conk',    kind = 'ledge',   x = 1868, y = 468, w = 50,  h = 22,  material = 'fungus', on = 'stump'},
    },

    -- Decoration only: the water dish sunk into the soil under the twig
    water = {x0 = 686, x1 = 774, y = 860},

    -- Terrarium: a home for a pair of every kind, and where each starts (solid
    -- id, and x along its top). A jar's cast (#74, World.cast_of) says which
    -- pairs move in. The names are placeholders until naming (#29); a jar's own
    -- come from its book.
    --
    -- Each starts where its body wants to: the springtails in the soil and
    -- on the flat stone, the snails in the soil under the arch and high on the
    -- left-hand glass over the stair (`y` up its inner face, #77; the one on a
    -- top first, so the self-test lays a snail's eggs by it), and the moth still
    -- to come (`under`) beneath the shelf and the lid, which #78 teaches
    -- World:place.
    homes = {
        {key = 'worm',       name = 'Loam',   solid = 'soil',    x = 580},
        {key = 'worm',       name = 'Rill',   solid = 'arch',    x = 430},
        {key = 'blob',       name = 'Dew',    solid = 'soil',    x = 960},
        {key = 'blob',       name = 'Bead',   solid = 'cairn',   x = 800},
        {key = 'spider',     name = 'Wick',   solid = 'soil',    x = 1860},
        {key = 'spider',     name = 'Tansy',  solid = 'shelf',   x = 1840},
        {key = 'springtail', name = 'Fleck',  solid = 'soil',    x = 1340},
        {key = 'springtail', name = 'Pip',    solid = 'flat',    x = 1110},
        {key = 'snail',      name = 'Sorrel', solid = 'soil',    x = 440},
        {key = 'snail',      name = 'Whorl',  solid = 'glass_l', y = 300},
        {key = 'moth',       name = 'Dusk',   solid = 'shelf',   x = 1800, under = true},
        {key = 'moth',       name = 'Lumen',  solid = 'lid',     x = 1240, under = true},
    },
}
