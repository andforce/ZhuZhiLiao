@preconcurrency import MetalKit
import QuartzCore
import simd
import UIKit

struct EarthCameraAngles: Equatable, Sendable {
    var yaw: Float
    var pitch: Float
}

enum EarthCameraFocus {
    static let initialAngles = EarthCameraAngles(yaw: -1.35, pitch: 0.18)

    static func preferredNode(
        in nodes: [EarthNode],
        from angles: EarthCameraAngles
    ) -> EarthNode? {
        if let myNode = nodes.first(where: \.highlightsMe) {
            return myNode
        }

        return nodes.max { lhs, rhs in
            frontDepth(of: lhs, at: angles) < frontDepth(of: rhs, at: angles)
        }
    }

    static func centeredAngles(for node: EarthNode) -> EarthCameraAngles {
        let point = EarthBoundaryLoader.spherePoint(
            latitude: node.latitude,
            longitude: node.longitude
        )

        var pitch = atan2(point.y, point.z)
        if pitch > .pi / 2 {
            pitch -= .pi
        } else if pitch < -.pi / 2 {
            pitch += .pi
        }

        let pitchedPoint = simd_float4x4.rotation(
            angle: pitch,
            axis: SIMD3<Float>(1, 0, 0)
        ) * SIMD4<Float>(point, 1)
        let yaw = atan2(-pitchedPoint.x, pitchedPoint.z)
        return EarthCameraAngles(yaw: yaw, pitch: pitch)
    }

    static func frontDepth(of node: EarthNode, at angles: EarthCameraAngles) -> Float {
        let point = EarthBoundaryLoader.spherePoint(
            latitude: node.latitude,
            longitude: node.longitude
        )
        let globe = simd_float4x4.rotation(
            angle: angles.yaw,
            axis: SIMD3<Float>(0, 1, 0)
        ) * simd_float4x4.rotation(
            angle: angles.pitch,
            axis: SIMD3<Float>(1, 0, 0)
        )
        return (globe * SIMD4<Float>(point, 1)).z
    }
}

private struct EarthDrawUniforms {
    var viewProjectionMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var normalMatrix: simd_float4x4
    var baseColor: SIMD4<Float>
    var materialParameters: SIMD4<Float>
    var coolLightColor: SIMD4<Float>
    var warmLightColor: SIMD4<Float>
}

