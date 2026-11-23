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
    float depth = saturate((f - 1.0) * 0.012);
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

// ---- 5 matrix (real glyphs from an atlas: 8×8 cells of digits, letters and katakana)
static float3 matrixTheme(float a, float y, float t, texture2d<float> atlas) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float3 col = float3(0.0, 0.012, 0.005);
    for (int l = 0; l < 3; l++) {
        float fl = float(l), sc = 30 + fl * 26, rows = sc * 0.62;
        float colId = floor(a * sc), h = h11(colId + fl * 13.7);
        float speed = 0.5 + 1.3 * h;
        float s = fract(y * 0.6 + 0.5 + t * speed * 0.2 + h * 7.0);
        float2 cuv = float2(fract(a * sc), fract(y * rows)); float rowId = floor(y * rows);
        float churn = floor(t * (0.6 + 1.6 * h11(colId * 1.3 + rowId)) );
        float gi = floor(h21(float2(colId, rowId) + churn * 3.1 + fl * 5.0) * 64.0);
        float2 auv = (float2(fmod(gi, 8.0), floor(gi / 8.0)) + float2(0.1 + cuv.x * 0.8, 0.06 + (1.0 - cuv.y) * 0.88)) / 8.0;
        float g = atlas.sample(smp, auv).r;
        float active = step(0.2, h11(colId * 3.7 + fl));
        float trail = pow(saturate(1 - s), 2.2);
        float head = smoothstep(0.045, 0.0, s);
        col += float3(0.1, 1.0, 0.38) * g * trail * active * (1.0 - fl * 0.28);
        col += float3(0.8, 1.0, 0.9) * g * head * active * (1.0 - fl * 0.25);
        col += float3(0.0, 0.25, 0.08) * g * 0.05 * active;   // ghost glyphs below the head
    }
    col += float3(0.0, 0.05, 0.02) * smoothstep(-0.2, 1.0, y) * 0.4;
    return col;
}

// ---- gears (steampunk facades)
static float4 gear(float2 p, float R, float teeth, float rot, float spokes) {
    float r = length(p), ang = atan2(p.y, p.x) + rot;
    float tooth = smoothstep(-0.25, 0.25, sin(ang * teeth));
    float rim = R * (1.0 + 0.13 * tooth);
    float outer = smoothstep(rim, rim - 0.01 * R, r);
    float ring = outer * smoothstep(R * 0.72, R * 0.76, r);
    float arms = outer * step(r, R * 0.76) * smoothstep(0.075, 0.04, abs(sin(ang * spokes)) * r / R);
    float hub = smoothstep(R * 0.22, R * 0.2, r);
    float mask = max(ring, max(arms, hub));
    float shade = 0.62 + 0.38 * smoothstep(R * 0.72, R * 1.1, r) + 0.18 * cos(ang - 0.7);
    shade *= 1.0 - smoothstep(R * 0.07, R * 0.05, r) * 0.9;
    shade *= 1.0 - 0.45 * smoothstep(rim - 0.04 * R, rim, r);
    return float4(mask, shade, 0, 0);
}

// ---- street café scenes (3 rain, 4 sunny, 6 cyberpunk, 7 steampunk, 8 solarpunk)
// You sit at a café table on the right pavement of a street that runs along -Z. Eye at origin, ground at y = GY.
constant float GY = -1.15;
constant float XN = 5.5;
constant float XF = 13.0;

static float3 fogColor(int th) {
    switch (th) { case 3: return float3(0.07, 0.08, 0.11); case 4: return float3(0.80, 0.88, 0.95); case 6: return float3(0.30, 0.05, 0.34);
                  case 7: return float3(0.78, 0.52, 0.32); default: return float3(0.80, 0.93, 0.88); }
}
static float fogK(int th) {
    switch (th) { case 3: return 0.04; case 4: return 0.012; case 6: return 0.032; case 7: return 0.028; default: return 0.012; }
}
// Fog after Inigo Quilez, "better fog" (iquilezles.org/articles/fog, snippets MIT): the fog is tinted toward the sun when looking
// at it, and denser close to the ground (exponential height falloff).
static float3 sunDirFor(int th) {
    switch (th) { case 3: return normalize(float3(0.1, 0.25, -1.0)); case 4: return normalize(float3(0.45, 0.7, -0.55));
                  case 6: return normalize(float3(0.6, 0.3, -0.7)); case 7: return normalize(float3(0.0, 0.2, -1.0)); default: return normalize(float3(-0.35, 0.75, -0.55)); }
}
static float3 sunTintFor(int th) {
    switch (th) { case 3: return float3(0.9, 0.6, 0.35); case 4: return float3(1.0, 0.9, 0.7); case 6: return float3(1.0, 0.3, 0.8);
                  case 7: return float3(1.0, 0.7, 0.35); default: return float3(1.0, 0.95, 0.7); }
}
static float3 fogApply(float3 col, float dist, float3 rd, int th) {
    float h = max(rd.y * dist - GY, 0.0);                       // height of the point above the ground
    float density = fogK(th) * (1.0 + 0.9 * exp(-h * 0.35));    // thicker near the ground
    float amount = 1.0 - exp(-dist * density);
    float sunAmount = pow(max(dot(rd, sunDirFor(th)), 0.0), 8.0);
    return mix(col, mix(fogColor(th), sunTintFor(th), sunAmount * 0.8), amount);
}

static float cellW(int th) { switch (th) { case 3: return 6.0; case 4: return 5.0; case 6: return 7.0; case 7: return 6.5; default: return 8.0; } }
static float bHeight(float u, float side, int layer, int th) {
    float cw = cellW(th); float c = floor(u / cw) + side * 31.0 + float(layer) * 17.0;
    float hh = h11(c * 1.7 + 3.0);
    float base = layer == 0 ? 7.0 : 14.0, range = layer == 0 ? 8.0 : 16.0;
    if (th == 4) { base = layer == 0 ? 8.0 : 11.0; range = layer == 0 ? 3.0 : 5.0; }
    if (th == 8) { base = layer == 0 ? 9.0 : 16.0; range = layer == 0 ? 8.0 : 14.0; }
    return base + hh * range;
}

