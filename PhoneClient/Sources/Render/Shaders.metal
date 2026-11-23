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

struct ThemeParams { float3 right; float3 up; float3 back; float tanY; float aspect; float time; int theme; };

static float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
static float h21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3 - 2 * f);
    return mix(mix(h21(i), h21(i + float2(1, 0)), f.x), mix(h21(i + float2(0, 1)), h21(i + float2(1, 1)), f.x), f.y);
}
static float fbm(float2 p) { float v = 0, a = 0.5; for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.03 + float2(17.1, 9.2); a *= 0.5; } return v; }
static float adiff(float a, float b) { float x = a - b; return atan2(sin(x), cos(x)); }
static float rain(float a, float y, float t, float sc, float speed, float slant, float seed) {
    float aa = a + y * slant; float cell = floor(aa * sc); float h = h11(cell + seed);
    float yy = fract(y * 1.3 + h * 9 - t * speed * (0.8 + h * 0.6));
    float lane = smoothstep(0.34, 0.0, abs(fract(aa * sc) - 0.5));
    return smoothstep(0.0, 0.03, yy) * smoothstep(0.22, 0.0, yy) * lane * step(0.45, h11(cell * 1.7 + seed * 3));
}

// ---- 1 lava lamp
static float lavaField(float2 p, float t) {
    float f = 0;
    for (int i = 0; i < 12; i++) {
        float fi = float(i), r = 0.2 + 0.1 * h11(fi + 3);
        float2 c = float2((fi / 12.0) * 6.2832 - 3.1416 + 0.25 * sin(t * 0.21 + fi * 1.9), 1.15 * sin(t * (0.1 + 0.035 * h11(fi)) + fi * 2.7));
        float2 q = float2(adiff(p.x, c.x), p.y - c.y); f += r * r / (dot(q, q) + 1e-3);
    }
    f += 0.5 * exp(-(p.y + 1.25) * 3.5) + 0.5 * exp((p.y - 1.25) * 3.5);
    return f;
}
static float3 lavaTheme(float a, float y, float t) {
    float2 p = float2(a, y * 1.5); float f = lavaField(p, t); float e = 0.02;
    float2 g = float2(lavaField(p + float2(e, 0), t) - lavaField(p - float2(e, 0), t), lavaField(p + float2(0, e), t) - lavaField(p - float2(0, e), t)) / (2 * e);
    float3 bg = mix(float3(1.0, 0.74, 0.08), float3(1.0, 0.9, 0.32), smoothstep(-1, 1, y));
    bg *= 1.0 - 0.22 * smoothstep(0.2, 1.6, length(float2(a * 0.35, y * 1.1)));
    float halo = smoothstep(0.25, 1.0, f);
    bg = mix(bg, float3(1.0, 0.5, 0.1), halo * 0.3);
    g *= saturate(1.5 - (f - 1.0) * 0.9);
    float3 n = normalize(float3(-g * 0.12, 1.0));
    float3 L = normalize(float3(-0.5, 0.65, 0.6));
    float diff = saturate(dot(n, L)), spec = pow(saturate(dot(reflect(-L, n), float3(0, 0, 1))), 28);
    float depth = saturate((f - 1.0) * 0.1);
    float3 base = mix(float3(1.0, 0.27, 0.07), float3(0.5, 0.02, 0.05), depth);
    float3 c = base * (0.5 + 0.75 * diff) + spec * 0.8 + float3(1, 0.5, 0.2) * pow(1 - saturate(n.z), 2) * 0.25;
    return mix(bg, c, smoothstep(0.97, 1.05, f));
}

