// From chrischaps/Fishbowl @ b0624e4 (shaders/object.glsl)
// Lighting for everything in the jar: ambient light, then distance haze
// toward the dim at the back of the jar.
// Terrarium: no water, so no caustics. In their place, the lamp's cone: things
// under the lamp are a little brighter, and warmer, than things at the sides.
extern vec3 ambient;
extern vec3 fog;
extern float haze;
extern vec3 lamp;      // the lamp as it shines (colour * brightness)
extern vec2 pool;      // lamp screen x, cone half-width

vec4 effect(vec4 vcolor, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * vcolor;
    float u = (sc.x - pool.x) / pool.y;
    vec3 lit = c.rgb * ambient + c.rgb * lamp * exp(-u * u * 1.6) * 0.22;
    lit = mix(lit, fog, haze);
    return vec4(lit, c.a);
}