static float3 skyStreet(float3 d, float t, int th) {
    float a = atan2(d.x, -d.z), y = d.y;
    float cl = fbm(float2(a * 1.6 + t * 0.02, y * 3.0 + 2.0));
    switch (th) {
    case 3: {
        float3 c = mix(float3(0.20, 0.17, 0.20), float3(0.05, 0.06, 0.10), saturate(y * 1.3));
        c *= 0.55 + cl * 0.9;
        float flashT = fract(t * 0.11);
        float flash = step(0.965, flashT) * (0.55 + 0.45 * sin(t * 55));
        return c + float3(0.7, 0.78, 1.0) * flash * (0.25 + cl * 0.8);
    }
    case 4: {
        float3 c = mix(float3(0.82, 0.92, 1.0), float3(0.14, 0.46, 0.95), saturate(pow(max(y, 0.0), 0.6) * 1.5));
        float3 sunDir = normalize(float3(0.45, 0.7, -0.55)); float sd = saturate(dot(d, sunDir));
        c += float3(1.0, 0.9, 0.6) * pow(sd, 30) * 0.6 + float3(1.0, 0.97, 0.8) * smoothstep(0.9993, 0.9997, sd);
        c = mix(c, float3(1.0), smoothstep(0.5, 0.82, cl) * smoothstep(0.1, 0.4, y) * 0.9);
        for (int b = 0; b < 5; b++) {   // birds
            float fb = float(b); float ba = adiff(a, fract(t * (0.012 + fb * 0.003) + fb * 0.21) * 6.2832 - 3.1416);
            float2 q = float2(ba * 9.0, (y - 0.55 - fb * 0.07) * 9.0);
            float flap = sin(t * 9 + fb * 2.0) * 0.35;
            float bird = smoothstep(0.07, 0.0, abs(q.y - (abs(q.x) * (0.7 + flap) - 0.1)) ) * step(abs(q.x), 0.45);
            c = mix(c, float3(0.1), bird * 0.9);
        }
        return c;
    }
    case 6: {
        float3 c = mix(float3(0.55, 0.06, 0.45), float3(0.03, 0.0, 0.10), saturate(pow(max(y, 0.0), 0.6) * 1.6));
        c += float3(0.5, 0.2, 0.8) * cl * 0.15 * saturate(y * 2);
        for (int l = 0; l < 3; l++) {   // flying traffic lanes
            float fl = float(l); float ey = 0.28 + fl * 0.14;
            float cellN = 24.0 + fl * 10.0; float aa = a * cellN / 6.2832 + t * (0.6 + fl * 0.3) * (l == 1 ? -1.0 : 1.0);
            float cid = floor(aa); float on = step(0.6, h11(cid + fl * 7.0));
            float tail = smoothstep(0.0, 0.9, fract(aa)) * smoothstep(1.0, 0.85, fract(aa));
            float lane = smoothstep(0.012, 0.0, abs(y - ey)) * tail * on;
            float3 lc = l == 1 ? float3(1.0, 0.1, 0.3) : float3(0.2, 0.9, 1.0);
            c += lc * lane * 1.6;
        }
        float beam = pow(saturate(1 - abs(adiff(a, 2.2 + sin(t * 0.3) * 0.5) * 3.0)), 3.0) * smoothstep(0.0, 0.6, y);
        return c + float3(0.5, 0.8, 1.0) * beam * 0.18;
    }
    case 7: {
        float3 c = mix(float3(0.98, 0.62, 0.3), float3(0.30, 0.26, 0.42), saturate(pow(max(y, 0.0), 0.6) * 1.5));
        c = mix(c, float3(1.0, 0.85, 0.6), smoothstep(0.5, 0.85, cl) * 0.5 * smoothstep(0.1, 0.5, y));
        for (int k = 0; k < 3; k++) {   // airships
            float fk = float(k);
            float a0 = fract(t * (0.006 + fk * 0.002) + fk * 0.33) * 6.2832 - 3.1416, el = 0.42 + fk * 0.17;
            float2 q = float2(adiff(a, a0), y - el);
            float L = 0.2 - fk * 0.04, H = 0.055 - fk * 0.01;
            float env = smoothstep(1.0, 0.94, length(float2(q.x / L, q.y / H)));
            float3 ec = mix(float3(0.35, 0.2, 0.12), float3(0.85, 0.6, 0.3), saturate(0.5 + q.y / H * 0.6));
            ec *= 0.8 + 0.2 * step(0.5, fract(q.x / L * 6.0));
            float fin = smoothstep(0.02, 0.0, abs(q.x + L * 0.95) - 0.012) * step(abs(q.y), H * 1.3);
            float gond = step(abs(q.x), L * 0.25) * step(-H * 1.5, q.y) * step(q.y, -H * 0.9);
            float prop = smoothstep(0.012, 0.0, abs(q.x + L * 1.08)) * step(abs(q.y), H * 0.6) * (0.5 + 0.5 * sin(t * 40));
            c = mix(c, ec, max(env, max(fin, gond * 0.0)));
            c = mix(c, float3(0.15, 0.08, 0.05), gond);
            c = mix(c, float3(0.9, 0.8, 0.6), prop * 0.5);
        }
        return c;
    }
    default: {
        float3 c = mix(float3(0.95, 0.97, 0.85), float3(0.30, 0.78, 0.92), saturate(pow(max(y, 0.0), 0.6) * 1.5));
        float3 sunDir = normalize(float3(-0.35, 0.75, -0.55)); float sd = saturate(dot(d, sunDir));
        c += float3(1.0, 0.95, 0.6) * pow(sd, 30) * 0.5 + float3(1.0, 0.97, 0.8) * smoothstep(0.9992, 0.9996, sd);
        c = mix(c, float3(1.0), smoothstep(0.55, 0.85, cl) * smoothstep(0.1, 0.4, y) * 0.8);
        for (int k = 0; k < 4; k++) {   // drones / kites
            float fk = float(k); float a0 = fract(t * 0.01 * (1 + fk * 0.4) + fk * 0.27) * 6.2832 - 3.1416;
            float2 q = float2(adiff(a, a0), y - 0.45 - fk * 0.1);
            float body = smoothstep(0.012, 0.006, length(q * float2(1, 1.6)));
            float blink = 0.5 + 0.5 * sin(t * 4 + fk * 3);
            c = mix(c, float3(0.2, 0.6, 0.3), body);
            c += float3(1.0, 0.9, 0.3) * smoothstep(0.02, 0.0, length(q + float2(0, 0.01))) * blink * 0.6;
        }
        return c;
    }
    }
}

