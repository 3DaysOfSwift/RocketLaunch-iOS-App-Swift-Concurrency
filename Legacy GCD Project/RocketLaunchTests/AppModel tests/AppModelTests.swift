import XCTest
@testable import RocketLaunch

/// Deterministic callback tests: no network, sleeps, Tasks or async test functions.
final class GCDFeatureTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)
    private func launch(_ id: Int = 1, time: Date? = nil, name: String = "Mission") -> RocketLaunch {
        RocketLaunch(id: id, name: name, missions: [], estimatedDate: .init(month: nil, day: nil, year: nil),
                     details: .init(provider: "SpaceX", plannedTime: time ?? instant.addingTimeInterval(7200)))
    }
    private func model(_ repo: ControlledRepository, clock: TestClock? = nil,
                       notifications: ControlledNotifications = ControlledNotifications()) -> LaunchScheduleFeature {
        let date = instant
        return LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repo)],
            now: { clock?.read() ?? date }, notificationClient: notifications)
    }
    private func snapshot(_ feature: LaunchScheduleFeature) -> LaunchScheduleSnapshot {
        let done = expectation(description: "snapshot")
        var value = LaunchScheduleSnapshot.initial
        feature.getSnapshot { result in XCTAssertTrue(Thread.isMainThread); value = result; done.fulfill() }
        wait(for: [done], timeout: 3); return value
    }
    private func reminders(_ feature: LaunchScheduleFeature) -> RemindersSnapshot {
        let done = expectation(description: "reminders"); var value = RemindersSnapshot.initial
        feature.getReminderSnapshot { value = $0; done.fulfill() }
        wait(for: [done], timeout: 3); return value
    }
    private func load(_ feature: LaunchScheduleFeature, repo: ControlledRepository, launches: [RocketLaunch]) {
        let started = expectation(description: "started"), done = expectation(description: "loaded")
        repo.onStart = { started.fulfill() }
        feature.refresh { done.fulfill() }
        wait(for: [started], timeout: 3)
        repo.completeLatest(.success(launches))
        wait(for: [done], timeout: 3)
    }
    func testConstructionDoesNotStartNetworkWork() {
        let repo = ControlledRepository()
        let feature = model(repo)
        XCTAssertEqual(snapshot(feature).state, .idle)
        XCTAssertEqual(repo.count, 0)
    }
    func testEarliestLaunchAndIndependentFailure() {
        let a = ControlledRepository(), b = ControlledRepository()
        let date = instant
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: a), .init(id: .spaceX, repository: b)], now: { date })
        let startedA = expectation(description: "A"), startedB = expectation(description: "B"), done = expectation(description: "all")
        a.onStart = { startedA.fulfill() }; b.onStart = { startedB.fulfill() }
        feature.refresh { done.fulfill() }
        wait(for: [startedA, startedB], timeout: 3)
        let first = launch(), later = launch(2, time: instant.addingTimeInterval(9000))
        a.completeLatest(.success([later, first]))
        let partial = snapshot(feature)
        XCTAssertEqual(partial.nextLaunch, first)
        XCTAssertEqual(partial.sources[1].phase, .loading)
        b.completeLatest(.failure(URLError(.cannotConnectToHost)))
        wait(for: [done], timeout: 3)
        let settled = snapshot(feature)
        XCTAssertEqual(settled.nextLaunch, first)
        XCTAssertEqual(settled.sources[1].phase, .failed(.network))
    }
    func testEmptyAndElapsedLaunchesHaveNoNext() {
        let repo = ControlledRepository(), feature = model(ControlledRepository())
        XCTAssertEqual(snapshot(feature).state, .idle)
        let loaded = model(repo)
        load(loaded, repo: repo, launches: [launch(time: instant.addingTimeInterval(-60))])
        XCTAssertEqual(snapshot(loaded).state, .empty)
        XCTAssertEqual(snapshot(loaded).sources[0].launches.count, 1)
    }
    func testClockExpiryClearsStoredNext() {
        let repo = ControlledRepository(), clock = TestClock(instant)
        let feature = model(repo, clock: clock)
        load(feature, repo: repo, launches: [launch(time: instant.addingTimeInterval(60))])
        XCTAssertNotNil(snapshot(feature).nextLaunch)
        clock.advance(61); feature.updateNextLaunch()
        XCTAssertNil(snapshot(feature).nextLaunch)
        XCTAssertTrue(snapshot(feature).upcomingLaunches.isEmpty)
    }
    func testTwoCallersShareRequestAndOneCancellationPreservesOther() {
        let repo = ControlledRepository()
        let shared = model(repo)
        let started = expectation(description: "started"), firstDone = expectation(description: "first"), secondDone = expectation(description: "second")
        repo.onStart = { started.fulfill() }
        let first = shared.refresh(source: .rocketLaunchLive) { firstDone.fulfill() }
        shared.refresh(source: .rocketLaunchLive) { secondDone.fulfill() }
        wait(for: [started], timeout: 3)
        _ = snapshot(shared) // queue barrier ensures both waiters have registered
        first.cancel(); wait(for: [firstDone], timeout: 3)
        XCTAssertEqual(repo.count, 1); XCTAssertFalse(repo.token(0).isCancelled)
        repo.complete(0, .success([launch()]))
        wait(for: [secondDone], timeout: 3)
        XCTAssertNotNil(snapshot(shared).nextLaunch)
    }
    func testLastCancellationDetachesLateResponseFromNewRequest() {
        let repo = ControlledRepository()
        let shared = model(repo)
        let firstStarted = expectation(description: "first started"), firstDone = expectation(description: "cancelled")
        repo.onStart = { firstStarted.fulfill() }
        let token = shared.refresh { firstDone.fulfill() }
        wait(for: [firstStarted], timeout: 3)
        token.cancel(); wait(for: [firstDone], timeout: 3)
        XCTAssertTrue(repo.token(0).isCancelled)
        XCTAssertEqual(snapshot(shared).sources[0].phase, .idle)
        let secondStarted = expectation(description: "second started"), secondDone = expectation(description: "new")
        repo.onStart = { secondStarted.fulfill() }
        shared.refresh { secondDone.fulfill() }
        wait(for: [secondStarted], timeout: 3)
        let newer = launch(2)
        repo.complete(1, .success([newer])); wait(for: [secondDone], timeout: 3)
        repo.complete(0, .success([launch()]))
        XCTAssertEqual(snapshot(shared).nextLaunch, newer)
    }
    func testAlreadyCancelledHandleFinishesExactlyOnce() {
        let repo = ControlledRepository(), feature = model(repo)
        let done = expectation(description: "done")
        let token = feature.refresh { done.fulfill() }
        token.cancel(); token.cancel()
        wait(for: [done], timeout: 3)
        XCTAssertEqual(snapshot(feature).sources[0].phase, .idle)
    }
    func testCooldownPreventsRepeatRequest() {
        let repo = ControlledRepository(), date = instant
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repo, minimumRefreshInterval: 300)], now: { date })
        load(feature, repo: repo, launches: [launch()])
        let done = expectation(description: "cooldown")
        feature.refresh { done.fulfill() }; wait(for: [done], timeout: 3)
        XCTAssertEqual(repo.count, 1)
    }
    func testObserverReplaysOnMainAndCancellationSuppressesDelivery() {
        let repo = ControlledRepository(), feature = model(repo)
        let initial = expectation(description: "replay")
        var count = 0
        let token = feature.observe { value in
            XCTAssertTrue(Thread.isMainThread); count += 1
            if value.revision == 0 { initial.fulfill() }
        }
        wait(for: [initial], timeout: 3); token.cancel()
        load(feature, repo: repo, launches: [launch()])
        XCTAssertEqual(count, 1)
    }
    func testFailureRetainsCacheAndRetryRecovers() {
        let repo = ControlledRepository(), feature = model(repo)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let started = expectation(description: "retry"), done = expectation(description: "failed")
        repo.onStart = { started.fulfill() }; feature.refresh { done.fulfill() }
        wait(for: [started], timeout: 3); repo.completeLatest(.failure(URLError(.notConnectedToInternet)))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(snapshot(feature).state, .failed(.offline, previous: value))
        load(feature, repo: repo, launches: [launch(2)])
        XCTAssertEqual(snapshot(feature).state, .loaded(launch(2)))
    }
    func testChangesAppearOnlyAfterChangedDownload() {
        let repo = ControlledRepository(), feature = model(repo)
        load(feature, repo: repo, launches: [launch()]); XCTAssertTrue(snapshot(feature).updates.isEmpty)
        load(feature, repo: repo, launches: [launch(name: "Updated mission")])
        XCTAssertEqual(snapshot(feature).updates.count, 1)
        XCTAssertEqual(snapshot(feature).operators.first?.name, "SpaceX")
    }
    func testReminderUsesLatestCacheRecordAndCompletesOnMain() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let old = launch(); load(feature, repo: repo, launches: [old])
        let current = launch(time: instant.addingTimeInterval(9000)); load(feature, repo: repo, launches: [current])
        let started = expectation(description: "schedule"), done = expectation(description: "save")
        notifications.onSchedule = { started.fulfill() }
        feature.setReminder(for: old.id, minutesBefore: 15) { result in
            XCTAssertTrue(Thread.isMainThread); XCTAssertEqual(try? result.get(), .saved); done.fulfill()
        }
        wait(for: [started], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.launch, current)
        XCTAssertEqual(reminders(feature).reminders.first?.status, .pending)
        notifications.complete(0, .success(())); wait(for: [done], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.status, .scheduled)
    }
    func testNewReminderWinsWhenOldSchedulingFinishesLast() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let first = expectation(description: "first scheduled"), second = expectation(description: "second scheduled")
        let oldDone = expectation(description: "old done"), newDone = expectation(description: "new done")
        notifications.onSchedule = { first.fulfill() }
        feature.setReminder(for: value.id, minutesBefore: 15) { result in XCTAssertEqual(try? result.get(), .superseded); oldDone.fulfill() }
        wait(for: [first], timeout: 3)
        notifications.onSchedule = { second.fulfill() }
        feature.setReminder(for: value.id, minutesBefore: 5) { result in XCTAssertEqual(try? result.get(), .saved); newDone.fulfill() }
        wait(for: [second], timeout: 3)
        notifications.complete(1, .success(())); wait(for: [newDone], timeout: 3)
        notifications.complete(0, .success(())); wait(for: [oldDone], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.minutesBefore, 5)
        XCTAssertTrue(notifications.cancelled.contains(notifications.identifier(0)))
    }
    func testRemovalDuringSchedulingCannotRestoreReminder() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let started = expectation(description: "started"), done = expectation(description: "save"), removed = expectation(description: "removed")
        notifications.onSchedule = { started.fulfill() }
        feature.setReminder(for: value.id, minutesBefore: 15) { result in XCTAssertEqual(try? result.get(), .superseded); done.fulfill() }
        wait(for: [started], timeout: 3)
        feature.removeReminder(value.id) { removed.fulfill() }; wait(for: [removed], timeout: 3)
        notifications.complete(0, .success(())); wait(for: [done], timeout: 3)
        XCTAssertTrue(reminders(feature).reminders.isEmpty)
    }
    func testReminderFailureIsExplicit() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let started = expectation(description: "started"), done = expectation(description: "denied")
        notifications.onSchedule = { started.fulfill() }
        feature.setReminder(for: value.id, minutesBefore: 15) { result in
            if case .success = result { XCTFail("Expected permission failure") }; done.fulfill()
        }
        wait(for: [started], timeout: 3); notifications.complete(0, .failure(ReminderError.denied))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.status, .failed)
    }
    func testUnknownLaunchDoesNotScheduleNotification() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let done = expectation(description: "invalid")
        feature.setReminder(for: "missing", minutesBefore: 15) { result in
            if case .success = result { XCTFail("Expected missing launch") }; done.fulfill()
        }
        wait(for: [done], timeout: 3); XCTAssertEqual(notifications.count, 0)
    }
    func testBusinessCalculationRunsOffMainQueue() {
        let repo = ControlledRepository(), date = instant
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repo)], now: {
            XCTAssertFalse(Thread.isMainThread)
            return date
        })
        load(feature, repo: repo, launches: [launch()])
        XCTAssertNotNil(snapshot(feature).nextLaunch)
    }
    func testViewModelReceivesCallbackSnapshot() {
        let repo = ControlledRepository(), feature = model(repo)
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.startObserving()
        defer { viewModel.stopObserving(); viewModel.cancelRefresh() }
        let value = launch()
        load(feature, repo: repo, launches: [value])
        let synced = expectation(description: "view model")
        viewModel.synchronize { synced.fulfill() }
        wait(for: [synced], timeout: 3)
        XCTAssertEqual(viewModel.currentLaunch, value)
        XCTAssertEqual(viewModel.operators.first?.name, "SpaceX")
    }
    func testInvalidLeadTimeDoesNotStartExternalEffect() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let done = expectation(description: "invalid lead time")
        feature.setReminder(for: value.id, minutesBefore: 7) { result in
            guard case .failure(ReminderError.invalidLeadTime) = result else { XCTFail("Expected invalid lead time"); done.fulfill(); return }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertTrue(reminders(feature).reminders.isEmpty)
        XCTAssertEqual(notifications.count, 0)
    }
    func testRefreshReplacesPendingReminderWithoutRestoringOldID() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), feature = model(repo, notifications: notifications)
        let old = launch(); load(feature, repo: repo, launches: [old])
        let first = expectation(description: "first scheduled"), replacement = expectation(description: "replacement scheduled"), saved = expectation(description: "original save settled")
        notifications.onSchedule = { first.fulfill() }
        feature.setReminder(for: old.id, minutesBefore: 15) { result in
            XCTAssertEqual(try? result.get(), .superseded); saved.fulfill()
        }
        wait(for: [first], timeout: 3)
        notifications.onSchedule = { replacement.fulfill() }
        let current = launch(time: instant.addingTimeInterval(10_000))
        load(feature, repo: repo, launches: [current])
        wait(for: [replacement], timeout: 3)
        notifications.complete(1, .success(()))
        notifications.complete(0, .success(()))
        wait(for: [saved], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.launch, current)
        XCTAssertEqual(reminders(feature).reminders.first?.status, .scheduled)
        XCTAssertEqual(reminders(feature).reminders.first?.notificationID, notifications.identifier(1))
    }
    func testNotificationFinishingAfterFireDateCannotReportSaved() {
        let repo = ControlledRepository(), notifications = ControlledNotifications(), clock = TestClock(instant)
        let feature = model(repo, clock: clock, notifications: notifications)
        let value = launch(); load(feature, repo: repo, launches: [value])
        let started = expectation(description: "schedule"), done = expectation(description: "expired")
        notifications.onSchedule = { started.fulfill() }
        feature.setReminder(for: value.id, minutesBefore: 15) { result in
            if case .success = result { XCTFail("An expired reminder cannot be confirmed") }
            done.fulfill()
        }
        wait(for: [started], timeout: 3)
        clock.advance(8000)
        notifications.complete(0, .success(())); wait(for: [done], timeout: 3)
        XCTAssertEqual(reminders(feature).reminders.first?.status, .failed)
    }

}

