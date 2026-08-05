#include <metal_stdlib>
using namespace metal;

struct BackgroundUniforms {
    float2 viewportSize;
    float time;
    float activity;
    float4 sourceSkyTop;
    float4 sourceSkyMiddle;
    float4 sourceSkyBottom;
    float4 sourceAtmosphere;
    float4 sourceAccent;
    float4 sourceSilhouette;
    float4 targetSkyTop;
    float4 targetSkyMiddle;
    float4 targetSkyBottom;
    float4 targetAtmosphere;
    float4 targetAccent;
    float4 targetSilhouette;
    float4 themeParameters;
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

float particleField(
    float2 uv,
    float aspect,
    float time,
    float2 grid,
    float speed,
    float threshold,
    float size,
    float drift
) {
    float2 animatedUV = uv + float2(sin(time * 0.17 + uv.y * 8.0) * drift, time * speed);
    float2 cell = floor(animatedUV * grid);
    float2 local = fract(animatedUV * grid);
    float random = hash21(cell + 3.71);
    float2 center = float2(hash21(cell + 8.13), hash21(cell + 15.77));
    float distanceToParticle = length((local - center) * float2(aspect, 1.0));
    return (1.0 - smoothstep(size, size * 1.8, distanceToParticle))
        * step(threshold, random);
}

float3 seasonalScene(
    float2 uv,
    float aspect,
    float time,
    float activity,
    float theme,
    float3 skyTop,
    float3 skyMiddle,
    float3 skyBottom,
    float3 atmosphere,
    float3 accent,
    float3 silhouette
) {
    float3 color = mix(skyTop, skyMiddle, smoothstep(0.0, 0.58, uv.y));
    color = mix(color, skyBottom, smoothstep(0.56, 1.04, uv.y));

    float haze = exp(-pow((uv.y - 0.70) * 4.3, 2.0));
    color += atmosphere * haze * 0.12;

    if (theme < 0.5) {
        // 春：薄日、柳影与缓慢飘落的桃瓣。
        float sunDistance = aspectDistance(uv, float2(0.79, 0.20), aspect);
        float sunGlow = 1.0 - smoothstep(0.035, 0.18, sunDistance);
        float sun = 1.0 - smoothstep(0.040, 0.048, sunDistance);
        color += accent * sunGlow * 0.12;
        color = mix(color, float3(0.94, 0.84, 0.64), sun * 0.82);

        float willow = 0.0;
        willow += softStroke(uv, float2(-0.03, 0.05), float2(0.18, 0.37), 0.010, aspect);
        willow += softStroke(uv, float2(0.06, 0.18), float2(0.11, 0.54), 0.004, aspect);
        willow += softStroke(uv, float2(0.13, 0.26), float2(0.22, 0.58), 0.003, aspect);
        willow += softStroke(uv, float2(1.02, 0.02), float2(0.88, 0.31), 0.007, aspect);
        color = mix(color, silhouette, clamp(willow, 0.0, 1.0) * 0.76);

        float petals = particleField(uv, aspect, time, float2(12.0, 21.0), -0.022, 0.88, 0.070, 0.010);
        color += accent * petals * 0.68;
    } else if (theme < 1.5) {
        // 夏：弯月、竹影与不规则闪动的流萤。
        float moonDistance = aspectDistance(uv, float2(0.80, 0.18), aspect);
        float moonGlow = 1.0 - smoothstep(0.035, 0.17, moonDistance);
        float moon = 1.0 - smoothstep(0.043, 0.051, moonDistance);
        float moonCut = 1.0 - smoothstep(0.038, 0.049, aspectDistance(uv, float2(0.823, 0.164), aspect));
        color += accent * moonGlow * 0.12;
        color = mix(color, float3(0.94, 0.90, 0.70), moon * (1.0 - moonCut) * 0.90);

        float bamboo = 0.0;
        bamboo += softStroke(uv, float2(-0.02, 1.04), float2(0.10, 0.42), 0.014, aspect);
        bamboo += softStroke(uv, float2(0.055, 0.66), float2(0.20, 0.56), 0.006, aspect);
        bamboo += softStroke(uv, float2(1.02, 1.02), float2(0.93, 0.47), 0.013, aspect);
        bamboo += softStroke(uv, float2(0.96, 0.67), float2(0.83, 0.58), 0.006, aspect);
        color = mix(color, silhouette, clamp(bamboo, 0.0, 1.0) * 0.76);

        float2 fireflyCell = floor(uv * float2(11.0, 20.0));
        float fireflyRandom = hash21(fireflyCell + 19.1);
        float2 fireflyCenter = (fireflyCell + float2(
            hash21(fireflyCell + 5.2),
            hash21(fireflyCell + 9.8)
        )) / float2(11.0, 20.0);
        float firefly = (1.0 - smoothstep(0.002, 0.008, aspectDistance(uv, fireflyCenter, aspect)))
            * step(0.83, fireflyRandom);
        float pulse = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(time * (0.7 + fireflyRandom) + fireflyRandom * 20.0), 3.0);
        color += accent * firefly * pulse;
    } else if (theme < 2.5) {
        // 秋：满月、层山与旋落的金叶。
        float moonDistance = aspectDistance(uv, float2(0.77, 0.22), aspect);
        float moonGlow = 1.0 - smoothstep(0.050, 0.22, moonDistance);
        float moon = 1.0 - smoothstep(0.070, 0.080, moonDistance);
        color += accent * moonGlow * 0.16;
        color = mix(color, float3(0.98, 0.74, 0.37), moon * 0.88);

        float farRidge = 0.77 + sin(uv.x * 8.0 + 0.6) * 0.035 + sin(uv.x * 17.0) * 0.018;
        float nearRidge = 0.86 + sin(uv.x * 6.0 + 2.1) * 0.055 + sin(uv.x * 13.0) * 0.022;
        color = mix(color, silhouette * 1.7, smoothstep(farRidge, farRidge + 0.025, uv.y) * 0.56);
        color = mix(color, silhouette, smoothstep(nearRidge, nearRidge + 0.020, uv.y) * 0.86);

        float leaves = particleField(uv, aspect, time, float2(11.0, 19.0), -0.035, 0.86, 0.080, 0.018);
        color += accent * leaves * 0.68;
    } else {
        // 冬：冷月、疏枝与细雪。
        float moonDistance = aspectDistance(uv, float2(0.82, 0.19), aspect);
        float moonGlow = 1.0 - smoothstep(0.045, 0.17, moonDistance);
        float moon = 1.0 - smoothstep(0.044, 0.052, moonDistance);
        color += accent * moonGlow * 0.14;
        color = mix(color, float3(0.90, 0.86, 0.72), moon * 0.92);

        float branches = 0.0;
        branches += softStroke(uv, float2(-0.02, 1.06), float2(0.060, 0.42), 0.012, aspect);
        branches += softStroke(uv, float2(0.052, 0.68), float2(0.18, 0.58), 0.007, aspect);
        branches += softStroke(uv, float2(0.020, 0.82), float2(-0.045, 0.75), 0.005, aspect);
        branches += softStroke(uv, float2(1.03, 1.06), float2(0.955, 0.44), 0.011, aspect);
        branches += softStroke(uv, float2(0.973, 0.69), float2(0.86, 0.59), 0.006, aspect);
        color = mix(color, silhouette, clamp(branches, 0.0, 1.0) * 0.88);

        float snow = particleField(uv, aspect, time, float2(16.0, 29.0), -0.028, 0.88, 0.050, 0.006);
        color += accent * snow * 0.78;
    }