// Glyph from the atlas (index 0-63) inside a unit cell; returns coverage.
static float glyphAt(texture2d<float> atlas, float idx, float2 uv) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float2 auv = (float2(fmod(idx, 8.0), floor(idx / 8.0)) + float2(0.08 + uv.x * 0.84, 0.05 + (1.0 - uv.y) * 0.9)) / 8.0;
    return atlas.sample(smp, auv).r;
}

// A window: x/y inside its cell. Returns rgb (glass + frame) and alpha (coverage).
static float4 windowPane(float2 w, float hsh, float t, int th, float lit, float2 world) {
    float2 gmin = float2(0.28, 0.30), gmax = float2(0.72, 0.82);
    if (th == 7) { gmin = float2(0.3, 0.25); gmax = float2(0.7, 0.85); }
    if (th == 8) { gmin = float2(0.12, 0.3); gmax = float2(0.88, 0.8); }
    float2 g = (w - gmin) / (gmax - gmin);
    float inGlass = step(0.0, g.x) * step(g.x, 1.0) * step(0.0, g.y) * step(g.y, 1.0);
    float2 fr = (w - gmin + 0.035) / (gmax - gmin + 0.07);
    float inFrame = step(0.0, fr.x) * step(fr.x, 1.0) * step(0.0, fr.y) * step(fr.y, 1.0);
    if (th == 7) {   // arched top
        float arch = step(g.y, 0.72 + 0.28 * sqrt(max(0.0, 1.0 - pow(g.x * 2.0 - 1.0, 2.0))));
        inGlass *= arch; inFrame *= step(fr.y, 0.74 + 0.3 * sqrt(max(0.0, 1.0 - pow(fr.x * 2.0 - 1.0, 2.0))));
    }
    if (inFrame < 0.5) return float4(0);
    float3 frameC = th == 6 ? float3(0.02, 0.02, 0.04) : (th == 7 ? float3(0.55, 0.32, 0.12) : (th == 3 ? float3(0.06, 0.05, 0.05) : float3(0.95, 0.95, 0.92)));
    if (inGlass < 0.5) return float4(frameC, 1);
    float mull = max(smoothstep(0.03, 0.0, abs(g.x - 0.5)), smoothstep(0.03, 0.0, abs(g.y - 0.55)));
    float3 glass;
    float lx = hsh;
    if (th == 3 || th == 7 || (th == 6 && lit > 0.5)) {
        float3 warm = th == 6 ? mix(float3(0.1, 0.8, 1.0), float3(1.0, 0.2, 0.7), step(0.5, hsh)) : (th == 7 ? float3(1.0, 0.62, 0.25) : float3(1.0, 0.72, 0.38));
        float curtain = 1.0 - 0.45 * step(g.y, 0.45) * smoothstep(0.1, 0.5, abs(sin(g.x * 9.0 + hsh * 6.0)));   // curtains/blinds
        float glow = 0.5 + 0.6 * smoothstep(0.0, 1.0, g.y);
        float flick = 0.85 + 0.15 * sin(t * 2.0 + hsh * 40.0);
        glass = (lit > 0.5 ? warm : float3(0.04, 0.06, 0.1)) * glow * curtain * flick * (0.55 + 0.7 * hsh);
        if (lit < 0.5) glass = mix(float3(0.03, 0.05, 0.09), float3(0.14, 0.18, 0.26), g.y);
    } else if (th == 6) {
        glass = mix(float3(0.02, 0.03, 0.06), float3(0.08, 0.12, 0.2), g.y);
    } else {
        // daylight: sky reflection + dark interior
        float3 sky = mix(float3(0.78, 0.9, 1.0), float3(0.3, 0.55, 0.85), g.y);
        float inter = 0.35 + 0.3 * smoothstep(0.0, 1.0, 1.0 - g.y);
        glass = mix(float3(0.1, 0.14, 0.17) * inter * 2.0, sky, 0.55 * smoothstep(0.1, 0.8, g.y + 0.2 * sin(g.x * 3.0 + hsh * 6.0)));
        if (th == 8) glass = mix(float3(0.1, 0.45, 0.55), float3(0.7, 0.95, 0.98), pow(g.y, 1.3));
    }
    glass = mix(glass, frameC, mull * (th == 8 ? 0.0 : 1.0));
    return float4(glass, 1);
}

