// Terrarium: silver (#94), the style seam's test (jar/styles.lua). The jar as
// a silver gelatin print: its light as grey, lifted through a soft toe and
// shoulder, the paper a little warm and the shadows a little cool, as a
// selenium-toned print's are. tone 0 is plain grey.
extern float tone;

vec4 effect(vec4 vcolor, Image frame, vec2 tc, vec2 sc) {
    vec3 c = max(Texel(frame, tc).rgb, 0.0);
    float y = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    y = mix(y, y * y * (3.0 - 2.0 * y), 0.35);
    vec3 shadow = vec3(0.94, 0.95, 1.04); // cool, where the silver is thick
    vec3 paper = vec3(1.04, 1.00, 0.92);  // warm, where it's thin
    vec3 toned = y * mix(shadow, paper, smoothstep(0.1, 0.9, y));
    return vec4(mix(vec3(y), toned, tone), 1.0);
}
