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
    func testSavePersistsAndRemoveCancelsOnlyItsNotification() async throws {
        let suite = "rocketlaunch-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, storage: .suite(suite), now: { [now] in now })
        try await feature.save(launch(), minutesBefore: 15)
        let projection1 = await feature.snapshot
        let saved = try XCTUnwrap(projection1.reminders.first)
        XCTAssertEqual(saved.fireDate, now.addingTimeInterval(6300))
        let restored = RemindersFeature(client: client, storage: .suite(suite))
        let projection2 = await restored.snapshot
        let projection3 = await feature.snapshot
        XCTAssertEqual(projection2.reminders, projection3.reminders)
        await feature.remove(saved.id)
        let projection4 = await feature.snapshot
        XCTAssertTrue(projection4.reminders.isEmpty)
        let canceled = await client.canceled
        XCTAssertEqual(canceled, [saved.notificationID])
    }
    func testUnknownAndElapsedTimesDoNotSchedule() async {
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, now: { [now] in now })
        for launch in [launch(nil), launch(60)] {
            do { try await feature.save(launch, minutesBefore: 15); XCTFail("Should reject") } catch {}
        }
        let count = await client.scheduled.count
        XCTAssertEqual(count, 0)
        let projection5 = await feature.snapshot
        XCTAssertTrue(projection5.reminders.isEmpty)
    }
    func testPermissionDenialDoesNotSaveReminder() async {
        let feature = RemindersFeature(client: RecordingNotifications(denied: true), now: { [now] in now })
        do { try await feature.save(launch(), minutesBefore: 15); XCTFail("Should reject") }
        catch { XCTAssertTrue(error is ReminderError) }
        let projection6 = await feature.snapshot
        XCTAssertTrue(projection6.reminders.isEmpty)
    }
    func testRefreshReschedulesAndUncertainTimeCancelsOldAlert() async throws {
        let client = RecordingNotifications()
        let feature = RemindersFeature(client: client, now: { [now] in now })
        try await feature.save(launch(), minutesBefore: 15)
        let projection7 = await feature.snapshot
        let original = projection7.reminders[0].notificationID
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [launch(10800)]))
        let projection8 = await feature.snapshot
        XCTAssertEqual(projection8.reminders[0].fireDate, now.addingTimeInterval(9900))
        let projection9 = await feature.snapshot
        XCTAssertNotEqual(projection9.reminders[0].notificationID, original)
        let scheduled = await client.scheduled
        XCTAssertEqual(scheduled.map(\.askPermission), [true, false])
        let projection10 = await feature.snapshot
        let updated = projection10.reminders[0].notificationID
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(nil)]))
        let projection11 = await feature.snapshot
        XCTAssertNotNil(projection11.reminders[0].issue)
        let canceled = await client.canceled
        XCTAssertEqual(Set(canceled), Set([original, updated]))
    }
    func testSourceIdentityKeepsRemindersIndependent() async throws {
        let feature = RemindersFeature(client: RecordingNotifications(), now: { [now] in now })
        try await feature.save(launch(), minutesBefore: 5)
        try await feature.save(launch(source: .launchLibrary), minutesBefore: 5)
        let projection12 = await feature.snapshot
        XCTAssertEqual(projection12.reminders.count, 2)
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
    func testRemoveWhileSchedulingCannotRestoreDeletedReminder() async throws {
        let started = expectation(description: "Scheduling started")
        let client = SuspendedNotifications { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { [now] in now })
        let launch = launch()
        let task = Task { try await feature.save(launch, minutesBefore: 15) }
        await fulfillment(of: [started], timeout: 2)
        await feature.remove(launch.id)
        await client.finish()
        let outcome = try await task.value
        XCTAssertEqual(outcome, .superseded)
        let projection19 = await feature.snapshot
        XCTAssertTrue(projection19.reminders.isEmpty)
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

    func testReminderReconciliationRejectsOlderSourceRevision() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double) -> RocketLaunch {
            .init(id: "1", source: .rocketLaunchLive, name: "Launch", missions: [],
                  estimatedDate: .init(month: nil, day: nil, year: nil),
                  details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let feature = RemindersFeature(client: RecordingNotifications(), now: {
            XCTAssertFalse(Thread.isMainThread)
            return now
        })
        try await feature.save(launch(3600), minutesBefore: 5)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 3, launches: [launch(7200)]))
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(5400)]))
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.first?.launch.details.plannedTime, now.addingTimeInterval(7200))
    }

    func testReminderStreamReplaysSavedStateToLateSubscriber() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let feature = RemindersFeature(client: RecordingNotifications(), now: { now })
        let launch = RocketLaunch(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(3600)))
        try await feature.save(launch, minutesBefore: 5)
        let stream = await feature.snapshots()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.reminders.first?.launch, launch)
        await feature.remove(launch.id)
        let removed = await iterator.next()
        XCTAssertEqual(removed?.reminders, [])
    }
}


