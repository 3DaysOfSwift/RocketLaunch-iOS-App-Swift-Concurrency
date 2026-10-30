import XCTest
import Observation
@testable import RocketLaunch

final class SettingsFeatureTests: XCTestCase {
    @MainActor func testDefaultThemeFollowsSystemPalette() async {
        XCTAssertEqual(SettingsFeature().selected, .system)
    }
    @MainActor func testThemeChangesAreObservable() async {
        let manager = SettingsFeature()
        let changed = expectation(description: "theme")
        withObservationTracking { _ = manager.selected } onChange: { changed.fulfill() }
        manager.select(.midnight)
        await waitFor([changed])
        XCTAssertEqual(manager.selected, .midnight)
    }
    @MainActor func testCycleVisitsEveryThemeAndWrapsToSystem() {
        let manager = SettingsFeature()
        var visited: Set<AppColourTheme> = []
        for _ in 0..<AppColourTheme.allCases.count {
            visited.insert(manager.selected)
            manager.selectNextTheme()
        }
        XCTAssertEqual(visited, Set(AppColourTheme.allCases))
        XCTAssertEqual(manager.selected, .system)
    }
    @MainActor func testSelectionIsRestoredAndInvalidPreferenceFallsBack() {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = SettingsFeature(defaults: defaults)
        manager.select(.forest)
        XCTAssertEqual(SettingsFeature(defaults: defaults).selected, .forest)
        defaults.set("unknown", forKey: "rocketlaunch.colourTheme")
        XCTAssertEqual(SettingsFeature(defaults: defaults).selected, .system)
    }
}
