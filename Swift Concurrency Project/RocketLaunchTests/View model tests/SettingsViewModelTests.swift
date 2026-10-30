import XCTest
import Observation
@testable import RocketLaunch

final class SettingsViewModelTests: XCTestCase {
    @MainActor func testScreensObserveOnePreferenceOwnerAndRestoreSavedChoice() async throws {
        let suite = "settings-owner-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.txt")
        let feature = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: suite)))
        await feature.loadIfNeeded()
        let first = SettingsViewModel(settingsFeature: feature)
        let second = SettingsViewModel(settingsFeature: feature)
        let changed = expectation(description: "other screen observes change")
        withObservationTracking { _ = second.selectedTheme } onChange: { changed.fulfill() }
        first.selectedTheme = .forest
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(second.selectedTheme, .forest)
        let restored = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: suite)))
        await restored.loadIfNeeded()
        XCTAssertEqual(restored.selected, .forest)
        XCTAssertEqual(SettingsViewModel(settingsFeature: SettingsFeature()).selectedTheme, .system)
    }
}
