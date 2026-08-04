import Foundation
import simd

enum EarthBoundaryLoader {
    static func vertices(resource: String, radius: Float) -> [MetalVertex] {
        guard let url = resourceURL(resource),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            return []
        }

        var result: [MetalVertex] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }
            switch type {
            case "Polygon":
                appendPolygon(geometry["coordinates"], radius: radius, to: &result)
            case "MultiPolygon":
                guard let polygons = geometry["coordinates"] as? [Any] else { continue }
                for polygon in polygons {
                    appendPolygon(polygon, radius: radius, to: &result)
                }
            default:
                continue
            }
        }
        return result
    }

    private static func resourceURL(_ resource: String) -> URL? {
        Bundle.main.url(
            forResource: resource,
            withExtension: "geojson",
            subdirectory: "Earth/Resources"
        ) ?? Bundle.main.url(forResource: resource, withExtension: "geojson")
    }

    private static func appendPolygon(
        _ value: Any?,
        radius: Float,
        to vertices: inout [MetalVertex]
    ) {
        guard let rings = value as? [Any] else { return }
        for ringValue in rings {
            guard let rawPoints = ringValue as? [[Any]], rawPoints.count > 1 else { continue }
            var previous: SIMD3<Float>?
            for rawPoint in rawPoints {
                guard rawPoint.count >= 2,
                      let longitude = number(rawPoint[0]),
                      let latitude = number(rawPoint[1]) else { continue }
                let point = spherePoint(
                    latitude: latitude,
                    longitude: longitude,
                    radius: radius
                )
                if let previous {
                    vertices.append(MetalVertex(position: previous, normal: simd_normalize(previous)))
                    vertices.append(MetalVertex(position: point, normal: simd_normalize(point)))
                }
                previous = point
            }
        }
    }

    private static func number(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func spherePoint(
        latitude: Double,
        longitude: Double,
        radius: Float = 1
    ) -> SIMD3<Float> {
        let latitude = Float(latitude * .pi / 180)
        let longitude = Float(longitude * .pi / 180)
        let latitudeRadius = cos(latitude)
        return SIMD3<Float>(
            -latitudeRadius * cos(longitude),
            sin(latitude),
            latitudeRadius * sin(longitude)
        ) * radius
    }
}
