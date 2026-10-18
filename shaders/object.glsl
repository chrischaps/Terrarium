// From chrischaps/Fishbowl @ b0624e4 (shaders/object.glsl)
// Lighting for everything in the jar: ambient light, then distance haze
// toward the dim at the back of the jar.
// Terrarium: no water, so no caustics. The lamp's light arrives with #3.
extern vec3 ambient;
extern vec3 fog;
extern float haze;

vec4 effect(vec4 vcolor, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * vcolor;
    vec3 lit = c.rgb * ambient;
    lit = mix(lit, fog, haze);
    return vec4(lit, c.a);
}
