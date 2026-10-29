import XCTest
import Observation
@testable import RocketLaunch

final class AppModelTests: XCTestCase {
    @MainActor func testApplicationDelegateCanBeReleasedFromSynchronousLifecycle() {
        weak var releasedDelegate: RocketLaunchAppDelegate?
        do {
            let delegate = RocketLaunchAppDelegate()
            releasedDelegate = delegate
            XCTAssertNotNil(releasedDelegate)
        }
        XCTAssertNil(releasedDelegate)
    }

    @MainActor func testRetainsProvidedFeatureWithoutStartingWork() async {
        let repository = PresentationLaunchRepository()
        let feature = LaunchScheduleFeature(repository: repository)
        let appModel = AppModel(launchScheduleFeature: feature)
        XCTAssertTrue(appModel.launchScheduleFeature === feature)
        let requests = await repository.requestCount
        XCTAssertEqual(requests, 0)
    }
    @MainActor func testLaunchLoadsOnceAndScreenRefreshRemainsAvailable() async {
        let repository = PresentationLaunchRepository()
        let feature = LaunchScheduleFeature(repository: repository)
        let model = AppModel(launchScheduleFeature: feature)
        await model.applicationDidFinishLaunching()
        await model.applicationDidFinishLaunching()
        let initialRequests = await repository.requestCount
        XCTAssertEqual(initialRequests, 1)
        await feature.refresh()
        let refreshedRequests = await repository.requestCount
        XCTAssertEqual(refreshedRequests, 2)
    }

