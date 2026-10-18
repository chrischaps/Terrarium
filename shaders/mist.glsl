// Terrarium: condensation's fine mist on the inside of the front glass.
// The mist texture holds the micro-droplets; the field says how damp the glass
// has to be before each part of it fogs (the lamp keeps the top clear longest);
// the dry layer is where beads and runs have gathered the mist up.
extern Image field;   // r: the dampness at which this spot fogs
extern Image dry;     // r: how much of the mist has been gathered here
extern float damp;    // DayCycle.env.damp
extern float soft;    // how gradually a spot fogs past its threshold
extern vec3 tint;     // the light the mist scatters

vec4 effect(vec4 vcolor, Image mist, vec2 uv, vec2 sc) {
    vec4 m = Texel(mist, uv);
    float thr = Texel(field, uv).r;
    float a = smoothstep(thr, thr + soft, damp);
    a *= 1.0 - clamp(Texel(dry, uv).r, 0.0, 1.0);
    return vec4(tint * m.rgb, m.a * a) * vcolor;
}