// ---- 2 vice city waves
static float3 viceTheme(float a, float y, float t, float3 d) {
    float3 low = float3(1.0, 0.45, 0.18), mid = float3(0.85, 0.1, 0.5), top = float3(0.05, 0.02, 0.22);
    float h = max(y, 0.0);
    float3 sky = mix(low, mix(mid, top, smoothstep(0.12, 0.75, h)), smoothstep(0.0, 0.2, h));
    sky += float(step(0.996, h21(floor(float2(a * 70, y * 70))))) * smoothstep(0.3, 0.7, h) * 0.9;
    float2 sv = float2(adiff(a, 0.0), y - 0.19); float sr = length(sv);
    float thick = saturate(-sv.y * 4.5);
    float on = sv.y > 0 ? 1.0 : step(thick, fract(sv.y * 15));
    float3 sunC = mix(float3(1.0, 0.18, 0.5), float3(1.0, 0.92, 0.25), smoothstep(-0.19, 0.19, sv.y));
    sky += float3(1.0, 0.3, 0.5) * exp(-sr * 4.5) * 0.55;
    sky = mix(sky, sunC, smoothstep(0.195, 0.188, sr) * on);
    float cell = floor(a * 46); float bh = 0.012 + 0.05 * pow(h11(cell), 2) + (h11(cell + 8) > 0.9 ? 0.05 : 0);
    if (y > 0 && y < bh) {
        float win = step(0.72, h21(floor(float2(a * 46 * 4, y * 140)))) * step(0.1, fract(a * 46 * 4)) * 0.9;
        return float3(0.07, 0.0, 0.16) + float3(1, 0.8, 0.4) * win * step(0.25, fract(y * 140));
    }
    if (y >= 0) return sky;
    float2 p = d.xz / max(-y, 0.008);
    float wv = sin(p.y * 1.1 - t * 1.4 + sin(p.x * 0.45 + t * 0.3) * 0.9);
    float crest = smoothstep(0.86, 0.98, wv) * saturate(-y * 14);
    float3 sea = mix(float3(0.01, 0.0, 0.1), float3(0.4, 0.05, 0.5), exp(y * 7));
    float3 cc = mix(float3(0.0, 0.95, 1.0), float3(1.0, 0.2, 0.85), 0.5 + 0.5 * sin(p.x * 0.25 + p.y * 0.1));
    sea += cc * crest * (0.35 + 0.65 * exp(y * 4));
    float refl = exp(-abs(p.x) * 0.5) * smoothstep(0.2, 0.9, 0.5 + 0.5 * sin(p.y * 5 - t * 3 + p.x * 0.8));
    sea += float3(1.0, 0.7, 0.3) * refl * exp(y * 5) * 0.8;
    return mix(sea, float3(1.0, 0.4, 0.35), exp(y * 22) * 0.8);
}

// ---- 3 rain
static float3 rainTheme(float a, float y, float t, float3 d) {
    float3 col;
    float cl = fbm(float2(a * 1.6 + t * 0.02, y * 2.4 + 3));
    float flashT = fract(t * 0.11); float flash = step(0.965, flashT) * (0.55 + 0.45 * sin(t * 55)) + step(0.9, fract(t * 0.11 + 0.5)) * step(fract(t * 0.11 + 0.5), 0.915) * 0.4;
    if (y >= 0) {
        col = mix(float3(0.16, 0.19, 0.24), float3(0.04, 0.05, 0.09), saturate(y * 1.4));
        col *= 0.55 + cl * 0.9;
        col += float3(0.7, 0.78, 1.0) * flash * (0.25 + cl * 0.8) * (1 - y * 0.5);
        float lights = step(0.985, h21(floor(float2(a * 80, y * 80)))) * step(y, 0.05) * 0.8;
        col += float3(1, 0.85, 0.5) * lights;
    } else {
        float2 p = d.xz / max(-y, 0.01);
        float2 g = p * 1.1; float2 id = floor(g); float2 f = fract(g) - 0.5;
        float ph = fract(t * 0.6 + h21(id)); float r = length(f);
        float ring = smoothstep(0.035, 0.0, abs(r - ph * 0.55)) * (1 - ph);
        float3 refl = mix(float3(0.05, 0.06, 0.09), float3(0.22, 0.27, 0.36), exp(y * 6));
        col = refl + float3(0.5, 0.6, 0.8) * ring * exp(y * 2.5) * 0.9 + float3(0.7, 0.78, 1.0) * flash * 0.3;
    }
    float rr = rain(a, y, t, 55, 1.1, 0.16, 1) * 0.5 + rain(a, y, t, 90, 1.5, 0.16, 2) * 0.4 + rain(a, y, t, 140, 1.9, 0.16, 3) * 0.3;
    col += float3(0.6, 0.7, 0.9) * rr;
    return col;
}