@MainActor final class ReminderConcurrencyTests: XCTestCase {
    func testNewerUnchangedRefreshSupersedesSuspendedReschedule() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double, id: Int = 1) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "Reschedule suspended")
        let client = SuspendingNotificationClient(suspendAt: 2) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        try await feature.save(launch(3600), minutesBefore: 5)
        let older = Task { await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(7200)])) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 3, launches: [launch(3600)]))
        await client.finish()
        await older.value
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.first?.launch.details.plannedTime, now.addingTimeInterval(3600), "Newest source says original time, but pending older reschedule must not overwrite it")
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }
    func testNewerUnknownTimeCancelsBothAlertsDuringSuspendedReschedule() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double?, id: Int = 1) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: offset.map { now.addingTimeInterval($0) }))
        }
        let started = expectation(description: "Reschedule suspended")
        let client = SuspendingNotificationClient(suspendAt: 2) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        try await feature.save(launch(3600), minutesBefore: 5)
        let older = Task { await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(7200)])) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 3, launches: [launch(nil)]))
        await client.finish()
        await older.value
        let value = await feature.snapshot
        XCTAssertNil(value.reminders.first?.launch.details.plannedTime)
        XCTAssertNotNil(value.reminders.first?.issue)
        let active = await client.activeIDs
        XCTAssertTrue(active.isEmpty)

    }
    func testNewerChangedRefreshSupersedesSuspendedReschedule() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double, id: Int = 1) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "Reschedule suspended")
        let client = SuspendingNotificationClient(suspendAt: 2) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        try await feature.save(launch(3600), minutesBefore: 5)
        let older = Task { await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(7200)])) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 3, launches: [launch(10800)]))
        await client.finish()
        await older.value
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.first?.launch.details.plannedTime, now.addingTimeInterval(10800), "Newest source says original time, but pending older reschedule must not overwrite it")
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }
    func testObsoleteSchedulingFailureDoesNotMarkLatestReminderAsFailed() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double, id: Int = 1) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "Reschedule suspended")
        let client = SuspendingNotificationClient(suspendAt: 2) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        try await feature.save(launch(3600), minutesBefore: 5)
        let older = Task { await feature.reconcile(.init(source: .rocketLaunchLive, revision: 2, launches: [launch(7200)])) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 3, launches: [launch(3600)]))
        await client.finish(failing: true)
        await older.value
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.first?.launch.details.plannedTime, now.addingTimeInterval(3600), "Newest source says original time, but pending older reschedule must not overwrite it")
        XCTAssertNil(value.reminders.first?.issue)
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }
    func testConcurrentSavesRespectCapacity() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ id: Int) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(3600)))
        }
        let started = expectation(description: "50th save suspended")
        let client = SuspendingNotificationClient(suspendAt: 50) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        for id in 1...49 { try await feature.save(launch(id), minutesBefore: 5) }
        let first = Task { try await feature.save(launch(50), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        do { try await feature.save(launch(51), minutesBefore: 5) } catch ReminderError.limit { }
        await client.finish()
        let outcome = try await first.value
        XCTAssertEqual(outcome, .saved)
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.count, 50)
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }

    func testFailedPendingAdditionReleasesItsReservedSlot() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ id: Int) -> RocketLaunch {
            .init(id: id, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(3600)))
        }
        let started = expectation(description: "50th save suspended")
        let client = SuspendingNotificationClient(suspendAt: 50) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        for id in 1...49 { try await feature.save(launch(id), minutesBefore: 5) }
        let first = Task { try await feature.save(launch(50), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        do { try await feature.save(launch(51), minutesBefore: 5) } catch ReminderError.limit { }
        await client.finish(failing: true)
        do { _ = try await first.value; XCTFail("Expected scheduling failure") } catch ReminderError.denied { }
        try await feature.save(launch(51), minutesBefore: 5)
        let value = await feature.snapshot
        XCTAssertEqual(value.reminders.count, 50)
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(value.reminders.map(\.notificationID)))
    }
}
private actor SuspendingNotificationClient: LaunchNotificationClient {
    let suspendAt: Int
    let started: @Sendable () -> Void
    private(set) var activeIDs: Set<String> = []
    private(set) var canceled: [String] = []
    var calls = 0
    var continuation: CheckedContinuation<Void, any Error>?
    init(suspendAt: Int, started: @escaping @Sendable () -> Void) { self.suspendAt = suspendAt; self.started = started }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        activeIDs.insert(id)
        calls += 1
        if calls == suspendAt {
            do { try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started() } }
            catch { activeIDs.remove(id); throw error }
        }
    }
    func finish(failing: Bool = false) {
        if failing { continuation?.resume(throwing: ReminderError.denied) }
        else { continuation?.resume() }
        continuation = nil
    }
    func cancel(_ id: String) async { activeIDs.remove(id); canceled.append(id) }
}

