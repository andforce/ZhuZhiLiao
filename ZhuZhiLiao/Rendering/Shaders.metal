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

float softStroke(float2 point, float2 start, float2 end, float width, float aspect) {
    float2 scale = float2(aspect, 1.0);
    return 1.0 - smoothstep(
        width,
        width + 0.004,
        segmentDistance(point * scale, start * scale, end * scale)
    );
}

float aspectDistance(float2 point, float2 center, float aspect) {
    return length((point - center) * float2(aspect, 1.0));
}

fragment float4 backgroundFragment(
    BackgroundVertexOut input [[stage_in]],
    constant BackgroundUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = float2(input.uv.x, 1.0 - input.uv.y);
    float aspect = max(uniforms.viewportSize.x / max(uniforms.viewportSize.y, 1.0), 0.1);
    float3 zenith = float3(0.014, 0.024, 0.064);
    float3 indigo = float3(0.034, 0.056, 0.126);
    float3 dusk = float3(0.090, 0.078, 0.132);
    float3 color = mix(zenith, indigo, smoothstep(0.0, 0.62, uv.y));
    color = mix(color, dusk, smoothstep(0.66, 1.02, uv.y) * 0.84);

    float haze = exp(-pow((uv.y - 0.73) * 4.5, 2.0));
    color += float3(0.050, 0.044, 0.065) * haze * 0.20;

    float moonDistance = aspectDistance(uv, float2(0.82, 0.19), aspect);
    float moonGlow = 1.0 - smoothstep(0.045, 0.16, moonDistance);
    float moon = 1.0 - smoothstep(0.044, 0.050, moonDistance);
    color += float3(0.48, 0.40, 0.25) * moonGlow * 0.15;
    color = mix(color, float3(0.90, 0.84, 0.67), moon * 0.94);
    float crater = 1.0 - smoothstep(
        0.006,
        0.013,
        aspectDistance(uv, float2(0.806, 0.201), aspect)
    );
    crater += (1.0 - smoothstep(
        0.004,
        0.010,
        aspectDistance(uv, float2(0.833, 0.174), aspect)
    )) * 0.62;
    color = mix(color, float3(0.63, 0.59, 0.49), clamp(crater * moon * 0.18, 0.0, 1.0));

    float2 snowCell = floor(uv * float2(22.0, 42.0));
    float snowRandom = hash21(snowCell + 4.2);
    float2 snowCenter = (snowCell + float2(
        hash21(snowCell + 7.3),
        hash21(snowCell + 12.7)
    )) / float2(22.0, 42.0);
    float snowDistance = aspectDistance(uv, snowCenter, aspect);
    float snow = (1.0 - smoothstep(0.0010, 0.0026, snowDistance))
        * step(0.94, snowRandom);
    float twinkle = 0.74 + sin(uniforms.time * 0.42 + snowRandom * 11.0) * 0.08;
    color += float3(0.88, 0.86, 0.77) * snow * twinkle;

    float branches = 0.0;
    branches += softStroke(uv, float2(-0.02, 1.06), float2(0.060, 0.42), 0.012, aspect);
    branches += softStroke(uv, float2(0.052, 0.68), float2(0.18, 0.58), 0.007, aspect);
    branches += softStroke(uv, float2(0.020, 0.82), float2(-0.045, 0.75), 0.005, aspect);
    branches += softStroke(uv, float2(1.03, 1.06), float2(0.955, 0.44), 0.011, aspect);
    branches += softStroke(uv, float2(0.973, 0.69), float2(0.86, 0.59), 0.006, aspect);
    branches += softStroke(uv, float2(0.985, 0.84), float2(1.055, 0.76), 0.005, aspect);
    color = mix(color, float3(0.007, 0.011, 0.028), clamp(branches, 0.0, 1.0) * 0.82);

    float activityGlow = 1.0 - smoothstep(
        0.03,
        0.34,
        aspectDistance(uv, float2(0.50, 0.50), aspect)
    );
    color += float3(0.15, 0.055, 0.016) * uniforms.activity * activityGlow * 0.26;

    float horizonGlow = exp(-pow((uv.y - 1.04) * 2.4, 2.0));
    color += float3(0.17, 0.050, 0.025) * horizonGlow * 0.16;
    float vignette = smoothstep(0.78, 0.20, aspectDistance(uv, float2(0.5, 0.48), aspect));
    color *= 0.70 + vignette * 0.34;
    float grain = hash21(floor(uv * uniforms.viewportSize) * 0.73) - 0.5;
    color += grain * 0.009;
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
    float3 warmDirection = normalize(float3(-0.62, 0.18, 0.74));
    float3 viewDirection = normalize(float3(0.0, 0.04, 1.0));
    float3 halfDirection = normalize(moonDirection + viewDirection);
    float diffuse = max(dot(normal, moonDirection), 0.0);
    float rim = pow(1.0 - max(dot(normal, viewDirection), 0.0), 2.7);
    float warm = max(dot(normal, warmDirection), 0.0);

    float3 base = uniforms.baseColor.rgb;
    float materialKind = uniforms.materialParameters.x;
    float roughness = 0.78;
    if (materialKind > 0.5 && materialKind < 1.5) {
        float streak = sin(input.textureCoordinate.x * 190.0 + sin(input.textureCoordinate.y * 17.0) * 2.2);
        float broad = sin(input.textureCoordinate.x * 28.0 + input.textureCoordinate.y * 5.0 + 0.8);
        float node = smoothstep(0.94, 1.0, sin(input.textureCoordinate.y * 34.0) * 0.5 + 0.5);
        base *= 0.90 + streak * 0.026 + broad * 0.060 - node * 0.06;
        roughness = 0.86;
    } else if (materialKind > 1.5 && materialKind < 2.5) {
        float2 centered = input.textureCoordinate - 0.5;
        float radialFiber = sin(atan2(centered.y, centered.x) * 38.0 + length(centered) * 90.0);
        base *= 0.97 + radialFiber * 0.007;
        roughness = 0.93;
    } else if (materialKind > 2.5 && materialKind < 3.5) {
        float lacquerVariation = sin(input.textureCoordinate.x * 17.0) * 0.018;
        base += lacquerVariation;
        roughness = 0.28;
    } else if (materialKind > 4.5 && materialKind < 5.5) {
        float centerVein = 1.0 - smoothstep(0.018, 0.050, abs(input.textureCoordinate.x - 0.5));
        float sideVeins = 1.0 - smoothstep(0.018, 0.055, abs(fract(input.textureCoordinate.y * 5.0) - 0.5));
        float veinMask = max(centerVein * 0.7, sideVeins * 0.12);
        base *= 0.92 + sin(input.textureCoordinate.y * 24.0) * 0.025;
        base = mix(base, base * 0.64, veinMask);
        roughness = 0.90;
    }

    float specularPower = mix(10.0, 74.0, 1.0 - roughness);
    float specular = pow(max(dot(normal, halfDirection), 0.0), specularPower)
        * mix(0.03, 0.42, 1.0 - roughness);
    float3 lighting = float3(0.23, 0.25, 0.34)
        + float3(1.0, 0.90, 0.70) * diffuse * 0.94
        + float3(0.96, 0.46, 0.22) * warm * 0.15
        + float3(0.34, 0.40, 0.72) * rim * 0.18;
    float emissive = uniforms.materialParameters.y;
    float3 color = base * lighting
        + float3(1.0, 0.86, 0.65) * specular
        + base * emissive * float3(1.24, 0.68, 0.30);
    return float4(color, uniforms.baseColor.a);
}
