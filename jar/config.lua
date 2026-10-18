-- From chrischaps/Fishbowl @ b0624e4 (config.lua)
-- Shared constants for the jar.
-- The jar is a shallow 3D box on a desk, seen through its front glass: world
-- x/y are pixels at the front glass, d is depth (0 = back glass, 1 = front glass).
-- Terrarium: the creatures live on one plane inside the box (PLANE_D), and the
-- level's own coordinates (Character's format) are placed on that plane at OX, OY.

local C = {}

C.W, C.H = 1280, 800

-- Projection: points farther back shrink toward this vanishing point
C.CX, C.CY = 640, 300
C.K_BACK = 0.84             -- projected scale at the back glass

-- Terrarium: where the level's origin sits in world space, and its depth
C.OX, C.OY = 240, 130
C.PLANE_D = 0.70            -- the creatures' plane: sharp, a little behind the glass
C.LEVEL_W, C.LEVEL_H = 800, 600

-- Terrarium: the box, in level coordinates. Inner side faces match the level's
-- walls (22px in, where Level:top_spans expects them); the lid's underside is 32.
C.GLASS_L, C.GLASS_R = 22, 778
C.GLASS_T = 32              -- underside of the lid
C.GLASS_B = 600             -- the jar's base, which stands on the desk
C.GLASS_THICK = 6
C.SOIL_Y = 420              -- soil top on the creatures' plane
C.SOIL_RISE = 14            -- the soil banks up a little toward the back glass

-- Terrarium: the desk runs from the wall behind the jar to just past the camera
C.DESK_BACK_D = -1.9
C.DESK_FRONT_D = 1.55

C.FAR_D = 0.32              -- scape behind this is drawn soft (depth of field)

-- Terrarium: a jar day is a real day (the light itself is jar/daycycle.lua)
C.DAY_SECONDS = 24 * 60 * 60

-- Terrarium: the lamp hangs over the middle of the lid; its light falls in a cone
C.LAMP_X = (C.GLASS_L + C.GLASS_R) / 2
C.LAMP_CONE = { top = 150, bottom = 360 }  -- half-widths at the lid and at the soil

-- The scape (stones, soil, the grain of the desk) is composed from its own
-- stream, seeded from the jar's seed, so the same jar always looks the same and
-- composing it never moves the simulation. See rng.scape.

return C