static float3 facadeCol(float u, float v, float side, int layer, float t, int th, float dist, texture2d<float> atlas) {
    float cw = cellW(th);
    float cell = floor(u / cw) + side * 31.0 + float(layer) * 17.0;
    float hh = h11(cell * 1.7 + 3.0), h2 = h11(cell * 2.9 + 1.0), h3 = h11(cell * 4.1 + 7.0);
    float H = bHeight(u, side, layer, th);
    float fu = u / cw - floor(u / cw);
    float floorH = 3.0, ww = (th == 8 ? 3.4 : 2.4);
    float lit = (side < 0) ? 1.0 : 0.6;
    float2 wid = float2(floor(u / ww), floor(v / floorH));
    float2 wxy = float2(fract(u / ww), fract(v / floorH));
    bool shop = v < floorH + 0.3;
    float winHash = h21(wid + cell * 3.0);
    float on = step(th == 6 ? 0.45 : 0.55, winHash);
    float3 col;
    // shop signs share a layout: a board above the door row
    float signBand = step(floorH - 0.1, v) * step(v, floorH + 0.65);
    switch (th) {
    case 3: {
        float2 br = float2(u * 3.2 + floor(v * 8.0) * 0.5, v * 8.0);
        float mortar = step(0.07, fract(br.x)) * step(0.1, fract(br.y));
        col = mix(float3(0.04), mix(float3(0.19, 0.09, 0.08), float3(0.3, 0.15, 0.11), h21(floor(br))), mortar) * (0.5 + 0.6 * vnoise(float2(u, v) * 0.8));
        break;
    }
    case 4: {
        float3 pal[4] = { float3(0.97, 0.86, 0.64), float3(0.93, 0.7, 0.5), float3(0.9, 0.56, 0.46), float3(0.96, 0.93, 0.82) };
        col = pal[int(hh * 3.99)] * (0.88 + 0.12 * vnoise(float2(u, v) * 3.0)) * lit;
        break;
    }
    case 6: col = float3(0.035, 0.035, 0.06) * (0.6 + vnoise(float2(u, v) * 0.7)); break;
    case 7: {
        float2 br = float2(u * 2.4 + floor(v * 4.5) * 0.5, v * 4.5);
        float mortar = step(0.05, fract(br.x)) * step(0.08, fract(br.y));
        col = mix(float3(0.12, 0.08, 0.06), mix(float3(0.46, 0.3, 0.2), float3(0.64, 0.43, 0.28), h21(floor(br))), mortar);
        break;
    }
    default: {
        col = float3(0.94, 0.97, 0.93) * (0.7 + 0.3 * lit);
        float band = smoothstep(0.08, 0.0, abs(wxy.y - 0.12));
        col = mix(col, float3(0.72, 0.84, 0.78), band * 0.6);
        float garden = smoothstep(0.5, 0.62, fbm(float2(u * 0.6, v * 0.6) + cell * 3.0));
        float3 leaf = mix(float3(0.1, 0.42, 0.14), float3(0.5, 0.82, 0.25), vnoise(float2(u, v) * 7.0));
        col = mix(col, leaf * (0.7 + 0.3 * lit), garden * (shop ? 0.3 : 0.95));
        break;
    }
    }
    // upper-floor windows
    if (!shop && v < H - 0.8) {
        float4 w = windowPane(wxy, winHash, t, th, on, float2(u, v));
        if (w.a > 0.5) col = w.rgb * (th == 4 || th == 8 ? (0.75 + 0.25 * lit) : 1.0);
        if (th == 4) {   // shutters + flower boxes
            float shut = (step(0.14, wxy.x) * step(wxy.x, 0.26) + step(0.74, wxy.x) * step(wxy.x, 0.86)) * step(0.3, wxy.y) * step(wxy.y, 0.82);
            col = mix(col, h2 > 0.5 ? float3(0.18, 0.5, 0.34) * lit : float3(0.25, 0.4, 0.72) * lit, shut * (1.0 - w.a));
            float box = step(0.22, wxy.x) * step(wxy.x, 0.78) * step(0.2, wxy.y) * step(wxy.y, 0.3);
            float3 fl = h21(floor(float2(u * 9.0, v * 9.0))) > 0.45 ? float3(0.95, 0.25, 0.4) : float3(0.25, 0.65, 0.25);
            col = mix(col, fl, box);
        }
        if (th == 8) {   // balcony rails
            col = mix(col, float3(0.2, 0.55, 0.25), step(0.25, wxy.y) * step(wxy.y, 0.3) * 0.8);
        }
    }
    // roofline, cornice, extras
    if (th == 4 && v > H - 1.0) col = float3(0.78, 0.36, 0.2) * (0.85 + 0.15 * step(0.5, fract(u * 4.0))) * lit;
    if (th == 7 && v > H - 0.7) col = float3(0.25, 0.12, 0.08);
    if (th == 3 && v > H - 0.4) col *= 0.5;
    if (th == 8 && v > H - 1.4) {
        float2 g = abs(fract(float2(u * 0.7, v * 0.9)) - 0.5);
        col = mix(float3(0.08, 0.14, 0.38), float3(0.25, 0.42, 0.72), smoothstep(0.45, 0.35, max(g.x, g.y))) * (0.7 + 0.5 * lit);
    }
    // shop fronts
    if (shop) {
        float2 sw = float2(fract(u / 3.2), v / floorH);
        float door = step(0.08, sw.x) * step(sw.x, 0.28) * step(v, 2.4);
        float glassArea = step(0.36, sw.x) * step(sw.x, 0.92) * step(0.28, v) * step(v, 2.4);
        float3 interior;
        switch (th) {
        case 3: interior = mix(float3(0.6, 0.32, 0.12), float3(1.0, 0.78, 0.45), vnoise(float2(u * 4.0, v * 3.0))) * (0.55 + 0.5 * step(0.25, fract(v * 1.6))); break;
        case 6: interior = mix(float3(0.9, 0.2, 0.7), float3(0.2, 0.9, 1.0), h2) * (0.35 + 0.5 * vnoise(float2(u * 5.0, v * 3.0))); break;
        case 7: interior = mix(float3(0.55, 0.3, 0.1), float3(1.0, 0.7, 0.3), vnoise(float2(u * 4.0, v * 3.0))) * (0.6 + 0.4 * step(0.3, fract(v * 1.5))); break;
        default: interior = mix(float3(0.25, 0.3, 0.32), float3(0.75, 0.88, 0.95), pow(v / 2.4, 1.2)); break;
        }
        float3 fr = th == 6 ? float3(0.02) : (th == 7 ? float3(0.45, 0.25, 0.1) : (th == 3 ? float3(0.05) : float3(0.35, 0.22, 0.14) * (th == 8 ? 0.0 : 1.0) + float3(0.9) * (th == 8 ? 1.0 : 0.0)));
        col = mix(col, fr, step(0.05, sw.x) * step(sw.x, 0.95) * step(0.2, v) * step(v, 2.55));
        col = mix(col, interior, glassArea);
        col = mix(col, fr * 0.8 + float3(0.1, 0.06, 0.03), door);
        if (th == 4 || th == 3 || th == 7) {  // little shop awning
            float aw = step(0.05, sw.x) * step(sw.x, 0.95) * step(2.5, v) * step(v, 2.95);
            float stripe = step(0.5, fract(u * 3.0));
            float3 ac = th == 4 ? mix(float3(0.9, 0.2, 0.2), float3(1.0), stripe) : (th == 3 ? mix(float3(0.45, 0.05, 0.1), float3(0.15, 0.03, 0.06), stripe) : mix(float3(0.4, 0.12, 0.08), float3(0.8, 0.6, 0.25), stripe));
            col = mix(col, ac * (th == 4 ? lit : 1.0), aw);
        }
    }
    // shop signs with lettering from the atlas
    if (signBand > 0.5) {
        float sx = fract(u / 3.2); if (side < 0) sx = 1.0 - sx;
        if (sx > 0.08 && sx < 0.92 && h3 > 0.25) {
            float row = (v - (floorH - 0.1)) / 0.75;
            float letters = 5.0; float lu = (sx - 0.08) / 0.84 * letters; float li = floor(lu);
            float gi = floor(h21(float2(floor(u / 3.2) + side * 11.0, li) + 2.0) * (th == 6 ? 28.0 : 36.0)) + (th == 6 ? 36.0 : 0.0);
            float g = glyphAt(atlas, gi, float2(fract(lu), row));
            float3 board, ink;
            switch (th) {
            case 3: board = float3(0.03); ink = h2 > 0.5 ? float3(1.0, 0.2, 0.3) : float3(0.3, 1.0, 0.7); break;
            case 6: board = float3(0.02, 0.02, 0.05); ink = h2 > 0.5 ? float3(1.0, 0.15, 0.6) : float3(0.1, 1.0, 0.9); break;
            case 7: board = float3(0.25, 0.1, 0.04); ink = float3(1.0, 0.8, 0.4); break;
            case 8: board = float3(0.2, 0.5, 0.3); ink = float3(1.0); break;
            default: board = float3(0.3, 0.17, 0.1) * lit; ink = float3(1.0, 0.95, 0.85) * lit; break;
            }
            float3 sc = mix(board, ink * ((th == 3 || th == 6) ? 1.6 + 0.3 * sin(t * 9.0 + h2 * 20.0) : 1.0), g);
            col = sc;
        }
    }
    // per-theme extras
    if (th == 6) {
        float edge = smoothstep(0.06, 0.0, abs(fu - 0.02)) + smoothstep(0.06, 0.0, abs(fu - 0.98));
        col += (h2 > 0.5 ? float3(1.0, 0.1, 0.5) : float3(0.1, 0.8, 1.0)) * edge * 0.5;
        // tall vertical katakana sign
        float sxp = ((side < 0 ? 1.0 - fu : fu) - 0.62) / 0.12;
        if (sxp > 0.0 && sxp < 1.0 && v > 4.0 && v < H - 1.5 && h3 > 0.4) {
            float rv = (v - 4.0) / 0.95; float ri = floor(rv);
            float gi = 36.0 + floor(h21(float2(cell, ri)) * 27.0);
            float g = glyphAt(atlas, gi, float2(sxp, fract(rv)));
            float3 nc = h2 > 0.5 ? float3(1.0, 0.15, 0.55) : float3(0.1, 0.95, 1.0);
            float flick = 0.75 + 0.25 * step(0.2, fract(t * 0.7 + cell * 0.37));
            col = mix(col + nc * 0.08, nc * 1.7 * flick, g);
            col += nc * smoothstep(0.35, 0.0, abs(sxp - 0.5)) * 0.1;
        }
        float bb = step(0.12, fu) * step(fu, 0.5) * step(7.0, v) * step(v, 11.0) * step(0.78, h2);   // hologram billboard
        float scan = 0.65 + 0.35 * sin(v * 70.0 - t * 7.0);
        float3 bc = mix(float3(1.0, 0.2, 0.6), float3(0.2, 0.9, 1.0), 0.5 + 0.5 * sin(t * 0.7 + cell));
        bc *= 0.4 + 0.8 * vnoise(float2(fu * 14.0 + t * 0.5, v * 3.0 + t * 3.0));
        col = mix(col, bc * scan * 1.3, bb);
    }
    if (th == 7 && v > floorH + 0.4) {
        for (int p = 0; p < 2; p++) {   // brass pipes
            float py = p == 0 ? 2.6 : 7.4; float cy = (v - py) / 0.2;
            if (abs(cy) < 1.0) { float cyl = sqrt(1 - cy * cy); col = mix(float3(0.25, 0.1, 0.05), float3(1.0, 0.65, 0.3), pow(cyl, 1.5)) * (0.85 + 0.15 * step(0.5, fract(u * 0.5))); }
        }
        if (h2 > 0.4 && v > 5.0 && v < H - 1.0) {   // rotating gear or clock
            float2 p = float2((fu - 0.5) * cw, v - min(8.2, H - 2.2));
            float4 g = gear(p, 1.5, 14.0, t * 0.3 * (h3 > 0.5 ? 1.0 : -1.0), 3.0);
            col = mix(col, mix(float3(0.35, 0.18, 0.08), float3(1.0, 0.75, 0.35), saturate(g.y)), g.x);
        }
    }
    // ambient occlusion at the street level and a subtle top-light gradient
    col *= 0.62 + 0.38 * smoothstep(0.0, 2.5, v);
    return col;
}

