import XCTest
import Observation
@testable import RocketLaunch

private actor ThemeFixture: ThemePersisting {
    var theme: AppColourTheme = .system
    var fail = false
    var writes: [AppColourTheme] = []
    var gate: CheckedContinuation<Void, Never>?
    var hold = false
    var onStart: (@Sendable () -> Void)?
    func onSaveStart(_ callback: @escaping @Sendable () -> Void) { onStart = callback }
    func configure(fail: Bool = false, hold: Bool = false) { self.fail = fail; self.hold = hold }
    func load() -> AppColourTheme { theme }
    func save(_ value: AppColourTheme) async throws {
        writes.append(value)
        if hold {
            hold = false
            await withCheckedContinuation { continuation in
                gate = continuation
                onStart?()
            }
        }
        if fail { throw CocoaError(.fileWriteUnknown) }
        theme = value
    }
    func release() { gate?.resume(); gate = nil }
    func recorded() -> [AppColourTheme] { writes }
}

final class SettingsFeatureTests: XCTestCase {
    @MainActor func testDefaultThemeFollowsSystemPalette() {
        XCTAssertEqual(SettingsFeature().selected, .system)
    }
    @MainActor func testThemeChangesAreObservable() async {
        let manager = SettingsFeature()
        await manager.loadIfNeeded()
        let changed = expectation(description: "theme")
        withObservationTracking { _ = manager.selected } onChange: { changed.fulfill() }
        await manager.select(.midnight).value
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(manager.selected, .midnight)
    }
    @MainActor func testCycleVisitsEveryThemeAndWrapsToSystem() async {
        let manager = SettingsFeature()
        var visited: Set<AppColourTheme> = []
        for _ in 0..<AppColourTheme.allCases.count {
            visited.insert(manager.selected)
            await manager.selectNextTheme().value
        }
        XCTAssertEqual(visited, Set(AppColourTheme.allCases))
        XCTAssertEqual(manager.selected, .system)
    }
    @MainActor func testLegacyPreferenceMigratesAndSavedChoiceRestores() async throws {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.txt")
        defaults.set("ocean", forKey: "rocketlaunch.colourTheme")
        let manager = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))
        await manager.loadIfNeeded()
        XCTAssertEqual(manager.selected, .ocean)
        await manager.select(.forest).value
        let restored = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))
        await restored.loadIfNeeded()
        XCTAssertEqual(restored.selected, .forest)
    }
    @MainActor func testInvalidLegacyValueIsNotSilentlyOverwritten() async throws {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.txt")
        defaults.set(42, forKey: "rocketlaunch.colourTheme")
        let manager = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))
        await manager.loadIfNeeded()
        XCTAssertNotNil(manager.storageError)
        await manager.select(.forest).value
        XCTAssertEqual(manager.selected, .system)
        XCTAssertEqual(defaults.integer(forKey: "rocketlaunch.colourTheme"), 42)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testFirstLoadReportsUnavailableDirectoryAndRetries() async throws {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let blocker = Data("not a directory".utf8)
        try blocker.write(to: directory)
        let feature = SettingsFeature(persistence: ThemePersistence(storage: .file(directory.appendingPathComponent("theme.txt"), legacySuite: name)))

        await feature.loadIfNeeded()
        XCTAssertNotNil(feature.storageError)
        XCTAssertTrue(feature.canRetryLoading)
        XCTAssertEqual(try Data(contentsOf: directory), blocker)
        try FileManager.default.removeItem(at: directory)
        await feature.loadIfNeeded()
        XCTAssertNil(feature.storageError)
        XCTAssertFalse(feature.canRetryLoading)
        XCTAssertEqual(feature.selected, .system)
    }

    @MainActor func testUnknownLegacyThemeReportsErrorWithoutOverwritingAndCanRetry() async throws {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.txt")
        defaults.set("unknown-theme", forKey: "rocketlaunch.colourTheme")
        let feature = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))

        await feature.loadIfNeeded()
        XCTAssertNotNil(feature.storageError)
        await feature.select(.forest).value
        XCTAssertEqual(defaults.string(forKey: "rocketlaunch.colourTheme"), "unknown-theme")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        defaults.set("ocean", forKey: "rocketlaunch.colourTheme")
        await feature.loadIfNeeded()
        XCTAssertNil(feature.storageError)
        XCTAssertEqual(feature.selected, .ocean)
    }

    @MainActor func testMissingMigratedFileDoesNotRestoreStaleLegacyPreference() async throws {
        let name = "rocketlaunch-theme-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.txt")
        defaults.set("ocean", forKey: "rocketlaunch.colourTheme")
        let manager = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))
        await manager.select(.forest).value
        try FileManager.default.removeItem(at: url)
        let restored = SettingsFeature(persistence: ThemePersistence(storage: .file(url, legacySuite: name)))
        await restored.loadIfNeeded()
        XCTAssertNotNil(restored.storageError)
        await restored.select(.sunset).value
        XCTAssertNotNil(restored.storageError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @MainActor func testFailedSaveDoesNotPublishAndCanBeRetried() async {
        let store = ThemeFixture()
        let manager = SettingsFeature(persistence: store)
        await store.configure(fail: true)
        await manager.select(.forest).value
        XCTAssertEqual(manager.selected, .system)
        XCTAssertNotNil(manager.storageError)
        await store.configure()
        await manager.select(.forest).value
        XCTAssertEqual(manager.selected, .forest)
        XCTAssertNil(manager.storageError)
    }
    @MainActor func testOverlappingChangesWaitForPersistenceAndRemainOrdered() async {
        let store = ThemeFixture()
        await store.configure(hold: true)
        let started = expectation(description: "first save started")
        await store.onSaveStart { started.fulfill() }
        let manager = SettingsFeature(persistence: store)
        let first = manager.select(.ocean)
        await fulfillment(of: [started], timeout: 2)
        let second = manager.select(.forest)
        XCTAssertEqual(manager.selected, .system)
        await store.release()
        await first.value
        await second.value
        let writes = await store.recorded()
        XCTAssertEqual(writes, [.ocean, .forest])
        XCTAssertEqual(manager.selected, .forest)
    }
}
