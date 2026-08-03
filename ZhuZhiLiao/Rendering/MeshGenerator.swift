import Metal
import simd

struct MetalVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var textureCoordinate: SIMD4<Float>

    init(
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        textureCoordinate: SIMD2<Float> = .zero,
        surfaceKind: Float = 0
    ) {
        self.position = SIMD4<Float>(position, 1)
        self.normal = SIMD4<Float>(normal, 0)
        self.textureCoordinate = SIMD4<Float>(
            textureCoordinate.x,
            textureCoordinate.y,
            surfaceKind,
            0
        )
    }
}

final class MetalMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    init(device: MTLDevice, vertices: [MetalVertex], indices: [UInt16]) {
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<MetalVertex>.stride * vertices.count,
            options: .storageModeShared
        )!
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared
        )!
        indexCount = indices.count
    }
}

enum MeshGenerator {
    static func cylinder(device: MTLDevice, segments: Int = 32) -> MetalMesh {
        frustum(
            device: device,
            bottomRadius: 0.5,
            topRadius: 0.5,
            segments: segments
        )
    }

    static func frustum(
        device: MTLDevice,
        bottomRadius: Float = 0.34,
        topRadius: Float = 0.5,
        segments: Int = 40
    ) -> MetalMesh {
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []
        let radiusSlope = topRadius - bottomRadius

        for segment in 0...segments {
            let fraction = Float(segment) / Float(segments)
            let angle = fraction * 2 * Float.pi
            let radialDirection = SIMD3<Float>(cos(angle), 0, sin(angle))
            let normal = simd_normalize(SIMD3<Float>(
                radialDirection.x,
                -radiusSlope,
                radialDirection.z
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radialDirection.x * bottomRadius,
                    -0.5,
                    radialDirection.z * bottomRadius
                ),
                normal: normal,
                textureCoordinate: SIMD2<Float>(fraction, 0)
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radialDirection.x * topRadius,
                    0.5,
                    radialDirection.z * topRadius
                ),
                normal: normal,
                textureCoordinate: SIMD2<Float>(fraction, 1)
            ))
        }

        for segment in 0..<segments {
            let lowerLeft = UInt16(segment * 2)
            let upperLeft = lowerLeft + 1
            let lowerRight = lowerLeft + 2
            let upperRight = lowerLeft + 3
            indices += [lowerLeft, upperLeft, lowerRight, upperLeft, upperRight, lowerRight]
        }

        appendCap(
            y: 0.5,
            radius: topRadius,
            normal: SIMD3<Float>(0, 1, 0),
            segments: segments,
            vertices: &vertices,
            indices: &indices,
            reverse: true
        )
        appendCap(
            y: -0.5,
            radius: bottomRadius,
            normal: SIMD3<Float>(0, -1, 0),
            segments: segments,
            vertices: &vertices,
            indices: &indices,
            reverse: false
        )

        return MetalMesh(device: device, vertices: vertices, indices: indices)
    }

    /// A subtly tapered bamboo tube with real wall thickness. `surfaceKind`
    /// distinguishes the outer wall (0), dark inner wall (1), and cut rims (2)
    /// so one draw call can still shade the three surfaces independently.
    static func hollowTube(
        device: MTLDevice,
        bottomRadius: Float = 0.45,
        topRadius: Float = 0.50,
        wallThickness: Float = 0.095,
        segments: Int = 48
    ) -> MetalMesh {
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []
        let outerSlope = topRadius - bottomRadius
        let innerBottomRadius = max(bottomRadius - wallThickness, 0.05)
        let innerTopRadius = max(topRadius - wallThickness, 0.05)
        let innerSlope = innerTopRadius - innerBottomRadius

        // Outer and inner cylindrical walls.
        for segment in 0...segments {
            let fraction = Float(segment) / Float(segments)
            let angle = fraction * 2 * Float.pi
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            let outerNormal = simd_normalize(SIMD3<Float>(
                radial.x,
                -outerSlope,
                radial.z
            ))
            let innerNormal = -simd_normalize(SIMD3<Float>(
                radial.x,
                -innerSlope,
                radial.z
            ))

            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radial.x * bottomRadius,
                    -0.5,
                    radial.z * bottomRadius
                ),
                normal: outerNormal,
                textureCoordinate: SIMD2<Float>(fraction, 0)
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radial.x * topRadius,
                    0.5,
                    radial.z * topRadius
                ),
                normal: outerNormal,
                textureCoordinate: SIMD2<Float>(fraction, 1)
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radial.x * innerBottomRadius,
                    -0.5,
                    radial.z * innerBottomRadius
                ),
                normal: innerNormal,
                textureCoordinate: SIMD2<Float>(fraction, 0),
                surfaceKind: 1
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(
                    radial.x * innerTopRadius,
                    0.5,
                    radial.z * innerTopRadius
                ),
                normal: innerNormal,
                textureCoordinate: SIMD2<Float>(fraction, 1),
                surfaceKind: 1
            ))
        }

        for segment in 0..<segments {
            let base = UInt16(segment * 4)
            let next = base + 4
            indices += [base, base + 1, next, base + 1, next + 1, next]
            indices += [base + 2, next + 2, base + 3, base + 3, next + 2, next + 3]
        }

        // The exposed annular cuts make the open end read as a bamboo tube
        // instead of a paper-thin shell.
        let rims: [(Float, Float, Float, SIMD3<Float>, Bool)] = [
            (-0.5, bottomRadius, innerBottomRadius, SIMD3<Float>(0, -1, 0), false),
            (0.5, topRadius, innerTopRadius, SIMD3<Float>(0, 1, 0), true)
        ]
        for (y, outerRadius, innerRadius, normal, reverse) in rims {
            let rimStart = UInt16(vertices.count)
            for segment in 0...segments {
                let fraction = Float(segment) / Float(segments)
                let angle = fraction * 2 * Float.pi
                let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
                vertices.append(MetalVertex(
                    position: SIMD3<Float>(radial.x * outerRadius, y, radial.z * outerRadius),
                    normal: normal,
                    textureCoordinate: SIMD2<Float>((cos(angle) + 1) * 0.5, (sin(angle) + 1) * 0.5),
                    surfaceKind: 2
                ))
                vertices.append(MetalVertex(
                    position: SIMD3<Float>(radial.x * innerRadius, y, radial.z * innerRadius),
                    normal: normal,
                    textureCoordinate: SIMD2<Float>((cos(angle) + 1) * 0.5, (sin(angle) + 1) * 0.5),
                    surfaceKind: 2
                ))
            }

            for segment in 0..<segments {
                let outer = rimStart + UInt16(segment * 2)
                let inner = outer + 1
                let nextOuter = outer + 2
                let nextInner = outer + 3
                indices += reverse
                    ? [outer, nextOuter, inner, inner, nextOuter, nextInner]
                    : [outer, inner, nextOuter, inner, nextInner, nextOuter]
            }
        }

        return MetalMesh(device: device, vertices: vertices, indices: indices)
    }

    static func wing(
        device: MTLDevice,
        lengthSegments: Int = 24,
        widthSegments: Int = 12
    ) -> MetalMesh {
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []
        let row = widthSegments + 1

        for surface in 0..<2 {
            let surfaceSign: Float = surface == 0 ? 1 : -1
            for lengthIndex in 0...lengthSegments {
                let v = Float(lengthIndex) / Float(lengthSegments)
                let leafProgress = pow(v, 0.88)
                let envelope = pow(max(sin(.pi * leafProgress), 0), 0.64)
                    * (0.92 - v * 0.12)
                for widthIndex in 0...widthSegments {
                    let u = Float(widthIndex) / Float(widthSegments)
                    let across = u * 2 - 1
                    let asymmetricWidth: Float = across < 0 ? 0.47 : 0.55
                    let width = envelope * asymmetricWidth
                    let arch = sin(.pi * v) * (1 - across * across) * 0.072
                    let thickness = surfaceSign * 0.012 * max(envelope, 0.12)
                    let normal = simd_normalize(SIMD3<Float>(
                        -across * 0.20,
                        (v - 0.48) * 0.10,
                        surfaceSign
                    ))
                    vertices.append(MetalVertex(
                        position: SIMD3<Float>(
                            across * width + sin(.pi * v) * 0.025,
                            0.5 - v,
                            arch + thickness
                        ),
                        normal: normal,
                        textureCoordinate: SIMD2<Float>(u, v)
                    ))
                }
            }
        }

        let surfaceVertexCount = (lengthSegments + 1) * row
        for surface in 0..<2 {
            let offset = surface * surfaceVertexCount
            for lengthIndex in 0..<lengthSegments {
                for widthIndex in 0..<widthSegments {
                    let a = UInt16(offset + lengthIndex * row + widthIndex)
                    let b = UInt16(offset + (lengthIndex + 1) * row + widthIndex)
                    if surface == 0 {
                        indices += [a, b, a + 1, a + 1, b, b + 1]
                    } else {
                        indices += [a, a + 1, b, a + 1, b + 1, b]
                    }
                }
            }
        }

        for sideWidthIndex in [0, widthSegments] {
            for lengthIndex in 0..<lengthSegments {
                let topA = UInt16(lengthIndex * row + sideWidthIndex)
                let topB = UInt16((lengthIndex + 1) * row + sideWidthIndex)
                let bottomA = UInt16(surfaceVertexCount) + topA
                let bottomB = UInt16(surfaceVertexCount) + topB
                if sideWidthIndex == 0 {
                    indices += [topA, bottomA, topB, topB, bottomA, bottomB]
                } else {
                    indices += [topA, topB, bottomA, topB, bottomB, bottomA]
                }
            }
        }

        return MetalMesh(device: device, vertices: vertices, indices: indices)
    }

    static func sphere(
        device: MTLDevice,
        latitudeSegments: Int = 18,
        longitudeSegments: Int = 24
    ) -> MetalMesh {
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []

        for latitude in 0...latitudeSegments {
            let v = Float(latitude) / Float(latitudeSegments)
            let phi = v * Float.pi
            for longitude in 0...longitudeSegments {
                let u = Float(longitude) / Float(longitudeSegments)
                let theta = u * 2 * Float.pi
                let normal = SIMD3<Float>(
                    sin(phi) * cos(theta),
                    cos(phi),
                    sin(phi) * sin(theta)
                )
                vertices.append(MetalVertex(
                    position: normal * 0.5,
                    normal: normal,
                    textureCoordinate: SIMD2<Float>(u, v)
                ))
            }
        }

        let row = longitudeSegments + 1
        for latitude in 0..<latitudeSegments {
            for longitude in 0..<longitudeSegments {
                let a = UInt16(latitude * row + longitude)
                let b = UInt16((latitude + 1) * row + longitude)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }

        return MetalMesh(device: device, vertices: vertices, indices: indices)
    }

    static func torus(
        device: MTLDevice,
        majorSegments: Int = 40,
        minorSegments: Int = 8
    ) -> MetalMesh {
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []
        let majorRadius: Float = 0.5
        let minorRadius: Float = 0.035

        for major in 0...majorSegments {
            let u = Float(major) / Float(majorSegments)
            let outerAngle = u * 2 * Float.pi
            for minor in 0...minorSegments {
                let v = Float(minor) / Float(minorSegments)
                let innerAngle = v * 2 * Float.pi
                let radial = majorRadius + minorRadius * cos(innerAngle)
                let position = SIMD3<Float>(
                    radial * cos(outerAngle),
                    radial * sin(outerAngle),
                    minorRadius * sin(innerAngle)
                )
                let normal = simd_normalize(SIMD3<Float>(
                    cos(innerAngle) * cos(outerAngle),
                    cos(innerAngle) * sin(outerAngle),
                    sin(innerAngle)
                ))
                vertices.append(MetalVertex(
                    position: position,
                    normal: normal,
                    textureCoordinate: SIMD2<Float>(u, v)
                ))
            }
        }

        let row = minorSegments + 1
        for major in 0..<majorSegments {
            for minor in 0..<minorSegments {
                let a = UInt16(major * row + minor)
                let b = UInt16((major + 1) * row + minor)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }

        return MetalMesh(device: device, vertices: vertices, indices: indices)
    }

    private static func appendCap(
        y: Float,
        radius: Float,
        normal: SIMD3<Float>,
        segments: Int,
        vertices: inout [MetalVertex],
        indices: inout [UInt16],
        reverse: Bool
    ) {
        let center = UInt16(vertices.count)
        vertices.append(MetalVertex(position: SIMD3<Float>(0, y, 0), normal: normal))

        for segment in 0...segments {
            let fraction = Float(segment) / Float(segments)
            let angle = fraction * 2 * Float.pi
            vertices.append(MetalVertex(
                position: SIMD3<Float>(cos(angle) * radius, y, sin(angle) * radius),
                normal: normal,
                textureCoordinate: SIMD2<Float>((cos(angle) + 1) * 0.5, (sin(angle) + 1) * 0.5)
            ))
        }

        for segment in 0..<segments {
            let first = center + 1 + UInt16(segment)
            let second = first + 1
            indices += reverse ? [center, second, first] : [center, first, second]
        }
    }
}