static float3 streetBackdrop(float3 d, float t, int th, texture2d<float> atlas, thread float &tHit) {
    float3 fog = fogColor(th);
    tHit = 1e9;
    float3 col = skyStreet(d, t, th);
    if (abs(d.x) > 1e-3) {
        float side = d.x < 0 ? -1.0 : 1.0;
        for (int layer = 0; layer < 2; layer++) {
            float tt = side * (layer == 0 ? XN : XF) / d.x;
            if (tt <= 0) continue;
            float3 P = d * tt; float v = P.y - GY;
            if (v > 0 && v < bHeight(P.z, side, layer, th)) {
                col = fogApply(facadeCol(P.z, v, side, layer, t, th, tt, atlas), tt, d, th);
                tHit = tt; break;
            }
        }
    }
    if (tHit > 1e8) col = mix(col, fog, saturate(0.35 - d.y) * 0.5);   // haze toward the horizon
    return col;
}

static float cobble(float2 p, float scale) {
    float2 q = p * scale; q.x += floor(q.y) * 0.5;
    float2 f = fract(q); float edge = smoothstep(0.0, 0.1, min(min(f.x, 1 - f.x), min(f.y, 1 - f.y)));
    return edge * (0.75 + 0.25 * h21(floor(q)));
}

static float3 groundStreet(float3 P, float3 d, float t, int th, float tg, texture2d<float> atlas) {
    float3 fog = fogColor(th);
    float2 xz = P.xz;
    float3 col;
    switch (th) {
    case 3: {
        float cb = cobble(xz, 4.5);
        float puddle = smoothstep(0.45, 0.6, fbm(xz * 0.45 + 4.0));
        float3 base = float3(0.06, 0.055, 0.06) * (0.5 + cb);
        float tb;
        float3 refl = streetBackdrop(float3(d.x, -d.y, d.z), t, th, atlas, tb);
        float fres = mix(0.35, 0.9, puddle) * (0.4 + 0.6 * pow(1 - saturate(-d.y), 2.0));
        col = mix(base, refl * 0.85 + float3(0.08, 0.05, 0.03), fres);
        float2 g = xz * 1.2; float2 id = floor(g); float ph = fract(t * 0.7 + h21(id)); float r = length(fract(g) - 0.5);
        col += float3(0.5, 0.6, 0.8) * smoothstep(0.03, 0.0, abs(r - ph * 0.5)) * (1 - ph) * 0.8 * (0.4 + puddle);
        break;
    }
    case 4: {
        float cb = cobble(xz, 3.6);
        col = mix(float3(0.42, 0.37, 0.32), float3(0.78, 0.7, 0.6), cb * (0.7 + 0.3 * vnoise(xz * 3.0)));
        float shade = smoothstep(2.2, 3.2, P.x + 0.5 * sin(P.z * 0.4));    // right building's shadow falls over our pavement
        float dapple = smoothstep(0.45, 0.7, fbm(xz * 1.4 + float2(t * 0.15, 0)));
        col *= mix(1.0, 0.55 + 0.35 * dapple, shade) * (0.9 + 0.1 * dapple);
        break;
    }
    case 6: {
        float3 base = float3(0.025, 0.025, 0.04) * (0.6 + 0.4 * cobble(xz, 2.2));
        float tb;
        float3 refl = streetBackdrop(float3(d.x, -d.y, d.z), t, th, atlas, tb);
        float fres = 0.55 + 0.4 * pow(1 - saturate(-d.y), 2.0);
        col = mix(base, refl * 1.1, fres);
        float lane = smoothstep(0.06, 0.0, abs(P.x + 0.2)) * step(0.5, fract(P.z * 0.4));
        col += float3(1.0, 0.2, 0.6) * lane * 0.6;
        float g = smoothstep(0.1, 0.0, min(abs(fract(P.x * 0.5) - 0.5) - 0.46, abs(fract(P.z * 0.5) - 0.5) - 0.46)) * 0.0;
        col += float3(0.3, 0.2, 0.5) * g;
        col += float3(0.5, 0.7, 1.0) * smoothstep(0.03, 0.0, abs(length(fract(xz * 1.3) - 0.5) - fract(t * 0.6 + h21(floor(xz * 1.3))) * 0.5)) * 0.35;
        break;
    }
    case 7: {
        float cb = cobble(xz, 4.0);
        col = mix(float3(0.14, 0.1, 0.08), float3(0.5, 0.38, 0.28), cb * (0.7 + 0.3 * vnoise(xz * 2.5)));
        float lamp = 0.0;
        for (int k = 0; k < 4; k++) { float lz = -5.0 - float(k) * 7.0; lamp += 0.7 / (1.0 + 0.5 * (pow(P.x - 4.6, 2.0) + pow(P.z - lz, 2.0))); lamp += 0.7 / (1.0 + 0.5 * (pow(P.x + 4.6, 2.0) + pow(P.z - lz, 2.0))); }
        col += float3(1.0, 0.6, 0.25) * lamp * 0.35;
        float steam = fbm(xz * 0.6 + float2(0, -t * 0.3));
        col = mix(col, float3(0.95, 0.85, 0.75), smoothstep(0.62, 0.9, steam) * 0.35);
        break;
    }
    default: {
        float x = P.x;
        float water = smoothstep(1.3, 1.1, abs(x + 0.0));
        float3 paver = mix(float3(0.74, 0.76, 0.7), float3(0.9, 0.92, 0.86), cobble(xz, 2.4));
        float grass = smoothstep(0.55, 0.62, fbm(xz * 0.5 + 2.0)) * step(2.4, abs(x));
        paver = mix(paver, mix(float3(0.2, 0.55, 0.2), float3(0.4, 0.72, 0.25), vnoise(xz * 5.0)), grass);
        float fl = step(0.93, h21(floor(xz * 4.0))) * smoothstep(0.22, 0.1, length(fract(xz * 4.0) - 0.5)) * grass;
        paver = mix(paver, h21(floor(xz * 4.0) + 3.0) > 0.5 ? float3(1.0, 0.85, 0.2) : float3(1.0, 0.45, 0.65), fl);
        float tb;
        float2 rip = float2(sin(P.z * 3.0 + t * 1.5) * 0.02, cos(P.x * 4.0 + t) * 0.02);
        float3 refl = streetBackdrop(normalize(float3(d.x + rip.x, -d.y, d.z + rip.y)), t, th, atlas, tb);
        float3 wc = mix(float3(0.1, 0.45, 0.55), refl, 0.55 + 0.3 * pow(1 - saturate(-d.y), 2.0));
        wc += float3(1) * smoothstep(0.92, 1.0, sin(P.z * 5.0 + t * 2.0 + P.x * 3.0)) * 0.15;
        col = mix(paver, wc, water);
        break;
    }
    }
    return fogApply(col, tg, d, th);
}