// ---- 4 sunny
static float3 sunnyTheme(float a, float y, float t, float3 d) {
    float3 sunDir = normalize(float3(0.35, 0.5, -0.8)); float sd = saturate(dot(d, sunDir));
    float3 col;
    float hill1 = 0.015 + 0.06 * sin(a * 1.5 + 1) + 0.03 * sin(a * 4 + 2) + 0.012 * sin(a * 11);
    float hill0 = 0.05 + 0.05 * sin(a * 2.2 + 4) + 0.025 * sin(a * 6 + 1);
    if (y >= max(hill1, hill0)) {
        col = mix(float3(0.85, 0.94, 1.0), float3(0.12, 0.45, 0.95), saturate(pow(y, 0.7) * 1.4));
        col += float3(1.0, 0.92, 0.6) * pow(sd, 40) * 0.5 + float3(1.0, 0.95, 0.75) * pow(sd, 400) * 1.4;
        col = mix(col, float3(1.0, 0.98, 0.85), smoothstep(0.9993, 0.9996, sd));
        float2 cp = float2(a * 2.0 + t * 0.03, y * 5.0);
        float c1 = fbm(cp), c2 = fbm(cp * 1.9 + 7 + t * 0.02);
        float cm = smoothstep(0.52, 0.82, c1) * smoothstep(0.02, 0.25, y) * smoothstep(1.0, 0.45, y);
        float3 cloudC = mix(float3(0.8, 0.85, 0.95), float3(1.0), saturate(c2 * 1.4 + (y * 3 - fract(cp.y)) * 0.0));
        col = mix(col, cloudC, cm * 0.92);
        return col;
    }
    if (y >= hill0 - 0.0 && hill0 > hill1) return mix(float3(0.45, 0.68, 0.62), float3(0.6, 0.78, 0.7), saturate((hill0 - y) * 10));
    if (y >= 0.0 || hill1 > 0.0 && y >= -0.02) {
        float tr = step(0.55, vnoise(float2(a * 140, 0))) * smoothstep(0.012, 0.0, y - hill1 + 0.012 * vnoise(float2(a * 140, 1)));
        return mix(float3(0.35, 0.65, 0.25), float3(0.5, 0.8, 0.3), saturate((hill1 - y) * 8)) + tr * 0.0;
    }
    float2 p = d.xz / max(-y, 0.02);
    float stripe = 0.5 + 0.5 * sin(p.y * 1.3 + 1);
    float3 grass = mix(float3(0.22, 0.55, 0.16), float3(0.38, 0.72, 0.22), stripe);
    float2 g = p * 5; float2 id = floor(g);
    float fl = step(0.93, h21(id)) * smoothstep(0.22, 0.12, length(fract(g) - 0.5));
    float3 fc = h21(id + 3) > 0.5 ? float3(1, 0.95, 0.3) : (h21(id + 9) > 0.5 ? float3(1, 0.45, 0.6) : float3(1));
    grass = mix(grass, fc, fl);
    return mix(grass, float3(0.7, 0.85, 0.85), exp(y * 10) * 0.7);
}

// ---- 5 matrix
static float3 matrixTheme(float a, float y, float t) {
    float3 col = float3(0.0, 0.015, 0.006);
    for (int l = 0; l < 3; l++) {
        float fl = float(l), sc = 34 + fl * 26, rows = sc * 1.8;
        float colId = floor(a * sc), h = h11(colId + fl * 13.7);
        float speed = 0.5 + 1.4 * h;
        float s = fract(y * 0.8 + 0.5 + t * speed * 0.22 + h * 7.0);
        float2 cuv = float2(fract(a * sc), fract(y * rows)); float2 cid = float2(colId, floor(y * rows));
        float seed = h21(cid + floor(t * speed * 4.0) + fl * 5.0);
        float2 gp = floor(cuv * float2(3, 5)); float bit = step(0.48, h21(gp + seed * 37.0));
        float mask = step(0.14, cuv.x) * step(cuv.x, 0.86) * step(0.1, cuv.y) * step(cuv.y, 0.9);
        float active = step(0.22, h11(colId * 3.7 + fl)); float trail = pow(saturate(1 - s), 2.4);
        float g = trail * bit * mask * active;
        float head = smoothstep(0.035, 0.0, s) * mask * active * (0.5 + 0.5 * bit);
        col += float3(0.1, 1.0, 0.38) * g * (1.0 - fl * 0.28) + float3(0.75, 1.0, 0.85) * head * (1.0 - fl * 0.25);
    }
    col += float3(0.0, 0.07, 0.03) * smoothstep(-0.2, 1.0, y) * 0.5;
    return col;
}

