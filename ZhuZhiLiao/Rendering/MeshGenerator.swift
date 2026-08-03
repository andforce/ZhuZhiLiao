import Metal
import simd

struct MetalVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var textureCoordinate: SIMD4<Float>

    init(
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        textureCoordinate: SIMD2<Float> = .zero
    ) {
        self.position = SIMD4<Float>(position, 1)
        self.normal = SIMD4<Float>(normal, 0)
        self.textureCoordinate = SIMD4<Float>(textureCoordinate.x, textureCoordinate.y, 0, 0)
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
        var vertices: [MetalVertex] = []
        var indices: [UInt16] = []

        for segment in 0...segments {
            let fraction = Float(segment) / Float(segments)
            let angle = fraction * 2 * Float.pi
            let x = cos(angle) * 0.5
            let z = sin(angle) * 0.5
            let normal = simd_normalize(SIMD3<Float>(x, 0, z))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(x, -0.5, z),
                normal: normal,
                textureCoordinate: SIMD2<Float>(fraction, 0)
            ))
            vertices.append(MetalVertex(
                position: SIMD3<Float>(x, 0.5, z),
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
            normal: SIMD3<Float>(0, 1, 0),
            segments: segments,
            vertices: &vertices,
            indices: &indices,
            reverse: false
        )
        appendCap(
            y: -0.5,
            normal: SIMD3<Float>(0, -1, 0),
            segments: segments,
            vertices: &vertices,
            indices: &indices,
            reverse: true
        )

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
                position: SIMD3<Float>(cos(angle) * 0.5, y, sin(angle) * 0.5),
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