// Ray against a vertical cylinder (axis through (cx, cz)); returns t or -1 when the hit height is outside [y0, y1].
static float cylHit(float3 d, float cx, float cz, float r, float y0, float y1) {
    float2 oc = float2(-cx, -cz); float2 dd = d.xz;
    float A = dot(dd, dd); if (A < 1e-6) return -1;
    float B = dot(oc, dd), C = dot(oc, oc) - r * r;
    float disc = B * B - A * C; if (disc < 0) return -1;
    float tt = (-B - sqrt(disc)) / A; if (tt <= 0) return -1;
    float yh = d.y * tt; return (yh >= y0 && yh <= y1) ? tt : -1;
}

static float3 streetProps(float3 d, float t, int th, float3 col, thread float &tb) {
    float3 fog = fogColor(th);
    // our own table + a few more on the right pavement
    float3 tabs[4] = { float3(0.0, 0, -0.95), float3(2.3, 0, -2.3), float3(3.6, 0, -4.4), float3(1.6, 0, -5.8) };
    float topY = -0.5, seatY = -0.74;
    for (int k = 0; k < 4; k++) {
        float cx = tabs[k].x, cz = tabs[k].z;
        // legs
        float tl = cylHit(d, cx, cz, 0.035, GY, topY);
        if (tl > 0 && tl < tb) { tb = tl; col = float3(0.1, 0.1, 0.11) + (th == 7 ? float3(0.25, 0.12, 0.05) : float3(0.0)); }
        // table top
        if (d.y < -1e-3) {
            float tt = topY / d.y;
            if (tt > 0 && tt < tb) {
                float3 P = d * tt; float2 q = P.xz - float2(cx, cz); float r = length(q);
                if (r < 0.42) {
                    float3 tc;
                    switch (th) {
                    case 3: tc = float3(0.12, 0.1, 0.09) + float3(0.9, 0.55, 0.25) * 0.15 / (1.0 + 20.0 * r * r); break;
                    case 4: tc = (step(0.5, fract(q.x * 7.0)) + step(0.5, fract(q.y * 7.0)) == 1.0) ? float3(0.9, 0.2, 0.2) : float3(1.0); break;
                    case 6: tc = float3(0.05, 0.05, 0.08) + float3(0.1, 0.9, 1.0) * smoothstep(0.04, 0.0, abs(r - 0.38)) * 1.5; break;
                    case 7: tc = float3(0.35, 0.18, 0.08) * (0.7 + 0.3 * cos(r * 30.0)) + float3(0.8, 0.5, 0.2) * smoothstep(0.03, 0.0, abs(r - 0.4)); break;
                    default: tc = float3(0.88, 0.8, 0.65) * (0.85 + 0.15 * vnoise(q * 12.0)); break;
                    }
                    col = tc; tb = tt;
                    // cup + saucer with steam
                    float2 cq = q - float2(0.1, 0.05); float cr = length(cq);
                    if (cr < 0.07) col = mix(float3(0.95), float3(0.2, 0.1, 0.05), smoothstep(0.045, 0.04, cr));
                }
            }
            // chairs: two seats per table
            for (int c = 0; c < 2; c++) {
                float ang = float(c) * 3.14159 + (k == 0 ? 1.57 : 0.4);
                float2 cc = float2(cx, cz) + float2(cos(ang), sin(ang)) * 0.62;
                float ts = seatY / d.y;
                if (ts > 0 && ts < tb) {
                    float3 P = d * ts; float r = length(P.xz - cc);
                    if (r < 0.2) { col = th == 3 ? float3(0.1, 0.07, 0.06) : (th == 6 ? float3(0.08, 0.06, 0.12) : (th == 7 ? float3(0.3, 0.14, 0.06) : float3(0.7, 0.3, 0.2))); tb = ts; }
                }
                float cl = cylHit(d, cc.x, cc.y, 0.025, GY, seatY);
                if (cl > 0 && cl < tb) { tb = cl; col = float3(0.1); }
            }
        }
    }
    // steam over our cup
    {
        float3 sp = float3(0.1, -0.5, -0.9);
        float rr = length(cross(d, sp - float3(0, 0.0, 0))) ;    // distance from the ray to the cup position
        float rise = fbm(float2(rr * 20.0, t * 0.8)) ;
        float3 ps = float3(0.1, -0.5 + 0.12 * fract(t * 0.5), -0.85);
        float dist = length(cross(d, ps));
        col += float3(0.9) * smoothstep(0.05, 0.0, dist) * rise * 0.5 * step(0.0, d.y + 0.8);
    }
    // lamp posts
    for (int k = 0; k < 4; k++) {
        float lz = -5.0 - float(k) * 7.0;
        for (int s = 0; s < 2; s++) {
            float lx = s == 0 ? -4.6 : 4.6;
            float tl = cylHit(d, lx, lz, 0.035, GY, 3.3);
            if (tl > 0 && tl < tb) { tb = tl; col = th == 7 ? float3(0.12, 0.09, 0.07) : float3(0.12, 0.13, 0.14); }
            float3 head = float3(lx, 3.45, lz);
            float dist = length(cross(d, head));
            float gl = 1.0 / (1.0 + 30.0 * dist * dist);
            float3 lc = th == 3 ? float3(1.0, 0.75, 0.4) : (th == 6 ? float3(0.3, 0.9, 1.0) : (th == 7 ? float3(1.0, 0.7, 0.3) : float3(1.0, 0.95, 0.8)));
            float on = th == 4 || th == 8 ? 0.15 : (0.85 + 0.15 * sin(t * 7 + float(k) * 3.0 + float(s)));
            col += lc * gl * on * (th == 7 ? 1.4 : 1.0) * smoothstep(0.0, 0.2, dot(normalize(head), d));
        }
    }
    // pedestrians (billboards walking along the pavements)
    for (int p = 0; p < 5; p++) {
        float fp = float(p); float dir = (p % 2 == 0) ? 1.0 : -1.0;
        float xp = (p % 2 == 0) ? 3.9 + fp * 0.1 : -3.9 - fp * 0.1;
        float zp = -fract(t * 0.035 * (1.0 + fp * 0.25) * dir + fp * 0.31) * 38.0;
        if (dir < 0) zp = -38.0 + fract(t * 0.035 * (1.0 + fp * 0.25) + fp * 0.31) * 38.0 - 2.0;
        if (zp > -1.5 || d.z > -1e-3) continue;
        float tt = zp / d.z;
        if (tt <= 0 || tt >= tb) continue;
        float3 P = d * tt;
        float2 q = float2(P.x - xp, P.y - GY);
        float body = step(abs(q.x), 0.2 * (1.0 - q.y * 0.08)) * step(0.0, q.y) * step(q.y, 1.5);
        float head = smoothstep(0.13, 0.1, length(float2(q.x, q.y - 1.62)));
        float legs = step(abs(q.x), 0.18) * step(q.y, 0.8) * step(0.5 * sin(t * 6.0 + fp) * 0.0, 1.0);
        float m = max(body, head);
        if (m > 0.5) {
            float3 cc;
            switch (th) {
            case 3: cc = mix(float3(0.07, 0.07, 0.1), float3(0.55, 0.1, 0.12), step(0.6, h11(fp * 3.0))); break;
            case 6: cc = float3(0.04, 0.04, 0.08) + float3(0.1, 0.9, 1.0) * smoothstep(0.03, 0.0, abs(q.x)) * 0.5 + float3(1.0, 0.2, 0.6) * step(1.55, q.y) * 0.3; break;
            case 7: cc = mix(float3(0.22, 0.12, 0.07), float3(0.08), step(0.5, h11(fp * 5.0))); break;
            case 4: cc = mix(float3(0.9, 0.35, 0.3), float3(0.3, 0.5, 0.8), step(0.5, h11(fp * 7.0))); break;
            default: cc = mix(float3(0.95, 0.9, 0.7), float3(0.25, 0.6, 0.35), step(0.5, h11(fp * 7.0))); break;
            }
            if (q.y > 1.5) cc = float3(0.85, 0.65, 0.5) * 0.6;
            col = fogApply(cc, tt, d, th); tb = tt;
        }
    }
    // café awning above us (right side), scalloped edge, per-theme colours
    if (d.y > 1e-3) {
        float tt = 0.9 / d.y;
        if (tt < tb) {
            float3 P = d * tt;
            if (P.x > 1.0 && P.x < XN && P.z < 0.6 && P.z > -3.0) {
                float stripe = step(0.5, fract(P.x * 1.4));
                float edge = P.x - 1.0;
                float scallop = 0.18 * abs(sin(P.z * 5.0));
                if (edge > scallop) {
                    float3 ac;
                    switch (th) {
                    case 3: ac = mix(float3(0.35, 0.05, 0.08), float3(0.12, 0.03, 0.05), stripe); break;
                    case 4: ac = mix(float3(0.92, 0.2, 0.18), float3(0.98), stripe); break;
                    case 6: ac = mix(float3(0.06, 0.02, 0.12), float3(0.1, 0.9, 1.0), smoothstep(0.1, 0.0, abs(fract(P.x * 1.4) - 0.5) - 0.42)); break;
                    case 7: ac = mix(float3(0.4, 0.12, 0.08), float3(0.8, 0.6, 0.25), stripe); break;
                    default: ac = mix(float3(0.2, 0.55, 0.25), float3(0.4, 0.75, 0.3), vnoise(P.xz * 5.0)); break;
                    }
                    ac *= 0.5 + 0.5 * smoothstep(-3.0, 0.0, P.z);
                    if (th == 3) ac += float3(0.5, 0.6, 0.8) * step(0.97, h21(floor(P.xz * 12.0))) * 0.4;   // drips
                    col = fogApply(ac, tt, d, th); tb = tt;
                }
            }
        }
    }
    // bunting (sunny / solar): flags strung across the street
    if (th == 4 || th == 8) {
        for (int k = 0; k < 3; k++) {
            float zb = -4.0 - float(k) * 7.0;
            if (d.z > -1e-3) continue;
            float tt = zb / d.z; if (tt <= 0 || tt >= tb) continue;
            float3 P = d * tt;
            float sag = 3.4 + 0.5 * (1.0 - pow(P.x / XN, 2.0)) - 0.5;
            float fy = P.y - sag;
            float fl = step(abs(P.x), XN) * step(-0.4, fy) * step(fy, 0.0) * step(abs(fract(P.x * 2.0) - 0.5) , 0.5 - (-fy) * 1.2);
            if (fl > 0.5) {
                float3 cc = h21(floor(float2(P.x * 2.0, float(k)))) > 0.5 ? float3(1.0, 0.8, 0.2) : (h21(floor(float2(P.x * 2.0, float(k))) + 4.0) > 0.5 ? float3(0.9, 0.3, 0.4) : float3(0.3, 0.7, 0.9));
                col = fogApply(cc, tt, d, th); tb = tt;
            }
        }
    }
    return col;
}

