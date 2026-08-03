import simd

extension simd_float4x4 {
    static func translation(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(value.x, value.y, value.z, 1)
        ))
    }

    static func scale(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(value.x, 0, 0, 0),
            SIMD4<Float>(0, value.y, 0, 0),
            SIMD4<Float>(0, 0, value.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotation(_ quaternion: simd_quatf) -> simd_float4x4 {
        simd_float4x4(quaternion)
    }

    static func rotation(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    static func perspective(
        fieldOfViewY: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        let yScale = 1 / tan(fieldOfViewY * 0.5)
        let xScale = yScale / max(aspect, 0.001)
        let zScale = far / (near - far)

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, near * zScale, 0)
        ))
    }

    static func lookAt(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> simd_float4x4 {
        let zAxis = simd_normalize(eye - target)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)

        return simd_float4x4(columns: (
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4<Float>(
                -simd_dot(xAxis, eye),
                -simd_dot(yAxis, eye),
                -simd_dot(zAxis, eye),
                1
            )
        ))
    }

    static func transform(
        translation: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) -> simd_float4x4 {
        .translation(translation) * .rotation(rotation) * .scale(scale)
    }

    static func segment(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float
    ) -> simd_float4x4 {
        let delta = end - start
        let length = max(simd_length(delta), 0.000_1)
        let direction = delta / length
        let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        return .transform(
            translation: (start + end) * 0.5,
            rotation: rotation,
            scale: SIMD3<Float>(radius, length, radius)
        )
    }
}

