// Terrarium: ascii-each (#97, jar/ascii.lua): a thing drawn on its own,
// marked on the frame's map of what's where. Where it covers at least half a
// pixel, the map takes its kind and its seed; a thing laid later (in front)
// marks over one laid before it.
extern float kind; // Ascii.KIND over 7
extern float seed; // its own, over 127

vec4 effect(vec4 vcolor, Image thing, vec2 tc, vec2 sc) {
    float a = Texel(thing, tc).a;
    if (a < 0.5) discard;
    return vec4(kind, seed, a, 1.0);
}
