import XCTest
import simd
@testable import ZhuZhiLiao

final class OrbitCounterTests: XCTestCase {
    func testContinuousOrbitCompletesOneWah() {
        var counter = OrbitCounter()
        var completed = 0

        for _ in 0..<4 {
            completed += counter.update(
                angleDelta: .pi / 2,
                axis: SIMD3<Float>(0, 0, 1),
                isQualified: true
            )
        }

        XCTAssertEqual(completed, 1)
    }

    func testDirectionReversalBreaksOrbitContinuity() {
        var counter = OrbitCounter()
        var completed = 0

        for _ in 0..<2 {
            completed += counter.update(
                angleDelta: .pi / 2,
                axis: SIMD3<Float>(0, 0, 1),
                isQualified: true
            )
        }
        for _ in 0..<2 {
            completed += counter.update(
                angleDelta: .pi / 2,
                axis: SIMD3<Float>(0, 0, -1),
                isQualified: true
            )
        }

        XCTAssertEqual(completed, 0)
    }

    func testUnqualifiedJitterResetsPartialOrbit() {
        var counter = OrbitCounter()
        _ = counter.update(
            angleDelta: .pi,
            axis: SIMD3<Float>(0, 0, 1),
            isQualified: true
        )
        _ = counter.update(
            angleDelta: 0,
            axis: SIMD3<Float>(0, 0, 1),
            isQualified: false
        )

        let completed = counter.update(
            angleDelta: .pi,
            axis: SIMD3<Float>(0, 0, 1),
            isQualified: true
        )

        XCTAssertEqual(completed, 0)
    }
}
