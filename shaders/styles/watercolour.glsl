// Terrarium: watercolour (#96), its second pass, at the frame's size: the
// washes (the first pass's, drawn up from half size) laid on paper. The
// pigment's density at each pixel darkens the wash the way Bousseau et al.'s
// watercolour model does ("Interactive watercolor rendering with temporal
// coherence and abstraction", 2006): C' = C - (C - C^2)(d - 1), so more
// pigment deepens a colour and less lifts it toward the paper, and white
// paper and black ink both stay as they are. The density gathers:
//   - at a wash's wet edge, where pigment is carried out to the rim as it
//     dries, on the darker side of each boundary;
//   - in blooms where the pigment dried unevenly, slow and wide;
//   - in the paper's tooth, where heavy pigment granulates, more strongly
//     the darker the wash.
// Under it lies the pencil, faint, where the frame as drawn has a line, so a
// creature's eye and outline still read. Over it the lights are kept: what
// in the frame as drawn is brighter than its wash (an eye's white, a glint, a
// marking glowing at night) comes back through, and a glow keeps its light.
// Everything is fixed to the frame, so a still jar is a still painting.
extern Image frame; // the jar as drawn, at this pass's size
extern vec2 px;     // one pixel of the window's frame, in texture coordinates

const vec3 PAPER = vec3(1.0, 0.975, 0.925); // a warm cold-press sheet
const float KEY = 0.75;     // the painting's key: below 1, lighter than the jar
const float SATURATE = 1.2; // pigment is richer than light
const float EDGE = 4.0;     // pigment carried to a wet edge
const float BLOOM = 0.35;   // pigment drying unevenly
const float TIDE = 0.25;   // pigment left at a backrun's rim
const float GRAIN = 0.8;    // pigment settling into the tooth
const float TOOTH = 0.06;   // the paper's own relief, in the light
const float PENCIL = 0.30;  // the underdrawing's weight

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 pigment(vec3 c, float d) { return c - (c - c * c) * (d - 1.0); }

vec4 effect(vec4 vcolor, Image wash, vec2 tc, vec2 sc) {
    vec2 p = tc / px; // the window's pixels: the paper is fixed to the frame
    vec3 c = clamp(Texel(wash, tc).rgb, 0.0, 1.0);
    float lc = lum(c);

    // The wet edge: a wash darker than the ring round it is near its rim
    float ring = 0.0;
    for (int k = 0; k < 8; k++) {
        float a = float(k) * 0.78539816;
        ring += lum(Texel(wash, tc + vec2(cos(a), sin(a)) * 5.0 * px).rgb);
    }
    ring /= 8.0;
    float edge = clamp((ring - lc) * EDGE, 0.0, 0.8);

    // The paper: a cold-press tooth of hollows a few pixels across, which the
    // pigment settles into
    float tooth = noise(p / 2.6 + 7.7) * 0.5 + noise(p / 6.0 + 3.1) * 0.3 + noise(p / 15.0) * 0.2;
    // Where the wash dried unevenly: wide, slow mottling, and in the flat
    // stretches the backruns, frilly tide lines where a wetter patch crept
    // back into a drying one and left its pigment at its rim
    float bloom = noise(p / 70.0 + 19.0) * 0.6 + noise(p / 23.0 + 2.3) * 0.4;
    vec2 q = p / 260.0;
    float tide = noise(q + 5.0) * 0.8 + noise(q * 3.1 + 9.0) * 0.15 + noise(p / 7.0) * 0.05 - 0.64;
    float flat_ = 1.0 - smoothstep(0.01, 0.05, abs(ring - lc));
    // dark at the rim, the pigment pushed out of the wetter patch inside it
    float backrun = (smoothstep(-0.03, 0.0, tide) - 1.5 * smoothstep(0.0, 0.07, tide)
        + 0.5 * smoothstep(0.07, 0.3, tide)) * flat_;

    // The painting's key: lighter than the jar in its middle tones, its
    // colour a little richer
    c = mix(c, pow(c, vec3(KEY)), smoothstep(0.02, 0.25, lc));
    float lk = lum(c);
    c = clamp(lk + (c - lk) * SATURATE, 0.0, 1.0);
    float dark = 1.0 - lk;
    // and the pigments mixing wet in wet: a little warmer here, cooler there
    c *= mix(vec3(1.04, 1.0, 0.95), vec3(0.96, 1.0, 1.05), bloom);

    float d = 1.0 + edge
        + BLOOM * (bloom - 0.5)
        + TIDE * backrun
        + GRAIN * (0.5 - tooth) * dark;
    c = clamp(pigment(c, d), 0.0, 1.0);
    c *= PAPER * (1.0 - TOOTH * (0.5 - tooth));

    // The pencil underneath, where the frame as drawn has an edge
    vec3 o = Texel(frame, tc).rgb;
    float l = lum(min(o, vec3(1.0)));
    float gx = lum(min(Texel(frame, tc + vec2(px.x, 0.0)).rgb, vec3(1.0)))
             - lum(min(Texel(frame, tc - vec2(px.x, 0.0)).rgb, vec3(1.0)));
    float gy = lum(min(Texel(frame, tc + vec2(0.0, px.y)).rgb, vec3(1.0)))
             - lum(min(Texel(frame, tc - vec2(0.0, px.y)).rgb, vec3(1.0)));
    float line = smoothstep(0.06, 0.28, length(vec2(gx, gy)));
    line *= 0.6 + 0.4 * noise(p / 2.2 + 11.0); // the graphite skips on the tooth
    c *= 1.0 - PENCIL * line * (0.5 + 0.5 * dark);

    // The lights: what's brighter in the frame than its wash is kept, and a
    // glow keeps the light it has beyond white
    float lift = smoothstep(0.06, 0.30, l - lc);
    c = mix(c, max(c, min(o, vec3(1.0)) * PAPER), lift);
    c += max(o - vec3(1.0), 0.0);

    return vec4(c, 1.0);
}