    float activityGlow = 1.0 - smoothstep(
        0.03,
        0.34,
        aspectDistance(uv, float2(0.50, 0.50), aspect)
    );
    color += accent * activity * activityGlow * 0.16;

    float horizonGlow = exp(-pow((uv.y - 1.03) * 2.5, 2.0));
    color += atmosphere * horizonGlow * 0.11;
    float vignette = smoothstep(0.80, 0.20, aspectDistance(uv, float2(0.5, 0.48), aspect));
    color *= 0.72 + vignette * 0.32;
    return color;
}

fragment float4 backgroundFragment(
    BackgroundVertexOut input [[stage_in]],
    constant BackgroundUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = float2(input.uv.x, 1.0 - input.uv.y);
    float aspect = max(uniforms.viewportSize.x / max(uniforms.viewportSize.y, 1.0), 0.1);
    float3 sourceColor = seasonalScene(
        uv,
        aspect,
        uniforms.time,
        uniforms.activity,
        uniforms.themeParameters.x,
        uniforms.sourceSkyTop.rgb,
        uniforms.sourceSkyMiddle.rgb,
        uniforms.sourceSkyBottom.rgb,
        uniforms.sourceAtmosphere.rgb,
        uniforms.sourceAccent.rgb,
        uniforms.sourceSilhouette.rgb
    );
    float3 targetColor = seasonalScene(
        uv,
        aspect,
        uniforms.time,
        uniforms.activity,
        uniforms.themeParameters.y,
        uniforms.targetSkyTop.rgb,
        uniforms.targetSkyMiddle.rgb,
        uniforms.targetSkyBottom.rgb,
        uniforms.targetAtmosphere.rgb,
        uniforms.targetAccent.rgb,
        uniforms.targetSilhouette.rgb
    );
    float3 color = mix(sourceColor, targetColor, uniforms.themeParameters.z);
    float grain = hash21(floor(uv * uniforms.viewportSize) * 0.73) - 0.5;
    color += grain * 0.007;
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
    float4 coolLightColor;
    float4 warmLightColor;
};

