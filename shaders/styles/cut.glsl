// Terrarium: probe-cut (#98's second probe, jar/styles.lua; --probes). Each
// layer treated on its own, which the frame's colour alone can't do: the soil,
// stones, scenery and moss are cut flat from paper, each its own colour in a
// few steps of light, and each nearer layer throws a shadow onto the one
// behind it, away from the lamp. The creatures are left as they are, every
// detail of them, so they stand out of the cut paper alive. It reads the
// matte (jar/matte.lua): r is a creature, g the layer's kind, b its depth.
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
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec3 c = max(Texel(frame, tc).rgb, 0.0);
    vec4 m = Texel(matte, tc);

    // The layer's colour, smoothed over its own pixels only, so no colour
    // crosses a cut
    vec3 sum = vec3(0.0);
    float n = 0.0;
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            vec2 uv = tc + vec2(float(i), float(j)) * 6.0 * scale * px;
            float w = 1.0 - smoothstep(0.02, 0.09, abs(Texel(matte, uv).g - m.g));
            sum += max(Texel(frame, uv).rgb, 0.0) * w;
            n += w;
        }
    }
    vec3 avg = sum / max(n, 0.001);
    // its light in three steps, its hue kept; what isn't a layer (the room,
    // the glass, the lamp's light in the air) isn't cut, only softened
    float l = luma(avg);
    // (each step's edge a little soft, or texture on the edge of a step
    // speckles: a single pass can't average a layer widely enough to be flat)
    float t = pow(l, 0.8) * 3.0;
    float steps = (floor(t) + smoothstep(0.3, 0.7, fract(t)) + 0.1) / 3.0;
    vec3 paper = avg / max(l, 0.002) * pow(steps, 1.25);
    paper = mix(paper, avg, step(m.g, 0.08));
    // the paper's fibre
    vec2 p = sc / scale;
    paper *= 0.95 + 0.05 * noise(p * 0.9) + 0.03 * noise(p * vec2(0.08, 0.6));

    // A nearer layer up and to the left of here is between this and the lamp
    float shade = 0.0;
    for (int k = 1; k <= 5; k++) {
        vec4 o = Texel(matte, tc + vec2(-0.6, -1.0) * float(k) * 2.2 * scale * px);
        shade += step(m.b + 0.012, o.b);
    }
    paper *= 1.0 - 0.42 * shade / 5.0;
    // and the cut edge of this one catches the light
    vec4 up = Texel(matte, tc + vec2(-0.6, -1.0) * 1.5 * scale * px);
    float edge = step(0.07, abs(up.g - m.g)) * step(up.b + 0.012, m.b);
    paper += edge * 0.10 * (0.4 + l);

    // The creatures as they are; the shadows the cut paper throws over them
    // too. (A blob's jelly is see-through, so its matte is less than whole:
    // any of a creature at all is all of it)
    vec3 alive = c * (1.0 - 0.42 * shade / 5.0);
    return vec4(mix(paper, alive, smoothstep(0.02, 0.2, m.r)), 1.0);
}
