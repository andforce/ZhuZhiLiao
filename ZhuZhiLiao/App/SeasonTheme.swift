import Observation
import SwiftUI
import simd

enum SeasonTheme: String, CaseIterable, Identifiable, Sendable {
    case spring
    case summer
    case autumn
    case winter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: "春"
        case .summer: "夏"
        case .autumn: "秋"
        case .winter: "冬"
        }
    }

    var fullName: String {
        switch self {
        case .spring: "春日新芽"
        case .summer: "夏夜流萤"
        case .autumn: "秋山照月"
        case .winter: "冬雪静枝"
        }
    }

    var tagline: String {
        switch self {
        case .spring: "桃影入青岚"
        case .summer: "竹风送流萤"
        case .autumn: "金叶映山月"
        case .winter: "疏枝落新雪"
        }
    }

    var symbolName: String {
        switch self {
        case .spring: "camera.macro"
        case .summer: "sparkles"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        }
    }

    var shaderIndex: Float {
        switch self {
        case .spring: 0
        case .summer: 1
        case .autumn: 2
        case .winter: 3
        }
    }

    var colors: SeasonColors {
        switch self {
        case .spring:
            SeasonColors(
                skyTop: Color(red: 0.025, green: 0.105, blue: 0.100),
                skyBottom: Color(red: 0.135, green: 0.285, blue: 0.235),
                panel: Color(red: 0.025, green: 0.115, blue: 0.105),
                accent: Color(red: 1.000, green: 0.455, blue: 0.570),
                secondaryAccent: Color(red: 0.455, green: 0.745, blue: 0.480),
                highlight: Color(red: 0.945, green: 0.850, blue: 0.650)
            )
        case .summer:
            SeasonColors(
                skyTop: Color(red: 0.008, green: 0.090, blue: 0.140),
                skyBottom: Color(red: 0.030, green: 0.275, blue: 0.365),
                panel: Color(red: 0.015, green: 0.105, blue: 0.150),
                accent: Color(red: 0.220, green: 0.850, blue: 0.755),
                secondaryAccent: Color(red: 0.250, green: 0.610, blue: 0.720),
                highlight: Color(red: 1.000, green: 0.820, blue: 0.390)
            )
        case .autumn:
            SeasonColors(
                skyTop: Color(red: 0.115, green: 0.035, blue: 0.055),
                skyBottom: Color(red: 0.410, green: 0.155, blue: 0.085),
                panel: Color(red: 0.150, green: 0.055, blue: 0.045),
                accent: Color(red: 0.940, green: 0.450, blue: 0.205),
                secondaryAccent: Color(red: 0.705, green: 0.185, blue: 0.105),
                highlight: Color(red: 0.965, green: 0.795, blue: 0.460)
            )
        case .winter:
            SeasonColors(
                skyTop: Color(red: 0.014, green: 0.035, blue: 0.095),
                skyBottom: Color(red: 0.190, green: 0.245, blue: 0.365),
                panel: Color(red: 0.035, green: 0.060, blue: 0.135),
                accent: Color(red: 0.385, green: 0.730, blue: 0.925),
                secondaryAccent: Color(red: 0.295, green: 0.425, blue: 0.680),
                highlight: Color(red: 0.920, green: 0.855, blue: 0.675)
            )
        }
    }

    var metalPalette: MetalSeasonPalette {
        switch self {
        case .spring:
            MetalSeasonPalette(
                skyTop: SIMD4<Float>(0.018, 0.075, 0.070, 1),
                skyMiddle: SIMD4<Float>(0.055, 0.175, 0.150, 1),
                skyBottom: SIMD4<Float>(0.155, 0.320, 0.250, 1),
                atmosphere: SIMD4<Float>(0.400, 0.650, 0.470, 1),
                seasonalAccent: SIMD4<Float>(1.000, 0.390, 0.520, 1),
                silhouette: SIMD4<Float>(0.010, 0.045, 0.035, 1),
                bamboo: SIMD4<Float>(0.56, 0.46, 0.18, 1),
                cutBamboo: SIMD4<Float>(0.88, 0.73, 0.41, 1),
                paleBamboo: SIMD4<Float>(0.88, 0.76, 0.48, 0.97),
                lacquer: SIMD4<Float>(0.67, 0.10, 0.13, 1),
                cord: SIMD4<Float>(0.84, 0.24, 0.26, 1),
                rope: SIMD4<Float>(0.82, 0.72, 0.50, 0.90),
                effect: SIMD4<Float>(1.00, 0.48, 0.58, 1),
                coolLight: SIMD4<Float>(0.64, 0.88, 0.76, 1),
                warmLight: SIMD4<Float>(1.00, 0.68, 0.54, 1)
            )
        case .summer:
            MetalSeasonPalette(
                skyTop: SIMD4<Float>(0.004, 0.055, 0.095, 1),
                skyMiddle: SIMD4<Float>(0.012, 0.145, 0.205, 1),
                skyBottom: SIMD4<Float>(0.035, 0.300, 0.380, 1),
                atmosphere: SIMD4<Float>(0.100, 0.630, 0.610, 1),
                seasonalAccent: SIMD4<Float>(1.000, 0.810, 0.310, 1),
                silhouette: SIMD4<Float>(0.006, 0.045, 0.060, 1),
                bamboo: SIMD4<Float>(0.58, 0.44, 0.17, 1),
                cutBamboo: SIMD4<Float>(0.85, 0.74, 0.39, 1),
                paleBamboo: SIMD4<Float>(0.86, 0.73, 0.43, 0.97),
                lacquer: SIMD4<Float>(0.70, 0.07, 0.08, 1),
                cord: SIMD4<Float>(0.80, 0.15, 0.15, 1),
                rope: SIMD4<Float>(0.70, 0.79, 0.58, 0.90),
                effect: SIMD4<Float>(0.23, 0.92, 0.76, 1),
                coolLight: SIMD4<Float>(0.35, 0.80, 0.88, 1),
                warmLight: SIMD4<Float>(1.00, 0.84, 0.42, 1)
            )
        case .autumn:
            MetalSeasonPalette(
                skyTop: SIMD4<Float>(0.075, 0.018, 0.030, 1),
                skyMiddle: SIMD4<Float>(0.245, 0.070, 0.045, 1),
                skyBottom: SIMD4<Float>(0.480, 0.205, 0.080, 1),
                atmosphere: SIMD4<Float>(0.860, 0.390, 0.120, 1),
                seasonalAccent: SIMD4<Float>(1.000, 0.690, 0.270, 1),
                silhouette: SIMD4<Float>(0.075, 0.018, 0.020, 1),
                bamboo: SIMD4<Float>(0.62, 0.38, 0.11, 1),
                cutBamboo: SIMD4<Float>(0.91, 0.65, 0.27, 1),
                paleBamboo: SIMD4<Float>(0.88, 0.67, 0.34, 0.97),
                lacquer: SIMD4<Float>(0.62, 0.075, 0.025, 1),
                cord: SIMD4<Float>(0.78, 0.18, 0.055, 1),
                rope: SIMD4<Float>(0.84, 0.64, 0.37, 0.90),
                effect: SIMD4<Float>(1.00, 0.59, 0.22, 1),
                coolLight: SIMD4<Float>(0.87, 0.63, 0.42, 1),
                warmLight: SIMD4<Float>(1.00, 0.52, 0.18, 1)
            )
        case .winter:
            MetalSeasonPalette(
                skyTop: SIMD4<Float>(0.010, 0.022, 0.062, 1),
                skyMiddle: SIMD4<Float>(0.030, 0.060, 0.130, 1),
                skyBottom: SIMD4<Float>(0.180, 0.220, 0.335, 1),
                atmosphere: SIMD4<Float>(0.300, 0.455, 0.690, 1),
                seasonalAccent: SIMD4<Float>(0.845, 0.920, 1.000, 1),
                silhouette: SIMD4<Float>(0.006, 0.012, 0.034, 1),
                bamboo: SIMD4<Float>(0.58, 0.43, 0.19, 1),
                cutBamboo: SIMD4<Float>(0.84, 0.70, 0.41, 1),
                paleBamboo: SIMD4<Float>(0.84, 0.74, 0.53, 0.97),
                lacquer: SIMD4<Float>(0.68, 0.08, 0.10, 1),
                cord: SIMD4<Float>(0.76, 0.16, 0.18, 1),
                rope: SIMD4<Float>(0.75, 0.73, 0.62, 0.90),
                effect: SIMD4<Float>(0.48, 0.80, 1.00, 1),
                coolLight: SIMD4<Float>(0.54, 0.70, 1.00, 1),
                warmLight: SIMD4<Float>(0.94, 0.82, 0.62, 1)
            )
        }
    }

    static func defaultTheme(for date: Date, calendar: Calendar = .current) -> SeasonTheme {
        theme(forMonth: calendar.component(.month, from: date))
    }

    static func theme(forMonth month: Int) -> SeasonTheme {
        switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

struct SeasonColors: Sendable {
    let skyTop: Color
    let skyBottom: Color
    let panel: Color
    let accent: Color
    let secondaryAccent: Color
    let highlight: Color
}

struct MetalSeasonPalette: Sendable {
    var skyTop: SIMD4<Float>
    var skyMiddle: SIMD4<Float>
    var skyBottom: SIMD4<Float>
    var atmosphere: SIMD4<Float>
    var seasonalAccent: SIMD4<Float>
    var silhouette: SIMD4<Float>
    var bamboo: SIMD4<Float>
    var cutBamboo: SIMD4<Float>
    var paleBamboo: SIMD4<Float>
    var lacquer: SIMD4<Float>
    var cord: SIMD4<Float>
    var rope: SIMD4<Float>
    var effect: SIMD4<Float>
    var coolLight: SIMD4<Float>
    var warmLight: SIMD4<Float>

    static func mix(
        from: MetalSeasonPalette,
        to: MetalSeasonPalette,
        progress: Float
    ) -> MetalSeasonPalette {
        let amount = min(max(progress, 0), 1)
        func blend(_ first: SIMD4<Float>, _ second: SIMD4<Float>) -> SIMD4<Float> {
            simd_mix(first, second, SIMD4<Float>(repeating: amount))
        }

        return MetalSeasonPalette(
            skyTop: blend(from.skyTop, to.skyTop),
            skyMiddle: blend(from.skyMiddle, to.skyMiddle),
            skyBottom: blend(from.skyBottom, to.skyBottom),
            atmosphere: blend(from.atmosphere, to.atmosphere),
            seasonalAccent: blend(from.seasonalAccent, to.seasonalAccent),
            silhouette: blend(from.silhouette, to.silhouette),
            bamboo: blend(from.bamboo, to.bamboo),
            cutBamboo: blend(from.cutBamboo, to.cutBamboo),
            paleBamboo: blend(from.paleBamboo, to.paleBamboo),
            lacquer: blend(from.lacquer, to.lacquer),
            cord: blend(from.cord, to.cord),
            rope: blend(from.rope, to.rope),
            effect: blend(from.effect, to.effect),
            coolLight: blend(from.coolLight, to.coolLight),
            warmLight: blend(from.warmLight, to.warmLight)
        )
    }
}

@MainActor
@Observable
final class SeasonThemeStore {
    static let preferenceKey = "zzl_selected_season"

    private(set) var selectedTheme: SeasonTheme
    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        date: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Self.preferenceKey),
           let storedTheme = SeasonTheme(rawValue: rawValue) {
            selectedTheme = storedTheme
        } else {
            let initialTheme = SeasonTheme.defaultTheme(for: date, calendar: calendar)
            selectedTheme = initialTheme
            defaults.set(initialTheme.rawValue, forKey: Self.preferenceKey)
        }
    }

    func select(_ theme: SeasonTheme) {
        guard selectedTheme != theme else { return }
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: Self.preferenceKey)
    }
}
