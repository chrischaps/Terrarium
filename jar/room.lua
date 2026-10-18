-- The jar's room: soil, a cork-bark arch, a twig bridge over a water dish, a
-- stone cairn and a slate shelf on the right-hand glass.
--
-- Same format as Character's world/levels/cave.lua, sized to the jar (800x600).
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
-- The climb, for the walkers: soil -> arch, standing stone or cairn (a jump of
-- 80-84) -> the twig joins the stone to the cairn -> shelf (a jump of 84 off the
-- cairn). Nothing reaches the shelf from the soil in one jump, so getting there
-- is a small journey. Spiders take the glass.

return {
    width = 800,
    height = 600,
    seed = 1,

    -- The lamp hangs above the lid. Bodies shade themselves away from it.
    lamp = {x = 400, y = -40},

    solids = {
        -- The glass and the lid
        {id = 'glass_l', kind = 'wall',    x = -60, y = -60, w = 82,  h = 720},
        {id = 'glass_r', kind = 'wall',    x = 778, y = -60, w = 82,  h = 720},
        {id = 'lid',     kind = 'ceiling', x = -60, y = -60, w = 920, h = 92},

        -- Soil, mossed on top
        {id = 'soil',    kind = 'floor',   x = -60, y = 420, w = 920, h = 240, moss = true},

        -- The cork-bark arch: a curl of bark standing on one foot, with room
        -- underneath for a blob to pass and a spider to hang
        {id = 'arch',      kind = 'ledge', x = 150, y = 340, w = 190, h = 18, moss = true, material = 'cork'},
        {id = 'arch_foot', kind = 'ledge', x = 160, y = 356, w = 28,  h = 68, material = 'cork', part_of = 'arch'},
        {id = 'arch_lip',  kind = 'ledge', x = 326, y = 356, w = 14,  h = 14, material = 'cork', part_of = 'arch'},

        -- A standing stone and a cairn of flat stones, a twig laid between them
        -- over the water dish
        {id = 'stone',   kind = 'ledge',   x = 436, y = 336, w = 46,  h = 88, moss = true, material = 'stone'},
        {id = 'twig',    kind = 'ledge',   x = 482, y = 336, w = 88,  h = 6,  moss = true, material = 'twig'},
        {id = 'cairn',   kind = 'ledge',   x = 570, y = 336, w = 60,  h = 88, moss = true, material = 'stone'},

        -- The shelf: a slate wedged against the right-hand glass
        {id = 'shelf',   kind = 'ledge',   x = 662, y = 252, w = 138, h = 22, moss = true, material = 'slate'},
    },

    -- Decoration only: the water dish sunk into the soil under the twig
    water = {x0 = 482, x1 = 570, y = 420},

    -- Where each creature starts (surface x, solid id)
    spawns = {
        worm   = {solid = 'soil', x = 100},
        blob   = {solid = 'soil', x = 390},
        spider = {solid = 'soil', x = 720},
    },
}
