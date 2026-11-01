// Terrarium: what the two pencil passes share (#95): the paper, the hatching,
// the line and the tone. `pencil.glsl` draws the whole finished frame with
// them; `pencil_body.glsl` draws one creature at a time, its hatching riding
// on its body. Included by both (jar/render.lua's #include).
//
// Every length here is in page px, a page being 1000 tall, so a capture at
// any size is the same drawing (but the paper's tooth, which is the screen's).
extern Image paper;     // r tooth, g mottle, b a wobble (jar/styles.lua's paper)
extern vec2 size;       // the frame, px
extern float time;      // jar seconds (the boil's clock)
extern float boil;      // how far the line wanders, page px
extern float exposure;  // how much light reads as bare paper
extern float contrast;  // > 1 draws the dark darker (the night, the room)

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float BOILS = 4.0;  // drawings a second
const float PERIOD = 5.2; // between hatch strokes, page px
const vec2 tex = vec2(512.0); // the paper's size (jar/styles.lua's PAPER)
const vec3 LEAD = vec3(0.17, 0.175, 0.195);

// A hash with no sine in it, so it holds on a GPU with short floats
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// The light at uv, as the eye takes it: ratios, not differences, so an edge
// at night is drawn as firmly as the same edge by day. `f0` is the light
// below which the eye stops telling ratios apart, a little of the light
// around, so a busy texture in the lamp's pool draws no more lines than the
// edge of a stone in the dark does.
vec3 seen(Image frame, vec2 uv, float f0) {
    return log2(max(Texel(frame, uv).rgb, 0.0) + f0);
}

// How hard an edge runs through uv: Sobel, `o` apart in uv
float edge(Image frame, vec2 uv, vec2 o, float f) {
    vec3 tl = seen(frame, uv + vec2(-o.x, -o.y), f), t = seen(frame, uv + vec2(0.0, -o.y), f), tr = seen(frame, uv + vec2(o.x, -o.y), f);
    vec3 l = seen(frame, uv + vec2(-o.x, 0.0), f), r = seen(frame, uv + vec2(o.x, 0.0), f);
    vec3 bl = seen(frame, uv + vec2(-o.x, o.y), f), b = seen(frame, uv + vec2(0.0, o.y), f), br = seen(frame, uv + vec2(o.x, o.y), f);
    vec3 gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    vec3 gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return sqrt(dot(gx, gx) + dot(gy, gy));
}

// Smooth noise along a line, 0 to 1
float vnoise1(float x, float seed) {
    float i = floor(x);
    float f = fract(x);
    return mix(hash12(vec2(i, seed)), hash12(vec2(i + 1.0, seed)), f * f * (3.0 - 2.0 * f));
}

// One layer of hatching at `angle`: parallel rows of strokes, as even over a
// flat shade as a practised hand lays them. The shade is in how hard and how
// broad they're drawn, not in where: a light one is every other row, thin and
// faint, and the rows between come in as it deepens. Each row is strokes of
// 55 to 110 px with a little gap between, their ends staggered row to row and
// tapering; a stroke's pressure comes and goes along it. `bend` waves the
// whole field together. p is in page px.
float hatch(vec2 p, float angle, float period, float shade, float bend, float seed) {
    if (shade <= 0.0) return 0.0;
    vec2 d = vec2(cos(angle), sin(angle));
    float u = dot(p, d);
    float v = dot(p, vec2(-d.y, d.x)) + bend;
    float row = floor(v / period);
    float centre = (row + 0.5 + (hash12(vec2(row, seed)) - 0.5) * 0.35) * period;
    float len = 55.0 + 55.0 * hash12(vec2(row, seed + 2.0));
    float uo = u / len + hash12(vec2(seed, row));
    float seg = floor(uo);
    float along = fract(uo);
    float gap = 5.0 / len;
    float taper = smoothstep(0.0, gap + 0.05, along) * (1.0 - smoothstep(0.93 - gap, 1.0 - gap, along));
    float between = mod(row, 2.0) * (1.0 - smoothstep(0.3, 0.6, shade));
    float press = shade * (1.0 - between) * mix(0.72, 1.0, vnoise1(u / 90.0, row * 1.7 + seed * 5.0))
        * mix(0.85, 1.0, hash12(vec2(seg, row + seed)));
    float width = mix(0.25, 0.8, shade) * taper;
    float line = 1.0 - smoothstep(width, width + 0.9, abs(v - centre));
    return line * press * mix(0.4, 1.0, taper);
}

// The shade, as a draughtsman sees it: how far `light` is from the paper's white
float darkness(float light) {
    return 1.0 - pow(1.0 - exp(-light * exposure), contrast);
}

// How much graphite a `dark` place at page px p takes: a first hatch for the
// shade, a steeper second crossing it for the dark, a flatter third for the
// darkest, and graphite rubbed in with a stump under them, uneven as rubbing is
float shading(vec2 p, float dark, float mottle) {
    float bend = (Texel(paper, p / (tex * 2.3)).b - 0.5) * 7.0;
    float h1 = hatch(p, -0.72, PERIOD, smoothstep(0.28, 0.66, dark), bend, 1.0);
    float h2 = hatch(p, -1.36, PERIOD * 1.05, smoothstep(0.55, 0.86, dark), bend, 2.0);
    float h3 = hatch(p, 0.18, PERIOD * 0.8, smoothstep(0.78, 1.0, dark), bend, 3.0);
    float rub = smoothstep(0.30, 1.0, dark);
    rub = rub * rub * mix(0.55, 1.0, mottle);
    return 1.0 - (1.0 - 0.5 * rub) * (1.0 - 0.72 * h1) * (1.0 - 0.80 * h2) * (1.0 - 0.88 * h3);
}

// Where the line's samples wander to at page px p: the paper's wobble, which
// moves on BOILS times a second, in uv for a canvas of `size`
vec2 wander(vec2 p, float k) {
    float drawing = floor(time * BOILS);
    vec2 at = vec2(hash12(vec2(drawing, 1.0)), hash12(vec2(drawing, 2.0)));
    vec2 wob = vec2(Texel(paper, p / (tex * 0.9) + at).b, Texel(paper, p.yx / (tex * 0.9) + at.yx + 0.5).b) - 0.5;
    return wob * boil * 2.0 * k / size;
}

// The page itself at screen px sc and page px p: its colour, and its tooth
// (graphite catches on the tooth and skips the hollows)
vec3 page(vec2 sc, vec2 p, out float tooth, out float mottle) {
    tooth = Texel(paper, sc / tex).r;
    mottle = Texel(paper, p / (tex * 3.1) + 0.37).g;
    return vec3(0.958, 0.944, 0.905) * (1.0 - 0.05 * mottle) * (1.0 - 0.035 * (1.0 - tooth));
}
