// Terrarium: ascii-each (#97), the first pass (jar/ascii.lua). A cell is set
// by the thing it holds, read off the map of what's where (ascii_mark.glsl)
// at the same 4 x 4 taps as its colour. The thing is the one that matters
// most with enough of itself in the cell: a creature from 2 taps of 16 (so a
// sliver of a body claims its cell), the moss from 3, a prop or the soil from
// 4, a far thing from 5; else the cell is the ground. Then only that thing's
// taps count: its colour is its own, never the moss's or the stone's behind
// it, its cover is how much of the cell it fills, and how it runs is the run
// of its silhouette, so its outline is its own. The ground's run is its light's.
//
// Out: the cell's colour; and its run (x, y), its cover, its kind over 8.
extern vec2 grid; // the grid's columns and rows
extern vec2 span; // a cell's size in the frame's uv
extern Image frame;
extern Image map;

float pressed(vec3 c) {
    float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return y / (y + 0.18);
}

void effect() {
    vec2 o = floor(VaryingTexCoord.xy * grid) * span;
    vec3 col[16];
    float kind[16];
    float seed[16];
    float n1 = 0.0, n2 = 0.0, n3 = 0.0, n4 = 0.0, n5 = 0.0;
    float lx = 0.0, ly = 0.0;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            int k = j * 4 + i;
            vec2 uv = o + (vec2(float(i), float(j)) + 0.5) * 0.25 * span;
            col[k] = max(Texel(frame, uv).rgb, 0.0);
            vec4 m = Texel(map, uv);
            kind[k] = floor(m.r * 7.0 + 0.5);
            seed[k] = floor(m.g * 127.0 + 0.5);
            n1 += kind[k] == 1.0 ? 1.0 : 0.0;
            n2 += kind[k] == 2.0 ? 1.0 : 0.0;
            n3 += kind[k] == 3.0 ? 1.0 : 0.0;
            n4 += kind[k] == 4.0 ? 1.0 : 0.0;
            n5 += kind[k] == 5.0 ? 1.0 : 0.0;
            float y = pressed(col[k]);
            lx += i < 2 ? -y : y;
            ly += j < 2 ? -y : y;
        }
    }
    float held = 0.0;
    if (n5 >= 2.0) held = 5.0;
    else if (n4 >= 3.0) held = 4.0;
    else if (n3 >= 4.0) held = 3.0;
    else if (n2 >= 4.0) held = 2.0;
    else if (n1 >= 5.0) held = 1.0;

    // which one of that kind: the one nearest the cell's middle
    float best = 99.0, which = 0.0;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            int k = j * 4 + i;
            vec2 d = vec2(float(i), float(j)) - 1.5;
            float dd = dot(d, d);
            if (kind[k] == held && dd < best) { best = dd; which = seed[k]; }
        }
    }

    vec3 sum = vec3(0.0);
    float n = 0.0, gx = 0.0, gy = 0.0;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            int k = j * 4 + i;
            float in_ = (kind[k] == held && (held == 0.0 || seed[k] == which)) ? 1.0 : 0.0;
            sum += col[k] * in_;
            n += in_;
            gx += (i < 2 ? -in_ : in_);
            gy += (j < 2 ? -in_ : in_);
        }
    }
    vec3 mean = n > 0.0 ? sum / n : vec3(0.0);
    vec2 run = held == 0.0 ? vec2(lx, ly) / 8.0 : vec2(gx, gy) / 8.0;
    love_Canvases[0] = vec4(mean, 1.0);
    love_Canvases[1] = vec4(run, n / 16.0, held / 8.0);
}
