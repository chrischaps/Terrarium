// Terrarium: the matte (#98, jar/matte.lua). Whatever is drawn, its shape
// only: the layer it belongs to, premultiplied by its coverage, so the
// matte's own blending keeps what's in front on top. r is a creature, g the
// layer's kind (Matte.KINDS over Matte.LAST), b its depth (0 the back glass,
// 1 the front).
extern vec3 layer;

vec4 effect(vec4 vcolor, Image tex, vec2 tc, vec2 sc) {
    // (a shape, not how see-through it is: a blob's jelly is as much blob as
    // its rim, so a third of cover is all of it, and only edges stay soft)
    float a = smoothstep(0.0, 0.33, Texel(tex, tc).a * vcolor.a);
    return vec4(layer * a, a);
}
