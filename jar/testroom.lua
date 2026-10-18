-- Test room: the jar's interior with nothing in it yet but soil and one stone.
--
-- Same format as Character's world/levels/cave.lua, sized to the jar (800x600).
-- Solids are all physics and navigation see. The walls sit just outside the
-- glass, with their inner faces 22px in, which is where Level:top_spans expects them.
-- The real scenery (shelf, twig bridge, cork arch) replaces this in #4.

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

        -- One flat stone, low enough for every body to reach
        {id = 'stone',   kind = 'ledge',   x = 470, y = 340, w = 170, h = 24,  moss = true},
    },

    -- Where each creature starts (surface x, solid id)
    spawns = {
        worm   = {solid = 'soil', x = 150},
        blob   = {solid = 'soil', x = 330},
        spider = {solid = 'soil', x = 700},
    },
}
