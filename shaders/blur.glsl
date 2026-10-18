// From chrischaps/Fishbowl @ b0624e4 (shaders/blur.glsl)
// Separable 9-tap gaussian
extern vec2 dir;   // texel step in uv

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 sc) {
    vec4 r = Texel(tex, uv) * 0.20236;
    r += (Texel(tex, uv + dir * 1.0) + Texel(tex, uv - dir * 1.0)) * 0.179044;
    r += (Texel(tex, uv + dir * 2.0) + Texel(tex, uv - dir * 2.0)) * 0.124009;
    r += (Texel(tex, uv + dir * 3.0) + Texel(tex, uv - dir * 3.0)) * 0.067234;
    r += (Texel(tex, uv + dir * 4.0) + Texel(tex, uv - dir * 4.0)) * 0.028532;
    return r * vcolor;
}