// ---- 6 cyberpunk
static float3 cyberSky(float a, float y, float t) {
    float h = max(y, 0.0);
    float3 col = mix(float3(1.0, 0.18, 0.55), mix(float3(0.35, 0.05, 0.5), float3(0.02, 0.01, 0.12), smoothstep(0.15, 0.8, h)), smoothstep(0.0, 0.3, h));
    float2 mv = float2(adiff(a, 0.9), y - 0.32); float mr = length(mv);
    col += float3(0.8, 0.3, 1.0) * exp(-mr * 6) * 0.5;
    col = mix(col, mix(float3(1.0, 0.6, 0.9), float3(0.55, 0.2, 0.9), smoothstep(-0.12, 0.12, mv.y)), smoothstep(0.125, 0.12, mr));
    col += float(step(0.997, h21(floor(float2(a * 90, y * 90))))) * smoothstep(0.4, 0.8, h) * 0.7;
    for (int L = 0; L < 3; L++) {
        float fL = float(L), sc = 20 + fL * 14, base = 0.05 + (2 - fL) * 0.03;
        float aa = a + fL * 0.37; float cell = floor(aa * sc); float hh = h11(cell + fL * 31);
        float bh = base + hh * hh * (0.3 - fL * 0.06) + (h11(cell + 5) > 0.9 ? 0.12 : 0);
        float fog = 0.35 + 0.65 * fL / 2.0;
        if (y < bh && y >= 0) {
            float2 wc = floor(float2(aa * sc * 6, y * 70)); float lit = step(0.62, h21(wc + fL * 9)) * step(0.15, fract(aa * sc * 6)) * step(0.2, fract(y * 70));
            lit *= 0.7 + 0.3 * sin(t * 2 + h21(wc) * 20);
            float3 neon = h11(cell + 9) > 0.5 ? float3(1.0, 0.1, 0.65) : float3(0.1, 0.9, 1.0);
            float3 b = mix(float3(0.25, 0.08, 0.35), float3(0.03, 0.01, 0.08), fog) * (0.6 + 0.4 * (1 - fog));
            b += neon * lit * 0.8 * fog;
            float edge = smoothstep(bh - 0.006, bh, y);
            b += neon * edge * 0.9;
            float sign = step(0.88, h11(cell + 77)) * step(0.35, fract(aa * sc)) * step(fract(aa * sc), 0.5) * step(0.4 * bh, y) * step(y, 0.85 * bh);
            b += mix(float3(1, 0.1, 0.4), float3(0.1, 1, 0.9), h11(cell + 3)) * sign * (0.7 + 0.3 * sin(t * 6 + cell));
            col = mix(col, b, 1.0);
        }
    }
    return col;
}
static float3 cyberTheme(float a, float y, float t, float3 d) {
    if (y >= 0) return cyberSky(a, y, t);
    float2 p = d.xz / max(-y, 0.01);
    float2 g = abs(fract(p * 0.4 + float2(0, t * 0.5)) - 0.5);
    float line = smoothstep(0.045, 0.0, min(g.x, g.y)) * exp(y * 2.2);
    float3 floorC = mix(float3(0.02, 0.0, 0.07), float3(0.2, 0.03, 0.3), exp(y * 6));
    float3 reflc = cyberSky(a + sin(p.y * 2 + t) * 0.004, -y, t) * 0.5 * exp(y * 3.0);
    float3 neon = mix(float3(0.0, 0.95, 1.0), float3(1.0, 0.15, 0.7), 0.5 + 0.5 * sin(p.x * 0.2));
    return floorC + reflc + neon * line * 0.9;
}

