#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut quadVertex(uint vid [[vertex_id]], constant float2 &scale [[buffer(0)]]) {
    const float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 t[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VOut o; o.pos = float4(p[vid] * scale, 0, 1); o.uv = t[vid]; return o;
}

fragment float4 quadFragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.uv);
}

// ---------------------------------------------------------------- F3 stereo

struct PanelUniforms { float4x4 mvp; float2 halfSize; };

vertex VOut panelVertex(uint vid [[vertex_id]], constant PanelUniforms &u [[buffer(0)]]) {
    const float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 t[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VOut o; o.pos = u.mvp * float4(p[vid] * u.halfSize, 0, 1); o.uv = t[vid]; return o;
}

// Grid + centre cross + unit ring, drawn in eye space (aspect-corrected).
fragment float4 testFragment(VOut in [[stage_in]], constant float &aspect [[buffer(0)]]) {
    float2 p = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
    p.x *= aspect;
    float2 q = p * 5.0;
    float2 g = abs(fract(q + 0.5) - 0.5) / max(fwidth(q), 1e-4);
    float line = 1.0 - min(min(g.x, g.y), 1.0);
    float3 col = mix(float3(0.03), float3(0.2, 0.9, 0.4), line);
    if (abs(p.x) < 0.006 || abs(p.y) < 0.006) col = float3(1);
    if (abs(length(p) - 1.0) < 0.008) col = float3(1.0, 0.3, 0.3);
    return float4(col, 1);
}

struct DistortParams {
    float2 lensCenter;   // normalized viewport coords, y up
    float aspect;        // viewport width / height
    float k1; float k2;
    float chroma;
    float sharpen;
    float maskRadius;
    float2 texel;        // 1 / eye texture size
};

fragment float4 distortFragment(VOut in [[stage_in]], texture2d<float> eyeTex [[texture(0)]],
                                constant DistortParams &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float2 p = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
    float2 d = p - u.lensCenter;
    float2 ds = float2(d.x * u.aspect, d.y);
    float r2 = dot(ds, ds);
    if (r2 > u.maskRadius * u.maskRadius) return float4(0, 0, 0, 1);
    float scale = 1.0 + u.k1 * r2 + u.k2 * r2 * r2;
    float2 sd = d * scale;
    float2 uvR = float2(sd.x * (1 - u.chroma), sd.y * (1 - u.chroma)) * 0.5;
    float2 uvG = sd * 0.5;
    float2 uvB = float2(sd.x * (1 + u.chroma), sd.y * (1 + u.chroma)) * 0.5;
    float2 c = float2(0.5, 0.5);
    float2 aR = c + float2(uvR.x, -uvR.y), aG = c + float2(uvG.x, -uvG.y), aB = c + float2(uvB.x, -uvB.y);
    float3 col = float3(eyeTex.sample(s, aR).r, eyeTex.sample(s, aG).g, eyeTex.sample(s, aB).b);
    if (u.sharpen > 0) {
        float3 n = eyeTex.sample(s, aG + float2(u.texel.x, 0)).rgb + eyeTex.sample(s, aG - float2(u.texel.x, 0)).rgb
                 + eyeTex.sample(s, aG + float2(0, u.texel.y)).rgb + eyeTex.sample(s, aG - float2(0, u.texel.y)).rgb;
        col += u.sharpen * (col - n * 0.25);
    }
    return float4(saturate(col), 1);
}

// ---------------------------------------------------------------- cursor sprite

struct SpriteUniforms { float2 center; float2 halfSize; };

vertex VOut spriteVertex(uint vid [[vertex_id]], constant SpriteUniforms &u [[buffer(0)]]) {
    const float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 t[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VOut o; o.pos = float4(u.center + p[vid] * u.halfSize, 0, 1); o.uv = t[vid]; return o;
}

fragment float4 spriteFragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.uv);
    return float4(c.rgb * c.a, c.a);   // premultiplied output, blend one / oneMinusSrcAlpha
}

// ---------------------------------------------------------------- F4 camera passthrough

struct CameraUniforms { float4x4 mvp; float2 xr; float2 yr; float z; };

