@preconcurrency import MetalKit
import QuartzCore
import simd

private struct BackgroundUniforms {
    var viewportSize: SIMD2<Float>
    var time: Float
    var activity: Float
}

private struct DrawUniforms {
    var viewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var normalMatrix: simd_float4x4
    var baseColor: SIMD4<Float>
    var materialParameters: SIMD4<Float>
}

private struct Ripple {
    var position: SIMD3<Float>
    var bornAt: Float
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice

    private let coordinator: ExperienceCoordinator
    private let commandQueue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let litPipeline: MTLRenderPipelineState
    private let backgroundDepthState: MTLDepthStencilState
    private let depthState: MTLDepthStencilState
    private let translucentDepthState: MTLDepthStencilState
    private let cylinder: MetalMesh
    private let resonator: MetalMesh
    private let wing: MetalMesh
    private let sphere: MetalMesh
    private let torus: MetalMesh
    private let ropeVertexBuffers: [MTLBuffer]
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private let sampleCount: Int
    private let isRunningUnitTests: Bool

    private var trail: [SIMD3<Float>] = []
    private var ripples: [Ripple] = []
    private var ropePoints: [SIMD3<Float>] = []
    private var ropeVertices: [MetalVertex] = []
    private var frameResourceIndex = 0
    private var stableBodyTangent = SIMD3<Float>(0, 0, 1)
    private var wingAngles = SIMD2<Float>(repeating: 0.18)
    private var wingVelocities = SIMD2<Float>.zero
    private var lastEffectsTime: Float?
    private var lastRippleTime: Float = 0
    private var viewportSize = SIMD2<Float>(1, 1)

    private let cameraEye = SIMD3<Float>(0, 0.10, 9.25)
    private let sceneAnchor = SIMD3<Float>(0.24, 0.72, 0)

