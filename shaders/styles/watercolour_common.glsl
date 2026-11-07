// Terrarium: what the watercolour passes (#96) share: the sheet, the noise
// everything wanders by (hashed, so it's the same sheet every time and reads
// no clock), and the pigment. Included by watercolour*.glsl.

const vec3 PAPER = vec3(1.0, 0.975, 0.925); // a warm cold-press sheet
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float lum(vec3 c) { return dot(c, LUMA); }

// Bousseau et al.'s pigment ("Interactive watercolor rendering with temporal
// coherence and abstraction", 2006): density d above 1 deepens a colour,
// below 1 lifts it toward the paper, and white and black stay put
vec3 pigment(vec3 c, float d) { return c - (c - c * c) * (d - 1.0); }

// The paper's tooth at p (the window's px, on the page): hollows a few px
// across that the pigment settles into
float tooth(vec2 p) {
    return noise(p / 2.6 + 7.7) * 0.5 + noise(p / 6.0 + 3.1) * 0.3 + noise(p / 15.0) * 0.2;
}

// Glazes: a value built from a few washes laid one over another, so it falls
// off in steps. l is the light, `wander` (0..1) moves the steps' boundaries,
// `layered` is how far the value is drawn to its glaze
vec3 glaze(vec3 c, float wander, float glazes, float layered) {
    float l = max(lum(c), 1e-4);
    float y = sqrt(l) * glazes + (wander - 0.5) * 0.7;
    float lq = (floor(y) + smoothstep(0.32, 0.68, fract(y))) / glazes;
    lq = mix(sqrt(l), lq, layered);
    return c * (lq * lq / l);
}
