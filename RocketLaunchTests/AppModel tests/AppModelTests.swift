import XCTest
import Observation
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

    func testBrowsingFiltersSearchCountryAndExcludesPastSpaceX() {
        let filters = BrowseViewModel()
        let group = LaunchOperator(id: "spacex", name: "SpaceX", launches: [launch(), launch(-1, source: .spaceX), launch(source: .launchLibrary, country: "China")])
        XCTAssertEqual(filters.launches(in: LaunchScheduleSnapshot.upcoming(from: group.launches, now: now)).count, 2)
        filters.country = "United States"
        XCTAssertEqual(filters.launches(in: LaunchScheduleSnapshot.upcoming(from: group.launches, now: now)).count, 1)
        filters.search = "moon"
        XCTAssertEqual(filters.launches(in: LaunchScheduleSnapshot.upcoming(from: group.launches, now: now)).count, 1)
        filters.search = "unknown"
        XCTAssertTrue(filters.launches(in: LaunchScheduleSnapshot.upcoming(from: group.launches, now: now)).isEmpty)
        filters.search = "SpaceX"
        XCTAssertEqual(filters.operators(in: [group]).count, 1)
        filters.country = "France"
        XCTAssertTrue(filters.operators(in: [group]).isEmpty)
    }
    func testScheduleChangesRequirePreviousDownloadAndIgnoreUnchangedRefresh() async {
        let repository = SequenceLaunchRepository([[launch()], [launch()], [launch(10800)]])
        let feature = LaunchScheduleFeature(repository: repository)
        await feature.refresh()
        let projection13 = await feature.snapshot
        XCTAssertTrue(projection13.updates.isEmpty)
        await feature.refresh()
        let projection14 = await feature.snapshot
        XCTAssertTrue(projection14.updates.isEmpty)
        await feature.refresh()
        let projection15 = await feature.snapshot
        XCTAssertEqual(projection15.updates.count, 1)
        let projection16 = await feature.snapshot
        XCTAssertTrue(projection16.updates[0].timeChanged)
        let projection17 = await feature.snapshot
        XCTAssertEqual(projection17.updates[0].previous.details.plannedTime, now.addingTimeInterval(7200))
        let projection18 = await feature.snapshot
        XCTAssertEqual(projection18.updates[0].launch.details.plannedTime, now.addingTimeInterval(10800))
    }
    func testWebLinksRejectNonWebSchemes() {
        XCTAssertNil(launchWebURL("javascript:alert(1)"))
        XCTAssertNil(launchWebURL("/relative/path"))
        XCTAssertEqual(launchWebURL("https://example.com/watch")?.host, "example.com")
    }
}

@MainActor
final class ActorSnapshotTests: XCTestCase {

    func testUnchangedClockDoesNotPublishAnotherRevision() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let initial = await feature.snapshot
        await feature.updateNextLaunch()
        let stillInitial = await feature.snapshot
        XCTAssertEqual(stillInitial, initial)
        await feature.refresh()
        let loaded = await feature.snapshot
        for _ in 0..<10 { await feature.updateNextLaunch() }
        let unchanged = await feature.snapshot
        XCTAssertEqual(unchanged, loaded)
    }
    func testCooldownExpiryPublishesEvenWithoutNewLaunches() async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: SequenceLaunchRepository([[]]), minimumRefreshInterval: 300)], now: { clock.read() })
        await feature.refresh()
        let loaded = await feature.snapshot
        clock.advance(60)
        await feature.updateNextLaunch()
        let unchanged = await feature.snapshot
        XCTAssertEqual(unchanged, loaded)
        clock.advance(240)
        await feature.updateNextLaunch()
        let expired = await feature.snapshot
        XCTAssertNil(expired.sources.first?.nextRefreshAt)
        XCTAssertGreaterThan(expired.revision, loaded.revision)
    }
    func testEachSubscriberReceivesInitialAndFinalSnapshots() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let firstStream = await feature.snapshots()
        let secondStream = await feature.snapshots()
        var first = firstStream.makeAsyncIterator()
        var second = secondStream.makeAsyncIterator()
        let initialA = await first.next()
        let initialB = await second.next()
        XCTAssertEqual(initialA, initialB)
        XCTAssertEqual(initialA?.state, .idle)
        await feature.refresh()
        let finalA = await first.next()
        let finalB = await second.next()
        XCTAssertEqual(finalA, finalB)
        XCTAssertEqual(finalA?.state, .empty)
        XCTAssertGreaterThan(finalA!.revision, initialA!.revision)
    }
    func testSlowSubscriberReceivesLatestCompleteSnapshot() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let stream = await feature.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        await feature.refresh()
        for _ in 0..<10 { await feature.updateNextLaunch() }
        let expected = await feature.snapshot
        let received = await iterator.next()
        XCTAssertEqual(received, expected)
    }
    func testCancelingOneSubscriberDoesNotStopAnother() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let firstStream = await feature.snapshots()
        let secondStream = await feature.snapshots()
        let started = expectation(description: "First subscriber started")
        let consumer = Task {
            started.fulfill()
            for await _ in firstStream {}
        }
        await fulfillment(of: [started], timeout: 2)
        consumer.cancel()
        await consumer.value
        await feature.refresh()
        var second = secondStream.makeAsyncIterator()
        let value = await second.next()
        XCTAssertEqual(value?.state, .empty)
    }
    func testFeatureComputationRunsAwayFromMainThread() async {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: SequenceLaunchRepository([[]]))], now: {
            // Called synchronously inside feature-isolated business processing.
            XCTAssertFalse(Thread.isMainThread)
            return date
        })
        await feature.refresh()
        let value = await feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }
}

