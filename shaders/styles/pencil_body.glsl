// Terrarium: pencil-each (#95), one creature drawn in pencil on its own. Its
// body was drawn alone onto a clear canvas (premultiplied, its glow added
// where it shines), and this lays it into the jar's frame as graphite on
// paper: its outline from its own silhouette, so nothing behind it or in
// front of it, no glow and no bead of condensation, can blur or double it;
// its markings from the edges of its colours; its shade hatched on its body,
// anchored to it, so the strokes go where it goes instead of the body sliding
// under strokes laid on the page.
//
// `mask` 0 draws it (premultiplied, over the frame, alpha left alone); 1
// gives what's left of the frame's alpha to draw (multiplied in, alpha only),
// so the whole-frame pass (pencil.glsl) leaves the body to this one.
#include "pencil_common.glsl"
extern vec2 anchor; // the body's middle, px in this canvas
extern float seed;  // the body's own, so two bodies don't share a hatching
extern float mask;

// How hard the silhouette's edge runs through uv
float rim(Image body, vec2 uv, vec2 o) {
    float tl = Texel(body, uv + vec2(-o.x, -o.y)).a, t = Texel(body, uv + vec2(0.0, -o.y)).a, tr = Texel(body, uv + vec2(o.x, -o.y)).a;
    float l = Texel(body, uv + vec2(-o.x, 0.0)).a, r = Texel(body, uv + vec2(o.x, 0.0)).a;
    float bl = Texel(body, uv + vec2(-o.x, o.y)).a, b = Texel(body, uv + vec2(0.0, o.y)).a, br = Texel(body, uv + vec2(o.x, o.y)).a;
    float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return sqrt(gx * gx + gy * gy);
}

vec4 effect(vec4 vcolor, Image body, vec2 tc, vec2 sc) {
    float k = size.y / 1000.0;
    vec2 p = (sc - anchor) / k + seed * vec2(37.0, 91.0); // page px, on the body
    float tooth, mottle;
    vec3 sheet = page(sc, sc / k, tooth, mottle);

    vec4 t = Texel(body, tc);
    float a = clamp(t.a, 0.0, 1.0);
    vec3 colour = max(t.rgb, 0.0) / max(a, 0.002); // its glow in it, where it has one
    float dark = darkness(dot(colour, LUMA));

    vec2 uv = tc + wander(p, k);
    vec2 o = 1.25 * k / size;
    float outline = smoothstep(0.8, 2.4, rim(body, uv, o));
    float marks = smoothstep(2.2, 4.4, edge(body, uv, o, 0.02 + 0.35 * dot(colour, LUMA))) * a;
    float line = max(outline, marks) * 0.88 * mix(0.74, 1.0, tooth);

    // the body: paper, hatched as dark as it is, and the line over it
    vec3 drawn = mix(sheet, LEAD, shading(p, dark, mottle) * mix(0.74, 1.0, tooth));
    float cover = line + a * (1.0 - line);
    if (mask > 0.5) return vec4(1.0 - cover);
    vec3 rgb = LEAD * line + drawn * a * (1.0 - line);
    // and where it glows off its body, the light goes on into the frame, to
    // lift the graphite off the page round it there
    return vec4(rgb + max(t.rgb - colour * a, 0.0), cover);
}
