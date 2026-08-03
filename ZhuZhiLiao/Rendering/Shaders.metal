#include <metal_stdlib>
using namespace metal;

struct BackgroundUniforms {
    float2 viewportSize;
    float time;
    float activity;
};

struct BackgroundVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex BackgroundVertexOut backgroundVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    BackgroundVertexOut output;
    float2 position = positions[vertexID];
    output.position = float4(position, 0.999, 1.0);
    output.uv = position * 0.5 + 0.5;
    return output;
}

float hash21(float2 value) {
    value = fract(value * float2(123.34, 456.21));
    value += dot(value, value + 45.32);
    return fract(value.x * value.y);
}

float segmentDistance(float2 point, float2 start, float2 end) {
    float2 segment = end - start;
    float denominator = max(dot(segment, segment), 0.00001);
    float position = clamp(dot(point - start, segment) / denominator, 0.0, 1.0);
    return length(point - (start + segment * position));
}

float bambooStroke(float2 point, float2 start, float2 end, float width) {
    return 1.0 - smoothstep(width, width + 0.004, segmentDistance(point, start, end));
}

fragment float4 backgroundFragment(
    BackgroundVertexOut input [[stage_in]],
    constant BackgroundUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = float2(input.uv.x, 1.0 - input.uv.y);
    float3 top = float3(0.035, 0.055, 0.145);
    float3 middle = float3(0.085, 0.115, 0.265);
    float3 bottom = float3(0.255, 0.185, 0.315);
    float3 color = mix(top, middle, smoothstep(0.0, 0.58, uv.y));
    color = mix(color, bottom, smoothstep(0.60, 1.0, uv.y));

    float2 starCell = floor(uv * float2(38.0, 82.0));
    float starRandom = hash21(starCell);
    float2 starCenter = (starCell + float2(hash21(starCell + 2.3), hash21(starCell + 7.7)))
        / float2(38.0, 82.0);
    float starDistance = distance(uv, starCenter);
    float star = (1.0 - smoothstep(0.001, 0.004, starDistance))
        * step(0.82, starRandom)
        * (0.35 + 0.65 * sin(uniforms.time * (0.7 + starRandom) + starRandom * 18.0) * 0.5 + 0.35);
    color += float3(0.85, 0.78, 0.62) * star;

    float moonDistance = distance(uv, float2(0.78, 0.18));
    float moonGlow = 1.0 - smoothstep(0.035, 0.15, moonDistance);
    float moon = 1.0 - smoothstep(0.055, 0.061, moonDistance);
    color += float3(0.38, 0.34, 0.27) * moonGlow * 0.28;
    color = mix(color, float3(0.94, 0.88, 0.72), moon * 0.92);
    float crater = (1.0 - smoothstep(0.008, 0.015, distance(uv, float2(0.765, 0.189))))
        + (1.0 - smoothstep(0.006, 0.012, distance(uv, float2(0.795, 0.162))));
    color = mix(color, float3(0.67, 0.62, 0.53), clamp(crater * moon * 0.33, 0.0, 1.0));

    float bamboo = 0.0;
    bamboo += bambooStroke(uv, float2(0.045, 1.05), float2(0.070, -0.05), 0.016);
    bamboo += bambooStroke(uv, float2(0.20, 1.02), float2(0.145, 0.10), 0.010);
    bamboo += bambooStroke(uv, float2(0.07, 0.68), float2(0.25, 0.55), 0.008);
    bamboo += bambooStroke(uv, float2(0.16, 0.48), float2(0.02, 0.38), 0.007);
    bamboo += bambooStroke(uv, float2(0.95, 1.05), float2(0.92, -0.05), 0.013);
    bamboo += bambooStroke(uv, float2(0.92, 0.62), float2(0.78, 0.50), 0.007);
    bamboo += bambooStroke(uv, float2(0.94, 0.35), float2(0.82, 0.27), 0.006);
    bamboo = clamp(bamboo, 0.0, 1.0);
    color = mix(color, float3(0.015, 0.020, 0.055), bamboo * 0.88);

    float horizonGlow = exp(-pow((uv.y - 1.03) * 2.2, 2.0));
    color += float3(0.24, 0.09, 0.045) * horizonGlow * 0.28;

    float vignette = smoothstep(0.88, 0.25, distance(uv, float2(0.5, 0.47)));
    color *= 0.58 + vignette * 0.52;
    float grain = hash21(uv * uniforms.viewportSize + floor(uniforms.time * 12.0)) - 0.5;
    color += grain * 0.018;
    color += float3(0.11, 0.035, 0.015) * uniforms.activity * 0.08;
    return float4(color, 1.0);
}

struct MetalVertex {
    float4 position;
    float4 normal;
    float4 textureCoordinate;
};

struct DrawUniforms {
    float4x4 viewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 baseColor;
    float4 materialParameters;
};

struct LitVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 textureCoordinate;
};

vertex LitVertexOut litVertex(
    const device MetalVertex *vertices [[buffer(0)]],
    constant DrawUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    MetalVertex currentVertex = vertices[vertexID];
    float4 worldPosition = uniforms.modelMatrix * currentVertex.position;
    LitVertexOut output;
    output.position = uniforms.viewProjectionMatrix * worldPosition;
    output.worldPosition = worldPosition.xyz;
    output.normal = normalize((uniforms.normalMatrix * currentVertex.normal).xyz);
    output.textureCoordinate = currentVertex.textureCoordinate.xy;
    return output;
}

fragment float4 litFragment(
    LitVertexOut input [[stage_in]],
    constant DrawUniforms &uniforms [[buffer(1)]]
) {
    float3 normal = normalize(input.normal);
    float3 moonDirection = normalize(float3(0.55, 0.78, 0.60));
    float3 rimDirection = normalize(float3(-0.65, 0.20, -0.72));
    float diffuse = max(dot(normal, moonDirection), 0.0);
    float rim = pow(1.0 - max(dot(normal, normalize(float3(0.0, 0.05, 1.0))), 0.0), 2.4);
    float warm = max(dot(normal, rimDirection), 0.0);

    float3 base = uniforms.baseColor.rgb;
    float materialKind = uniforms.materialParameters.x;
    if (materialKind > 0.5 && materialKind < 1.5) {
        float streak = sin(input.textureCoordinate.x * 230.0 + sin(input.textureCoordinate.y * 13.0) * 2.0);
        float broad = sin(input.textureCoordinate.x * 34.0 + 0.8);
        base *= 0.91 + streak * 0.035 + broad * 0.055;
    }

    float3 lighting = float3(0.30, 0.32, 0.45)
        + float3(1.0, 0.91, 0.75) * diffuse * 0.92
        + float3(1.0, 0.44, 0.20) * warm * 0.18
        + float3(0.42, 0.48, 0.88) * rim * 0.24;
    float emissive = uniforms.materialParameters.y;
    float3 color = base * lighting + base * emissive * float3(1.35, 0.72, 0.32);
    return float4(color, uniforms.baseColor.a);
}
