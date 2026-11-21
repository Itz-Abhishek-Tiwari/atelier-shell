// outline.frag — the "Outline" wallpaper transition (modules/background/Background.qml).
//
// For wallpapers with one clear subject (maps made by scripts/wallfx.py):
//   1. the old wallpaper steps back a little (a touch darker and greyer)
//   2. a thin, quiet line draws the subject's outline — two pens from the top
//   3. the subject fills in from that line, in small square cells
//   4. the rest of the new wallpaper spreads outward from the subject
// The subject settles from a touch closer than its background, for a little depth.
// Every extra ends at exactly zero, so handing over to the plain wallpaper can't show.
//
// Build: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o outline.v1.frag.qsb outline.frag
//        (bump the version when you change it: Qt caches by file name)
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;          // 0..1, linear in time
    float sw;         // screen, px
    float sh;
    float mw;         // map size, texels
    float mh;
    float sdRange;    // the map's G channel spans ±sdRange map px
    float lineW;      // outline width, screen px
    float cell;       // cell size, screen px
    vec4 cropOld;     // image uv = xy + screen uv * zw (cover-crop, centred)
    vec4 cropNew;
    vec4 ink;         // the line's colour
};
layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;
layout(binding = 3) uniform sampler2D mapTex;
layout(binding = 4) uniform sampler2D penTex;

float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// screen uv → new-image uv through a camera zoomed by z around the centre
vec2 newUv(vec2 uv, float z) { return cropNew.xy + (0.5 + (uv - 0.5) / z) * cropNew.zw; }

void main() {
    vec2 uv = qt_TexCoord0;
    float zCh = 1.0 + 0.03 * (1.0 - ease(t));     // the subject settles from a touch closer
    float zBg = 1.0 + 0.015 * (1.0 - ease(t));

    // 1. the stage steps back
    float back = ease(t / 0.18) * (1.0 - ease((t - 0.85) / 0.15));
    vec3 st = texture(oldTex, cropOld.xy + uv * cropOld.zw).rgb;
    st = mix(st, vec3(luma(st)), 0.25 * back) * (1.0 - 0.2 * back);

    // the subject's silhouette, anti-aliased from the signed distance
    vec4 m = texture(mapTex, newUv(uv, zCh));
    float pxPerMap = sw / (mw * cropNew.z) * zCh;
    float sdPx = (m.g * 2.0 - 1.0) * sdRange * pxPerMap;
    float aa = max(fwidth(sdPx), 1e-3);
    float inside = clamp(0.5 - sdPx / aa, 0.0, 1.0);

    // cells decide by their centre: crisp, stepped fronts
    vec2 grid = vec2(sw, sh) / cell;
    vec2 cuv = (floor(uv * grid) + 0.5) / grid;

    // 3. the subject fills in from its outline (depth 0 → 1)
    float Ti = ease((t - 0.30) / 0.30) * 1.02 - 0.01;
    vec3 cIn = texture(mapTex, newUv(cuv, zCh)).r <= Ti ? texture(newTex, newUv(uv, zCh)).rgb : st;
    // 4. then the world spreads outward from it
    float To = ease((t - 0.45) / 0.50) * 1.02 - 0.01;
    vec3 cOut = texture(mapTex, newUv(cuv, zBg)).b <= To ? texture(newTex, newUv(uv, zBg)).rgb : st;
    vec3 c = mix(cOut, cIn, inside);

    // 2. the line: drawn by two pens from the top, gone once the subject is in
    float drawP = ease((t - 0.02) / 0.33);
    float fade = 1.0 - ease((t - 0.45) / 0.25);
    float lp = texture(penTex, newUv(uv, zCh)).r;
    if (fade > 0.0 && lp > 0.0 && lp <= drawP) {
        float core = clamp(0.5 - (abs(sdPx) - lineW * 0.5) / aa, 0.0, 1.0);
        c = mix(c, ink.rgb, core * 0.8 * fade);
    }

    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