@MainActor
final class EarthMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let translucentDepthState: MTLDepthStencilState
    private let sphere: MetalMesh
    private let torus: MetalMesh
    private let countryBuffer: MTLBuffer?
    private let countryVertexCount: Int
    private let regionBuffer: MTLBuffer?
    private let regionVertexCount: Int
    private let sampleCount: Int

    private weak var view: MTKView?
    private var nodes: [EarthNode] = []
    private var renderedNodes: [EarthNode] = []
    private var serverClockOffsetMilliseconds: Int64 = 0
    private var localWahAt: Date?
    private var reduceMotion = false
    private var isAutoRotationEnabled = true
    private var yaw = EarthCameraFocus.initialAngles.yaw
    private var pitch = EarthCameraFocus.initialAngles.pitch
    private var cameraDistance: Float = 3.25
    private var lastFrameTime = CACurrentMediaTime()
    private var lastInteractionTime = CACurrentMediaTime()
    private var lastReportedDetail = -1
    private var viewportSize = SIMD2<Float>(1, 1)
    private var hasAppliedInitialFocus = false
    private var focusAnimation: FocusAnimation?
    private var onDetailChange: (Int) -> Void
    private var onSelect: (EarthNode?) -> Void

    private struct FocusAnimation {
        let start: EarthCameraAngles
        let target: EarthCameraAngles
        let startTime: CFTimeInterval
    }

    init(
        onDetailChange: @escaping (Int) -> Void,
        onSelect: @escaping (EarthNode?) -> Void
    ) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            fatalError("当前设备不支持 Metal")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.onDetailChange = onDetailChange
        self.onSelect = onSelect
        #if targetEnvironment(simulator)
        sampleCount = 1
        #else
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        #endif

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "哇声地球"
        descriptor.vertexFunction = library.makeFunction(name: "litVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "litFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = sampleCount
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("地球 Metal 管线创建失败：\(error.localizedDescription)")
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!
        let translucentDescriptor = MTLDepthStencilDescriptor()
        translucentDescriptor.depthCompareFunction = .lessEqual
        translucentDescriptor.isDepthWriteEnabled = false
        translucentDepthState = device.makeDepthStencilState(descriptor: translucentDescriptor)!

        sphere = MeshGenerator.sphere(device: device, latitudeSegments: 28, longitudeSegments: 40)
        torus = MeshGenerator.torus(device: device, majorSegments: 48, minorSegments: 6)
        let countries = EarthBoundaryLoader.vertices(
            resource: "ne_110m_admin_0_countries",
            radius: 1.006
        )
        countryVertexCount = countries.count
        countryBuffer = countries.isEmpty ? nil : device.makeBuffer(
            bytes: countries,
            length: MemoryLayout<MetalVertex>.stride * countries.count,
            options: .storageModeShared
        )
        let regions = EarthBoundaryLoader.vertices(
            resource: "ne_110m_admin_1_states_provinces",
            radius: 1.009
        )
        regionVertexCount = regions.count
        regionBuffer = regions.isEmpty ? nil : device.makeBuffer(
            bytes: regions,
            length: MemoryLayout<MetalVertex>.stride * regions.count,
            options: .storageModeShared
        )
        super.init()
    }

    func configure(_ view: MTKView) {
        self.view = view
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = sampleCount
        view.clearColor = MTLClearColor(red: 0.012, green: 0.022, blue: 0.055, alpha: 1)
        view.preferredFramesPerSecond = min(UIScreen.main.maximumFramesPerSecond, 60)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.isMultipleTouchEnabled = true

        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)))
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    func update(
        nodes: [EarthNode],
        serverClockOffsetMilliseconds: Int64,
        localWahAt: Date?,
        reduceMotion: Bool,
        isAutoRotationEnabled: Bool,
        onDetailChange: @escaping (Int) -> Void,
        onSelect: @escaping (EarthNode?) -> Void
    ) {
        self.nodes = nodes
        self.serverClockOffsetMilliseconds = serverClockOffsetMilliseconds
        self.localWahAt = localWahAt
        self.reduceMotion = reduceMotion
        self.isAutoRotationEnabled = isAutoRotationEnabled
        self.onDetailChange = onDetailChange
        self.onSelect = onSelect
        applyInitialFocusIfNeeded(to: nodes)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        let now = CACurrentMediaTime()
        let delta = min(max(now - lastFrameTime, 0), 0.05)
        lastFrameTime = now
        updateFocusAnimation(at: now)
        if focusAnimation == nil,
           isAutoRotationEnabled,
           !reduceMotion,
           now - lastInteractionTime > 3 {
            yaw += Float(delta) * 0.055
        }

        let matrices = sceneMatrices()
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        drawMesh(
            sphere,
            modelMatrix: matrices.globe * .scale(SIMD3<Float>(repeating: 2)),
            color: SIMD4<Float>(0.025, 0.07, 0.11, 0.98),
            emissive: 0.08,
            encoder: encoder,
            viewProjection: matrices.viewProjection
        )

        encoder.setCullMode(.none)
        drawLines(
            buffer: countryBuffer,
            count: countryVertexCount,
            color: SIMD4<Float>(0.48, 0.82, 0.82, 0.78),
            modelMatrix: matrices.globe,
            encoder: encoder,
            viewProjection: matrices.viewProjection
        )
        if cameraDistance < 3.0 {
            let alpha = min(max((3.0 - cameraDistance) / 0.65, 0), 1) * 0.42
            drawLines(
                buffer: regionBuffer,
                count: regionVertexCount,
                color: SIMD4<Float>(0.36, 0.67, 0.70, alpha),
                modelMatrix: matrices.globe,
                encoder: encoder,
                viewProjection: matrices.viewProjection
            )
        }

        renderedNodes = screenClusteredNodes(matrices: matrices)
        drawNodes(renderedNodes, encoder: encoder, matrices: matrices)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        reportDetailIfNeeded()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        focusAnimation = nil
        let translation = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        yaw += Float(translation.x) * 0.006
        pitch = min(
            max(pitch + Float(translation.y) * 0.005, -.pi / 2),
            .pi / 2
        )
        lastInteractionTime = CACurrentMediaTime()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.scale.isFinite, gesture.scale > 0 else { return }
        focusAnimation = nil
        cameraDistance = min(max(cameraDistance / Float(gesture.scale), 1.72), 4.25)
        gesture.scale = 1
        lastInteractionTime = CACurrentMediaTime()
        reportDetailIfNeeded()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        let location = gesture.location(in: view)
        let matrices = sceneMatrices()
        var best: (node: EarthNode, distance: CGFloat)?
        for node in renderedNodes {
            let point = EarthBoundaryLoader.spherePoint(
                latitude: node.latitude,
                longitude: node.longitude,
                radius: 1.04
            )
            let world = matrices.globe * SIMD4<Float>(point, 1)
            guard world.z > 0 else { continue }
            let clip = matrices.viewProjection * world
            guard clip.w > 0 else { continue }
            let normalized = SIMD2<Float>(clip.x, clip.y) / clip.w
            let screen = CGPoint(
                x: CGFloat((normalized.x * 0.5 + 0.5) * Float(view.bounds.width)),
                y: CGFloat((0.5 - normalized.y * 0.5) * Float(view.bounds.height))
            )
            let distance = hypot(screen.x - location.x, screen.y - location.y)
            if distance < 30, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (node, distance)
            }
        }
        onSelect(best?.node)
    }

    private func applyInitialFocusIfNeeded(to nodes: [EarthNode]) {
        guard !hasAppliedInitialFocus,
              let node = EarthCameraFocus.preferredNode(
                in: nodes,
                from: EarthCameraAngles(yaw: yaw, pitch: pitch)
              ) else {
            return
        }

        hasAppliedInitialFocus = true
        let target = EarthCameraFocus.centeredAngles(for: node)
        lastInteractionTime = CACurrentMediaTime()
        if reduceMotion {
            yaw = target.yaw
            pitch = target.pitch
        } else {
            focusAnimation = FocusAnimation(
                start: EarthCameraAngles(yaw: yaw, pitch: pitch),
                target: target,
                startTime: lastInteractionTime
            )
        }
    }

    private func updateFocusAnimation(at now: CFTimeInterval) {
        guard let animation = focusAnimation else { return }
        if reduceMotion {
            yaw = animation.target.yaw
            pitch = animation.target.pitch
            focusAnimation = nil
            return
        }

        let progress = min(max(Float((now - animation.startTime) / 0.65), 0), 1)
        let easedProgress = 1 - pow(1 - progress, 3)
        let yawDelta = atan2(
            sin(animation.target.yaw - animation.start.yaw),
            cos(animation.target.yaw - animation.start.yaw)
        )
        yaw = animation.start.yaw + yawDelta * easedProgress
        pitch = animation.start.pitch
            + (animation.target.pitch - animation.start.pitch) * easedProgress

        if progress >= 1 {
            yaw = animation.target.yaw
            pitch = animation.target.pitch
            focusAnimation = nil
            lastInteractionTime = now
        }
    }

    private func drawNodes(
        _ nodes: [EarthNode],
        encoder: MTLRenderCommandEncoder,
        matrices: (viewProjection: simd_float4x4, globe: simd_float4x4)
    ) {
        let localNow = Int64(Date().timeIntervalSince1970 * 1_000)
        let serverNow = localNow + serverClockOffsetMilliseconds
        let localActiveUntil = localWahAt.map {
            Int64($0.timeIntervalSince1970 * 1_000) + EarthActivity.durationMilliseconds
        }
        for node in nodes {
            let normal = EarthBoundaryLoader.spherePoint(
                latitude: node.latitude,
                longitude: node.longitude
            )
            let position = normal * 1.035
            let scoreScale = min(
                max(log10(Float(node.displayedWahs + 1)) * 0.010 + 0.026, 0.026),
                0.075
            )
            let userScale = node.kind == .cluster
                ? min(scoreScale + log10(Float(node.displayedUsers + 1)) * 0.012, 0.09)
                : scoreScale
            let visualScale = userScale * 0.1
            let color = node.highlightsMe
                ? SIMD4<Float>(0.98, 0.72, 0.28, 1)
                : SIMD4<Float>(0.36, 0.93, 0.86, 0.94)
            drawMesh(
                sphere,
                modelMatrix: matrices.globe
                    * .translation(position)
                    * .scale(SIMD3<Float>(repeating: visualScale * 2)),
                color: color,
                emissive: 0.55,
                encoder: encoder,
                viewProjection: matrices.viewProjection
            )

            var activeUntil = node.activeUntil
            if node.highlightsMe, let localActiveUntil {
                activeUntil = max(activeUntil ?? 0, localActiveUntil + serverClockOffsetMilliseconds)
            }
            guard let activeUntil, activeUntil > serverNow else { continue }
            encoder.setDepthStencilState(translucentDepthState)
            let alignment = simd_float4x4.rotation(
                simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal)
            )
            let phases: [Float] = reduceMotion ? [0.18] : [0, 0.33, 0.66]
            for offset in phases {
                let phase: Float
                if reduceMotion {
                    phase = offset
                } else {
                    let cycle = Float((serverNow % 2_800 + 2_800) % 2_800) / 2_800
                    phase = (cycle + offset).truncatingRemainder(dividingBy: 1)
                }
                let radius = (0.045 + phase * 0.18) * 0.1
                let alpha = reduceMotion ? 0.42 : (1 - phase) * 0.48
                drawMesh(
                    torus,
                    modelMatrix: matrices.globe
                        * .translation(position + normal * 0.008)
                        * alignment
                        * .scale(SIMD3<Float>(repeating: radius * 2)),
                    color: SIMD4<Float>(color.x, color.y, color.z, alpha),
                    emissive: 0.8,
                    encoder: encoder,
                    viewProjection: matrices.viewProjection
                )
            }
            encoder.setDepthStencilState(depthState)
        }
    }

    private func screenClusteredNodes(
        matrices: (viewProjection: simd_float4x4, globe: simd_float4x4)
    ) -> [EarthNode] {
        guard nodes.count > 1 else { return nodes }
        let cellSize: Float = 20
        var fixed: [EarthNode] = []
        var buckets: [SIMD2<Int32>: [EarthNode]] = [:]
        for node in nodes {
            // The user's own point remains individually visible and server-side
            // aggregate nodes retain their already-computed population semantics.
            guard node.kind == .player, !node.highlightsMe,
                  let screen = projectedPoint(for: node, matrices: matrices) else {
                fixed.append(node)
                continue
            }
            let key = SIMD2<Int32>(
                Int32(floor(screen.x / cellSize)),
                Int32(floor(screen.y / cellSize))
            )
            buckets[key, default: []].append(node)
        }

        for (key, bucket) in buckets {
            guard bucket.count > 1 else {
                fixed.append(contentsOf: bucket)
                continue
            }
            var vector = SIMD3<Double>.zero
            var totalWahs = 0
            var activeCount = 0
            var activeUntil: Int64?
            for node in bucket {
                let point = EarthBoundaryLoader.spherePoint(
                    latitude: node.latitude,
                    longitude: node.longitude
                )
                vector += SIMD3<Double>(Double(point.x), Double(point.y), Double(point.z))
                totalWahs += node.displayedWahs
                if let deadline = node.activeUntil {
                    activeCount += 1
                    activeUntil = max(activeUntil ?? 0, deadline)
                }
            }
            let normalized = simd_normalize(vector)
            let latitude = asin(normalized.y) * 180 / .pi
            let longitude = atan2(normalized.z, -normalized.x) * 180 / .pi
            fixed.append(EarthNode(
                kind: .cluster,
                id: "screen:\(key.x):\(key.y):\(bucket.count)",
                code: nil,
                score: nil,
                latitude: latitude,
                longitude: longitude,
                userCount: bucket.reduce(0) { $0 + $1.displayedUsers },
                totalWahs: totalWahs,
                activeCount: activeCount,
                activeUntil: activeUntil,
                isMe: false,
                containsMe: false
            ))
        }
        return fixed
    }

    private func projectedPoint(
        for node: EarthNode,
        matrices: (viewProjection: simd_float4x4, globe: simd_float4x4)
    ) -> SIMD2<Float>? {
        let point = EarthBoundaryLoader.spherePoint(
            latitude: node.latitude,
            longitude: node.longitude,
            radius: 1.04
        )
        let world = matrices.globe * SIMD4<Float>(point, 1)
        guard world.z > 0 else { return nil }
        let clip = matrices.viewProjection * world
        guard clip.w > 0 else { return nil }
        let normalized = SIMD2<Float>(clip.x, clip.y) / clip.w
        let width = Float(view?.bounds.width ?? CGFloat(viewportSize.x))
        let height = Float(view?.bounds.height ?? CGFloat(viewportSize.y))
        return SIMD2<Float>(
            (normalized.x * 0.5 + 0.5) * width,
            (0.5 - normalized.y * 0.5) * height
        )
    }

    private func sceneMatrices() -> (viewProjection: simd_float4x4, globe: simd_float4x4) {
        let aspect = max(viewportSize.x / max(viewportSize.y, 1), 0.1)
        let projection = simd_float4x4.perspective(
            fieldOfViewY: 0.72,
            aspect: aspect,
            near: 0.1,
            far: 20
        )
        let viewMatrix = simd_float4x4.lookAt(
            eye: SIMD3<Float>(0, 0, cameraDistance),
            target: .zero,
            up: SIMD3<Float>(0, 1, 0)
        )
        let globe = simd_float4x4.rotation(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * .rotation(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        return (projection * viewMatrix, globe)
    }

    private func drawLines(
        buffer: MTLBuffer?,
        count: Int,
        color: SIMD4<Float>,
        modelMatrix: simd_float4x4,
        encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4
    ) {
        guard let buffer, count > 0, color.w > 0 else { return }
        var uniforms = uniforms(
            modelMatrix: modelMatrix,
            color: color,
            emissive: 0.35,
            viewProjection: viewProjection
        )
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EarthDrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EarthDrawUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: count)
    }

    private func drawMesh(
        _ mesh: MetalMesh,
        modelMatrix: simd_float4x4,
        color: SIMD4<Float>,
        emissive: Float,
        encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4
    ) {
        var uniforms = uniforms(
            modelMatrix: modelMatrix,
            color: color,
            emissive: emissive,
            viewProjection: viewProjection
        )
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EarthDrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EarthDrawUniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: .uint16,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0
        )
    }

    private func uniforms(
        modelMatrix: simd_float4x4,
        color: SIMD4<Float>,
        emissive: Float,
        viewProjection: simd_float4x4
    ) -> EarthDrawUniforms {
        EarthDrawUniforms(
            viewProjectionMatrix: viewProjection,
            modelMatrix: modelMatrix,
            normalMatrix: simd_transpose(simd_inverse(modelMatrix)),
            baseColor: color,
            materialParameters: SIMD4<Float>(0, emissive, 0, 0),
            coolLightColor: SIMD4<Float>(0.48, 0.82, 0.92, 1),
            warmLightColor: SIMD4<Float>(0.92, 0.62, 0.28, 1)
        )
    }

    private func reportDetailIfNeeded() {
        let detail: Int
        switch cameraDistance {
        case 3.75...: detail = 0
        case 3.35...: detail = 1
        case 2.70...: detail = 2
        case 2.10...: detail = 3
        default: detail = 4
        }
        guard detail != lastReportedDetail else { return }
        lastReportedDetail = detail
        onDetailChange(detail)
    }
}