// ---- 7 steampunk
static float4 gear(float2 p, float R, float teeth, float rot, float spokes) {
    float r = length(p), ang = atan2(p.y, p.x) + rot;
    float tooth = smoothstep(-0.25, 0.25, sin(ang * teeth));
    float rim = R * (1.0 + 0.13 * tooth);
    float outer = smoothstep(rim, rim - 0.003, r);
    float ring = outer * smoothstep(R * 0.72, R * 0.76, r);
    float arms = outer * step(r, R * 0.76) * smoothstep(0.075, 0.04, abs(sin(ang * spokes)) * r / R);
    float hub = smoothstep(R * 0.22, R * 0.2, r);
    float mask = max(ring, max(arms, hub));
    float shade = 0.62 + 0.38 * smoothstep(R * 0.72, R * 1.1, r) + 0.18 * cos(ang * 1.0 - 0.7);
    shade *= 1.0 - smoothstep(R * 0.07, R * 0.05, r) * 0.9;
    shade *= 1.0 - 0.45 * smoothstep(rim - 0.012, rim, r);
    return float4(mask, shade, 0, 0);
}
static float3 steamTheme(float a, float y, float t) {
    float3 wall = mix(float3(0.28, 0.16, 0.08), float3(0.5, 0.31, 0.15), saturate(y * 0.5 + 0.5));
    float2 pg = float2(a / 0.42, y / 0.34); float2 cellf = fract(pg);
    float seam = smoothstep(0.03, 0.0, min(min(cellf.x, 1 - cellf.x) * 0.42, min(cellf.y, 1 - cellf.y) * 0.34 * 1.2));
    wall *= 0.8 + 0.3 * vnoise(pg * 6);
    wall = mix(wall, float3(0.08, 0.04, 0.02), seam * 0.8);
    float2 rv = (cellf - float2(0.08, 0.1)); float rivet = smoothstep(0.045, 0.02, length(float2(rv.x * 0.42, rv.y * 0.34) * 2.4));
    float2 rv2 = (cellf - float2(0.92, 0.1)); rivet += smoothstep(0.045, 0.02, length(float2(rv2.x * 0.42, rv2.y * 0.34) * 2.4));
    wall += float3(0.7, 0.5, 0.25) * rivet * 0.6;
    float lamp = exp(-length(float2(adiff(a, -0.3) * 1.2, y - 0.2)) * 2.2);
    wall += float3(1.0, 0.6, 0.2) * lamp * 0.35;
    float3 col = wall;
    float gy[2] = { 0.52, -0.42 }; 
    for (int k = 0; k < 2; k++) {
        float yy = (y - gy[k]) / 0.07; if (abs(yy) < 1) {
            float cyl = sqrt(1 - yy * yy);
            float3 pc = mix(float3(0.35, 0.16, 0.08), float3(0.95, 0.6, 0.32), pow(cyl, 1.6)) * (0.8 + 0.2 * sin(a * 40 * 0 + 0));
            float fl = smoothstep(0.03, 0.0, abs(fract(a / 0.9 + 0.3 * k) - 0.5) - 0.035);
            pc = mix(pc, float3(0.55, 0.35, 0.18) * (0.6 + 0.5 * cyl), fl);
            col = pc;
        }
    }
    float4 gd[6] = { float4(-1.9, 0.18, 0.28, 12), float4(-0.95, -0.03, 0.2, 9), float4(0.0, 0.2, 0.34, 14), float4(1.05, -0.12, 0.24, 10), float4(1.95, 0.22, 0.3, 12), float4(2.8, -0.05, 0.22, 9) };
    for (int i = 0; i < 6; i++) {
        float2 p = float2(adiff(a, gd[i].x), y - gd[i].y);
        if (abs(p.x) > gd[i].z * 1.3 || abs(p.y) > gd[i].z * 1.3) continue;
        float dirn = (i % 2 == 0) ? 1.0 : -1.0;
        float4 gr = gear(p, gd[i].z, gd[i].w, t * 0.35 * dirn * (1.0 / (1.0 + float(i) * 0.15)) + float(i), 3.0);
        float3 gc = mix(float3(0.42, 0.22, 0.09), float3(1.0, 0.78, 0.38), saturate(gr.y));
        col = mix(col, gc, gr.x);
    }
    float2 gp = float2(adiff(a, 0.75), y - 0.22); float gr = length(gp);
    float dial = smoothstep(0.14, 0.135, gr);
    float3 dc = float3(0.95, 0.9, 0.78) * (1 - smoothstep(0.09, 0.14, gr) * 0.3);
    float ga = atan2(gp.y, gp.x);
    float ticks = step(0.5, fract((ga + 3.14159) * 5.0)) * step(0.1, gr) * step(gr, 0.125) * step(abs(ga), 2.4) * step(-2.4, ga);
    dc = mix(dc, float3(0.1), ticks);
    float need = -0.4 + sin(t * 0.7) * 1.1; float nd = abs(sin(ga - (need + 3.14159 * 0)) ) * gr;
    dc = mix(dc, float3(0.7, 0.05, 0.05), step(nd, 0.006) * step(cos(ga - need), 0.0 - 0.0 + 1.0) * step(gr, 0.1) * step(0.0, cos(ga - need)));
    col = mix(col, dc, dial);
    col = mix(col, float3(0.9, 0.6, 0.25), smoothstep(0.012, 0.004, abs(gr - 0.145)) * 0.9 );
    float steam = fbm(float2(a * 3.0, y * 2.5 - t * 0.25)) * smoothstep(-0.2, 0.9, y) * smoothstep(1.0, 0.3, y);
    col += float3(0.95, 0.85, 0.7) * pow(steam, 2.0) * 0.45;
    return col;
}

