// Terrarium: probe-ink (#98's first probe, jar/styles.lua; --probes). A
// hand-inked line round every creature and round nothing else, which the
// frame's colour alone can't give: a worm on cork is brown on brown. The line
// is found in the matte (jar/matte.lua): it lies just outside a creature, its
// weight wanders along it as a pen's does, it's heavier on the underside (a
// pen goes back over the shadow side), and here and there it breaks.
extern Image matte;
extern vec2 px;     // one pixel, in uv
extern float scale; // the frame's height over the window's

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec3 c = Texel(frame, tc).rgb;
    float here = Texel(matte, tc).r;
    vec2 p = sc / scale;
    // the pen's weight, wandering along the line
    float r = (1.3 + 1.9 * noise(p * 0.05)) * scale;
    float near = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 0.5236; // twelve ways round
        vec2 d = vec2(cos(a), sin(a));
        // looking up (toward a body above), the pen reaches further: the
        // line under a creature is the heavy one
        d.y *= d.y < 0.0 ? 1.9 : 1.0;
        near = max(near, Texel(matte, tc + d * r * px).r);
        near = max(near, Texel(matte, tc + d * r * 0.5 * px).r);
    }
    float ink = (1.0 - here) * smoothstep(0.08, 0.45, near);
    // a dry pen: the line thins and now and then breaks
    ink *= smoothstep(0.12, 0.32, noise(p * 0.021 + 11.0));
    vec3 inkc = vec3(0.07, 0.055, 0.09);
    return vec4(mix(c, inkc, ink * 0.92), 1.0);
}