    @MainActor func testRepeatedLaunchDoesNotDuplicateActiveDownload() async {
        let began = expectation(description: "Launch download began")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: {})
        let feature = LaunchScheduleFeature(repository: repository)
        let model = AppModel(launchScheduleFeature: feature)
        var launchFinished = false
        let launch = Task {
            await model.applicationDidFinishLaunching()
            launchFinished = true
        }
        await waitFor([began])
        await model.applicationDidFinishLaunching()
        XCTAssertFalse(launchFinished)
        let requests = await repository.requestCount
        XCTAssertEqual(requests, 1)
        await repository.complete(0)
        await launch.value
        XCTAssertTrue(launchFinished)
        XCTAssertEqual(feature.state, .empty)
    }

    @MainActor func testLeavingScreenDoesNotCancelApplicationLaunchDownload() async {
        let began = expectation(description: "Launch download began")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: {})
        let feature = LaunchScheduleFeature(repository: repository)
        let model = AppModel(launchScheduleFeature: feature)
        let launch = Task { await model.applicationDidFinishLaunching() }
        await waitFor([began])
        let screen = LaunchScheduleViewModel(feature: feature)
        let refresh = screen.requestRefresh()
        screen.cancelRefresh()
        await refresh.value
        await repository.complete(0)
        await launch.value
        let requests = await repository.requestCount
        let cancellations = await repository.cancellations
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(cancellations[0], false)
        XCTAssertEqual(feature.state, .empty)
    }

    @MainActor func testActiveLifecycleRefreshesTimeWithoutDownloadingAgainAndCancelsPromptly() async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let repository = PresentationLaunchRepository()
        let feature = LaunchScheduleFeature(sources: [
            .init(id: .launchLibrary, repository: repository, minimumRefreshInterval: 60)
        ], now: { clock.read() })
        let model = AppModel(launchScheduleFeature: feature)
        await model.applicationDidFinishLaunching()
        XCTAssertNotNil(feature.sources.first?.nextRefreshAt)
        clock.advance(61)
        let updated = expectation(description: "Active lifecycle updated time-sensitive state")
        withObservationTracking { _ = feature.sources } onChange: { updated.fulfill() }
        let monitoring = Task { await model.applicationDidBecomeActive() }
        await waitFor([updated])
        XCTAssertNil(feature.sources.first?.nextRefreshAt)
        monitoring.cancel()
        let stopped = expectation(description: "Monitoring cancellation completes")
        let completion = Task { await monitoring.value; stopped.fulfill() }
        await waitFor([stopped])
        await completion.value
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
    }

    @MainActor func testCancelledLifecycleDoesNotUpdateScheduleState() async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let feature = LaunchScheduleFeature(sources: [
            .init(id: .launchLibrary, repository: PresentationLaunchRepository(), minimumRefreshInterval: 60)
        ], now: { clock.read() })
        let model = AppModel(launchScheduleFeature: feature)
        await model.applicationDidFinishLaunching()
        let before = feature.snapshot
        clock.advance(61)
        let monitoring = Task { await model.applicationDidBecomeActive() }
        monitoring.cancel()
        await monitoring.value
        XCTAssertEqual(feature.snapshot, before)
    }

    @available(iOS 26.0, *)
    @MainActor func testForegroundCallersShareTimerUntilLastCallerLeaves() async {
        let began = expectation(description: "shared timer sleeping")
        let stopped = expectation(description: "last caller stops timer")
        let sleeper = LifecycleSleeper(onStart: { began.fulfill() }, onStop: { stopped.fulfill() })
        let feature = LaunchScheduleFeature(sources: [], waitForScheduleTick: { try await sleeper.wait() })
        // Immediate tasks register both callers before this test continues.
        let first = Task.immediate { await feature.monitorScheduleTime() }
        let second = Task.immediate { await feature.monitorScheduleTime() }
        await waitFor([began])
        first.cancel()
        await first.value
        let starts = await sleeper.starts
        let stopsBeforeLastCaller = await sleeper.stops
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stopsBeforeLastCaller, 0)
        second.cancel()
        await second.value
        await waitFor([stopped])
        let stops = await sleeper.stops
        XCTAssertEqual(stops, 1)
    }

    @MainActor func testForegroundMonitoringRestartsAfterLastCallerLeaves() async {
        let firstStart = expectation(description: "first timer started")
        let secondStart = expectation(description: "replacement timer started")
        let firstStop = expectation(description: "first timer stopped")
        let secondStop = expectation(description: "replacement timer stopped")
        let sleeper = RestartLifecycleSleeper(
            onStart: { ($0 == 1 ? firstStart : secondStart).fulfill() },
            onStop: { ($0 == 1 ? firstStop : secondStop).fulfill() })
        let feature = LaunchScheduleFeature(sources: [], waitForScheduleTick: { try await sleeper.wait() })
        let first = Task { await feature.monitorScheduleTime() }
        await waitFor([firstStart])
        first.cancel()
        await first.value
        await waitFor([firstStop])

        let replacement = Task { await feature.monitorScheduleTime() }
        await waitFor([secondStart])
        replacement.cancel()
        await replacement.value
        await waitFor([secondStop])
        let starts = await sleeper.starts
        XCTAssertEqual(starts, 2)
    }

    @MainActor func testIndependentApplicationGraphsDoNotShareFeatureRequests() async {
        let a = PresentationLaunchRepository()
        let firstFeature = LaunchScheduleFeature(repository: a)
        let b = PresentationLaunchRepository()
        let secondFeature = LaunchScheduleFeature(repository: b)
        let first = AppModel(launchScheduleFeature: firstFeature)
        _ = AppModel(launchScheduleFeature: secondFeature)
        await first.launchScheduleFeature.refresh()
        let aCount = await a.requestCount
        XCTAssertEqual(aCount, 1)
        let bCount = await b.requestCount
        XCTAssertEqual(bCount, 0)
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
        var filters = LaunchBrowseQuery()
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
        let projection13 = feature.snapshot
        XCTAssertTrue(projection13.updates.isEmpty)
        await feature.refresh()
        let projection14 = feature.snapshot
        XCTAssertTrue(projection14.updates.isEmpty)
        await feature.refresh()
        let projection15 = feature.snapshot
        XCTAssertEqual(projection15.updates.count, 1)
        let projection16 = feature.snapshot
        XCTAssertTrue(projection16.updates[0].timeChanged)
        let projection17 = feature.snapshot
        XCTAssertEqual(projection17.updates[0].previous.details.plannedTime, now.addingTimeInterval(7200))
        let projection18 = feature.snapshot
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
        let initial = feature.snapshot
        feature.updateNextLaunch()
        let stillInitial = feature.snapshot
        XCTAssertEqual(stillInitial, initial)
        await feature.refresh()
        let loaded = feature.snapshot
        for _ in 0..<10 { feature.updateNextLaunch() }
        let unchanged = feature.snapshot
        XCTAssertEqual(unchanged, loaded)
    }
    func testCooldownExpiryPublishesEvenWithoutNewLaunches() async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: SequenceLaunchRepository([[]]), minimumRefreshInterval: 300)], now: { clock.read() })
        await feature.refresh()
        let loaded = feature.snapshot
        clock.advance(60)
        feature.updateNextLaunch()
        let unchanged = feature.snapshot
        XCTAssertEqual(unchanged, loaded)
        clock.advance(240)
        feature.updateNextLaunch()
        let expired = feature.snapshot
        XCTAssertNil(expired.sources.first?.nextRefreshAt)
        XCTAssertGreaterThan(expired.revision, loaded.revision)
    }
    func testEachSubscriberReceivesInitialAndFinalSnapshots() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let firstStream = feature.snapshots()
        let secondStream = feature.snapshots()
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
        let stream = feature.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        await feature.refresh()
        for _ in 0..<10 { feature.updateNextLaunch() }
        let expected = feature.snapshot
        let received = await iterator.next()
        XCTAssertEqual(received, expected)
    }
    func testCancelingOneSubscriberDoesNotStopAnother() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let firstStream = feature.snapshots()
        let secondStream = feature.snapshots()
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
    func testFeaturePublishesObservableSourceChangesOnMainActor() async {
        let feature = LaunchScheduleFeature(repository: SequenceLaunchRepository([[]]))
        let changed = expectation(description: "observable source state changed")
        withObservationTracking {
            _ = feature.sources
        } onChange: {
            MainActor.assertIsolated()
            changed.fulfill()
        }
        await feature.refresh()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(feature.sources.first?.phase, .loaded)
        XCTAssertEqual(feature.state, .empty)
    }

    func testFeatureStateUsesMainActorAndRepositoryUsesItsOwnActor() async {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: SequenceLaunchRepository([[]]))], now: {
            MainActor.assertIsolated()
            return date
        })
        await feature.refresh()
        let value = feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }
}

