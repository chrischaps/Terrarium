// Terrarium: watercolour-each (#96), the frame's own pass. Every thing in the
// jar was painted already, one at a time (watercolour_body.glsl), and the
// frame's alpha is how much of each pixel is still to paint: 0 on a thing, 1
// on the ground round them (the room, the jar's air and its far side). That
// ground is kept close to the paper, a pale wash of its colour that deepens
// a little where it's dark, laid as two or three glazes with soft wet edges,
// blooming and running back in the flat. Its own edges come only from the
// ground, never from a thing, so no thing gets a second outline. What was
// painted already is kept as it is; a layer alpha-blended in front of a
// thing after it (a mote, condensation, the lamp's light) lightens it and no
// more. All of it is fixed to the page.
#include "watercolour_common.glsl"
extern vec2 px;     // one of the window's px in texture coordinates
extern vec2 ground; // how deep the wash goes where it's darkest, and its wet edges

// The ground's colour round tc, `r` apart: only the ground counts
vec4 groundRing(Image frame, vec2 tc, vec2 r) {
    vec4 s = vec4(0.0);
    for (int k = 0; k < 8; k++) {
        float a = float(k) * 0.78539816 + 0.39;
        vec4 t = Texel(frame, tc + vec2(cos(a), sin(a)) * r);
        // (only what's wholly ground: a thing's soft edge holds its paint)
        float g = smoothstep(0.85, 1.0, t.a);
        s += vec4(max(t.rgb, 0.0) * g, g);
    }
    return s;
}

// The wash the ground at colour c is painted with: its colour, lightened
// toward the paper as far as `deep` lets it be dark
float washOf(vec3 c) { return 1.0 - lum(pow(clamp(c, 0.0, 1.0), vec3(0.6))); }

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec2 p = tc / px; // the window's px, on the page
    vec4 c0 = Texel(frame, tc);
    float g = clamp(c0.a, 0.0, 1.0);

    // The ground's colour, taken broadly
    float g0 = smoothstep(0.85, 1.0, c0.a);
    vec4 r1 = groundRing(frame, tc, 4.0 * px);
    vec4 r2 = groundRing(frame, tc, 11.0 * px);
    vec4 r3 = groundRing(frame, tc, 24.0 * px);
    vec3 c = (max(c0.rgb, 0.0) * g0 + r1.rgb + r2.rgb + r3.rgb) / max(g0 + r1.a + r2.a + r3.a, 0.002);
    vec3 farc = (r2.rgb + r3.rgb) / max(r2.a + r3.a, 0.002);

    // How much pigment: a little, deeper where the ground is dark, in soft
    // glazes whose boundaries wander
    float w = washOf(c);
    float wander = noise(p / 38.0 + 3.7) * 0.75 + noise(p / 12.0 + 6.1) * 0.25;
    float y = w * 3.0 + (wander - 0.5) * 0.8;
    float wq = (floor(y) + smoothstep(0.2, 0.8, fract(y))) / 3.0;
    // (by day a pale wash; at night, still the paper, but a deeper wash of
    // the night's own colour over it)
    float night = smoothstep(0.6, 0.8, w);
    w = mix(w, wq, 0.4) * ground.x * (1.0 + 0.8 * night);

    // ...and its hue: the ground's own, washed out
    float lc = max(lum(c), 0.02);
    vec3 hue = clamp(mix(vec3(1.0), c / lc, 0.55), 0.0, 1.6);
    vec3 pig = clamp(vec3(0.22) * hue, 0.0, 1.0);

    // Wet edges where the ground's own wash steps darker than round it, a
    // bloom, the backruns in the flat, the tooth
    float edge = clamp((washOf(c) - washOf(farc)) * 3.0, 0.0, 0.6) * ground.y;
    float bloom = noise(p / 70.0 + 19.0) * 0.6 + noise(p / 23.0 + 2.3) * 0.4;
    vec2 q = p / 260.0;
    float tide = noise(q + 5.0) * 0.8 + noise(q * 3.1 + 9.0) * 0.15 + noise(p / 7.0) * 0.05 - 0.6;
    float backrun = smoothstep(-0.03, 0.0, tide) - 1.4 * smoothstep(0.0, 0.07, tide) + 0.4 * smoothstep(0.07, 0.3, tide);
    float relief = tooth(p);
    float amount = w * (1.0 + 0.35 * (bloom - 0.5)) + edge * w + 0.12 * backrun * w
        + 0.15 * (0.5 - relief) * w;
    amount = clamp(amount, 0.0, 1.0);
    vec3 painted = mix(PAPER, pig * PAPER, amount);
    painted *= 1.0 - 0.06 * (0.5 - relief);

    // What was painted already is kept
    vec3 kept = max(c0.rgb, 0.0);
    return vec4(mix(kept, painted, g), 1.0);
}
