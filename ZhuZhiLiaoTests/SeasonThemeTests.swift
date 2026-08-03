import XCTest
@testable import ZhuZhiLiao

@MainActor
final class SeasonThemeTests: XCTestCase {
    func testMonthMappingCoversSeasonBoundaries() {
        XCTAssertEqual(SeasonTheme.theme(forMonth: 2), .winter)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 3), .spring)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 5), .spring)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 6), .summer)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 8), .summer)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 9), .autumn)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 11), .autumn)
        XCTAssertEqual(SeasonTheme.theme(forMonth: 12), .winter)
    }

    func testFirstLaunchUsesCurrentSeasonAndPersistsIt() throws {
        let defaults = try makeDefaults()
        let store = SeasonThemeStore(
            defaults: defaults,
            date: makeDate(year: 2026, month: 7, day: 12),
            calendar: testCalendar
        )

        XCTAssertEqual(store.selectedTheme, .summer)
        XCTAssertEqual(defaults.string(forKey: SeasonThemeStore.preferenceKey), "summer")
    }

    func testManualSelectionIsRestoredOnNextLaunch() throws {
        let defaults = try makeDefaults()
        let firstStore = SeasonThemeStore(
            defaults: defaults,
            date: makeDate(year: 2026, month: 4, day: 1),
            calendar: testCalendar
        )
        firstStore.select(.autumn)

        let restoredStore = SeasonThemeStore(
            defaults: defaults,
            date: makeDate(year: 2026, month: 1, day: 1),
            calendar: testCalendar
        )

        XCTAssertEqual(restoredStore.selectedTheme, .autumn)
    }

    func testInvalidStoredValueFallsBackToCurrentSeason() throws {
        let defaults = try makeDefaults()
        defaults.set("monsoon", forKey: SeasonThemeStore.preferenceKey)

        let store = SeasonThemeStore(
            defaults: defaults,
            date: makeDate(year: 2026, month: 1, day: 9),
            calendar: testCalendar
        )

        XCTAssertEqual(store.selectedTheme, .winter)
        XCTAssertEqual(defaults.string(forKey: SeasonThemeStore.preferenceKey), "winter")
    }

    func testEveryThemeHasUniqueStableIdentityAndFinitePaletteValues() {
        XCTAssertEqual(Set(SeasonTheme.allCases.map(\.rawValue)).count, 4)
        XCTAssertEqual(Set(SeasonTheme.allCases.map(\.shaderIndex)).count, 4)

        for theme in SeasonTheme.allCases {
            let palette = theme.metalPalette
            let vectors = [
                palette.skyTop,
                palette.skyMiddle,
                palette.skyBottom,
                palette.atmosphere,
                palette.seasonalAccent,
                palette.silhouette,
                palette.bamboo,
                palette.cutBamboo,
                palette.paleBamboo,
                palette.lacquer,
                palette.cord,
                palette.rope,
                palette.effect,
                palette.coolLight,
                palette.warmLight
            ]
            XCTAssertTrue(
                vectors.allSatisfy { vector in
                    vector.x.isFinite
                        && vector.y.isFinite
                        && vector.z.isFinite
                        && vector.w.isFinite
                }
            )
        }
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        testCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SeasonThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