private actor SequenceLaunchRepository: LaunchRepository {
    var pages: [[RocketLaunch]]
    init(_ pages: [[RocketLaunch]]) { self.pages = pages }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        XCTAssertFalse(Thread.isMainThread)
        return pages.removeFirst()
    }
}

@MainActor
final class UnifiedReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func launch(_ offset: Double? = 7200, id: Int = 1, source: LaunchSourceID = .rocketLaunchLive) -> RocketLaunch {
        .init(id: String(id), source: source, name: "Launch \(id)", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil),
              details: .init(plannedTime: offset.map { now.addingTimeInterval($0) }))
    }
    private func model(_ launches: [RocketLaunch], client: any LaunchNotificationClient = ControlledNotifications(), storage: ReminderStorage = .memory, persistence: (any ReminderPersisting)? = nil) async -> (LaunchScheduleFeature, MutableLaunchRepository) {
        let repository = MutableLaunchRepository(launches)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { [now] in
            MainActor.assertIsolated()
            return now
        }, notificationClient: client, reminderStorage: storage, reminderPersistence: persistence)
        await feature.refresh()
        return (feature, repository)
    }
    private func waitForScheduledReminder(_ feature: LaunchScheduleFeature) async {
        let scheduled = expectation(description: "latest reminder scheduled")
        let observer = Task {
            for await value in await feature.reminderSnapshots() {
                if value.reminders.first?.status == .scheduled { scheduled.fulfill(); return }
            }
        }
        await fulfillment(of: [scheduled], timeout: 2)
        observer.cancel()
    }

    func testOverlappingReminderReadsShareStorageLoad() async {
        let began = expectation(description: "storage load suspended")
        let persistence = ControlledReminderPersistence(holdLoad: true, started: { began.fulfill() })
        let feature = LaunchScheduleFeature(sources: [], reminderPersistence: persistence)
        let first = Task { await feature.reminderSnapshot }
        await fulfillment(of: [began], timeout: 2)
        let second = Task { await feature.reminderSnapshot }
        await persistence.resumeLoad()
        let one = await first.value
        let two = await second.value
        let loads = await persistence.loads
        XCTAssertEqual(one, two)
        XCTAssertEqual(loads, 1)
    }

    func testReminderWritesStayOrderedWhileStorageIsSuspended() async throws {
        let began = expectation(description: "first storage write suspended")
        let persistence = ControlledReminderPersistence(started: { began.fulfill() })
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client, persistence: persistence)
        let id = launch().id
        let first = Task { try await feature.setReminder(for: id, minutesBefore: 15) }
        await fulfillment(of: [began], timeout: 2)
        let laterPublished = expectation(description: "new desired reminder published")
        let observer = Task {
            for await value in await feature.reminderSnapshots() {
                if value.reminders.first?.minutesBefore == 5 {
                    laterPublished.fulfill()
                    return
                }
            }
        }
        let second = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [laterPublished], timeout: 2)
        observer.cancel()
        let writesBeforeRelease = await persistence.writes
        let notificationCallsBeforeRelease = await client.calls
        XCTAssertEqual(writesBeforeRelease.count, 1)
        XCTAssertEqual(notificationCallsBeforeRelease, 0)

        await persistence.resumeSave()
        let firstResult = try await first.value
        let secondResult = try await second.value
        let writes = await persistence.writes
        let saved = await feature.reminderSnapshot
        let active = await client.active
        XCTAssertEqual(firstResult, .superseded)
        XCTAssertEqual(secondResult, .saved)
        XCTAssertEqual(writes.map { $0.first?.minutesBefore }, [15, 5, 5])
        XCTAssertEqual(writes.last, saved.reminders)
        XCTAssertEqual(saved.reminders.first?.status, .scheduled)
        XCTAssertEqual(active, Set(saved.reminders.map(\.notificationID)))
    }

    func testNewRefreshDownloadsWhilePreviousNotificationIsSuspended() async throws {
        let started = expectation(description: "reschedule suspended")
        let client = ControlledNotifications(hold: 2) { _ in started.fulfill() }
        let (feature, repository) = await model([launch(3600)], client: client)
        try await feature.setReminder(for: launch().id, minutesBefore: 5)
        await repository.set([launch(7200)])
        let first = Task { await feature.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await repository.set([launch(10800)])
        let refreshed = expectation(description: "new download completes before old notification")
        let second = Task { await feature.refresh(); refreshed.fulfill() }
        await fulfillment(of: [refreshed], timeout: 2)
        let snapshot = feature.snapshot
        XCTAssertEqual(snapshot.sources.first?.launches.first, launch(10800))
        await client.finish()
        await first.value
        await second.value
        let settled = expectation(description: "obsolete notification cleaned up")
        await client.onNextCancel { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        await waitForScheduledReminder(feature)
        let desired = await feature.reminderSnapshot
        let active = await client.active
        XCTAssertEqual(desired.reminders.first?.launch, launch(10800))
        XCTAssertEqual(active, Set(desired.reminders.map(\.notificationID)))
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
        await waitForScheduledReminder(feature)
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
        // Refresh must finish even though its notification delivery is suspended.
        let refreshed = expectation(description: "refresh completes before notification")
        let completion = Task { await updating.value; refreshed.fulfill() }
        await fulfillment(of: [refreshed], timeout: 2)
        completion.cancel()
        await repository.set([launch(3600)]); await feature.refresh()
        await client.finish()
        // Wait until the older effect has completed cleanup using the client callback.
        let settled = expectation(description: "obsolete effect canceled")
        await client.onNextCancel { settled.fulfill() }
        // onNextCancel also fires immediately if cancellation already happened twice.
        await fulfillment(of: [settled], timeout: 2)
        await waitForScheduledReminder(feature)
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
    func testCancellationBeforeDispatchPreservesExistingReminderAndAllowsRetry() async throws {
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        try await feature.setReminder(for: id, minutesBefore: 15)
        let original = await feature.reminderSnapshot
        let originalNotifications = await client.active

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await feature.setReminder(for: id, minutesBefore: 5)
        }
        do {
            _ = try await cancelled.value
            XCTFail("A request cancelled before dispatch must not replace a reminder")
        } catch is CancellationError {}

        let unchanged = await feature.reminderSnapshot
        let notifications = await client.active
        let calls = await client.calls
        let cancellations = await client.cancelCount
        XCTAssertEqual(unchanged, original)
        XCTAssertEqual(notifications, originalNotifications)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cancellations, 0)

        let result = try await feature.setReminder(for: id, minutesBefore: 5)
        let retried = await feature.reminderSnapshot
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(retried.reminders.first?.minutesBefore, 5)
        XCTAssertEqual(retried.reminders.first?.status, .scheduled)
    }

    func testRemovalCancelledWhileLoadingDoesNotDeleteRestoredReminder() async {
        let started = expectation(description: "Loading saved reminder")
        let stored = LaunchReminder(launch: launch(), notificationID: "existing", minutesBefore: 15,
            fireDate: now.addingTimeInterval(600), issue: nil)
        let persistence = ControlledReminderPersistence(holdLoad: true, initial: [stored]) { started.fulfill() }
        let client = ControlledNotifications()
        let feature = LaunchScheduleFeature(sources: [], notificationClient: client, reminderPersistence: persistence)
        let removal = Task { await feature.removeReminder(stored.id) }
        await fulfillment(of: [started], timeout: 2)
        removal.cancel()
        await persistence.resumeLoad()
        await removal.value
        XCTAssertEqual(feature.reminders, [stored])
        let writes = await persistence.writes
        let cancellations = await client.cancelCount
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(cancellations, 0)
    }

    func testCancelledRemovalPreservesReminderAndNotificationUntilRetry() async throws {
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        try await feature.setReminder(for: id, minutesBefore: 15)
        let original = await feature.reminderSnapshot
        let originalNotifications = await client.active
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await feature.removeReminder(id)
        }
        await cancelled.value
        let unchanged = await feature.reminderSnapshot
        let notifications = await client.active
        let cancellations = await client.cancelCount
        XCTAssertEqual(unchanged, original)
        XCTAssertEqual(notifications, originalNotifications)
        XCTAssertEqual(cancellations, 0)

        await feature.removeReminder(id)
        let removed = await feature.reminderSnapshot
        let remainingNotifications = await client.active
        XCTAssertTrue(removed.reminders.isEmpty)
        XCTAssertTrue(remainingNotifications.isEmpty)
    }

    func testCallerCancellationDoesNotDiscardAcceptedReminder() async throws {
        let started = expectation(description: "notification scheduling suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        let pending = await feature.reminderSnapshot
        XCTAssertEqual(pending.reminders.first?.status, .pending)

        save.cancel()
        // The external service accepts the write despite cancellation of its caller.
        await client.finish()
        let outcome = try await save.value
        let saved = await feature.reminderSnapshot
        let active = await client.active
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(saved.reminders.first?.status, .scheduled)
        XCTAssertEqual(saved.reminders.first?.notificationID, pending.reminders.first?.notificationID)
        XCTAssertEqual(active, Set(saved.reminders.map(\.notificationID)))
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
        await repository.set([launch(10800)]); await feature.refresh(); await waitForScheduledReminder(feature); await client.finish(fail: true)
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
    func testEncodingFailurePreservesPreviouslyStoredReminderBytes() async throws {
        let suite = "rocket-encoding-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ReminderPersistence(storage: .suite(suite))
        let valid = LaunchReminder(launch: launch(), notificationID: "valid", minutesBefore: 5,
            fireDate: now.addingTimeInterval(6900), issue: nil)
        try await storage.save([valid])
        let original = try XCTUnwrap(defaults.data(forKey: "rocketlaunch.reminders.v1"))
        let invalid = LaunchReminder(launch: launch(), notificationID: "invalid", minutesBefore: 5,
            fireDate: Date(timeIntervalSince1970: .infinity), issue: nil)
        do {
            try await storage.save([invalid])
            XCTFail("Expected encoding failure")
        } catch is EncodingError {}
        XCTAssertEqual(defaults.data(forKey: "rocketlaunch.reminders.v1"), original)
        let restored = try await storage.load()
        XCTAssertEqual(restored, [valid])
    }

    func testInitialPersistenceFailureDoesNotScheduleAndCanRetry() async throws {
        let storage = FailingReminderPersistence(failingWrites: [1])
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client, persistence: storage)
        do {
            try await feature.setReminder(for: launch().id, minutesBefore: 5)
            XCTFail("Expected storage error")
        } catch ReminderError.storageWriteFailed {}
        XCTAssertNotNil(feature.reminderWriteError)
        XCTAssertEqual(feature.reminders.first?.status, .failed)
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        let outcome = try await feature.setReminder(for: launch().id, minutesBefore: 5)
        XCTAssertEqual(outcome, .saved)
        XCTAssertNil(feature.reminderWriteError)
        let stored = await storage.records
        XCTAssertEqual(stored, feature.reminders)
    }

    func testFailedReplacementWritePreservesExistingReminderAndNotification() async throws {
        let storage = FailingReminderPersistence(failingWrites: [3])
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client, persistence: storage)
        try await feature.setReminder(for: launch().id, minutesBefore: 15)
        let previous = feature.reminders
        do {
            try await feature.setReminder(for: launch().id, minutesBefore: 5)
            XCTFail("Expected replacement storage error")
        } catch ReminderError.storageWriteFailed {}
        XCTAssertEqual(feature.reminders, previous)
        let active = await client.active
        XCTAssertEqual(active, Set(previous.map(\.notificationID)))
        let stored = await storage.records
        XCTAssertEqual(stored, previous)
        XCTAssertNotNil(feature.reminderWriteError)
    }

    func testFinalPersistenceFailureCancelsInstalledNotification() async throws {
        let storage = FailingReminderPersistence(failingWrites: [2, 3])
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client, persistence: storage)
        do {
            try await feature.setReminder(for: launch().id, minutesBefore: 5)
            XCTFail("Expected final storage error")
        } catch ReminderError.storageWriteFailed {}
        XCTAssertEqual(feature.reminders.first?.status, .failed)
        XCTAssertNotNil(feature.reminderWriteError)
        let active = await client.active
        XCTAssertTrue(active.isEmpty)
        await feature.retryReminderWrite()
        XCTAssertNil(feature.reminderWriteError)
        let stored = await storage.records
        XCTAssertEqual(stored, feature.reminders)
    }

    func testRemovalPersistenceFailureStillCleansNotificationAndCanRetry() async throws {
        let storage = FailingReminderPersistence(failingWrites: [3])
        let client = ControlledNotifications()
        let (feature, _) = await model([launch()], client: client, persistence: storage)
        try await feature.setReminder(for: launch().id, minutesBefore: 5)
        await feature.removeReminder(launch().id)
        XCTAssertTrue(feature.reminders.isEmpty)
        XCTAssertNotNil(feature.reminderWriteError)
        let active = await client.active
        XCTAssertTrue(active.isEmpty)
        await feature.retryReminderWrite()
        XCTAssertNil(feature.reminderWriteError)
        let stored = await storage.records
        XCTAssertTrue(stored.isEmpty)
    }

    func testUnreadableReminderDataIsNotOverwrittenByNewSave() async throws {
        let suite = "rocket-corrupt-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("unreadable saved reminders".utf8)
        defaults.set(original, forKey: "rocketlaunch.reminders.v1")
        let (feature, _) = await model([launch()], storage: .suite(suite))
        do {
            try await feature.setReminder(for: launch().id, minutesBefore: 15)
            XCTFail("Unreadable saved reminders must block a replacement write")
        } catch ReminderError.storageUnavailable {}
        XCTAssertEqual(defaults.data(forKey: "rocketlaunch.reminders.v1"), original)
        let viewModel = ReminderViewModel(feature: feature)
        XCTAssertNotNil(viewModel.storageError)
        await feature.removeReminder(launch().id)
        XCTAssertEqual(defaults.data(forKey: "rocketlaunch.reminders.v1"), original)

        // Simulate storage becoming readable again; retry must restore its contents.
        let stored = LaunchReminder(launch: launch(), notificationID: "existing", minutesBefore: 15,
            fireDate: now.addingTimeInterval(6300), issue: nil)
        let stream = await feature.reminderSnapshots()
        let recovered = expectation(description: "existing subscriber receives restored data")
        let observer = Task {
            for await snapshot in stream {
                if snapshot.reminders == [stored] { recovered.fulfill(); return }
            }
        }
        defer { observer.cancel() }
        defaults.set(try JSONEncoder().encode([stored]), forKey: "rocketlaunch.reminders.v1")
        await viewModel.loadIfNeeded().value
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertNil(viewModel.storageError)
        XCTAssertEqual(viewModel.reminders, [stored])
        let outcome = try await feature.setReminder(for: launch().id, minutesBefore: 5)
        XCTAssertEqual(outcome, .saved)
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
    func testCancelledSchedulingCleansPartialNotificationAndAllowsRetry() async throws {
        let started = expectation(description: "notification scheduling suspended")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let id = launch().id
        let save = Task { try await feature.setReminder(for: id, minutesBefore: 5) }
        await fulfillment(of: [started], timeout: 2)
        save.cancel()
        await client.finishWithCancellationAfterPartialAcceptance()
        do {
            _ = try await save.value
            XCTFail("Cancellation must reach the caller")
        } catch is CancellationError {
            // The model must retain honest state even when the service cancels.
        }
        let failed = await feature.reminderSnapshot
        let activeAfterFailure = await client.active
        XCTAssertEqual(failed.reminders.first?.status, .failed)
        XCTAssertNotNil(failed.reminders.first?.issue)
        XCTAssertTrue(activeAfterFailure.isEmpty)

        let retry = try await feature.setReminder(for: id, minutesBefore: 5)
        let saved = await feature.reminderSnapshot
        let activeAfterRetry = await client.active
        XCTAssertEqual(retry, .saved)
        XCTAssertEqual(saved.reminders.first?.status, .scheduled)
        XCTAssertNil(saved.reminders.first?.issue)
        XCTAssertEqual(activeAfterRetry, Set(saved.reminders.map(\.notificationID)))
    }

    func testDoubleTapDoesNotStartTwoSaves() async {
        let started = expectation(description: "save suspended")
        let finished = expectation(description: "UI command finishes")
        let client = ControlledNotifications(hold: 1) { _ in started.fulfill() }
        let (feature, _) = await model([launch()], client: client)
        let vm = LaunchDetailScreenViewModel(feature: feature)
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
    private var suspendedNotificationID: String?
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
            suspendedNotificationID = id
            try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started(calls) }
        }
        active.insert(id) // Simulate a late external success even after cancel(id).
    }
    func finish(fail: Bool = false) {
        if fail { continuation?.resume(throwing: ReminderError.denied) } else { continuation?.resume() }
        continuation = nil
    }
    func finishWithCancellationAfterPartialAcceptance() {
        if let id = suspendedNotificationID { active.insert(id) }
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        suspendedNotificationID = nil
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
    @available(iOS 26.0, *)
    func testCancellingOneRegisteredCallerPreservesTheOtherCaller() async {
        let began = expectation(description: "shared provider started")
        let finished = expectation(description: "shared provider completed")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        await feature.loadRemindersIfNeeded()

        // Both closures inherit MainActor and start immediately. With storage
        // already loaded, their first suspension is the registered continuation.
        // No cooldown or scheduler delay can impersonate a joined caller here.
        let first = Task.immediate { await feature.refresh(source: .rocketLaunchLive) }
        let second = Task.immediate { await feature.refresh(source: .rocketLaunchLive) }
        await waitFor([began])
        first.cancel()
        await first.value
        XCTAssertEqual(feature.sources.first?.phase, .loading)

        await repository.complete(0)
        await second.value
        await waitFor([finished])
        let count = await repository.requestCount
        let cancellations = await repository.cancellations
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cancellations[0], false)
        XCTAssertEqual(feature.state, .empty)
    }

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
        let value = feature.snapshot
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
        let stream = feature.snapshots()
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
        let stream = feature.snapshots()
        for await value in stream { if value.sources.first?.phase == .loaded { break } }
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
        vm.cancelRefresh()
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
        let value = feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }
}