final class ControlledRepository: LaunchRepository {
    private let lock = NSLock()
    private var callbacks: [(Result<[RocketLaunch], Error>) -> Void] = []
    private var tokens: [CancellationToken] = []
    private var started: (() -> Void)?
    var onStart: (() -> Void)? { get { lock.lock(); defer { lock.unlock() }; return started } set { lock.lock(); started = newValue; lock.unlock() } }
    var count: Int { lock.lock(); defer { lock.unlock() }; return callbacks.count }
    func token(_ index: Int) -> CancellationToken { lock.lock(); defer { lock.unlock() }; return tokens[index] }
    func fetchUpcomingLaunches(completion: @escaping (Result<[RocketLaunch], Error>) -> Void) -> CancellationToken {
        let token = CancellationToken()
        lock.lock(); callbacks.append(completion); tokens.append(token); let start = started; lock.unlock()
        start?(); return token
    }
    func complete(_ index: Int, _ result: Result<[RocketLaunch], Error>) {
        lock.lock(); let callback = callbacks[index]; lock.unlock(); callback(result)
    }
    func completeLatest(_ result: Result<[RocketLaunch], Error>) { complete(count - 1, result) }
}
private final class TestClock {
    private let lock = NSLock(); private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}
private final class ControlledNotifications: LaunchNotificationClient {
    private let lock = NSLock()
    private var callbacks: [(Result<Void, Error>) -> Void] = []
    private var ids: [String] = [], removed: [String] = []
    private var started: (() -> Void)?
    var onSchedule: (() -> Void)? { get { lock.lock(); defer { lock.unlock() }; return started } set { lock.lock(); started = newValue; lock.unlock() } }
    var count: Int { lock.lock(); defer { lock.unlock() }; return ids.count }
    var cancelled: [String] { lock.lock(); defer { lock.unlock() }; return removed }
    func identifier(_ index: Int) -> String { lock.lock(); defer { lock.unlock() }; return ids[index] }
    func schedule(id: String, title: String, date: Date, askPermission: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock(); ids.append(id); callbacks.append(completion); let start = started; lock.unlock(); start?()
    }
    func cancel(_ id: String, completion: @escaping () -> Void) { lock.lock(); removed.append(id); lock.unlock(); completion() }
    func complete(_ index: Int, _ result: Result<Void, Error>) { lock.lock(); let callback = callbacks[index]; lock.unlock(); callback(result) }
}
