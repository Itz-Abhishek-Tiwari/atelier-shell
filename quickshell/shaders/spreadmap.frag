// spreadmap.frag — the arrival map for the "Spread" wallpaper transition.
//
// Rendered ONCE per wallpaper change, at one texel per cell (1920×1080 / 4 px = 480×270),
// into a half-float texture: R = the moment (0..~1) that cell flips to the new wallpaper.
// spread.frag then only looks it up, so a frame costs a handful of texture reads instead
// of recomputing colonies and noise for every pixel.
//
// Build: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o spreadmap.frag.qsb spreadmap.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float aspect;     // screen width / height
    float seed;
    vec4 c0;          // colonies: x (0..aspect), y (0..1), start time, unused
    vec4 c1;
    vec4 c2;
    vec4 c3;
    vec4 c4;
};

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x),
               mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return 0.55 * vnoise(p) + 0.30 * vnoise(p * 2.13) + 0.15 * vnoise(p * 4.41); }

float reach(vec4 c, vec2 p) { return c.z + distance(p, c.xy) * 0.62; }

void main() {
    vec2 p = vec2(qt_TexCoord0.x * aspect, qt_TexCoord0.y);
    float a = min(min(min(reach(c0, p), reach(c1, p)), min(reach(c2, p), reach(c3, p))), reach(c4, p));
    a += (fbm(p * 5.0) - 0.5) * 0.16;          // ragged, organic fronts
    fragColor = vec4(a, 0.0, 0.0, 1.0);
}
