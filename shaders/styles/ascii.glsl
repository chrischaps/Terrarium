// Terrarium: ascii (#97), the second pass (jar/ascii.lua). Every pixel finds
// its cell and inks the glyph the cell's light asks for, in the cell's colour:
// a glyph off the ramp by how bright it is; the stroke along an edge where
// one runs through it (| / - \), so outlines read as lines; and where the
// cell is the moss's green, a roguelike's grass (, ") instead, so a creature,
// never that green, stands out of it in the ramp's dense glyphs. Dark cells
// go almost black, with only a breath of their colour behind the glyph, the
// way a terminal's phosphor glows.
extern Image eye;    // one texel: the frame's mean light
extern Image cells;  // a texel a cell: its colour
extern Image edges;  // a texel a cell: how its light runs (x, y), its pressed light, how much it's moss
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

    // (by day the jar is a dark room: most of it lies between 0.1 and 0.2, a
    // quiet field of dots, with its moss, creatures and the lamp's pool above,
    // so the ramp spans 0.1 to 0.6. By night the eye opens, up to three times,
    // as the jar's mean light falls below a day's.)
    float open = clamp(0.16 / max(Texel(eye, vec2(0.5)).r, 0.001), 1.0, 3.0);
    float y = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float t = pow(clamp((y * open - 0.1) / 0.5, 0.0, 1.0), 0.85);
    float pick = floor(t * (ramp - 1.0) + 0.5);

    if (run.w > 0.5 && t > 0.06) {
        // the moss: sparse grass, then thick
        pick = ramp + 4.0 + (t > 0.12 ? 1.0 : 0.0);
    } else if (length(run.xy) > 0.11 && t > 0.05) {
        // an edge through the cell, if the light runs across it hard enough
        float a = mod(atan(run.y, run.x) + PI, PI);
        pick = ramp + mod(floor(a / (PI * 0.25) + 0.5), 4.0);
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
    vec3 c = rich * lift * mask + col * 0.05;
    return vec4(c, 1.0);
}
