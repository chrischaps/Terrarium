// Terrarium: ascii (#97), the second pass (jar/ascii.lua). Every pixel finds
// its cell and inks the glyph its cell asks for, in the cell's colour. What
// it asks for comes of the cell's kind (from the first pass):
//
//   6  the frame set at once (ascii): a glyph off the ramp by its light, or
//      the stroke along an edge where its light runs hard across it;
//   5  a creature (ascii-each): dense, never lighter than the ramp's middle,
//      in its own colour, so a body reads however small; a sliver of it at
//      its edge is the stroke along its silhouette;
//   4  the moss: a roguelike's grass, sparse (,) then thick (");
//   3  a prop, 2 the soil: its outline in strokes along its silhouette, its
//      inside at most two steps (. :) and only as its broad light asks;
//   1  a far thing: a fainter outline and nothing in it;
//   0  the ground (the room, the air, the jar's far side): all but bare, a
//      faint dot where it's lit and a faint stroke where its light breaks,
//      and the ramp only where the lamp's light is strong.
//
// Dark cells go almost black, with only a breath of their colour behind the
// glyph, the way a terminal's phosphor glows.
extern Image eye;    // one texel: the frame's mean light
extern Image cells;  // a texel a cell: its colour
extern Image edges;  // a texel a cell: how it runs (x, y), its cover, its kind over 8
extern Image atlas;  // the glyphs, a cell each in a row
extern vec2 grid;    // columns, rows
extern vec2 cellPx;  // a cell in the target's pixels
extern vec2 outPx;   // the target's size
extern float glyphCount;
extern float ramp;   // glyphs on the ramp; the four edges and two grasses follow them
extern float slot[16]; // the ramp's glyphs, light to dark ink, then the rest, as atlas cells

const float PI = 3.14159265;

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec2 px = tc * outPx;
    vec2 cell = floor(px / cellPx);
    vec2 inside = px - cell * cellPx;
    vec2 at = (cell + 0.5) / grid;
    vec3 col = Texel(cells, at).rgb;
    vec4 run = Texel(edges, at);
    float kind = floor(run.w * 8.0 + 0.5);
    float cover = run.z;
    float slope = length(run.xy);

    // (by day the jar is a dark room: most of it lies between 0.1 and 0.2, a
    // quiet field of dots, with its moss, creatures and the lamp's pool above,
    // so the ramp spans 0.1 to 0.6. By night the eye opens, up to three times,
    // as the jar's mean light falls below a day's.)
    float open = clamp(0.16 / max(Texel(eye, vec2(0.5)).r, 0.001), 1.0, 3.0);
    float y = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float t = pow(clamp((y * open - 0.1) / 0.5, 0.0, 1.0), 0.85);
    float pick = floor(t * (ramp - 1.0) + 0.5);
    float stroke = ramp + mod(floor(mod(atan(run.y, run.x) + PI, PI) / (PI * 0.25) + 0.5), 4.0);
    float grass = ramp + 4.0 + (t > 0.12 ? 1.0 : 0.0);
    float ink = 1.0;

    if (kind > 5.5) {
        // the frame set at once
        if (slope > 0.11 && t > 0.05) pick = stroke;
    } else if (kind > 4.5) {
        // a creature
        pick = (cover < 0.4 && slope > 0.2) ? stroke : max(pick, floor(ramp * 0.5));
        ink = 1.15;
    } else if (kind > 3.5) {
        // the moss
        if (t > 0.06) pick = grass;
        ink = 1.2;
    } else if (kind > 1.5) {
        // a prop, or the soil
        if (cover < 0.85 && slope > 0.25) {
            pick = stroke;
            ink = 1.1;
        } else {
            // (the soil's light is taken more broadly: it's dark, and
            // a field of dots is what keeps the jar's mass)
            float lo = kind > 2.5 ? 0.1 : 0.0, hi = kind > 2.5 ? 0.35 : 0.2;
            pick = t <= lo ? 0.0 : (t < hi ? 1.0 : 2.0);
            ink = 0.8;
        }
    } else if (kind > 0.5) {
        // a far thing
        pick = (cover < 0.85 && slope > 0.25) ? stroke : 0.0;
        ink = 0.6;
    } else {
        // the ground
        if (slope > 0.14 && t > 0.05) {
            pick = stroke;
            ink = 0.6;
        } else {
            // (bare but for a dot, except where the lamp's light is strong)
            pick = t > 0.4 ? pick : min(pick, 1.0);
            ink = 0.55;
        }
    }

    float s = 0.0;
    for (int i = 0; i < 16; i++) {
        if (float(i) == pick) s = slot[i];
    }
    float mask = Texel(atlas, vec2((s * cellPx.x + inside.x) / (glyphCount * cellPx.x), inside.y / cellPx.y)).a;

    // The ink is the cell's colour a little richer, lifted so a glyph's
    // strokes are as bright as its place on the ramp: a sparse one in the
    // dark still shows its cell's colour, a dense one under the lamp burns.
    // A night's ink stays a little dimmer than a day's, opened eye or not.
    vec3 rich = max(mix(vec3(y), col, 1.35), 0.0);
    float lift = min((0.3 + 0.8 * t) * (0.6 + 0.4 / open) / max(y, 0.001), 8.0 * open);
    vec3 c = rich * lift * ink * mask + col * (kind > 5.5 ? 0.05 : 0.025);
    return vec4(c, 1.0);
}
