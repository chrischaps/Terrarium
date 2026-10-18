// From chrischaps/Fishbowl @ b0624e4 (shaders/composite.glsl)
// Final composite: edge refraction through the front glass, a vignette, and grain.
// Terrarium: no water, so the waterline, the surface underside and the tap
// ripple are gone. Refraction only happens where you look through the glass.
extern vec4 glassRect;     // x0, y0, x1, y1 of the front glass on screen
extern float aberration;
extern float vignette;
extern float grain;
extern float time;
extern vec2 size;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 sampleScene(Image scene, vec2 uv, vec2 sc) {
    // Thick-glass refraction: channels separate toward the jar's edges
    vec2 lo = glassRect.xy, hi = glassRect.zw;
    if (sc.x < lo.x || sc.x > hi.x || sc.y < lo.y || sc.y > hi.y) return Texel(scene, uv).rgb;
    vec2 c = (sc - (lo + hi) * 0.5) / (hi - lo);
    float r2 = dot(c, c);
    vec2 o = c * r2 * aberration * (hi - lo) / size;
    return vec3(Texel(scene, uv + o).r, Texel(scene, uv).g, Texel(scene, uv - o).b);
}

vec4 effect(vec4 vcolor, Image scene, vec2 tc, vec2 sc) {
    vec3 col = sampleScene(scene, tc, sc);

    // The room falls away into the dark at its edges
    vec2 v = tc - 0.5;
    v.x *= size.x / size.y;
    col *= 1.0 - vignette * smoothstep(0.35, 0.95, length(v));

    // Grain plus dither before 8-bit quantization (prevents banding)
    float n = hash(sc + fract(time * 7.13) * 100.0) - 0.5;
    col += n * grain + (hash(sc * 1.37 + 11.0) - 0.5) / 255.0;

    return vec4(clamp(col, 0.0, 1.0), 1.0);
}
