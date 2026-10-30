import XCTest
import Observation
@testable import RocketLaunch

final class SettingsViewModelTests: XCTestCase {
    @MainActor func testScreensObserveOnePreferenceOwnerAndRestoreSavedChoice() async throws {
        let suite = "settings-owner-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = SettingsFeature(defaults: defaults)
        let first = SettingsViewModel(settingsFeature: feature)
        let second = SettingsViewModel(settingsFeature: feature)
        let changed = expectation(description: "other screen observes change")
        withObservationTracking { _ = second.selectedTheme } onChange: { changed.fulfill() }
        first.selectedTheme = .forest
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(second.selectedTheme, .forest)
        XCTAssertEqual(SettingsFeature(defaults: defaults).selected, .forest)
        XCTAssertEqual(SettingsViewModel(settingsFeature: SettingsFeature()).selectedTheme, .system)
    }
}