private actor ControlledReminderPersistence: ReminderPersisting {
    private let initial: [LaunchReminder]
    private let holdLoad: Bool
    private let started: @Sendable () -> Void
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private(set) var loads = 0
    private(set) var writes: [[LaunchReminder]] = []

    init(holdLoad: Bool = false, initial: [LaunchReminder] = [], started: @escaping @Sendable () -> Void) {
        self.initial = initial
        self.holdLoad = holdLoad
        self.started = started
    }
    func load() async -> [LaunchReminder] {
        XCTAssertFalse(Thread.isMainThread)
        loads += 1
        if holdLoad {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                started()
            }
        }
        return initial
    }
    func save(_ reminders: [LaunchReminder]) async {
        XCTAssertFalse(Thread.isMainThread)
        writes.append(reminders)
        if writes.count == 1 {
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
                started()
            }
        }
    }
    func resumeLoad() { loadContinuation?.resume(); loadContinuation = nil }
    func resumeSave() { saveContinuation?.resume(); saveContinuation = nil }
}

private actor LifecycleSleeper {
    private let onStart: @Sendable () -> Void
    private let onStop: @Sendable () -> Void
    private(set) var starts = 0
    private(set) var stops = 0
    init(onStart: @escaping @Sendable () -> Void, onStop: @escaping @Sendable () -> Void) {
        self.onStart = onStart
        self.onStop = onStop
    }
    func wait() async throws {
        starts += 1
        onStart()
        defer { stops += 1; onStop() }
        // The test cancels this sleep; it never waits for this duration to elapse.
        try await Task.sleep(for: .seconds(3600))
    }
}

private actor RestartLifecycleSleeper {
    private let onStart: @Sendable (Int) -> Void
    private let onStop: @Sendable (Int) -> Void
    private(set) var starts = 0
    init(onStart: @escaping @Sendable (Int) -> Void, onStop: @escaping @Sendable (Int) -> Void) {
        self.onStart = onStart
        self.onStop = onStop
    }
    func wait() async throws {
        starts += 1
        let call = starts
        onStart(call)
        defer { onStop(call) }
        try await Task.sleep(for: .seconds(3600))
    }
}

private actor FailingReminderPersistence: ReminderPersisting {
    enum Failure: Error { case write }
    private let failingWrites: Set<Int>
    private var writes = 0
    private(set) var records: [LaunchReminder] = []
    init(failingWrites: Set<Int>) { self.failingWrites = failingWrites }
    func load() -> [LaunchReminder] { records }
    func save(_ reminders: [LaunchReminder]) throws {
        writes += 1
        if failingWrites.contains(writes) { throw Failure.write }
        records = reminders
    }
}