private actor SequenceLaunchRepository: LaunchRepository {
    var pages: [[RocketLaunch]]
    init(_ pages: [[RocketLaunch]]) { self.pages = pages }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] { pages.removeFirst() }
}

@MainActor
final class UnifiedReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func launch(_ offset: Double? = 7200, id: Int = 1, source: LaunchSourceID = .rocketLaunchLive) -> RocketLaunch {
        .init(id: String(id), source: source, name: "Launch \(id)", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil),
              details: .init(plannedTime: offset.map { now.addingTimeInterval($0) }))
    }
    private func model(_ launches: [RocketLaunch], client: any LaunchNotificationClient = ControlledNotifications(), storage: ReminderStorage = .memory) async -> (LaunchScheduleFeature, MutableLaunchRepository) {
        let repository = MutableLaunchRepository(launches)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { [now] in
            XCTAssertFalse(Thread.isMainThread)
            return now
        }, notificationClient: client, reminderStorage: storage)
        await feature.refresh()
        return (feature, repository)
    }
    func testTimePassingDuringSchedulingCannotConfirmExpiredReminder() async throws {
        let clock = TestClock(now)
        let started = expectation(description: "scheduling waits")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let repository = MutableLaunchRepository([launch(360)])
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { clock.read() }, notificationClient: client)
        await feature.refresh()
        let id = launch().id
        let task = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        clock.advance(120); await client.finish()
        do { _ = try await task.value; XCTFail("Expired during scheduling") } catch ReminderError.tooLate {}
        let value = await feature.reminderSnapshot
        XCTAssertEqual(value.reminders.first?.status, .failed)
        let active = await client.active
        XCTAssertTrue(active.isEmpty)
    }
    func testPersistedPendingStateIsNotReportedAsScheduledOnRestart() async throws {
        let suite = "rocket-pending-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let pending = LaunchReminder(launch: launch(), notificationID: "interrupted", minutesBefore: 5, fireDate: now.addingTimeInterval(600), issue: nil, status: .pending)
        UserDefaults(suiteName: suite)?.set(try JSONEncoder().encode([pending]), forKey: "rocketlaunch.reminders.v1")
        let (feature, _) = await model([launch()], storage: .suite(suite))
        let value = await feature.reminderSnapshot
        XCTAssertEqual(value.reminders.first?.status, .failed)
        XCTAssertNotNil(value.reminders.first?.issue)
    }
    func testSaveByIDUsesCurrentCacheDespiteOldScreenValue() async throws {
        let old = launch(3600)
        let (feature, repository) = await model([old])
        _ = try await feature.setReminder(for: old.id, minutesBefore: 15)
        await repository.set([launch(7200)])
        await feature.refresh()
        let outcome = try await feature.setReminder(for: old.id, minutesBefore: 5)
        let result = await feature.reminderSnapshot
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(result.reminders.first?.fireDate, now.addingTimeInterval(6900))
        XCTAssertEqual(result.reminders.first?.launch, launch(7200))
    }
    func testDesiredReminderExistsBeforeNotificationReturns() async throws {
        let started = expectation(description: "notification suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 15) }
        await fulfillment(of: [started], timeout: 2)
        let pending = await feature.reminderSnapshot
        XCTAssertEqual(pending.reminders.count, 1)
        XCTAssertEqual(pending.reminders.first?.status, .pending)
        await client.finish()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .saved)
        let saved = await feature.reminderSnapshot
        XCTAssertEqual(saved.reminders.first?.status, .scheduled)
    }
    func testRefreshDuringFirstSaveUpdatesDesiredTimeAndCleansOldNotification() async throws {
        let started = expectation(description: "first save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, repository) = await model([launch(3600)], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await repository.set([launch(7200)]); await feature.refresh()
        await client.finish()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .superseded)
        let current = await feature.reminderSnapshot
        XCTAssertEqual(current.reminders.first?.launch, launch(7200))
        XCTAssertEqual(current.reminders.first?.status, .scheduled)
        let flags = await client.permissionFlags
        XCTAssertEqual(flags, [true, true], "The replacement continues the active user permission intent")
        let active = await client.active
        XCTAssertEqual(active, Set(current.reminders.map(\.notificationID)))
    }
    func testLaterRefreshReturningToOriginalTimeWinsOverSuspendedEffect() async throws {
        let started = expectation(description: "first reschedule suspended")
        let client = ControlledNotifications(hold: 2) { _ in started.fulfill() }
        let (feature, repository) = await model([launch(3600)], client: client)
        try await feature.setReminder(for: launch().id, minutesBefore: 5)
        await repository.set([launch(7200)])
        let updating = Task { await feature.refresh() }
        await fulfillment(of: [started], timeout: 2)
        // Cancel only the refresh waiter. Its already committed desired state remains.
        updating.cancel(); await updating.value
        await repository.set([launch(3600)]); await feature.refresh()
        await client.finish()
        // Wait until the older effect has completed cleanup using the client callback.
        let settled = expectation(description: "obsolete effect canceled")
        await client.onNextCancel { settled.fulfill() }
        // onNextCancel also fires immediately if cancellation already happened twice.
        await fulfillment(of: [settled], timeout: 2)
        let current = await feature.reminderSnapshot
        XCTAssertEqual(current.reminders.first?.launch, launch(3600))
        XCTAssertEqual(current.reminders.first?.status, .scheduled)
        let active = await client.active
        XCTAssertEqual(active, Set(current.reminders.map(\.notificationID)))
    }

    func testUnchangedRefreshPreservesPendingSave() async throws {
        let started = expectation(description: "save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.refresh(); await client.finish()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .saved)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
    }
    func testUnknownTimeDuringPendingSaveCancelsAlertAndKeepsHonestFailure() async throws {
        let started = expectation(description: "save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, repository) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await repository.set([launch(nil)]); await feature.refresh(); await client.finish()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .superseded)
        let value = await feature.reminderSnapshot
        XCTAssertNil(value.reminders.first?.launch.details.plannedTime)
        XCTAssertEqual(value.reminders.first?.status, .failed)
        let active = await client.active
        XCTAssertTrue(active.isEmpty)
    }
    func testRemoveDuringSchedulingDoesNotRestoreRecord() async throws {
        let started = expectation(description: "save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.removeReminder(id); await client.finish()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .superseded)
        let value = await feature.reminderSnapshot
        XCTAssertTrue(value.reminders.isEmpty)
        let active = await client.active
        XCTAssertTrue(active.isEmpty)
    }
    func testLaterUserPreferenceWinsWhileEarlierNotificationIsPending() async throws {
        let started = expectation(description: "save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let first = Task { try await feature.setReminder(for: id, minutesBefore: 15) }
        await fulfillment(of: [started], timeout: 2)
        let later = try await feature.setReminder(for: id, minutesBefore: 5)
        await client.finish()
        let earlier = try await first.value
        XCTAssertEqual(later, .saved); XCTAssertEqual(earlier, .superseded)
        let value = await feature.reminderSnapshot
        XCTAssertEqual(value.reminders.first?.minutesBefore, 5)
        let active = await client.active
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }
    func testObsoleteFailureCannotMarkNewDesiredReminderFailed() async throws {
        let started = expectation(description: "save suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, repository) = await model([launch()], client: client)
        let id = launch().id
        let first = Task { try await feature.setReminder(for: id, minutesBefore: 15) }
        await fulfillment(of: [started], timeout: 2)
        await repository.set([launch(10800)]); await feature.refresh(); await client.finish(fail: true)
        let outcome = try await first.value
        XCTAssertEqual(outcome, .superseded)
        let value = await feature.reminderSnapshot
        XCTAssertEqual(value.reminders.first?.status, .scheduled)
        XCTAssertNil(value.reminders.first?.issue)
    }
    func testCapacityIncludesPendingDesiredRecord() async throws {
        let started = expectation(description: "50th save suspended")
        let client = ControlledNotifications(hold: 50) { _ in started.fulfill() }
        let launches = (1...51).map { launch(id: $0) }
        let (feature, _) = await model(launches, client: client)
        for item in launches.prefix(49) { try await feature.setReminder(for: item.id, minutesBefore: 5) }
        let id = launches[49].id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        do { try await feature.setReminder(for: launches[50].id, minutesBefore: 5); XCTFail("Capacity exceeded") }
        catch ReminderError.limit {}
        await client.finish(); _ = try await save.value
        let value = await feature.reminderSnapshot
        XCTAssertEqual(value.reminders.count, 50)
    }
    func testFailedDeliveryIsVisibleAndCanBeRetried() async throws {
        let client = ControlledNotifications(deny: true)
        let (feature, _) = await model([launch()], client: client)
        do { try await feature.setReminder(for: launch().id, minutesBefore: 5); XCTFail("Denied") }
        catch ReminderError.denied {}
        let failed = await feature.reminderSnapshot
        XCTAssertEqual(failed.reminders.first?.status, .failed)
        await client.allow()
        let result = try await feature.setReminder(for: launch().id, minutesBefore: 5)
        XCTAssertEqual(result, .saved)
        let saved = await feature.reminderSnapshot
        XCTAssertEqual(saved.reminders.first?.status, .scheduled)
    }
    func testUnknownIDAndInvalidTimeDoNotSchedule() async throws {
        let client = ControlledNotifications()
        let (feature, _) = await model([launch(nil)], client: client)
        do { try await feature.setReminder(for: "missing", minutesBefore: 5); XCTFail() } catch ReminderError.launchUnavailable {}
        do { try await feature.setReminder(for: launch().id, minutesBefore: 5); XCTFail() } catch ReminderError.unknownTime {}
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
    }
    func testInvalidLeadTimeAndElapsedTimeDoNotSchedule() async throws {
        let client = ControlledNotifications()
        let (feature, _) = await model([launch(60)], client: client)
        do { try await feature.setReminder(for: launch().id, minutesBefore: -1); XCTFail() } catch ReminderError.invalidLeadTime {}
        do { try await feature.setReminder(for: launch().id, minutesBefore: 5); XCTFail() } catch ReminderError.tooLate {}
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
    }
    func testReminderPersistenceAndLateSubscriberReplay() async throws {
        let suite = "rocket-unified-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let (feature, _) = await model([launch()], storage: .suite(suite))
        try await feature.setReminder(for: launch().id, minutesBefore: 15)
        let expected = await feature.reminderSnapshot
        let (restored, _) = await model([launch()], storage: .suite(suite))
        let stream = await restored.reminderSnapshots()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.reminders, expected.reminders)
        await restored.removeReminder(launch().id)
        let removed = await iterator.next()
        XCTAssertTrue(removed!.reminders.isEmpty)
    }
    func testLegacyStoredReminderDecodesWithoutStatus() throws {
        let value = LaunchReminder(launch: launch(), notificationID: "legacy", minutesBefore: 15, fireDate: now, issue: nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        json.removeValue(forKey: "status")
        let decoded = try JSONDecoder().decode(LaunchReminder.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.status, .scheduled)
    }
    func testSourceQualifiedIDsRemainIndependent() async throws {
        let values = [launch(source: .rocketLaunchLive), launch(source: .launchLibrary)]
        let (feature, _) = await model(values)
        for value in values { try await feature.setReminder(for: value.id, minutesBefore: 5) }
        let saved = await feature.reminderSnapshot
        XCTAssertEqual(saved.reminders.count, 2)
    }
    func testDoubleTapDoesNotStartTwoSaves() async {
        let started = expectation(description: "save suspended")
        let finished = expectation(description: "UI command finishes")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let vm = ReminderViewModel(feature: feature)
        vm.save(launch().id, minutesBefore: 5); vm.save(launch().id, minutesBefore: 5)
        await fulfillment(of: [started], timeout: 2)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        withObservationTracking { _ = vm.isBusy } onChange: { finished.fulfill() }
        await client.finish(); await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(vm.contains(launch().id))
    }
}

private actor MutableLaunchRepository: LaunchRepository {
    var values: [RocketLaunch]
    init(_ values: [RocketLaunch]) { self.values = values }
    func set(_ values: [RocketLaunch]) { self.values = values }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] { values }
}
private actor ControlledNotifications: LaunchNotificationClient {
    let hold: Int?
    let started: @Sendable (Int) -> Void
    var deny: Bool
    private(set) var active: Set<String> = []
    private(set) var calls = 0
    private(set) var permissionFlags: [Bool] = []
    var continuation: CheckedContinuation<Void, any Error>?
    var cancelCount = 0
    var canceledHook: (@Sendable () -> Void)?
    init(hold: Int? = nil, deny: Bool = false, started: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.hold = hold; self.deny = deny; self.started = started
    }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        calls += 1
        permissionFlags.append(askPermission)
        if deny { throw ReminderError.denied }
        if calls == hold {
            try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started(calls) }
        }
        active.insert(id) // Simulate a late external success even after cancel(id).
    }
    func finish(fail: Bool = false) {
        if fail { continuation?.resume(throwing: ReminderError.denied) } else { continuation?.resume() }
        continuation = nil
    }
    func allow() { deny = false }
    func onNextCancel(_ hook: @escaping @Sendable () -> Void) {
        if cancelCount >= 3 { hook() } else { canceledHook = hook }
    }
    func cancel(_ id: String) async {
        active.remove(id); cancelCount += 1
        if cancelCount >= 3 { canceledHook?(); canceledHook = nil }
    }
}

@MainActor final class SharedRefreshTests: XCTestCase {
    func testReappearanceBeforeOldTransportFinishesRestartsInitialLoad() async {
        let firstBegan = expectation(description: "first")
        let secondBegan = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? firstBegan : secondBegan).fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let old = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [firstBegan], timeout: 2)
        old.cancel(); await old.value // cancellation releases ownership before transport cooperates
        let new = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [secondBegan], timeout: 2)
        await repository.complete(1, with: .success([])); await new.value
        await repository.complete(0, with: .success([]))
        let value = await feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }
    func testPartialInitialLoadRetriesOnlyCanceledSource() async {
        let aStarted = expectation(description: "A")
        let bStarted = expectation(description: "B")
        let bRetried = expectation(description: "B retry")
        let a = ControlledLaunchRepository { _ in aStarted.fulfill() }
        let b = ControlledLaunchRepository { index in (index == 0 ? bStarted : bRetried).fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: a), .init(id: .launchLibrary, repository: b)])
        let initial = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [aStarted, bStarted], timeout: 2)
        let stream = await feature.snapshots()
        let accepted = expectation(description: "A committed")
        let observer = Task { for await value in stream { if value.sources.first?.phase == .loaded { accepted.fulfill(); break } } }
        await a.complete(0, with: .success([])); await fulfillment(of: [accepted], timeout: 2); await observer.value
        initial.cancel(); await initial.value
        let retry = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [bRetried], timeout: 2)
        await b.complete(1, with: .success([])); await retry.value
        await b.complete(0, with: .failure(CancellationError()))
        let aCount = await a.requestCount
        XCTAssertEqual(aCount, 1)
    }
    func testRepeatedRefreshDuringCooldownKeepsOriginalRequest() async {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: repository, minimumRefreshInterval: 300)])
        let vm = LaunchScheduleViewModel(feature: feature)
        vm.requestRefresh(); await fulfillment(of: [began], timeout: 2)
        vm.requestRefresh(); vm.requestRefresh(source: .launchLibrary)
        await repository.complete(0, with: .success([]))
        let stream = await feature.snapshots()
        for await value in stream { if value.sources.first?.phase == .loaded { break } }
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
        vm.cancelRefresh(); vm.stopObserving()
    }
    func testTwoCallersShareOneRequestAndBothReceiveItsResult() async {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: repository, minimumRefreshInterval: 300)])
        let first = Task { await feature.refresh() }
        await fulfillment(of: [began], timeout: 2)
        let second = Task { await feature.refresh() }
        await repository.complete(0, with: .success([]))
        await first.value; await second.value
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
        let value = await feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }
}
