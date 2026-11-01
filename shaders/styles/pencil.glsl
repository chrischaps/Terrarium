// Terrarium: pencil (#95), a style (jar/styles.lua). The jar as a sketchbook
// page: its edges drawn in graphite, its shade hatched, its light left as the
// paper. A first hatch for the shade, a steeper second crossing it for the
// dark, a flatter third for the darkest, graphite rubbed in under them; none
// in the light. The hatching is laid on the page, not on the jar, and never
// reads the clock, so it holds still while the jar is still. Only the line
// boils, a little, a few times a second, as a drawn line does from one
// drawing to the next.
//
// This draws the whole finished frame at once. Under pencil-each the things
// in the jar were drawn already, one at a time (pencil_body.glsl), and the
// frame's alpha is how much of each pixel is still to draw: 0 on a thing, 1
// on the ground round them (the room, the air, the jar's far side). `masked`
// is 1 then, and that ground is kept to the paper (`ground`); it's 0 for
// plain pencil, whose frame is opaque and all drawn here.
#include "pencil_common.glsl"
extern float masked;
extern vec2 ground; // under pencil-each: the ground's wash where darkest, and its line

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    float k = size.y / 1000.0; // screen px a page px
    vec2 p = sc / k;            // page px
    float tooth, mottle;
    vec3 sheet = page(sc, p, tooth, mottle);

    // The light, taken over a few px so a speck (a mote, a bead of
    // condensation) shades less than a surface does
    vec2 s = 1.5 * k / size;
    vec4 c0 = Texel(frame, tc);
    vec4 c1 = Texel(frame, tc + vec2(s.x, s.y)), c2 = Texel(frame, tc + vec2(-s.x, s.y));
    vec4 c3 = Texel(frame, tc + vec2(s.x, -s.y)), c4 = Texel(frame, tc + vec2(-s.x, -s.y));
    vec3 c = 4.0 * c0.rgb + c1.rgb + c2.rgb + c3.rgb + c4.rgb;
    float light = dot(max(c / 8.0, 0.0), LUMA);
    float dark = darkness(light);

    // The line, its samples wandering, and only where the edge is crisp: the
    // far jar's blur gives soft gradients that stay under the threshold, so
    // it's drawn in tone alone
    float e = edge(frame, tc + wander(p, k), 1.25 * k / size, 0.02 + 0.35 * light);
    float line = smoothstep(2.2, 4.4, e);
    float shade = shading(p, dark, mottle);
    // (the ground under pencil-each: no hatching, a wash as uneven as the paper)
    float wash = smoothstep(0.30, 1.0, dark) * mix(0.55, 1.0, mottle) * ground.x;
    shade = mix(shade, wash, masked);
    line *= mix(1.0, ground.y, masked);

    // The line gives way in the deepest shade, where the drawing is all tone
    line *= 1.0 - 0.5 * smoothstep(0.75, 0.98, dark);
    // ...and next to a creature drawn already, which has its own
    float held = min(min(c0.a, c1.a), min(min(c2.a, c3.a), c4.a));
    line *= mix(1.0, smoothstep(0.5, 1.0, held), masked);

    float cover = 1.0 - (1.0 - shade) * (1.0 - 0.88 * line);
    cover *= mix(0.74, 1.0, tooth);
    vec3 drawn = mix(sheet, LEAD, cover);
    // what was drawn already, kept, but grey on the paper's tint: a glow laid
    // over it after (the lantern, the moss's capsules) lightens it and no more
    const vec3 TINT = vec3(1.015, 1.0, 0.959);
    vec3 kept = min(vec3(dot(max(c0.rgb, 0.0), LUMA)) * TINT, vec3(1.0));
    return vec4(mix(drawn, kept, (1.0 - clamp(c0.a, 0.0, 1.0)) * masked), 1.0);
}
