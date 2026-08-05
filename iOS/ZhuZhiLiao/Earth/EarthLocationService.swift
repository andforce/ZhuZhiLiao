import CoreLocation
import Foundation

enum EarthLocationError: LocalizedError {
    case denied
    case unavailable
    case invalidLocation

    var errorDescription: String? {
        switch self {
        case .denied: "没有位置权限，你仍然可以浏览哇声地球"
        case .unavailable: "当前无法获取位置，请稍后再试"
        case .invalidLocation: "获取到的位置无效，请稍后再试"
        }
    }
}

enum EarthLocationGrid {
    static let cellSizeKilometers = 20.0
    static let latitudeStep = cellSizeKilometers / 111.32

    static func cellID(latitude: Double, longitude: Double) -> String? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        let latitudeBandCount = Int(ceil(180 / latitudeStep))
        let latitudeIndex = min(
            max(Int(floor((latitude + 90) / latitudeStep)), 0),
            latitudeBandCount - 1
        )
        let centerLatitude = min(
            90 - latitudeStep / 2,
            -90 + (Double(latitudeIndex) + 0.5) * latitudeStep
        )
        let circumference = 40_075 * max(cos(centerLatitude * .pi / 180), 0)
        let longitudeBandCount = max(1, Int((circumference / cellSizeKilometers).rounded()))
        let normalizedLongitude = longitude == 180 ? -180 : longitude
        let longitudeIndex = min(
            max(Int(floor((normalizedLongitude + 180) / 360 * Double(longitudeBandCount))), 0),
            longitudeBandCount - 1
        )
        return "v1:\(latitudeIndex):\(longitudeIndex)"
    }
}

@MainActor
final class EarthLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, any Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var canRefreshWithoutPrompt: Bool {
        manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    func requestOneLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw EarthLocationError.unavailable
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            throw EarthLocationError.denied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw EarthLocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation?.resume(throwing: CancellationError())
            self.continuation = continuation
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            finish(.failure(EarthLocationError.denied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(EarthLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.coordinate.latitude) <= 90,
              abs(location.coordinate.longitude) <= 180 else {
            finish(.failure(EarthLocationError.invalidLocation))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
