// Terrarium: watercolour-each (#96), one thing in the jar painted on its own:
// a creature, a piece of the scenery, a stone, a fern, the soil, the moss.
// It was drawn alone onto a clear canvas (premultiplied, its glow added where
// it shines; jar/styles.lua's Styles.body), and this lays it into the jar's
// frame as a wash on paper:
//   - its shape is its own silhouette, its outline moved a little by noise
//     that rides on the thing, so the colour runs past its line in places and
//     falls short in others, and the run goes where the creature goes;
//   - its pigment pools at its own rim as a wash's does drying (the wet
//     edge), and at the boundaries of its markings and glazes inside it;
//   - its value is built of a few glazes, and its pigment blooms and
//     granulates, all anchored to the thing, so a creature carries its paint
//     with it instead of walking through a pattern fixed to the screen;
//   - a faint pencil line keeps its outline and, on a creature, its markings
//     and eyes; its lights are left as paper and its glow still glows.
// Only the paper's own tooth is the page's.
//
// `look` (Styles.LOOK) is how it's painted: x its weight (a far thing is a
// paler wash, the painter's distance), y how much of its inside detail is
// kept (a creature's markings all; a prop is a flat wash of its broad tone,
// so its texture doesn't come through), z how wide that broad tone is taken,
// in the window's px, w the deepest it's painted.
//
// `mask` 0 lays it in (premultiplied, over the frame, alpha left alone); 1
// gives what's left of the frame's alpha to paint (multiplied in, alpha
// only), so the ground's pass (watercolour_ground.glsl) leaves it be.
#include "watercolour_common.glsl"
extern vec2 size;   // this canvas, px
extern vec2 px;     // one of the window's px in this canvas's texture coordinates
extern vec2 anchor; // the thing's middle, px in this canvas
extern float seed;  // its own, so two things don't share their blooms
extern vec4 look;   // weight, detail, softness, deepest
extern float mask;

const float KEY = 0.75;     // lighter than the jar, as the frame's watercolour
const float SATURATE = 1.2;
const float BLEED = 1.6;    // how far its colour runs past its line, window px
const float RIM = 0.55;     // pigment carried to its own rim
const float EDGE = 3.0;     // pigment at a boundary inside it
const float BLOOM = 0.35;
const float GRAIN = 0.7;
const float TOOTH = 0.06;
const float PENCIL = 0.28;

// Its colour and coverage round uv, `r` apart in uv, and how much of it is
// there: only its own pixels count toward the colour, so its rim doesn't
// come out darker for the clear canvas round it
vec4 ring(Image body, vec2 uv, vec2 r) {
    vec4 s = vec4(0.0);
    for (int k = 0; k < 8; k++) {
        float a = float(k) * 0.78539816;
        s += Texel(body, uv + vec2(cos(a), sin(a)) * r);
    }
    return s / 8.0;
}

vec3 colourOf(vec4 t) { return max(t.rgb, 0.0) / max(t.a, 0.002); }

// Its broad tone over a disc `r` across in uv (16 taps on a sunflower
// spiral, turned by `turn` so what a few taps miss comes out as the
// pigment's own unevenness, not as the texture under it), its own pixels only
vec3 broad(Image body, vec2 uv, vec2 r, float turn) {
    vec4 s = Texel(body, uv);
    for (int k = 1; k <= 16; k++) {
        float f = float(k);
        float a = f * 2.39996 + turn * 6.2832;
        s += Texel(body, uv + vec2(cos(a), sin(a)) * sqrt(f / 16.0) * r);
    }
    return max(s.rgb, 0.0) / max(s.a, 0.002);
}

// How hard its silhouette's edge runs through uv
float rim(Image body, vec2 uv, vec2 o) {
    float tl = Texel(body, uv + vec2(-o.x, -o.y)).a, t = Texel(body, uv + vec2(0.0, -o.y)).a, tr = Texel(body, uv + vec2(o.x, -o.y)).a;
    float l = Texel(body, uv + vec2(-o.x, 0.0)).a, r = Texel(body, uv + vec2(o.x, 0.0)).a;
    float bl = Texel(body, uv + vec2(-o.x, o.y)).a, b = Texel(body, uv + vec2(0.0, o.y)).a, br = Texel(body, uv + vec2(o.x, o.y)).a;
    float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return sqrt(gx * gx + gy * gy);
}

// How hard its colour's edge runs through uv (its markings, its eyes)
float marks(Image body, vec2 uv, vec2 o) {
    float l = lum(colourOf(Texel(body, uv - vec2(o.x, 0.0)))), r = lum(colourOf(Texel(body, uv + vec2(o.x, 0.0))));
    float t = lum(colourOf(Texel(body, uv - vec2(0.0, o.y)))), b = lum(colourOf(Texel(body, uv + vec2(0.0, o.y))));
    return length(vec2(r - l, b - t));
}