static float3 streetTheme(float3 d, float t, int th, texture2d<float> atlas) {
    float tb;
    float3 col = streetBackdrop(d, t, th, atlas, tb);
    if (d.y < -1e-3) {
        float tg = GY / d.y;
        if (tg < tb) { col = groundStreet(d * tg, d, t, th, tg, atlas); tb = tg; }
    }
    col = streetProps(d, t, th, col, tb);
    // atmosphere: rain streaks / dust motes
    float a = atan2(d.x, -d.z), y = d.y;
    if (th == 3 || th == 6) {
        float rr = 0.0;
        rr += rain(a, y, t, 70.0, 1.4, 0.12, 1.0) * 0.5 + rain(a, y, t, 120.0, 1.9, 0.12, 2.0) * 0.4 + rain(a, y, t, 200.0, 2.4, 0.12, 3.0) * 0.3;
        col += (th == 3 ? float3(0.6, 0.7, 0.9) : float3(0.5, 0.7, 1.0)) * rr * (th == 3 ? 0.7 : 0.45);
    } else if (th == 4 || th == 8) {
        float2 pc = float2(a * 22.0, y * 22.0 - t * 0.3); float2 id = floor(pc);
        col += float3(1.0, 0.95, 0.6) * step(0.94, h21(id)) * smoothstep(0.2, 0.0, length(fract(pc) - 0.5)) * 0.35;
    } else if (th == 7) {
        col += float3(1.0, 0.8, 0.5) * 0.06 * fbm(float2(a * 4.0, y * 4.0 - t * 0.1));
    }
    return col;
}

