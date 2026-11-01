// Terrarium: probe-matte (#98, jar/styles.lua; --probes). The matte itself
// (jar/matte.lua) in false colour, to see what a style is told: each kind of
// layer its own colour, darker the deeper it is, and the creatures red.
extern Image matte;

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec4 m = Texel(matte, tc);
    int k = int(floor(m.g * 6.0 + 0.5));
    vec3 c = vec3(0.06, 0.06, 0.08);           // nothing: the room, the glass, the light
    if (k == 1) c = vec3(0.45, 0.32, 0.20);    // soil
    if (k == 2) c = vec3(0.40, 0.45, 0.55);    // the scape's stones and plants
    if (k == 3) c = vec3(0.75, 0.62, 0.42);    // the scenery
    if (k == 4) c = vec3(0.35, 0.65, 0.25);    // moss
    if (k == 5) c = vec3(0.95, 0.85, 0.35);    // eggs, crumbs, trails
    if (k == 6) c = vec3(0.95, 0.20, 0.25);    // creatures
    c *= 0.45 + 0.55 * m.b;
    // (and the frame, faintly, to find your way)
    float y = dot(max(Texel(frame, tc).rgb, 0.0), vec3(0.2126, 0.7152, 0.0722));
    c = mix(c, vec3(y), 0.12);
    return vec4(c, 1.0);
}