vec4 effect(vec4 vcolor, Image body, vec2 tc, vec2 sc) {
    float k = size.x * px.x;                               // canvas px a window px
    vec2 p = (sc - anchor) / k + seed * vec2(37.0, 91.0); // window px, on the thing
    vec2 q = sc / k;                                      // window px, on the page

    // The bleed: its shape and colours wander, by noise that rides on it
    vec2 run = vec2(noise(p / 15.0), noise(p / 15.0 + 23.1)) - 0.5;
    run += 0.5 * (vec2(noise(p / 5.0 + 4.7), noise(p / 5.0 + 61.3)) - 0.5);
    vec2 uv = tc + run * 2.0 * BLEED * px;

    vec4 t = Texel(body, uv);
    // a wash is opaque where it lies: a soft or translucent edge (the blob's
    // jelly) is taken whole, so nothing of the frame under it shows through
    float a = smoothstep(0.03, 0.4, t.a);
    vec3 colour = colourOf(t); // its glow in it, where it has one

    // Its broad tone, and how much of its own detail stays over it
    vec4 near = ring(body, uv, max(look.z, 1.5) * px);
    vec4 wide = ring(body, uv, max(look.z, 4.0) * 2.0 * px);
    vec3 tone = broad(body, uv, max(look.z, 2.0) * px, noise(p / 3.0));
    vec3 c = clamp(mix(tone, colour, look.y * 0.6), 0.0, 1.0);

    // The painting's key, its glazes, and distance as a paler wash
    float l0 = lum(c);
    c = mix(c, pow(c, vec3(KEY)), smoothstep(0.02, 0.25, l0));
    float lk = lum(c);
    c = clamp(lk + (c - lk) * SATURATE, 0.0, 1.0);
    float wander = noise(p / 21.0 + 3.7) * 0.75 + noise(p / 7.0 + 6.1) * 0.25;
    c = glaze(c, wander, 6.0, mix(0.75, 0.4, look.y));
    c = mix(PAPER * 0.97, c, 0.45 + 0.55 * look.x);
    c = max(c, vec3((1.0 - look.w) * 0.35)); // a prop is painted no darker than says it's dark
    float dark = 1.0 - lum(c);

    // Where its pigment gathers: at its rim, at a boundary inside it, in
    // blooms, and in the tooth
    float inside = clamp(a - near.a, 0.0, 1.0) + 0.5 * clamp(a - wide.a, 0.0, 1.0);
    float rimmed = smoothstep(0.05, 0.45, inside);
    vec3 nearColour = near.rgb / max(near.a, 0.002);
    float boundary = clamp((lum(nearColour) - lum(colour)) * EDGE, 0.0, 0.6) * (0.4 + 0.6 * look.y);
    float bloom = noise(p / 40.0 + 19.0) * 0.6 + noise(p / 14.0 + 2.3) * 0.4;
    float grain = noise(p / 2.4 + 9.1) * 0.6 + noise(p / 5.5 + 1.7) * 0.4;
    float relief = tooth(q);
    float d = 1.0 + RIM * rimmed + boundary
        + BLOOM * (bloom - 0.5)
        + GRAIN * (0.5 - mix(grain, relief, 0.4)) * dark;
    c = clamp(pigment(c, d), 0.0, 1.0);
    c *= PAPER * (1.0 - TOOTH * (0.5 - relief));

    // The pencil under it: its outline, and on a creature its markings
    vec2 o = 1.2 * px;
    float outline = smoothstep(0.7, 2.2, rim(body, tc, o));
    float inner = smoothstep(0.08, 0.3, marks(body, tc, o)) * smoothstep(0.5, 0.9, t.a) * look.y;
    float line = max(outline, inner) * (0.55 + 0.45 * noise(q / 2.2 + 11.0)) * PENCIL * look.x;

    // Its lights left as paper: on a creature, what was brighter than its
    // wash comes back (an eye's white, a glint, a marking lit up)
    float lift = smoothstep(0.06, 0.3, lum(min(colour, vec3(1.0))) - lum(c)) * look.y;
    c = mix(c, max(c, min(colour, vec3(1.0)) * PAPER), lift);
    // and a glow keeps the light it has beyond white
    c += max(colour - vec3(1.0), 0.0) * a;

    const vec3 LEAD = vec3(0.24, 0.24, 0.25);
    float cover = max(a, line);
    if (mask > 0.5) return vec4(1.0 - cover);
    vec3 rgb = mix(c * a, LEAD, line) ;
    // where it glows off its body, the light goes on into the frame
    return vec4(rgb + max(t.rgb - colour * t.a, 0.0), cover);
}