    init(coordinator: ExperienceCoordinator) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            fatalError("当前设备不支持 Metal")
        }

        self.coordinator = coordinator
        self.device = device
        self.commandQueue = commandQueue
        isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #if targetEnvironment(simulator)
        // SimMetalHost 在部分 Xcode/iOS Simulator 组合下无法稳定分配
        // 多重采样 drawable；真机仍使用计划中的 4x MSAA。
        sampleCount = 1
        #else
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        #endif

        let backgroundDescriptor = MTLRenderPipelineDescriptor()
        backgroundDescriptor.label = "水墨夜景"
        backgroundDescriptor.vertexFunction = library.makeFunction(name: "backgroundVertex")
        backgroundDescriptor.fragmentFunction = library.makeFunction(name: "backgroundFragment")
        backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        backgroundDescriptor.depthAttachmentPixelFormat = .depth32Float
        backgroundDescriptor.rasterSampleCount = sampleCount

        let litDescriptor = MTLRenderPipelineDescriptor()
        litDescriptor.label = "竹知了光照"
        litDescriptor.vertexFunction = library.makeFunction(name: "litVertex")
        litDescriptor.fragmentFunction = library.makeFunction(name: "litFragment")
        litDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        litDescriptor.depthAttachmentPixelFormat = .depth32Float
        litDescriptor.rasterSampleCount = sampleCount
        let colorAttachment = litDescriptor.colorAttachments[0]!
        colorAttachment.isBlendingEnabled = true
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            backgroundPipeline = try device.makeRenderPipelineState(descriptor: backgroundDescriptor)
            litPipeline = try device.makeRenderPipelineState(descriptor: litDescriptor)
        } catch {
            fatalError("Metal 管线创建失败：\(error.localizedDescription)")
        }

        let backgroundDepthDescriptor = MTLDepthStencilDescriptor()
        backgroundDepthDescriptor.depthCompareFunction = .always
        backgroundDepthDescriptor.isDepthWriteEnabled = false
        backgroundDepthState = device.makeDepthStencilState(descriptor: backgroundDepthDescriptor)!

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

        let translucentDescriptor = MTLDepthStencilDescriptor()
        translucentDescriptor.depthCompareFunction = .lessEqual
        translucentDescriptor.isDepthWriteEnabled = false
        translucentDepthState = device.makeDepthStencilState(descriptor: translucentDescriptor)!

        cylinder = MeshGenerator.cylinder(device: device)
        resonator = MeshGenerator.frustum(
            device: device,
            bottomRadius: 0.41,
            topRadius: 0.5
        )
        wing = MeshGenerator.wing(device: device)
        sphere = MeshGenerator.sphere(device: device)
        torus = MeshGenerator.torus(device: device)
        ropeVertexBuffers = (0..<3).map { _ in
            device.makeBuffer(
                length: MemoryLayout<MetalVertex>.stride * 50,
                options: .storageModeShared
            )!
        }

        super.init()
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = sampleCount
        view.clearColor = MTLClearColor(red: 0.03, green: 0.045, blue: 0.12, alpha: 1)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        view.autoResizeDrawable = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard !isRunningUnitTests,
              coordinator.isRunning,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        inFlightSemaphore.wait()
        commandBuffer.label = "竹知了画面"
        let ropeVertexBuffer = ropeVertexBuffers[frameResourceIndex]
        frameResourceIndex = (frameResourceIndex + 1) % ropeVertexBuffers.count
        commandBuffer.addCompletedHandler { [inFlightSemaphore] completedBuffer in
            inFlightSemaphore.signal()
            if let error = completedBuffer.error {
                print("Metal 渲染失败：\(error)；详情：\((error as NSError).userInfo)")
            }
        }

        let snapshot = coordinator.frame(at: CACurrentMediaTime())
        let bobPosition = sceneAnchor + snapshot.state.position
        updateEffects(snapshot: snapshot, bobPosition: bobPosition)

        var backgroundUniforms = BackgroundUniforms(
            viewportSize: viewportSize,
            time: snapshot.elapsedTime,
            activity: snapshot.state.activity
        )
        encoder.pushDebugGroup("水墨夜景")
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setDepthStencilState(backgroundDepthState)
        encoder.setFragmentBytes(
            &backgroundUniforms,
            length: MemoryLayout<BackgroundUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.popDebugGroup()

        let aspect = max(viewportSize.x / max(viewportSize.y, 1), 0.1)
        let projection = simd_float4x4.perspective(
            fieldOfViewY: 42 * .pi / 180,
            aspect: aspect,
            near: 0.1,
            far: 50
        )
        let viewMatrix = simd_float4x4.lookAt(
            eye: cameraEye,
            target: SIMD3<Float>(0, -0.15, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        let viewProjection = projection * viewMatrix

        encoder.pushDebugGroup("程序化竹知了")
        encoder.setRenderPipelineState(litPipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        drawToy(
            encoder: encoder,
            snapshot: snapshot,
            bobPosition: bobPosition,
            viewProjection: viewProjection
        )
        drawRope(
            encoder: encoder,
            state: snapshot.state,
            bobPosition: bobPosition,
            vertexBuffer: ropeVertexBuffer,
            viewProjection: viewProjection
        )
        drawEffects(
            encoder: encoder,
            time: snapshot.elapsedTime,
            viewProjection: viewProjection
        )
        encoder.popDebugGroup()

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawToy(
        encoder: MTLRenderCommandEncoder,
        snapshot: RenderSnapshot,
        bobPosition: SIMD3<Float>,
        viewProjection: simd_float4x4
    ) {
        let bamboo = SIMD4<Float>(0.62, 0.42, 0.16, 1)
        let cutBamboo = SIMD4<Float>(0.86, 0.69, 0.38, 1)
        let paleBamboo = SIMD4<Float>(0.79, 0.64, 0.35, 0.92)
        let lacquer = SIMD4<Float>(0.60, 0.075, 0.035, 1)
        let cordRed = SIMD4<Float>(0.74, 0.16, 0.075, 1)
        let ink = SIMD4<Float>(0.018, 0.014, 0.012, 1)

        let shaftStart = sceneAnchor + SIMD3<Float>(0, -0.055, 0)
        let shaftEnd = sceneAnchor + SIMD3<Float>(0, -1.55, 0)
        let shaftDirection = simd_normalize(shaftEnd - shaftStart)
        draw(
            mesh: cylinder,
            modelMatrix: .segment(from: shaftStart, to: shaftEnd, radius: 0.055),
            color: bamboo,
            materialKind: 1,
            encoder: encoder,
            viewProjection: viewProjection
        )
        draw(
            mesh: cylinder,
            modelMatrix: .segment(
                from: sceneAnchor - shaftDirection * 0.08,
                to: sceneAnchor + shaftDirection * 0.11,
                radius: 0.092
            ),
            color: cordRed,
            materialKind: 3,
            encoder: encoder,
            viewProjection: viewProjection
        )
        drawSphere(
            at: sceneAnchor - shaftDirection * 0.20,
            scale: 0.115,
            color: lacquer,
            materialKind: 3,
            encoder: encoder,
            viewProjection: viewProjection
        )
        drawSphere(
            at: sceneAnchor + shaftDirection * 0.13,
            scale: 0.071,
            color: cutBamboo,
            materialKind: 1,
            encoder: encoder,
            viewProjection: viewProjection
        )

        let towardAnchor = simd_normalize(sceneAnchor - bobPosition)
        var bodyTangent = stableBodyTangent
            - towardAnchor * simd_dot(stableBodyTangent, towardAnchor)
        if simd_length_squared(bodyTangent) < 0.000_001 {
            let fallback = abs(towardAnchor.y) < 0.9
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(0, 0, 1)
            bodyTangent = simd_cross(fallback, towardAnchor)
        }
        bodyTangent = simd_normalize(bodyTangent)
        let sideAxis = simd_normalize(simd_cross(towardAnchor, bodyTangent))
        let forwardAxis = simd_normalize(simd_cross(sideAxis, towardAnchor))
        let alignment = simd_float4x4(columns: (
            SIMD4<Float>(sideAxis, 0),
            SIMD4<Float>(towardAnchor, 0),
            SIMD4<Float>(forwardAxis, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        let spin = simd_quatf(angle: snapshot.phase * 0.45, axis: SIMD3<Float>(0, 1, 0))
        let bodyFrame = simd_float4x4.translation(bobPosition)
            * alignment
            * simd_float4x4.rotation(spin)

        draw(
            mesh: resonator,
            modelMatrix: bodyFrame
                * .translation(SIMD3<Float>(0, -0.42, 0))
                * .scale(SIMD3<Float>(0.68, 0.84, 0.68)),
            color: bamboo,
            materialKind: 1,
            encoder: encoder,
            viewProjection: viewProjection
        )
        draw(
            mesh: cylinder,
            modelMatrix: bodyFrame
                * .translation(SIMD3<Float>(0, 0.005, 0))
                * .scale(SIMD3<Float>(0.73, 0.074, 0.73)),
            color: lacquer,
            materialKind: 3,
            encoder: encoder,
            viewProjection: viewProjection
        )
        draw(
            mesh: cylinder,
            modelMatrix: bodyFrame
                * .translation(SIMD3<Float>(0, 0.057, 0))
                * .scale(SIMD3<Float>(0.65, 0.030, 0.65)),
            color: SIMD4<Float>(0.91, 0.79, 0.52, 1),
            materialKind: 2,
            emissive: snapshot.state.activity * 0.34,
            encoder: encoder,
            viewProjection: viewProjection
        )
        draw(
            mesh: sphere,
            modelMatrix: bodyFrame
                * .translation(SIMD3<Float>(0, -0.18, 0.31))
                * .scale(SIMD3<Float>(0.28, 0.20, 0.18)),
            color: cutBamboo,
            materialKind: 1,
            encoder: encoder,
            viewProjection: viewProjection
        )

        for (wingIndex, sign) in [Float(-1), 1].enumerated() {
            let eyeTransform = bodyFrame
                * .translation(SIMD3<Float>(sign * 0.105, -0.16, 0.43))
                * .scale(SIMD3<Float>(repeating: 0.060))
            draw(mesh: sphere, modelMatrix: eyeTransform, color: ink, encoder: encoder, viewProjection: viewProjection)

            let flap = wingAngles[wingIndex]
            let wingRotation = simd_quatf(angle: sign * (0.28 + flap * 0.45), axis: SIMD3<Float>(0, 0, 1))
                * simd_quatf(angle: sign * 0.09, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: 0.10, axis: SIMD3<Float>(1, 0, 0))
            let wingTransform = bodyFrame
                * .translation(SIMD3<Float>(sign * 0.14, -0.43, 0.23))
                * .rotation(wingRotation)
                * .scale(SIMD3<Float>(0.50, 0.86, 0.34))
            draw(
                mesh: wing,
                modelMatrix: wingTransform,
                color: paleBamboo,
                materialKind: 5,
                encoder: encoder,
                viewProjection: viewProjection
            )
        }
    }

    private func drawRope(
        encoder: MTLRenderCommandEncoder,
        state: ToyPhysicsState,
        bobPosition: SIMD3<Float>,
        vertexBuffer: MTLBuffer,
        viewProjection: simd_float4x4
    ) {
        let pointCount = 25
        let sag = max(0, state.ropeLength - simd_length(state.position)) * 0.32
        ropePoints.removeAll(keepingCapacity: true)
        ropePoints.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let fraction = Float(index) / Float(pointCount - 1)
            var point = simd_mix(sceneAnchor, bobPosition, SIMD3<Float>(repeating: fraction))
            point.y -= sag * sin(.pi * fraction)
            ropePoints.append(point)
        }

        ropeVertices.removeAll(keepingCapacity: true)
        ropeVertices.reserveCapacity(pointCount * 2)
        for index in 0..<pointCount {
            let previous = ropePoints[max(index - 1, 0)]
            let next = ropePoints[min(index + 1, pointCount - 1)]
            let tangent = simd_normalize(next - previous)
            let viewDirection = simd_normalize(cameraEye - ropePoints[index])
            var side = simd_cross(tangent, viewDirection)
            if simd_length_squared(side) < 0.000_001 {
                side = SIMD3<Float>(1, 0, 0)
            } else {
                side = simd_normalize(side)
            }
            let normal = simd_normalize(simd_cross(side, tangent))
            let width: Float = 0.011
            ropeVertices.append(MetalVertex(position: ropePoints[index] - side * width, normal: normal))
            ropeVertices.append(MetalVertex(position: ropePoints[index] + side * width, normal: normal))
        }

        ropeVertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }

        var uniforms = DrawUniforms(
            viewProjectionMatrix: viewProjection,
            modelMatrix: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float4x4,
            baseColor: SIMD4<Float>(0.75, 0.66, 0.48, 0.90),
            materialParameters: SIMD4<Float>(4, 0, 0, 0)
        )
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ropeVertices.count)
        encoder.setCullMode(.back)
    }

    private func updateEffects(snapshot: RenderSnapshot, bobPosition: SIMD3<Float>) {
        let deltaTime = min(max(snapshot.elapsedTime - (lastEffectsTime ?? snapshot.elapsedTime), 0), 0.05)
        lastEffectsTime = snapshot.elapsedTime

        let ropeAxis = simd_normalize(sceneAnchor - bobPosition)
        let tangentialVelocity = snapshot.state.velocity
            - ropeAxis * simd_dot(snapshot.state.velocity, ropeAxis)
        let tangentMagnitude = simd_length(tangentialVelocity)
        let projectedStableTangent = stableBodyTangent
            - ropeAxis * simd_dot(stableBodyTangent, ropeAxis)
        if tangentMagnitude > 0.025 {
            let measuredTangent = tangentialVelocity / tangentMagnitude
            if simd_dot(measuredTangent, stableBodyTangent) < -0.2 {
                stableBodyTangent = measuredTangent
            } else {
                stableBodyTangent = simd_normalize(
                    stableBodyTangent * 0.82 + measuredTangent * 0.18
                )
            }
        } else if simd_length_squared(projectedStableTangent) > 0.000_001 {
            stableBodyTangent = simd_normalize(projectedStableTangent)
        }

        for wingIndex in 0..<2 {
            let sign: Float = wingIndex == 0 ? -1 : 1
            let target = 0.18
                + snapshot.state.activity
                    * sin(snapshot.elapsedTime * 46 + sign * 0.35) * 0.32
                + min(simd_length(snapshot.state.velocity) * 0.018, 0.28)
            let acceleration = (target - wingAngles[wingIndex]) * 82
                - wingVelocities[wingIndex] * 13
            wingVelocities[wingIndex] += acceleration * deltaTime
            wingAngles[wingIndex] += wingVelocities[wingIndex] * deltaTime
        }

        if snapshot.state.activity > 0.07,
           trail.last.map({ simd_distance($0, bobPosition) > 0.045 }) ?? true {
            trail.insert(bobPosition, at: 0)
            if trail.count > 34 {
                trail.removeLast(trail.count - 34)
            }
        } else if snapshot.state.activity < 0.04, !trail.isEmpty {
            trail.removeLast(min(2, trail.count))
        }

        if snapshot.state.activity > 0.16,
           snapshot.elapsedTime - lastRippleTime > 0.34 {
            ripples.append(Ripple(position: bobPosition, bornAt: snapshot.elapsedTime))
            lastRippleTime = snapshot.elapsedTime
        }
        ripples.removeAll { snapshot.elapsedTime - $0.bornAt > 0.9 }
    }

    private func drawEffects(
        encoder: MTLRenderCommandEncoder,
        time: Float,
        viewProjection: simd_float4x4
    ) {
        encoder.setDepthStencilState(translucentDepthState)

        for (index, position) in trail.enumerated() where index % 2 == 0 {
            let progress = Float(index) / Float(max(trail.count, 1))
            let scale = 0.064 * (1 - progress) + 0.014
            let alpha = (1 - progress) * 0.14
            let transform = simd_float4x4.translation(position)
                * .scale(SIMD3<Float>(repeating: scale))
            draw(
                mesh: sphere,
                modelMatrix: transform,
                color: SIMD4<Float>(0.97, 0.78, 0.43, alpha),
                emissive: 0.42,
                encoder: encoder,
                viewProjection: viewProjection
            )
        }

        for ripple in ripples {
            let age = time - ripple.bornAt
            let progress = min(max(age / 0.9, 0), 1)
            let transform = simd_float4x4.translation(ripple.position + SIMD3<Float>(0, 0, 0.05))
                * .scale(SIMD3<Float>(repeating: 0.25 + progress * 0.88))
            draw(
                mesh: torus,
                modelMatrix: transform,
                color: SIMD4<Float>(0.97, 0.76, 0.38, (1 - progress) * 0.24),
                emissive: 0.36,
                encoder: encoder,
                viewProjection: viewProjection
            )
        }

        encoder.setDepthStencilState(depthState)
    }

    private func drawSphere(
        at position: SIMD3<Float>,
        scale: Float,
        color: SIMD4<Float>,
        materialKind: Float = 0,
        encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4
    ) {
        draw(
            mesh: sphere,
            modelMatrix: .translation(position) * .scale(SIMD3<Float>(repeating: scale)),
            color: color,
            materialKind: materialKind,
            encoder: encoder,
            viewProjection: viewProjection
        )
    }

    private func draw(
        mesh: MetalMesh,
        modelMatrix: simd_float4x4,
        color: SIMD4<Float>,
        materialKind: Float = 0,
        emissive: Float = 0,
        encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4
    ) {
        var uniforms = DrawUniforms(
            viewProjectionMatrix: viewProjection,
            modelMatrix: modelMatrix,
            normalMatrix: simd_transpose(simd_inverse(modelMatrix)),
            baseColor: color,
            materialParameters: SIMD4<Float>(materialKind, emissive, 0, 0)
        )
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: .uint16,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0
        )
    }
}
