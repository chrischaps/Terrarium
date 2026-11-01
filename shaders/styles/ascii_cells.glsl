// Terrarium: ascii (#97), the first pass (jar/ascii.lua). Each texel is a cell
// of the character grid: the frame's colour averaged over a 4 x 4 grid of taps
// in it (each a linear tap, so 2 x 2 of the frame's pixels), and beside it,
// in the second canvas, how its light runs (the right half against the left,
// the lower against the upper, on light pressed toward 1 so a dim edge counts
// as much as a bright one), and its kind: the moss where it is the moss's
// green, else the frame set at once (the kinds of ascii_each_cells.glsl).
extern vec2 grid; // the grid's columns and rows
extern vec2 span; // a cell's size in the frame's uv
extern Image frame;

float pressed(vec3 c) {
    float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return y / (y + 0.18);
}

// How much a colour is the moss's green: its OKLCH hue between 116 and 144
// degrees, past the snail's bronze (to 109) and short of the blob's mint
// (from 150), and colourful enough to be green at all (bodies/skin.lua)
float moss(vec3 c) {
    vec3 lin = pow(max(c, 0.0), vec3(2.2));
    vec3 lms = vec3(
        dot(lin, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
        dot(lin, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
        dot(lin, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
    lms = pow(lms, vec3(1.0 / 3.0));
    float a = dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099));
    float b = dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660));
    float hue = degrees(atan(b, a));
    float chroma = length(vec2(a, b));
    return smoothstep(112.0, 118.0, hue) * (1.0 - smoothstep(142.0, 147.0, hue))
        * smoothstep(0.035, 0.06, chroma);
}

void effect() {
    vec2 o = floor(VaryingTexCoord.xy * grid) * span;
    vec3 sum = vec3(0.0);
    float gx = 0.0, gy = 0.0;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            vec3 c = max(Texel(frame, o + (vec2(float(i), float(j)) + 0.5) * 0.25 * span).rgb, 0.0);
            float y = pressed(c);
            sum += c;
            gx += i < 2 ? -y : y;
            gy += j < 2 ? -y : y;
        }
    }
    vec3 mean = sum / 16.0;
    love_Canvases[0] = vec4(mean, 1.0);
    // (its kind, as ascii_each_cells.glsl gives one: 4, the moss, by its
    // green; else 6, the frame set at once)
    love_Canvases[1] = vec4(gx / 8.0, gy / 8.0, 1.0, (moss(mean) > 0.5 ? 4.0 : 6.0) / 8.0);
}