// Quad whose corners are the camera image's pixel rays at distance |z| (principal point and focal length baked in).
vertex VOut cameraVertex(uint vid [[vertex_id]], constant CameraUniforms &u [[buffer(0)]]) {
    const float2 t[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    float2 uv = t[vid];
    float x = mix(u.xr.x, u.xr.y, uv.x);
    float y = mix(u.yr.x, u.yr.y, 1.0 - uv.y);   // yr.x = bottom, yr.y = top
    VOut o; o.pos = u.mvp * float4(x, y, u.z, 1); o.uv = uv; return o;
}

fragment float4 cameraFragment(VOut in [[stage_in]], texture2d<float> yTex [[texture(0)]],
                               texture2d<float> cbcrTex [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    const float4x4 m = float4x4(float4(1.0, 1.0, 1.0, 0.0), float4(0.0, -0.3441, 1.772, 0.0),
                                float4(1.402, -0.7141, 0.0, 0.0), float4(-0.701, 0.5291, -0.886, 1.0));
    float y = yTex.sample(s, in.uv).r;
    float2 c = cbcrTex.sample(s, in.uv).rg;
    return float4(saturate((m * float4(y, c, 1.0)).rgb), 1.0);
}

// ---------------------------------------------------------------- world themes (shown when the real world is darkened)

struct ThemeParams { float3 right; float pad0; float3 up; float pad1; float3 back; float pad2; float tanY; float aspect; float time; int theme; };

static float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
static float h21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3 - 2 * f);
    return mix(mix(h21(i), h21(i + float2(1, 0)), f.x), mix(h21(i + float2(0, 1)), h21(i + float2(1, 1)), f.x), f.y);
}
static float2 azel(float3 d) { return float2(atan2(d.x, -d.z), d.y); }
static float adiff(float a, float b) { float x = a - b; return atan2(sin(x), cos(x)); }

