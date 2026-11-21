// spread.frag — the "Spread" wallpaper transition (modules/background/Background.qml).
//
// The new wallpaper eats through the old one in small square cells, starting from a few
// colonies that land at random places and moments. When each cell flips comes from the
// arrival map (spreadmap.frag, rendered once per change), so a frame is just a few
// texture reads:
//
//   • a cell that has just flipped burns for an instant in the accent colour
//   • a thin glow rides the front
//   • now and then a lone cell sparks just ahead of it
//
// Every extra is scaled by sin(πt): exactly zero at both ends, so handing over to the
// plain wallpaper can't show.
//
// Build: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o spread.v3.frag.qsb spread.frag   (bump the version when you change it: Qt caches by file name)
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;          // 0..1, linear in time
    float gw;         // grid size in cells (= map texture size)
    float gh;
    float seed;
    float glow;       // 0..1
    float amax;       // the latest arrival in this map (computed in QML), so the front uses the whole duration
    vec4 cropOld;     // image uv = xy + screen uv * zw (cover-crop, centred)
    vec4 cropNew;
    vec4 ember;       // accent colour
};
layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;
layout(binding = 3) uniform sampler2D mapTex;

const float PI = 3.14159265;
const float LIFE = 0.06;     // how long a flipped cell burns (in arrival units)

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453); }
float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }

// exact per-cell arrival: sample the map at the texel centre
float cellAt(vec2 cid) { return texture(mapTex, (clamp(cid, vec2(0.0), vec2(gw, gh) - 1.0) + 0.5) / vec2(gw, gh)).r; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 cid = floor(uv * vec2(gw, gh));

    float energy = sin(PI * t);
    float T = ease(t) * (amax + LIFE + 0.10) - 0.08;   // the last cell flips just before the end
    float a = cellAt(cid);
    vec3 hot = mix(ember.rgb, vec3(1.0), 0.18);
    vec3 c;

    if (a > T) {
        c = texture(oldTex, cropOld.xy + uv * cropOld.zw).rgb;
        float ahead = a - T;                   // a spark: a lone cell just ahead of the front
        if (ahead < 0.025 && glow > 0.0) {
            float flick = hash2(cid);
            if (flick > 0.985) c = mix(c, hot, (1.0 - ahead / 0.025) * 0.8 * glow * step(0.0, T));
        }
    } else {
        vec2 z = 0.5 + (uv - 0.5) / (1.0 + 0.03 * (1.0 - ease(t)));   // settles from a touch closer
        c = texture(newTex, cropNew.xy + z * cropNew.zw).rgb;
        float life = (T - a) / LIFE;
        if (life < 1.0) {                      // only freshly flipped cells do the extra work
            bool edge = max(max(cellAt(cid + vec2(1.0, 0.0)), cellAt(cid - vec2(1.0, 0.0))),
                            max(cellAt(cid + vec2(0.0, 1.0)), cellAt(cid - vec2(0.0, 1.0)))) > T;
            float burn = (1.0 - life) * (1.0 - life) * (edge ? 1.0 : 0.5);
            c = mix(c, hot, burn * (0.55 + 0.45 * hash2(cid)) * 0.85 * glow);
        }
    }
    // the thin glow riding the front (the map, filtered smoothly)
    float s = texture(mapTex, uv).r;
    c += ember.rgb * 0.22 * glow * energy * exp(-abs(s - T) / 0.007);

    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
