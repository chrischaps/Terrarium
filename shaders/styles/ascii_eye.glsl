// Terrarium: ascii (#97), the eye (jar/ascii.lua). One texel: the frame's mean
// light, from an 8 x 8 grid over its cells, so the glyph pass can open up to a
// dark jar the way an eye does at night and the moonlit moss still reads.
extern Image cells;

vec4 effect(vec4 vcolor, Image tex, vec2 tc, vec2 sc) {
    float sum = 0.0;
    for (int j = 0; j < 8; j++) {
        for (int i = 0; i < 8; i++) {
            vec3 c = Texel(cells, (vec2(float(i), float(j)) + 0.5) / 8.0).rgb;
            sum += dot(max(c, 0.0), vec3(0.2126, 0.7152, 0.0722));
        }
    }
    return vec4(vec3(sum / 64.0), 1.0);
}
