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
