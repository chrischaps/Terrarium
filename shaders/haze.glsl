// From chrischaps/Fishbowl @ b0624e4 (shaders/haze.glsl)
// Composites the soft far layer (premultiplied) with distance haze
extern vec3 fog;
extern float haze;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 sc) {
    vec4 c = Texel(tex, uv);
    c.rgb = mix(c.rgb, fog * c.a, haze);
    return c * vcolor;
}
