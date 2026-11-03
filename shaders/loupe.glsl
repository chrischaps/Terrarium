// Terrarium: the loupe's lens (#122). A plate cut to a circle with a soft pixel
// of edge (a stencil's would be sharp, and the paper styles' thin rings don't
// cover it), a lens's edge darkening toward its rim, and for the glyph styles
// the circle stepped to the plate's cells, so no glyph is cut in half.
extern float feather; // a pixel, in the circle's own radius
extern vec2 cell;     // a cell in uv, or 0 for a smooth edge
extern float rim;     // how dark the lens's edge goes

vec4 effect(vec4 vcolor, Image plate, vec2 uv, vec2 sc) {
    vec2 at = uv;
    if (cell.x > 0.0) at = (floor(uv / cell) + 0.5) * cell;
    float d = length(at * 2.0 - 1.0);
    float cover = cell.x > 0.0 ? step(d, 1.0) : 1.0 - smoothstep(1.0 - 2.0 * feather, 1.0, d);
    vec3 c = Texel(plate, uv).rgb * (1.0 - rim * smoothstep(0.7, 1.0, d));
    return vec4(c, cover * vcolor.a);
}