struct LitVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float3 textureCoordinate;
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
    output.textureCoordinate = currentVertex.textureCoordinate.xyz;
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
    float2 uv = input.textureCoordinate.xy;
    float surfaceKind = input.textureCoordinate.z;
    float roughness = 0.78;
    if (materialKind > 0.5 && materialKind < 1.5) {
        float fineFiber = sin(uv.x * 238.0 + sin(uv.y * 15.0) * 2.4);
        float broadFiber = sin(uv.x * 31.0 + uv.y * 5.0 + 0.8);
        float mottling = sin(uv.y * 11.0 + sin(uv.x * 19.0)) * 0.5 + 0.5;
        base *= 0.91 + fineFiber * 0.022 + broadFiber * 0.055 + mottling * 0.025;
        roughness = 0.88;

        if (surfaceKind > 0.5 && surfaceKind < 1.5) {
            // The cavity stays readable under moonlight without looking like
            // a flat black cap.
            base *= 0.34 + mottling * 0.10;
            roughness = 0.96;
        } else if (surfaceKind > 1.5) {
            float2 centered = uv - 0.5;
            float ray = sin(atan2(centered.y, centered.x) * 44.0 + length(centered) * 38.0);
            float growthRing = sin(length(centered) * 112.0);
            base *= 1.08 + ray * 0.025 + growthRing * 0.018;
            roughness = 0.94;
        }
    } else if (materialKind > 1.5 && materialKind < 2.5) {
        float2 centered = uv - 0.5;
        float radialFiber = sin(atan2(centered.y, centered.x) * 38.0 + length(centered) * 90.0);
        float growthRing = sin(length(centered) * 118.0 + radialFiber * 0.3);
        base *= 0.98 + radialFiber * 0.018 + growthRing * 0.012;
        roughness = 0.93;
    } else if (materialKind > 2.5 && materialKind < 3.5) {
        float lacquerVariation = sin(uv.x * 17.0) * 0.018;
        base += lacquerVariation;
        roughness = 0.28;
    } else if (materialKind > 3.5 && materialKind < 4.5) {
        float twist = sin((uv.x * 33.0 + uv.y * 19.0) * 2.0 * M_PI_F);
        base *= 0.88 + twist * 0.055;
        roughness = 0.82;
    } else if (materialKind > 4.5 && materialKind < 5.5) {
        float across = abs(uv.x - 0.5);
        float centerVein = 1.0 - smoothstep(0.016, 0.043, across);
        float branchCoordinate = uv.y * 5.8 + across * 1.42;
        float branchDistance = min(fract(branchCoordinate), 1.0 - fract(branchCoordinate));
        float sideVeins = (1.0 - smoothstep(0.018, 0.060, branchDistance))
            * smoothstep(0.055, 0.17, across);
        float edgeFiber = smoothstep(0.435, 0.495, across);
        float veinMask = max(centerVein * 0.82, max(sideVeins * 0.38, edgeFiber * 0.34));
        base *= 0.94 + sin(uv.y * 28.0 + uv.x * 3.0) * 0.025;
        base = mix(base, base * 0.58, veinMask);
        roughness = 0.90;
    } else if (materialKind > 5.5 && materialKind < 6.5) {
        float2 centered = uv - 0.5;
        float radialTension = sin(atan2(centered.y, centered.x) * 52.0 + length(centered) * 15.0);
        float paperFiber = sin(uv.x * 153.0 + sin(uv.y * 71.0) * 1.8)
            + sin(uv.y * 197.0 + uv.x * 8.0) * 0.55;
        float edgeAge = smoothstep(0.32, 0.50, length(centered));
        base *= 0.96 + radialTension * 0.012 + paperFiber * 0.012 - edgeAge * 0.075;
        roughness = 0.98;
    }

    float specularPower = mix(10.0, 74.0, 1.0 - roughness);
    float specular = pow(max(dot(normal, halfDirection), 0.0), specularPower)
        * mix(0.03, 0.42, 1.0 - roughness);
    float3 coolLight = uniforms.coolLightColor.rgb;
    float3 warmLight = uniforms.warmLightColor.rgb;
    float3 lighting = coolLight * 0.25
        + float3(1.0, 0.92, 0.75) * diffuse * 0.88
        + warmLight * warm * 0.18
        + coolLight * rim * 0.22;
    float emissive = uniforms.materialParameters.y;
    float3 color = base * lighting
        + warmLight * specular
        + base * emissive * mix(coolLight, warmLight, 0.55);
    return float4(color, uniforms.baseColor.a);
}