static float3 themeColor(float3 d, float t, int theme, texture2d<float> atlas) {
    float a = atan2(d.x, -d.z), y = d.y;
    switch (theme) {
    case 1: return lavaTheme(a, y, t);
    case 2: return viceTheme(a, y, t, d);
    case 5: return matrixTheme(a, y, t, atlas);
    default: return streetTheme(d, t, theme, atlas);
    }
}

fragment float4 themeFragment(VOut in [[stage_in]], constant ThemeParams &u [[buffer(0)]], texture2d<float> atlas [[texture(0)]]) {
    float2 n = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
    float3 ray = normalize(float3(n.x * u.tanY * u.aspect, n.y * u.tanY, -1));
    float3 d = normalize(u.right * ray.x + u.up * ray.y + u.back * ray.z);
    float3 c = themeColor(d, u.time, u.theme, atlas);
    if (u.theme != 1 && u.theme != 2 && u.theme != 5) {
        // Filmic shoulder so lamps/neon roll off instead of clipping, plus a gentle vignette.
        float3 x = max(c, 0.0);
        c = select(0.7 + 0.3 * (1.0 - exp(-(x - 0.7) / 0.3)), x, x < 0.7);
        c *= 1.0 - 0.28 * pow(saturate(length(n) * 0.75), 2.6);
    }
    return float4(saturate(c), 1);
}
