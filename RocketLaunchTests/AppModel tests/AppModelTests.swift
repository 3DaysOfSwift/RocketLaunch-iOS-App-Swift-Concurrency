import XCTest
@testable import RocketLaunch

final class AppModelTests: XCTestCase {
    @MainActor func testRetainsProvidedFeatureWithoutStartingWork() async {
        let feature = ControlledLaunchFeature()
        let appModel = AppModel(launchSchedule: feature)
        XCTAssertTrue(appModel.launchSchedule === feature)
        XCTAssertEqual(feature.refreshCount, 0)
    }
    @MainActor func testIndependentApplicationGraphsDoNotShareFeatureRequests() async {
        let firstFeature = ControlledLaunchFeature()
        let secondFeature = ControlledLaunchFeature()
        let first = AppModel(launchSchedule: firstFeature)
        _ = AppModel(launchSchedule: secondFeature)
        await first.launchSchedule.refresh()
        XCTAssertEqual(firstFeature.refreshCount, 1)
        XCTAssertEqual(secondFeature.refreshCount, 0)
    }
}

@MainActor
final class RemindersAndBrowsingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func launch(_ offset: Double? = 7200, source: LaunchSourceID = .rocketLaunchLive, country: String = "USA") -> RocketLaunch {
        let date = offset.map { now.addingTimeInterval($0) }
        return RocketLaunch(id: "1", source: source, name: "Moon mission", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(provider: "SpaceX", vehicle: "Falcon", country: country, plannedTime: date, sortTime: date))
    }
    func testSavePersistsAndRemoveCancelsOnlyItsNotification() async throws {
        let suite = "rocketlaunch-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, defaults: defaults, now: { self.now })
        try await feature.save(launch(), minutesBefore: 15)
        let saved = try XCTUnwrap(feature.reminders.first)
        XCTAssertEqual(saved.fireDate, now.addingTimeInterval(6300))
        let restored = RemindersFeature(client: client, defaults: defaults)
        XCTAssertEqual(restored.reminders, feature.reminders)
        await feature.remove(saved.id)
        XCTAssertTrue(feature.reminders.isEmpty)
        let canceled = await client.canceled
        XCTAssertEqual(canceled, [saved.notificationID])
    }
    func testUnknownAndElapsedTimesDoNotSchedule() async {
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, now: { self.now })
        for launch in [launch(nil), launch(60)] {
            do { try await feature.save(launch, minutesBefore: 15); XCTFail("Should reject") } catch {}
        }
        let count = await client.scheduled.count
        XCTAssertEqual(count, 0)
        XCTAssertTrue(feature.reminders.isEmpty)
    }
    func testPermissionDenialDoesNotSaveReminder() async {
        let feature = RemindersFeature(client: RecordingNotifications(denied: true), now: { self.now })
        do { try await feature.save(launch(), minutesBefore: 15); XCTFail("Should reject") }
        catch { XCTAssertTrue(error is ReminderError) }
        XCTAssertTrue(feature.reminders.isEmpty)
    }
    func testRefreshReschedulesAndUncertainTimeCancelsOldAlert() async throws {
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, now: { self.now })
        try await feature.save(launch(), minutesBefore: 15)
        let original = feature.reminders[0].notificationID
        await feature.reconcile([launch(10800)])
        XCTAssertEqual(feature.reminders[0].fireDate, now.addingTimeInterval(9900))
        XCTAssertNotEqual(feature.reminders[0].notificationID, original)
        let scheduled = await client.scheduled
        XCTAssertEqual(scheduled.map(\.askPermission), [true, false])
        let updated = feature.reminders[0].notificationID
        await feature.reconcile([launch(nil)])
        XCTAssertNotNil(feature.reminders[0].issue)
        let canceled = await client.canceled
        XCTAssertEqual(Set(canceled), Set([original, updated]))
    }
    func testSourceIdentityKeepsRemindersIndependent() async throws {
        let feature = RemindersFeature(client: RecordingNotifications(), now: { self.now })
        try await feature.save(launch(), minutesBefore: 5)
        try await feature.save(launch(source: .launchLibrary), minutesBefore: 5)
        XCTAssertEqual(feature.reminders.count, 2)
    }
    func testBrowsingFiltersSearchCountryAndExcludesPastSpaceX() {
        let filters = BrowseViewModel()
        let group = LaunchOperator(id: "spacex", name: "SpaceX", launches: [launch(), launch(-1, source: .spaceX), launch(source: .launchLibrary, country: "China")])
        XCTAssertEqual(filters.launches(in: [group], now: now).count, 2)
        filters.country = "United States"
        XCTAssertEqual(filters.launches(in: [group], now: now).count, 1)
        filters.search = "moon"
        XCTAssertEqual(filters.launches(in: [group], now: now).count, 1)
        filters.search = "unknown"
        XCTAssertTrue(filters.launches(in: [group], now: now).isEmpty)
        filters.search = "SpaceX"
        XCTAssertEqual(filters.operators(in: [group]).count, 1)
        filters.country = "France"
        XCTAssertTrue(filters.operators(in: [group]).isEmpty)
    }
    func testScheduleChangesRequirePreviousDownloadAndIgnoreUnchangedRefresh() async {
        let repository = SequenceLaunchRepository([[launch()], [launch()], [launch(10800)]])
        let feature = LaunchScheduleFeature(repository: repository)
        await feature.refresh()
        XCTAssertTrue(feature.updates.isEmpty)
        await feature.refresh()
        XCTAssertTrue(feature.updates.isEmpty)
        await feature.refresh()
        XCTAssertEqual(feature.updates.count, 1)
        XCTAssertTrue(feature.updates[0].timeChanged)
        XCTAssertEqual(feature.updates[0].previous.details.plannedTime, now.addingTimeInterval(7200))
        XCTAssertEqual(feature.updates[0].launch.details.plannedTime, now.addingTimeInterval(10800))
    }
    func testRemoveWhileSchedulingCannotRestoreDeletedReminder() async throws {
        let started = expectation(description: "Scheduling started")
        let client = SuspendedNotifications { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { self.now })
        let launch = launch()
        let task = Task { try await feature.save(launch, minutesBefore: 15) }
        await fulfillment(of: [started], timeout: 2)
        await feature.remove(launch.id)
        await client.finish()
        try await task.value
        XCTAssertTrue(feature.reminders.isEmpty)
        let count = await client.canceled.count
        XCTAssertEqual(count, 1)
    }
    func testWebLinksRejectNonWebSchemes() {
        XCTAssertNil(launchWebURL("javascript:alert(1)"))
        XCTAssertNil(launchWebURL("/relative/path"))
        XCTAssertEqual(launchWebURL("https://example.com/watch")?.host, "example.com")
    }
}

private actor RecordingNotifications: LaunchNotificationClient {
    struct Request { let id: String; let askPermission: Bool }
    let denied: Bool
    private(set) var scheduled: [Request] = []
    private(set) var canceled: [String] = []
    init(denied: Bool = false) { self.denied = denied }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        if denied { throw ReminderError.denied }
        scheduled.append(.init(id: id, askPermission: askPermission))
    }
    func cancel(_ id: String) async { canceled.append(id) }
}

private actor SequenceLaunchRepository: LaunchRepository {
    var pages: [[RocketLaunch]]
    init(_ pages: [[RocketLaunch]]) { self.pages = pages }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] { pages.removeFirst() }
}

private actor SuspendedNotifications: LaunchNotificationClient {
    let started: @Sendable () -> Void
    var continuation: CheckedContinuation<Void, Never>?
    private(set) var canceled: [String] = []
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started()
        }
    }
    func finish() { continuation?.resume(); continuation = nil }
    func cancel(_ id: String) async { canceled.append(id) }
}
