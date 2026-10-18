// From chrischaps/Fishbowl @ b0624e4 (shaders/floor.glsl)
// The soil bed seen from above at a grazing angle. Each pixel's depth is
// recovered from its screen y, so the light and the haze recede with the floor.
// Terrarium: no water, so no caustics. In their place, the pool of lamp light
// on the moss under the lamp, which follows the day.
extern vec3 ambient;
extern vec3 fog;
extern float hazeMax;
extern vec3 lamp;      // the lamp as it shines (colour * brightness)
extern vec3 view;      // cx, cy, kBack
extern float floorY;   // soil top on the creatures' plane (world y)
extern float floorRise;
extern float planeD;
extern vec2 pool;      // lamp world x, pool half-width

vec4 effect(vec4 vcolor, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * vcolor;

    // Recover depth from screen y on the (back-rising) floor: fixed-point solve
    float d = 0.5;
    float k = 1.0;
    for (int i = 0; i < 5; i++) {
        float back = max(0.0, planeD - d) / planeD;
        float y = floorY - floorRise * pow(back, 1.3);
        k = clamp((sc.y - view.y) / (y - view.y), view.z, 1.0);
        d = (k - view.z) / (1.0 - view.z);
    }
    float wx = view.x + (sc.x - view.x) / k;

    float u = (wx - pool.x) / pool.y;
    float lit = exp(-u * u * 1.6) * (0.55 + 0.45 * d);

    vec3 col = c.rgb * ambient + c.rgb * lamp * lit * 0.35;
    col = mix(col, fog, pow(1.0 - d, 1.6) * hazeMax);
    return vec4(col, c.a);
}
