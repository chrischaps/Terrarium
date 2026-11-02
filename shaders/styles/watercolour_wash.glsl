// Terrarium: watercolour (#96), its first pass, at half the frame's size: the
// washes. A generalised Kuwahara filter (Kyprianidis et al., "Image and Video
// Abstraction by Anisotropic Kuwahara Filtering", the polynomial sectors):
// round each pixel, eight overlapping sectors of a disc each take the mean
// and spread of their colours, and the pixel becomes their means weighted
// toward the calmest. Flat stretches go flatter and their boundaries stay,
// as a wash fills a shape and stops at its edge. Before it looks, the pixel
// is moved a little by noise fixed to the frame, so the colour has run past
// its lines in places and fallen short in others: the bleed.
extern vec2 px; // one pixel of the window's frame, in texture coordinates

const int R = 4;          // the disc's radius, in steps
const float STEP = 2.5;   // a step, in the window's pixels
const float BLEED = 2.6;  // how far the colour runs, in the window's pixels
const float Q = 8.0;      // how hard the calmest sector wins
const float GLAZES = 7.0; // how many washes build the darkest value
const float LAYERED = 0.65; // how far the value is drawn to its glaze

#include "watercolour_common.glsl"

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    // the bleed: two octaves of a slow wander, fixed to the frame
    vec2 p = tc / px;
    vec2 run = vec2(noise(p / 34.0), noise(p / 34.0 + 17.3)) - 0.5;
    run += 0.5 * (vec2(noise(p / 11.0 + 5.1), noise(p / 11.0 + 41.7)) - 0.5);
    vec2 at = tc + run * 2.0 * BLEED * px;

    const float PI = 3.14159265;
    float zeta = 2.0 / float(R);
    float eta = (zeta + cos(PI / 8.0)) / pow(sin(PI / 8.0), 2.0);
    vec4 m[8];
    vec3 s[8];
    for (int k = 0; k < 8; k++) { m[k] = vec4(0.0); s[k] = vec3(0.0); }

    for (int j = -R; j <= R; j++) {
        for (int i = -R; i <= R; i++) {
            vec2 v = vec2(float(i), float(j)) / float(R);
            float d2 = dot(v, v);
            if (d2 > 1.0) continue;
            // the colours are washes, so a glow's light above white is the
            // second pass's to put back
            vec3 c = min(Texel(frame, at + vec2(float(i), float(j)) * STEP * px).rgb, vec3(1.0));
            float w[8];
            float vxx = zeta - eta * v.x * v.x, vyy = zeta - eta * v.y * v.y;
            float z;
            z = max(0.0, v.y + vxx); w[0] = z * z;
            z = max(0.0, -v.x + vyy); w[2] = z * z;
            z = max(0.0, -v.y + vxx); w[4] = z * z;
            z = max(0.0, v.x + vyy); w[6] = z * z;
            vec2 r = 0.70710678 * vec2(v.x - v.y, v.x + v.y);
            vxx = zeta - eta * r.x * r.x; vyy = zeta - eta * r.y * r.y;
            z = max(0.0, r.y + vxx); w[1] = z * z;
            z = max(0.0, -r.x + vyy); w[3] = z * z;
            z = max(0.0, -r.y + vxx); w[5] = z * z;
            z = max(0.0, r.x + vyy); w[7] = z * z;
            float sum = w[0] + w[1] + w[2] + w[3] + w[4] + w[5] + w[6] + w[7];
            float g = exp(-3.125 * d2) / max(sum, 1e-6);
            for (int k = 0; k < 8; k++) {
                float wk = w[k] * g;
                m[k] += vec4(c * wk, wk);
                s[k] += c * c * wk;
            }
        }
    }

    vec4 o = vec4(0.0);
    for (int k = 0; k < 8; k++) {
        if (m[k].w <= 0.0) continue;
        vec3 mean = m[k].rgb / m[k].w;
        vec3 var = abs(s[k] / m[k].w - mean * mean);
        float sigma2 = var.r + var.g + var.b;
        float wk = 1.0 / (1.0 + pow(1000.0 * sigma2, 0.5 * Q));
        o += vec4(mean * wk, wk);
    }
    vec3 c = o.rgb / max(o.w, 1e-6);

    // Glazes: a painter builds a value from a few washes laid one over
    // another, so the light falls off in steps, not smoothly. The value
    // (as the eye reads it, near its square root) is drawn toward GLAZES
    // levels, their boundaries wandering with the same fixed noise.
    vec2 w = p + 9.0 * (vec2(noise(p / 13.0 + 1.3), noise(p / 13.0 + 8.9)) - 0.5);
    float wander = noise(w / 34.0 + 3.7) * 0.75 + noise(w / 10.0 + 6.1) * 0.25;
    return vec4(glaze(c, wander, GLAZES, LAYERED), 1.0);
}