@MainActor final class AdditionalConcurrencyReviewTests: XCTestCase {
    func testFirstSaveMustNotCommitTimeSupersededDuringScheduling() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double) -> RocketLaunch {
            .init(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "First save suspended")
        let client = SuspendingNotificationClient(suspendAt: 1) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        let saving = Task { try await feature.save(launch(3600), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [launch(7200)]))
        await client.finish()
        let outcome = try await saving.value
        XCTAssertEqual(outcome, .superseded)
        let snapshot = await feature.snapshot
        XCTAssertTrue(snapshot.reminders.isEmpty)
        let active = await client.activeIDs
        XCTAssertTrue(active.isEmpty)
    }

    func testUnchangedRefreshPreservesPendingFirstSave() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double) -> RocketLaunch {
            .init(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "First save suspended")
        let client = SuspendingNotificationClient(suspendAt: 1) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        let saving = Task { try await feature.save(launch(3600), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [launch(3600)]))
        await client.finish()
        let outcome = try await saving.value
        XCTAssertEqual(outcome, .saved)
        let snapshot = await feature.snapshot
        XCTAssertEqual(snapshot.reminders.first?.launch, launch(3600))
        let active = await client.activeIDs
        XCTAssertEqual(active, Set(snapshot.reminders.map(\.notificationID)))
    }

    func testUnknownTimeSupersedesPendingFirstSave() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double?) -> RocketLaunch {
            .init(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: offset.map { now.addingTimeInterval($0) }))
        }
        let started = expectation(description: "First save suspended")
        let client = SuspendingNotificationClient(suspendAt: 1) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        let saving = Task { try await feature.save(launch(3600), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [launch(nil)]))
        await client.finish()
        let outcome = try await saving.value
        XCTAssertEqual(outcome, .superseded)
        let snapshot = await feature.snapshot
        XCTAssertTrue(snapshot.reminders.isEmpty)
        let active = await client.activeIDs
        XCTAssertTrue(active.isEmpty)
    }

    func testSupersededFirstSaveReturnsOutcomeEvenWhenSchedulingFails() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: Double) -> RocketLaunch {
            .init(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(offset)))
        }
        let started = expectation(description: "First save suspended")
        let client = SuspendingNotificationClient(suspendAt: 1) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        let saving = Task { try await feature.save(launch(3600), minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [launch(7200)]))
        await client.finish(failing: true)
        let outcome = try await saving.value
        XCTAssertEqual(outcome, .superseded)
        let snapshot = await feature.snapshot
        XCTAssertTrue(snapshot.reminders.isEmpty)
        let active = await client.activeIDs
        XCTAssertTrue(active.isEmpty)
    }

    func testViewModelIgnoresDoubleTapAndExplainsSupersededSave() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(3600)))
        let changed = RocketLaunch(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: now.addingTimeInterval(7200)))
        let started = expectation(description: "Save started")
        let finished = expectation(description: "ViewModel finishes")
        let client = SuspendingNotificationClient(suspendAt: 1) { started.fulfill() }
        let feature = RemindersFeature(client: client, now: { now })
        let viewModel = ReminderViewModel(feature: feature)
        viewModel.save(launch, minutesBefore: 5)
        viewModel.save(launch, minutesBefore: 5)
        await fulfillment(of: [started], timeout: 2)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        withObservationTracking { _ = viewModel.isBusy } onChange: { finished.fulfill() }
        await feature.reconcile(.init(source: .rocketLaunchLive, revision: 1, launches: [changed]))
        await client.finish()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.reminders.isEmpty)
    }

    func testPartialInitialLoadRetriesOnlyIdleProvider() async {
        let aStarted = expectation(description: "A started")
        let bStarted = expectation(description: "B started")
        let retryStarted = expectation(description: "B retries")
        let a = ControlledLaunchRepository { _ in aStarted.fulfill() }
        let b = ControlledLaunchRepository { index in if index == 0 { bStarted.fulfill() } else { retryStarted.fulfill() } }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: a), .init(id: .launchLibrary, repository: b)])
        let load = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [aStarted, bStarted], timeout: 2)
        // A commits before the screen disappears; B is still downloading.
        let stream = await feature.snapshots()
        let aLoaded = expectation(description: "A committed")
        let observer = Task {
            for await value in stream {
                if value.sources.first?.phase == .loaded { aLoaded.fulfill(); break }
            }
        }
        await a.complete(0, with: .success([]))
        await fulfillment(of: [aLoaded], timeout: 2)
        await observer.value
        load.cancel()
        await b.complete(0, with: .failure(CancellationError()))
        await load.value
        let retry = Task { await feature.loadIfNeeded() }
        await fulfillment(of: [retryStarted], timeout: 2)
        let count = await b.requestCount
        XCTAssertEqual(count, 2, "Idle provider should resume when the screen loads again")
        if count == 2 { await b.complete(1, with: .success([])) }
        await retry.value
        let aCount = await a.requestCount
        XCTAssertEqual(aCount, 1)
    }
}