static float3 themeColor(float3 d, float t, int theme) {
    float2 ae = azel(d); float a = ae.x, y = d.y;
    switch (theme) {
    case 1: { // red lava lamp on yellow
        float3 bg = mix(float3(1.0, 0.72, 0.12), float3(1.0, 0.88, 0.3), saturate(y * 0.5 + 0.5));
        float f = 0;
        for (int i = 0; i < 7; i++) {
            float fi = float(i);
            float2 c = float2(a * 0 + (fi - 3) * 0.55 + sin(t * 0.3 + fi * 1.7) * 0.25, sin(t * (0.25 + fi * 0.04) + fi * 2.3) * 0.75);
            float2 p = float2(a, y * 1.6) - c; p.x = adiff(a, c.x);
            f += 0.06 / (dot(p, p) + 0.02);
        }
        float m = smoothstep(0.9, 1.1, f);
        float3 lava = mix(float3(0.75, 0.05, 0.05), float3(1.0, 0.25, 0.1), saturate((f - 1) * 0.6));
        return mix(bg, lava, m);
    }
    case 2: { // vice city waves
        float3 sky = mix(float3(1.0, 0.45, 0.2), float3(0.35, 0.08, 0.55), saturate(y * 2));
        float sun = smoothstep(0.30, 0.28, length(float2(adiff(a, 0.0), y - 0.22)));
        float bands = step(0.5, fract((y - 0.05) * 18)) * smoothstep(0.35, 0.05, y - 0.05);
        sky = mix(sky, mix(float3(1, 0.9, 0.25), float3(1, 0.2, 0.55), saturate((0.45 - y) * 3)) * (1 - bands * 0.9), sun);
        if (y < 0.0) {
            float2 p = d.xz / max(-y, 0.02);
            float wave = sin(p.y * 2.2 + t * 1.6 + sin(p.x * 0.7 + t * 0.5) * 1.5);
            float line = smoothstep(0.82, 0.95, wave);
            float3 sea = mix(float3(0.05, 0.02, 0.2), float3(0.0, 0.7, 0.9), line);
            sea += float3(1, 0.3, 0.7) * smoothstep(0.1, 0.0, abs(p.x * 0.2 - sin(t * 0.2))) * 0.2;
            return mix(sea, float3(0.9, 0.3, 0.6), smoothstep(-0.12, 0, y) * 0.8);
        }
        return sky;
    }
    case 3: { // rain
        float3 col = mix(float3(0.07, 0.10, 0.14), float3(0.22, 0.27, 0.33), saturate(y * 0.7 + 0.5));
        col *= 0.8 + vnoise(float2(a * 3, y * 3 + t * 0.05)) * 0.4;
        for (int l = 0; l < 3; l++) {
            float sc = 40 + l * 25; float cell = floor(a * sc); float h = h11(cell + l * 91);
            float speed = 0.7 + h * 0.8 + l * 0.3;
            float yy = fract(y * 1.5 + 0.3 - t * speed * 0.6 + h * 7);
            float inCol = smoothstep(0.30, 0.0, abs(fract(a * sc) - 0.5)) ;
            float streak = smoothstep(0.0, 0.02, yy) * smoothstep(0.18, 0.0, yy);
            col += float3(0.55, 0.65, 0.8) * streak * inCol * (0.35 - l * 0.08) * step(0.5, h11(cell * 1.3 + 4));
        }
        return col;
    }
    case 4: { // sunny
        float3 sky = mix(float3(0.75, 0.9, 1.0), float3(0.15, 0.5, 0.95), saturate(y * 1.4));
        float3 sunDir = normalize(float3(0.35, 0.55, -0.75));
        float sd = saturate(dot(d, sunDir));
        sky += float3(1.0, 0.9, 0.55) * pow(sd, 60) * 0.8 + float3(1.0, 0.95, 0.7) * smoothstep(0.9985, 0.9992, sd);
        float cl = vnoise(float2(a * 2.2 + t * 0.03, y * 5)) * 0.6 + vnoise(float2(a * 5 + t * 0.05, y * 11)) * 0.4;
        sky = mix(sky, float3(1), smoothstep(0.55, 0.85, cl) * smoothstep(0.0, 0.25, y) * 0.9);
        if (y < 0.0) return mix(float3(0.35, 0.7, 0.3), float3(0.55, 0.8, 0.35), saturate(-y * 1.5)) * (0.9 + vnoise(d.xz / max(-y, 0.05) * 3) * 0.15);
        return sky;
    }
    case 5: { // matrix
        float sc = 60; float col = floor(a * sc); float h = h11(col);
        float cellY = y * 38;
        float head = fract(t * (0.25 + h * 0.5) + h * 9);
        float pos = fract(-cellY / 38.0 * 0.9 + 0.5);
        float trail = fract(head - pos);
        float intensity = pow(saturate(1 - trail * 2.2), 2.0) * step(0.15, h11(col * 3.7));
        float glyph = step(0.35, h21(float2(col, floor(cellY) + floor(t * 6 * (0.5 + h)))));
        float lead = smoothstep(0.03, 0.0, trail);
        float inCell = step(0.18, fract(a * sc)) * step(fract(a * sc), 0.82) * step(0.12, fract(cellY)) ;
        return float3(0.0, 0.03, 0.0) + float3(0.1, 1.0, 0.3) * intensity * glyph * inCell + float3(0.7, 1, 0.8) * lead * inCell * 0.8;
    }
    case 6: { // cyberpunk
        float3 sky = mix(float3(0.9, 0.1, 0.55), float3(0.04, 0.02, 0.15), saturate(y * 1.6));
        if (y < 0.0) {
            float2 p = d.xz / max(-y, 0.02);
            float2 g = abs(fract(p * 0.5 + float2(0, t * 0.5)) - 0.5);
            float line = smoothstep(0.03, 0.0, min(g.x, g.y) * 1.0 / max(1.0, -1.0 / max(-y, 0.05) * 0.0 + 1));
            float3 floorC = mix(float3(0.02, 0.0, 0.08), float3(0.0, 0.9, 1.0), line * saturate(1 - (-y) * 2));
            return mix(floorC, sky, smoothstep(-0.05, 0, y));
        }
        float cell = floor(a * 28); float bh = 0.05 + h11(cell) * 0.35 + h11(cell + 50) * 0.15;
        if (y < bh) {
            float2 w = float2(fract(a * 28), fract(y * 40));
            float win = step(0.6, h21(floor(float2(a * 28 * 3, y * 40)) + cell)) * step(0.25, w.y) * step(0.2, fract(a * 84));
            float3 neon = h11(cell + 9) > 0.5 ? float3(1, 0.1, 0.7) : float3(0.1, 0.9, 1);
            return float3(0.02, 0.01, 0.06) + neon * win * 0.9 + neon * smoothstep(bh - 0.01, bh, y) * 0.8;
        }
        return sky;
    }
    case 7: { // steampunk
        float3 col = mix(float3(0.25, 0.14, 0.07), float3(0.7, 0.5, 0.25), saturate(y * 0.6 + 0.5));
        col *= 0.85 + vnoise(float2(a * 4, y * 4 + t * 0.02)) * 0.3;
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float2 c = float2(-1.9 + fi * 0.95, sin(fi * 2.1) * 0.35 + 0.1);
            float2 p = float2(adiff(a, c.x), y - c.y);
            float r = length(p), ang = atan2(p.y, p.x) + t * (fi == 1 || fi == 3 ? -0.3 : 0.3) * (1.0 + fi * 0.1);
            float R = 0.22 + 0.06 * fract(fi * 0.37); float teeth = 10 + fi * 2;
            float edge = R * (1.0 + 0.14 * smoothstep(-0.1, 0.1, sin(ang * teeth)));
            float body = smoothstep(edge, edge - 0.01, r) * smoothstep(R * 0.28, R * 0.32, r);
            float spokes = smoothstep(0.02, 0.0, abs(sin(ang * 3)) * r - 0.0) * step(r, R * 0.8) * step(R * 0.3, r) * 0.0;
            col = mix(col, mix(float3(0.45, 0.25, 0.1), float3(0.85, 0.6, 0.25), saturate(0.5 + 0.5 * cos(ang * 2) * (1 - r / R))), body);
            col = mix(col, float3(0.1, 0.06, 0.03), smoothstep(R * 0.3, R * 0.28, r) * smoothstep(R * 0.08, R * 0.1, r) * 0.9 + spokes);
        }
        float steam = vnoise(float2(a * 3, y * 3 - t * 0.2)) * smoothstep(-0.3, 0.8, y);
        return col + float3(0.9, 0.8, 0.6) * steam * 0.12;
    }
    default: { // 8: solarpunk
        float3 sky = mix(float3(1.0, 0.95, 0.7), float3(0.45, 0.85, 0.95), saturate(y * 1.3));
        float2 sp = float2(adiff(a, 0.0), y - 0.35);
        float ang = atan2(sp.y, sp.x);
        float rays = 0.5 + 0.5 * sin(ang * 14 + t * 0.2);
        sky += float3(1, 0.9, 0.4) * rays * smoothstep(1.4, 0.0, length(sp)) * 0.25;
        sky = mix(sky, float3(1.0, 0.85, 0.3), smoothstep(0.17, 0.15, length(sp)));
        float hill1 = 0.02 + 0.10 * sin(a * 2.0 + 1) + 0.04 * sin(a * 5);
        float hill2 = -0.06 + 0.08 * sin(a * 3.0 + 4) + 0.03 * sin(a * 7 + 2);
        if (y < hill2) return mix(float3(0.1, 0.45, 0.2), float3(0.2, 0.6, 0.25), saturate(hill2 - y));
        if (y < hill1) return mix(float3(0.3, 0.7, 0.3), float3(0.5, 0.8, 0.35), saturate(hill1 - y) * 3);
        float leaf = step(0.985, h21(floor(float2(a * 30, y * 30 - t * 0.3)))) ;
        return sky + float3(0.3, 0.8, 0.3) * leaf * 0.4;
    }
    }
}

fragment float4 themeFragment(VOut in [[stage_in]], constant ThemeParams &u [[buffer(0)]]) {
    float2 n = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
    float3 ray = normalize(float3(n.x * u.tanY * u.aspect, n.y * u.tanY, -1));
    float3 d = normalize(u.right * ray.x + u.up * ray.y + u.back * ray.z);
    return float4(themeColor(d, u.time, u.theme), 1);
}