// ---- 8 solarpunk
static float3 solarTheme(float a, float y, float t, float3 d) {
    float3 col = mix(float3(1.0, 0.93, 0.62), float3(0.35, 0.8, 0.92), saturate(pow(max(y, 0.0), 0.6) * 1.5));
    float2 sp = float2(adiff(a, 0.0), y - 0.32); float sr = length(sp); float ang = atan2(sp.y, sp.x);
    col += float3(1.0, 0.9, 0.45) * (0.5 + 0.5 * sin(ang * 16 + t * 0.15)) * smoothstep(1.3, 0.0, sr) * 0.22;
    col += float3(1.0, 0.85, 0.4) * exp(-sr * 5) * 0.5;
    col = mix(col, float3(1.0, 0.88, 0.3), smoothstep(0.15, 0.14, sr));
    float cl = smoothstep(0.55, 0.8, fbm(float2(a * 2.2 + t * 0.02, y * 6 + 4))) * smoothstep(0.1, 0.3, y);
    col = mix(col, float3(1.0, 0.98, 0.92), cl * 0.55);
    float hf = 0.05 + 0.04 * sin(a * 3 + 1) + 0.025 * sin(a * 7);
    float hm = 0.0 + 0.05 * sin(a * 2.0 + 4) + 0.03 * sin(a * 5 + 2) + 0.012 * sin(a * 21);
    if (y < hf && y >= 0) {
        float3 hc = mix(float3(0.45, 0.72, 0.65), float3(0.55, 0.8, 0.7), saturate((hf - y) * 12));
        col = hc; 
        float tr = step(0.6, vnoise(float2(a * 120, 5))) * smoothstep(hf - 0.025, hf, y) * 0.0;
        col -= tr;
    }
    for (int k = 0; k < 9; k++) {
        float ca = (float(k) - 4.0) * 0.72 + 0.16 * h11(float(k) + 4);
        float x = adiff(a, ca); float th = 0.22 + 0.2 * h11(float(k) + 11);
        float w = 0.035 + 0.02 * h11(float(k) + 21) - 0.012 * saturate(y / th);
        if (y < 0 || y > th + 0.05 || abs(x) > w + 0.05) continue;
        float body = step(abs(x), w) * step(y, th);
        float band = fract(y * 22 + h11(float(k)) * 3);
        float over = step(0.78, band);
        float lush = step(abs(x), w + 0.012 * over) * step(y, th) * over;
        float3 tc = float3(0.97, 0.96, 0.9) * (0.82 + 0.2 * smoothstep(-w, w, x));
        float win = step(0.2, fract(x * 150)) * step(0.8, 1 - abs(band * 2 - 1.1) ) * 0.0 + step(0.25, band) * step(band, 0.62) * step(0.35, fract(x * 150 + 0.5)) * 0.55;
        tc = mix(tc, float3(0.2, 0.62, 0.75), win);
        if (body > 0) col = tc;
        if (lush > 0) col = mix(float3(0.16, 0.6, 0.2), float3(0.4, 0.8, 0.3), vnoise(float2(a * 400, y * 200)));
        float roof = smoothstep(0.04, 0.0, length(float2(x * 0.8, y - th - 0.005)) - 0.026);
        col = mix(col, float3(0.15, 0.58, 0.22), roof);
        float panel = step(abs(x - 0.0), w * 1.25) * step(th + 0.03, y) * step(y, th + 0.04 + x * 0.1) ;
        col = mix(col, float3(0.1, 0.2, 0.5), panel);
    }
    float2 tp = float2(adiff(a, -1.55), y - 0.17);
    float pole = step(abs(tp.x), 0.003) * step(0.0, y) * step(y, 0.17);
    float bl = 0;
    for (int b = 0; b < 3; b++) {
        float ba = t * 0.5 + float(b) * 2.094; float2 dirv = float2(cos(ba), sin(ba));
        float proj = clamp(dot(tp, dirv), 0.0, 0.09); float dist = length(tp - dirv * proj);
        bl = max(bl, step(dist, 0.004 * (1.2 - proj * 6)));
    }
    col = mix(col, float3(0.97), max(pole, bl));
    float hmix = hm;
    if (y < hmix) {
        float3 gc = mix(float3(0.18, 0.55, 0.2), float3(0.35, 0.72, 0.28), saturate((hmix - y) * 7));
        float tree = step(0.5, vnoise(float2(a * 90, 2))) * smoothstep(0.02, 0.0, y - hmix + 0.012 + 0.012 * vnoise(float2(a * 90, 7)));
        gc = mix(gc, float3(0.08, 0.4, 0.15), tree);
        col = gc;
        if (y < -0.02) {
            float2 p = d.xz / max(-y, 0.02); float2 g = p * 4; float2 id = floor(g);
            float fl = step(0.9, h21(id)) * smoothstep(0.22, 0.1, length(fract(g) - 0.5));
            float3 fc = h21(id + 3) > 0.5 ? float3(1, 0.85, 0.2) : float3(1, 0.5, 0.65);
            col = mix(mix(float3(0.17, 0.5, 0.17), float3(0.3, 0.68, 0.25), 0.5 + 0.5 * sin(p.y * 1.2)), fc, fl);
            col = mix(col, float3(0.75, 0.88, 0.7), exp(y * 9) * 0.6);
        }
    }
    float2 pc = float2(a * 14, y * 14 - t * 0.35); float2 pid = floor(pc);
    float poll = step(0.93, h21(pid)) * smoothstep(0.2, 0.0, length(fract(pc) - 0.5 - 0.2 * float2(sin(t + h21(pid) * 6), 0)));
    col += float3(1.0, 0.95, 0.5) * poll * 0.6;
    return col;
}

static float3 themeColor(float3 d, float t, int theme) {
    float a = atan2(d.x, -d.z), y = d.y;
    switch (theme) {
    case 1: return lavaTheme(a, y, t);
    case 2: return viceTheme(a, y, t, d);
    case 3: return rainTheme(a, y, t, d);
    case 4: return sunnyTheme(a, y, t, d);
    case 5: return matrixTheme(a, y, t);
    case 6: return cyberTheme(a, y, t, d);
    case 7: return steamTheme(a, y, t);
    default: return solarTheme(a, y, t, d);
    }
}

fragment float4 themeFragment(VOut in [[stage_in]], constant ThemeParams &u [[buffer(0)]]) {
    float2 n = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
    float3 ray = normalize(float3(n.x * u.tanY * u.aspect, n.y * u.tanY, -1));
    float3 d = normalize(u.right * ray.x + u.up * ray.y + u.back * ray.z);
    return float4(themeColor(d, u.time, u.theme), 1);
}
