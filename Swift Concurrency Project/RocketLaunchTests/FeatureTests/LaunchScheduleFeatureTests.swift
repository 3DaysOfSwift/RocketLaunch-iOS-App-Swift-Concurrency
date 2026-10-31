import XCTest
import Observation
@testable import RocketLaunch

final class LaunchScheduleFeatureTests: XCTestCase {

    func testUnavailableCacheLocationReportsFailureForReadsAndWrites() async {
        let cache = LaunchScheduleCache(fileURL: nil)
        do {
            _ = try await cache.load()
            XCTFail("Expected the missing cache location to fail")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile)
        }
        do {
            try await cache.save(.init(source: .rocketLaunchLive, launches: [], fetchedAt: .now))
            XCTFail("Expected the missing cache location to fail")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile)
        }
    }

    @MainActor func testActiveReminderExpiresAtItsFireTimeUsingTheFeatureClock() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let reminder = LaunchReminder(launch: launch, notificationID: "test", minutesBefore: 15,
            fireDate: clock.read().addingTimeInterval(60), issue: nil)
        let feature = LaunchScheduleFeature(sources: [], now: { clock.read() },
            reminderPersistence: ActiveReminderPersistence(reminder))
        await feature.loadRemindersIfNeeded()
        XCTAssertTrue(feature.hasActiveReminder(for: launch.id))
        XCTAssertFalse(feature.hasActiveReminder(for: "missing"))
        clock.advance(60)
        XCTAssertFalse(feature.hasActiveReminder(for: launch.id))
        XCTAssertEqual(feature.reminders, [reminder], "Expiry must not erase reminder history")
    }

    @MainActor func testUnsuccessfulRemindersAreNotReportedAsActive() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let cases: [(LaunchReminder.Status, String?)] = [
            (.pending, nil), (.failed, nil), (.scheduled, "Scheduling failed")
        ]
        for (status, issue) in cases {
            let reminder = LaunchReminder(launch: launch, notificationID: "test", minutesBefore: 15,
                fireDate: date.addingTimeInterval(60), issue: issue, status: status)
            let feature = LaunchScheduleFeature(sources: [], now: { date },
                reminderPersistence: ActiveReminderPersistence(reminder))
            await feature.loadRemindersIfNeeded()
            XCTAssertFalse(feature.hasActiveReminder(for: launch.id), "Unexpected active status: \(status)")
        }
    }
    @MainActor func testElapsedLaunchCannotBecomeNext() async {
        await verifyNextAfterTimePasses(initialOffset: -60, advance: 0)
    }

    @MainActor func testNextExpiresWhenClockPassesFinalCachedLaunch() async {
        await verifyNextAfterTimePasses(initialOffset: 60, advance: 61)
    }

    @MainActor private func verifyNextAfterTimePasses(initialOffset: TimeInterval, advance: TimeInterval) async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launch = RocketLaunch(id: 123, name: "Clock boundary", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: clock.read().addingTimeInterval(initialOffset)))
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { clock.read() })
        let request = Task { await feature.refresh() }
        await waitFor([began])
        await repository.complete(0, with: .success([launch]))
        await request.value
        if initialOffset > 0 {
            let before = feature.snapshot
            XCTAssertEqual(before.nextLaunch?.id, launch.id)
        }
        clock.advance(advance)
        feature.updateNextLaunch()
        let after = feature.snapshot
        XCTAssertNil(after.nextLaunch)
        XCTAssertTrue(after.upcomingLaunches.isEmpty)
        XCTAssertEqual(after.state, .empty)
        XCTAssertEqual(after.sources[0].launches, [launch], "Expiry must not erase the provider cache")
    }

    @MainActor func testConcurrentInitialLoadsShareOneRequestAndLoadedStateIsRetained() async {
        let began = expectation(description: "Initial request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let first = Task { await feature.loadIfNeeded() }
        await waitFor([began])
        let joining = Task { await feature.loadIfNeeded() }
        let pendingCount = await repository.requestCount
        XCTAssertEqual(pendingCount, 1)
        await repository.complete(0, with: .success([]))
        await first.value
        await joining.value
        await feature.loadIfNeeded()
        let settledCount = await repository.requestCount
        XCTAssertEqual(settledCount, 1)
    }

    @MainActor func testCanceledInitialLoadCanBeRetried() async {
        let began = expectation(description: "Initial request")
        let retryBegan = expectation(description: "Retry request")
        let repository = ControlledLaunchRepository { index in (index == 0 ? began : retryBegan).fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let first = Task { await feature.loadIfNeeded() }
        await waitFor([began])
        first.cancel()
        await repository.complete(0, with: .failure(CancellationError()))
        await first.value
        let retry = Task { await feature.loadIfNeeded() }
        await waitFor([retryBegan])
        await repository.complete(1, with: .success([]))
        await retry.value
        let value = feature.snapshot
        XCTAssertEqual(value.state, .empty)
    }

    @MainActor func testConstructionDoesNotFetch() async {
        let repository = ControlledLaunchRepository()
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let projection1 = launchSchedule.snapshot
        XCTAssertEqual(projection1.state, .idle)
        let count = await repository.requestCount
        XCTAssertEqual(count, 0)
    }

    @MainActor func testRefreshStoresAllLaunchesAndSelectsUpcomingCandidate() async throws {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let launches = try LaunchFixtures.launches()
        let task = Task { await launchSchedule.refresh() }
        await waitFor([began])
        let projection2 = launchSchedule.snapshot
        XCTAssertEqual(projection2.state, .loading)
        XCTAssertEqual(projection2.displayedLaunch, nil)
        await repository.complete(0, with: .success(launches))
        await task.value
        let projection3 = launchSchedule.snapshot
        XCTAssertEqual(projection3.state, .loaded)
        XCTAssertEqual(projection3.displayedLaunch, launches[2])
        let projection4 = launchSchedule.snapshot
        XCTAssertEqual(projection4.sources[0].launches, launches)
    }

    @MainActor func testEmptyResponseHasAnHonestEmptyState() async {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let task = Task { await launchSchedule.refresh() }
        await waitFor([began])
        await repository.complete(0, with: .success([]))
        await task.value
        let projection5 = launchSchedule.snapshot
        XCTAssertEqual(projection5.state, .empty)
    }

    @MainActor func testFailuresAreClassifiedForRecovery() async {
        let cases: [(any Error, LaunchLoadFailure)] = [
            (URLError(.notConnectedToInternet), .offline), (URLError(.timedOut), .timedOut),
            (LaunchRepositoryError.httpStatus(503), .server(statusCode: 503)),
            (LaunchRepositoryError.invalidData, .invalidData),
            (LaunchRepositoryError.invalidResponse, .invalidResponse),
            (URLError(.cannotConnectToHost), .network)
        ]
        for (error, failure) in cases {
            let began = expectation(description: "request")
            let repository = ControlledLaunchRepository { _ in began.fulfill() }
            let launchSchedule = LaunchScheduleFeature(repository: repository)
            let task = Task { await launchSchedule.refresh() }
            await waitFor([began])
            await repository.complete(0, with: .failure(error))
            await task.value
            let projection6 = launchSchedule.snapshot
            XCTAssertEqual(projection6.state, .failed)
        XCTAssertEqual(projection6.loadFailure, failure)
        XCTAssertEqual(projection6.displayedLaunch, nil)
        }
    }

    @MainActor func testFailureRetainsLastLaunchAndRetryCanReplaceIt() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let third = expectation(description: "third")
        let repository = ControlledLaunchRepository { index in
            [first, second, third][index].fulfill()
        }
        let launchSchedule = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }) // Before the December 2023 fixture launches.
        let launches = try LaunchFixtures.launches()
        let initial = Task { await launchSchedule.refresh() }
        await waitFor([first]); await repository.complete(0, with: .success([launches[0]])); await initial.value
        let failed = Task { await launchSchedule.refresh() }
        await waitFor([second])
        let projection7 = launchSchedule.snapshot
        XCTAssertEqual(projection7.state, .loading)
        XCTAssertEqual(projection7.displayedLaunch, launches[0])
        await repository.complete(1, with: .failure(URLError(.notConnectedToInternet))); await failed.value
        let projection8 = launchSchedule.snapshot
        XCTAssertEqual(projection8.state, .failed)
        XCTAssertEqual(projection8.loadFailure, .offline)
        XCTAssertEqual(projection8.displayedLaunch, launches[0])
        let retry = Task { await launchSchedule.refresh() }
        await waitFor([third]); await repository.complete(2, with: .success([launches[1]])); await retry.value
        let projection9 = launchSchedule.snapshot
        XCTAssertEqual(projection9.state, .loaded)
        XCTAssertEqual(projection9.displayedLaunch, launches[1])
    }

    @MainActor func testOlderSuccessCannotOverwriteNewerSuccess() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }) // Before the December 2023 fixture launches.
        let launches = try LaunchFixtures.launches()
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        old.cancel(); await old.value
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        await repository.complete(1, with: .success([launches[1]])); await new.value
        await repository.complete(0, with: .success([launches[0]])); await old.value
        let projection10 = launchSchedule.snapshot
        XCTAssertEqual(projection10.state, .loaded)
        XCTAssertEqual(projection10.displayedLaunch, launches[1])
    }

    @MainActor func testOlderFailureCannotOverwriteNewerSuccess() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }) // Before the December 2023 fixture launches.
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        old.cancel(); await old.value
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        await repository.complete(1, with: .success([launch])); await new.value
        await repository.complete(0, with: .failure(URLError(.timedOut))); await old.value
        let projection11 = launchSchedule.snapshot
        XCTAssertEqual(projection11.state, .loaded)
        XCTAssertEqual(projection11.displayedLaunch, launch)
    }

    @MainActor func testCancelledSuccessDoesNotPublishOrLeaveLoadingState() async throws {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let task = Task { await launchSchedule.refresh() }; await waitFor([began])
        task.cancel(); await task.value
        await repository.complete(0, with: .success(try LaunchFixtures.launches())); await task.value
        let projection12 = launchSchedule.snapshot
        XCTAssertEqual(projection12.state, .idle)
    }

    @MainActor func testCancellingReplacementRestoresLastSettledState() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        old.cancel(); await old.value
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        new.cancel()
        await repository.complete(1, with: .failure(CancellationError())); await new.value
        await repository.complete(0, with: .success(try LaunchFixtures.launches())); await old.value
        let projection13 = launchSchedule.snapshot
        XCTAssertEqual(projection13.state, .idle)
    }
}

final class ProgressiveLaunchTests: XCTestCase {
    @MainActor func testFirstSourcePublishesTabsBeforeSecondSourceFinishes() async {
        let aStarted = expectation(description: "A started")
        let bStarted = expectation(description: "B started")
        let published = expectation(description: "first operator published")
        let a = ControlledLaunchRepository { _ in aStarted.fulfill() }
        let b = ControlledLaunchRepository { _ in bStarted.fulfill() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: a), .init(id: .launchLibrary, repository: b)], now: { now })
        let first = launch("1", .rocketLaunchLive, "SpaceX", now.addingTimeInterval(600))
        let second = launch("1", .launchLibrary, "Blue Origin", now.addingTimeInterval(300))
        let task = Task { await feature.refresh() }
        await waitFor([aStarted, bStarted])
        let stream = feature.snapshots()
        let observation = Task {
            for await value in stream where !value.operators.isEmpty {
                published.fulfill()
                return
            }
        }
        defer { observation.cancel() }
        await a.complete(0, with: .success([first]))
        await waitFor([published])
        let projection14 = feature.snapshot
        XCTAssertEqual(projection14.nextLaunch, first)
        let projection15 = feature.snapshot
        XCTAssertEqual(projection15.operators.map(\.name), ["SpaceX"])
        let projection16 = feature.snapshot
        XCTAssertEqual(projection16.sources[1].phase, .loading)
        await b.complete(0, with: .success([second])); await task.value
        let projection17 = feature.snapshot
        XCTAssertEqual(projection17.nextLaunch, second)
        let projection18 = feature.snapshot
        XCTAssertEqual(projection18.operators.map(\.name), ["SpaceX", "Blue Origin"])
        XCTAssertNotEqual(first.id, second.id)
        let projection19 = feature.snapshot
        XCTAssertEqual(projection19.sources[0].launches, [first])
        let projection20 = feature.snapshot
        XCTAssertEqual(projection20.sources[1].launches, [second])
    }

    @MainActor func testFailedSourceDoesNotCancelAnotherSource() async {
        let aStarted = expectation(description: "A")
        let bStarted = expectation(description: "B")
        let a = ControlledLaunchRepository { _ in aStarted.fulfill() }
        let b = ControlledLaunchRepository { _ in bStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: a), .init(id: .launchLibrary, repository: b)])
        let expected = launch("1", .launchLibrary, "SpaceX", Date().addingTimeInterval(600))
        let task = Task { await feature.refresh() }; await waitFor([aStarted, bStarted])
        await a.complete(0, with: .failure(URLError(.timedOut)))
        await b.complete(0, with: .success([expected])); await task.value
        let projection21 = feature.snapshot
        XCTAssertEqual(projection21.sources[0].phase, .failed)
        XCTAssertEqual(projection21.sources[0].failure, .timedOut)
        let projection22 = feature.snapshot
        XCTAssertEqual(projection22.state, .loaded)
        XCTAssertEqual(projection22.displayedLaunch, expected)
    }

    @MainActor func testIndividualRefreshUpdatesStoredNextAndRetainsEmptyOperatorTab() async {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { i in (i == 0 ? first : second).fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let record = launch("1", .rocketLaunchLive, "SpaceX", Date().addingTimeInterval(600))
        let initial = Task { await feature.refresh() }; await waitFor([first])
        await repository.complete(0, with: .success([record])); await initial.value
        let refresh = Task { await feature.refresh(source: .rocketLaunchLive) }; await waitFor([second])
        await repository.complete(1, with: .success([])); await refresh.value
        let projection23 = feature.snapshot
        XCTAssertNil(projection23.nextLaunch)
        let projection24 = feature.snapshot
        XCTAssertEqual(projection24.state, .empty)
        let projection25 = feature.snapshot
        XCTAssertEqual(projection25.operators.map(\.name), ["SpaceX"])
        let projection26 = feature.snapshot
        XCTAssertTrue(projection26.operators[0].launches.isEmpty)
        let projection27 = feature.snapshot
        XCTAssertEqual(projection27.operators[0].sourceIDs, [.rocketLaunchLive])
    }

    @MainActor func testFailedRefreshRetainsRowsAndReportsFailure() async {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { i in (i == 0 ? first : second).fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let record = launch("1", .rocketLaunchLive, "SpaceX", Date().addingTimeInterval(600))
        let initial = Task { await feature.refresh() }; await waitFor([first])
        await repository.complete(0, with: .success([record])); await initial.value
        let refresh = Task { await feature.refresh() }; await waitFor([second])
        await repository.complete(1, with: .failure(URLError(.notConnectedToInternet))); await refresh.value
        let projection28 = feature.snapshot
        XCTAssertEqual(projection28.operators[0].launches, [record])
        let projection29 = feature.snapshot
        XCTAssertEqual(projection29.sources[0].phase, .failed)
        XCTAssertEqual(projection29.sources[0].failure, .offline)
        let projection30 = feature.snapshot
        XCTAssertNil(projection30.nextLaunch)
        let projection31 = feature.snapshot
        XCTAssertEqual(projection31.state, .failed)
        XCTAssertEqual(projection31.loadFailure, .offline)
        XCTAssertEqual(projection31.displayedLaunch, record)
    }

    @MainActor func testStoredNextChangesWhenTimePassesWithoutARequest() async {
        let started = expectation(description: "started")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { clock.read() })
        let first = launch("1", .rocketLaunchLive, "SpaceX", clock.read().addingTimeInterval(60))
        let second = launch("2", .rocketLaunchLive, "SpaceX", clock.read().addingTimeInterval(120))
        let task = Task { await feature.refresh() }; await waitFor([started])
        await repository.complete(0, with: .success([first, second])); await task.value
        let projection32 = feature.snapshot
        XCTAssertEqual(projection32.nextLaunch, first)
        clock.advance(90); feature.updateNextLaunch()
        let projection33 = feature.snapshot
        XCTAssertEqual(projection33.nextLaunch, second)
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
    }

    @MainActor func testEstimatedLaunchesAreSortedWithoutInventingExactTimes() async throws {
        let started = expectation(description: "started")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        func record(_ id: String, _ offset: TimeInterval) -> RocketLaunch {
            .init(id: id, source: .rocketLaunchLive, name: id, missions: [],
                  estimatedDate: .init(month: nil, day: nil, year: nil),
                  details: .init(provider: "SpaceX", sortTime: date.addingTimeInterval(offset)))
        }
        let early = record("early", 100), late = record("late", 200)
        let task = Task { await feature.refresh() }; await waitFor([started])
        await repository.complete(0, with: .success([late, early])); await task.value
        let projection34 = feature.snapshot
        XCTAssertEqual(projection34.operators[0].launches, [early, late])
        let projection35 = feature.snapshot
        XCTAssertNil(projection35.operators[0].launches[0].details.plannedTime)
    }

    @MainActor func testFailedSourceKeepsItsErrorWhenCooldownExpires() async throws {
        let started = expectation(description: "source request started")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: repository, minimumRefreshInterval: 300)], now: { clock.read() })
        let refresh = Task { await feature.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await refresh.value
        let before = try XCTUnwrap(feature.sources.first)
        XCTAssertEqual(before.phase, .failed)
        XCTAssertEqual(before.minimumRefreshInterval, 300)
        XCTAssertEqual(before.failure, .offline)
        XCTAssertNotNil(before.nextRefreshAt)
        clock.advance(301)
        feature.updateNextLaunch()
        let after = try XCTUnwrap(feature.sources.first)
        XCTAssertEqual(after.phase, .failed)
        XCTAssertEqual(after.minimumRefreshInterval, 300)
        XCTAssertEqual(after.failure, .offline)
        XCTAssertNil(after.nextRefreshAt)
        XCTAssertEqual(feature.loadFailure, .offline)
    }

    @MainActor func testSourceCooldownAvoidsDuplicateRequests() async {
        let started = expectation(description: "started")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .launchLibrary, repository: repository, minimumRefreshInterval: 300)])
        let task = Task { await feature.refresh() }; await waitFor([started])
        await repository.complete(0, with: .success([])); await task.value
        await feature.refresh()
        let count = await repository.requestCount
        XCTAssertEqual(count, 1)
    }

    private func launch(_ id: String, _ source: LaunchSourceID, _ name: String, _ date: Date) -> RocketLaunch {
        RocketLaunch(id: id, source: source, name: "Mission", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(provider: name, plannedTime: date))
    }
}

final class OperatorIdentityTests: XCTestCase {
    func testKnownOperatorAliasesShareATabIdentity() {
        XCTAssertEqual(LaunchOperator.key(for: "CASC"), LaunchOperator.key(for: "China Aerospace Science and Technology Corporation"))
        XCTAssertEqual(LaunchOperator.key(for: " SpaceX "), LaunchOperator.key(for: "spacex"))
        XCTAssertEqual(LaunchOperator.canonicalName(nil), "Unknown operator")
    }
}


final class LaunchCountdownTests: XCTestCase {
    func testOnlyExactFutureTimeCanCountDown() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(LaunchDetails(sortTime: now.addingTimeInterval(600)).countdown(at: now), .timeUnconfirmed)
        XCTAssertEqual(LaunchDetails(plannedTime: now.addingTimeInterval(1)).countdown(at: now), .remaining(1))
        XCTAssertEqual(LaunchDetails(plannedTime: now).countdown(at: now), .awaitingUpdate)
        XCTAssertEqual(LaunchDetails(plannedTime: now.addingTimeInterval(-1)).countdown(at: now), .awaitingUpdate)
    }
}

private actor ActiveReminderPersistence: ReminderPersisting {
    private let reminder: LaunchReminder
    init(_ reminder: LaunchReminder) { self.reminder = reminder }
    func load() async -> [LaunchReminder] { [reminder] }
    func save(_ reminders: [LaunchReminder]) async {}
}

final class LaunchScheduleCacheTests: XCTestCase {
    func testBinarySnapshotRoundTripsAllLaunchFieldsAndRejectsTruncation() throws {
        let launch = RocketLaunch(id: "id:123", source: .spaceX, name: "Español 🚀", missions: [
            .init(name: "Mission", description: "Description"), .init(name: "Second", description: nil)
        ], estimatedDate: .init(month: 12, day: nil, year: 2030), details: .init(
            provider: "SpaceX", vehicle: "Falcon", country: "US", site: "Site",
            plannedTime: Date(timeIntervalSinceReferenceDate: -100), sortTime: Date(timeIntervalSinceReferenceDate: 400),
            estimatedDateLabel: "Soon", missionDescription: "Payload",
            watchURL: URL(string: "https://example.org/watch"), detailsURL: URL(string: "https://example.org/details")))
        let input = [SavedLaunchSchedule(source: .spaceX, launches: [launch], fetchedAt: Date(timeIntervalSinceReferenceDate: 500))]
        let data = try BinaryLaunchSchedules.encode(input)
        XCTAssertEqual(try BinaryLaunchSchedules.decode(data), input)
        for length in 0..<data.count {
            XCTAssertThrowsError(try BinaryLaunchSchedules.decode(Data(data.prefix(length))), "Accepted truncated snapshot at \(length)")
        }
        var unknownVersion = data
        unknownVersion[unknownVersion.startIndex] ^= 1
        XCTAssertThrowsError(try BinaryLaunchSchedules.decode(unknownVersion))
        XCTAssertThrowsError(try BinaryLaunchSchedules.decode(data + Data([0])))
    }

    @MainActor func testSavedDownloadSurvivesFeatureRecreationWhenOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 123, name: "Saved launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: now.addingTimeInterval(3600)))
        let onlineStarted = expectation(description: "Online download")
        let online = ControlledLaunchRepository { _ in onlineStarted.fulfill() }
        let first = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: online)],
            cache: LaunchScheduleCache(fileURL: url), now: { now })
        let download = Task { await first.loadIfNeeded() }
        await waitFor([onlineStarted])
        await online.complete(0, with: .success([launch]))
        await download.value
        XCTAssertEqual(first.displayedLaunch, launch)

        let offlineStarted = expectation(description: "Offline refresh")
        let offline = ControlledLaunchRepository { _ in offlineStarted.fulfill() }
        let reopened = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: offline)],
            cache: LaunchScheduleCache(fileURL: url), now: { now })
        let restored = expectation(description: "Cached launch appears")
        let observer = Task { for await snapshot in reopened.snapshots() where snapshot.displayedLaunch == launch { restored.fulfill(); break } }
        let restore = Task { await reopened.loadIfNeeded() }
        await waitFor([offlineStarted, restored])
        observer.cancel()
        XCTAssertEqual(reopened.displayedLaunch, launch)
        await offline.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await restore.value
        XCTAssertEqual(reopened.displayedLaunch, launch)
        XCTAssertEqual(reopened.loadFailure, .offline)
        XCTAssertNotNil(LaunchScheduleViewModel(launchScheduleFeature: reopened).savedScheduleMessage)
    }

    @MainActor func testSavedScheduleAppearsWhenOfflineRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LaunchScheduleCache(fileURL: directory.appendingPathComponent("schedule.dat"))
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 123, name: "Saved launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: date.addingTimeInterval(3600)))
        try await cache.save(.init(source: .rocketLaunchLive, launches: [launch], fetchedAt: date))
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: cache, now: { date })
        let restored = expectation(description: "Cached launch appears")
        let observer = Task { for await snapshot in feature.snapshots() where snapshot.displayedLaunch == launch { restored.fulfill(); break } }
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started, restored])
        observer.cancel()
        XCTAssertEqual(feature.displayedLaunch, launch)
        let viewModel = LaunchScheduleViewModel(launchScheduleFeature: feature)
        XCTAssertNotNil(viewModel.savedScheduleMessage)
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await task.value
        XCTAssertEqual(feature.displayedLaunch, launch)
        XCTAssertEqual(feature.sources.first?.fetchedAt, date)
        XCTAssertEqual(feature.loadFailure, .offline)
        XCTAssertNotNil(viewModel.savedScheduleMessage)
    }

    @MainActor func testNetworkStartsWhileCacheIsLoadingAndOfflineKeepsCachedLaunch() async {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 123, name: "Cached", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: date.addingTimeInterval(3600)))
        let readStarted = expectation(description: "Cache read starts")
        let networkStarted = expectation(description: "Network starts without waiting for cache")
        let cachedAppeared = expectation(description: "Cached launch appears during refresh")
        let cache = DelayedReadLaunchCache(schedules: [.init(source: .rocketLaunchLive, launches: [launch], fetchedAt: date)]) { readStarted.fulfill() }
        let repository = ControlledLaunchRepository { _ in networkStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache, now: { date })
        let observer = Task { for await snapshot in feature.snapshots() where snapshot.displayedLaunch == launch { cachedAppeared.fulfill(); break } }
        let refresh = Task { await feature.loadIfNeeded() }
        await waitFor([readStarted, networkStarted])
        await cache.finishRead()
        await waitFor([cachedAppeared])
        observer.cancel()
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await refresh.value
        XCTAssertEqual(feature.displayedLaunch, launch)
        XCTAssertEqual(feature.loadFailure, .offline)
    }

    @MainActor func testCacheCanArriveAfterAnOfflineFailure() async {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 123, name: "Cached", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil), details: .init(plannedTime: date.addingTimeInterval(3600)))
        let readStarted = expectation(description: "Cache read starts")
        let networkStarted = expectation(description: "Network starts")
        let cachedAppeared = expectation(description: "Cached launch appears after failure")
        let cache = DelayedReadLaunchCache(schedules: [.init(source: .rocketLaunchLive, launches: [launch], fetchedAt: date)]) { readStarted.fulfill() }
        let repository = ControlledLaunchRepository { _ in networkStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache, now: { date })
        let observer = Task { for await snapshot in feature.snapshots() where snapshot.displayedLaunch == launch { cachedAppeared.fulfill(); break } }
        let refresh = Task { await feature.loadIfNeeded() }
        await waitFor([readStarted, networkStarted])
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await refresh.value
        await cache.finishRead()
        await waitFor([cachedAppeared])
        observer.cancel()
        XCTAssertEqual(feature.displayedLaunch, launch)
        XCTAssertEqual(feature.loadFailure, .offline)
    }

    @MainActor func testLateCacheCannotReplaceNewServerData() async {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let old = RocketLaunch(id: 1, name: "Old", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))
        let fresh = RocketLaunch(id: 2, name: "Fresh", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))
        let readStarted = expectation(description: "Cache read starts")
        let networkStarted = expectation(description: "Network starts")
        let cache = DelayedReadLaunchCache(schedules: [.init(source: .rocketLaunchLive, launches: [old], fetchedAt: date)]) { readStarted.fulfill() }
        let repository = ControlledLaunchRepository { _ in networkStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache, now: { date })
        let refresh = Task { await feature.loadIfNeeded() }
        await waitFor([readStarted, networkStarted])
        await repository.complete(0, with: .success([fresh]))
        await refresh.value
        XCTAssertEqual(feature.sources[0].launches, [fresh])
        let stalePublished = expectation(description: "Stale cache must not be published")
        stalePublished.isInverted = true
        let observer = Task { for await snapshot in feature.snapshots() where snapshot.sources.first?.launches == [old] { stalePublished.fulfill(); break } }
        await cache.finishRead()
        await fulfillment(of: [stalePublished], timeout: 0.3)
        observer.cancel()
        XCTAssertEqual(feature.sources[0].launches, [fresh])
    }

    @MainActor func testSuccessfulRefreshIsPersistedForNextLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let cache = LaunchScheduleCache(fileURL: url)
        let began = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([began])
        let launch = RocketLaunch(id: 123, name: "Downloaded launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil))
        await repository.complete(0, with: .success([launch]))
        await task.value
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(restored.first?.launches, [launch])
        XCTAssertEqual(feature.sources[0].launches, [launch])
    }

    @MainActor func testFirstRefreshAfterRestoringCacheDoesNotCreateSessionUpdates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LaunchScheduleCache(fileURL: directory.appendingPathComponent("schedule.dat"))
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        func launch(_ offset: TimeInterval) -> RocketLaunch {
            RocketLaunch(id: 123, name: "Launch", missions: [],
                estimatedDate: .init(month: nil, day: nil, year: nil),
                details: .init(plannedTime: date.addingTimeInterval(offset)))
        }
        try await cache.save(.init(source: .rocketLaunchLive, launches: [launch(3600)], fetchedAt: date))
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: cache, now: { date })
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started])
        await repository.complete(0, with: .success([launch(7200)]))
        await task.value
        XCTAssertTrue(feature.updates.isEmpty, "Changes made before this session must not appear as session updates")
        XCTAssertEqual(feature.displayedLaunch?.details.plannedTime, date.addingTimeInterval(7200))
        XCTAssertNil(LaunchScheduleViewModel(launchScheduleFeature: feature).savedScheduleMessage)
    }

    @MainActor func testCancelledOlderDownloadCannotReplaceNewerCachedSchedule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let first = expectation(description: "First download starts")
        let second = expectation(description: "Replacement download starts")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: LaunchScheduleCache(fileURL: url), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let launches = try LaunchFixtures.launches()
        let old = Task { await feature.refresh() }
        await waitFor([first])
        old.cancel()
        await old.value
        let new = Task { await feature.refresh() }
        await waitFor([second])
        await repository.complete(1, with: .success([launches[1]]))
        await new.value
        await repository.complete(0, with: .success([launches[0]]))
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(feature.sources[0].launches, [launches[1]])
        XCTAssertEqual(restored.first?.launches, [launches[1]])
    }

    func testConcurrentProviderWritesPreserveBothSchedules() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let cache = LaunchScheduleCache(fileURL: url)
        let first = SavedLaunchSchedule(source: .rocketLaunchLive, launches: [], fetchedAt: .now)
        let second = SavedLaunchSchedule(source: .spaceX, launches: [], fetchedAt: .now)
        async let firstWrite: Void = cache.save(first)
        async let secondWrite: Void = cache.save(second)
        _ = try await (firstWrite, secondWrite)
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(Set(restored.map(\.source)), [.rocketLaunchLive, .spaceX])
    }

    @MainActor func testInvalidCacheIsDiscardedSilentlyWhenNetworkIsOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        try Data("invalid cache".utf8).write(to: url)
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: LaunchScheduleCache(fileURL: url))
        let viewModel = LaunchScheduleViewModel(launchScheduleFeature: feature)
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started])
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await task.value
        XCTAssertEqual(feature.loadFailure, .offline)
        XCTAssertNil(viewModel.savedScheduleError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testFailedCacheReadDoesNotStartAnExtraRefresh() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launch = RocketLaunch(id: 123, name: "Saved launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: date.addingTimeInterval(3600)))
        let cache = RetryLaunchCache(schedule: .init(source: .rocketLaunchLive, launches: [launch], fetchedAt: date))
        let first = expectation(description: "First network request")
        let second = expectation(description: "Retry network request")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: cache, now: { date })
        let initial = Task { await feature.loadIfNeeded() }
        await waitFor([first])
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await initial.value
        let initialRequestCount = await repository.requestCount
        XCTAssertEqual(initialRequestCount, 1)
        let retry = Task { await feature.refresh() }
        await waitFor([second])
        XCTAssertNil(feature.displayedLaunch)
        await repository.complete(1, with: .failure(URLError(.notConnectedToInternet)))
        await retry.value
        XCTAssertNil(feature.displayedLaunch)
        XCTAssertEqual(feature.loadFailure, .offline)
        let reads = await cache.readCount
        XCTAssertEqual(reads, 1)
    }

    @MainActor func testReadAndWriteFailureShowOneStorageMessage() async throws {
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: UnavailableLaunchCache())
        let viewModel = LaunchScheduleViewModel(launchScheduleFeature: feature)
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started])
        await repository.complete(0, with: .success([]))
        await task.value
        XCTAssertEqual(viewModel.savedScheduleError, "The current schedule is available, but could not be saved for offline use.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor func testUnreadableCacheRecoversWhenDownloadSucceeds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let original = Data("not JSON".utf8)
        try original.write(to: url)
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            cache: LaunchScheduleCache(fileURL: url))
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started])
        let launch = RocketLaunch(id: 123, name: "Recovered launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil))
        await repository.complete(0, with: .success([launch]))
        await task.value
        XCTAssertEqual(feature.sources[0].launches, [launch])
        XCTAssertNil(feature.savedScheduleWriteError)
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(restored.first?.launches, [launch])
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("schedule.dat.unreadable-") }
        XCTAssertTrue(backups.isEmpty)
    }

    @MainActor func testFreshScheduleAppearsWhileCacheWriteIsPending() async throws {
        let downloadStarted = expectation(description: "Download starts")
        let writeStarted = expectation(description: "Cache write starts")
        let repository = ControlledLaunchRepository { _ in downloadStarted.fulfill() }
        let cache = SuspendedLaunchCache { writeStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([downloadStarted])
        let launch = RocketLaunch(id: 123, name: "Fresh launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))
        await repository.complete(0, with: .success([launch]))
        await waitFor([writeStarted])
        XCTAssertEqual(feature.sources[0].launches, [launch])
        XCTAssertEqual(feature.sources[0].phase, .loaded)
        await cache.finish()
        await task.value
    }

    @MainActor func testNewerRefreshAppearsAndIsCachedAfterPendingOlderWrite() async throws {
        let firstDownload = expectation(description: "First download starts")
        let secondDownload = expectation(description: "Second download starts")
        let writeStarted = expectation(description: "First cache write starts")
        let repository = ControlledLaunchRepository { index in (index == 0 ? firstDownload : secondDownload).fulfill() }
        let cache = OrderedLaunchCache { writeStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let launches = try LaunchFixtures.launches()
        let first = Task { await feature.refresh() }
        await waitFor([firstDownload])
        await repository.complete(0, with: .success([launches[0]]))
        await waitFor([writeStarted])
        let newerDisplayed = expectation(description: "Newer schedule is displayed")
        let snapshots = feature.snapshots()
        let observer = Task {
            for await snapshot in snapshots where snapshot.sources.first?.launches == [launches[1]] {
                newerDisplayed.fulfill()
                return
            }
        }
        defer { observer.cancel() }
        let second = Task { await feature.refresh() }
        await waitFor([secondDownload])
        await repository.complete(1, with: .success([launches[1]]))
        await waitFor([newerDisplayed])
        XCTAssertEqual(feature.sources[0].launches, [launches[1]])
        await cache.finishFirst()
        await first.value
        await second.value
        let saved = await cache.saved
        XCTAssertEqual(saved.map(\.launches), [[launches[0]], [launches[1]]])
    }

    @MainActor func testFailedCacheWriteStillPublishesDownloadedSchedule() async throws {
        let started = expectation(description: "Network request starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let cache = FailingLaunchCache()
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let task = Task { await feature.loadIfNeeded() }
        await waitFor([started])
        let launch = RocketLaunch(id: 123, name: "Not saved", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil))
        await repository.complete(0, with: .success([launch]))
        await task.value
        XCTAssertEqual(feature.sources[0].launches, [launch])
        XCTAssertNil(feature.loadFailure)
        XCTAssertNotNil(feature.savedScheduleWriteError)
        let attempts = await cache.attempts
        XCTAssertEqual(attempts, 2)
    }

    @MainActor func testCacheWriteRetriesOnceAndClearsWarningOnSuccess() async throws {
        let started = expectation(description: "Download starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let cache = TransientLaunchCache()
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let task = Task { await feature.refresh() }
        await waitFor([started])
        let launch = RocketLaunch(id: 123, name: "Fresh launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))
        await repository.complete(0, with: .success([launch]))
        await task.value
        XCTAssertEqual(feature.sources[0].launches, [launch])
        XCTAssertNil(feature.savedScheduleWriteError)
        let attempts = await cache.attempts
        let saved = await cache.saved
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(saved?.launches, [launch])
    }

    @MainActor func testFailedCacheReplacementKeepsPreviousOfflineSchedule() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let launches = try LaunchFixtures.launches()
        let old = SavedLaunchSchedule(source: .rocketLaunchLive, launches: [launches[0]], fetchedAt: date)
        let cache = FailingLaunchCache(existing: [old])
        let started = expectation(description: "Download starts")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], cache: cache)
        let task = Task { await feature.refresh() }
        await waitFor([started])
        await repository.complete(0, with: .success([launches[1]]))
        await task.value
        XCTAssertEqual(feature.sources[0].launches, [launches[1]])
        let saved = await cache.load()
        XCTAssertEqual(saved, [old])
        XCTAssertNotNil(feature.savedScheduleWriteError)
    }

    func testSchedulesSurviveReopeningAndUpdateIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let first = SavedLaunchSchedule(source: .rocketLaunchLive, launches: [], fetchedAt: Date(timeIntervalSince1970: 1))
        let second = SavedLaunchSchedule(source: .spaceX, launches: [], fetchedAt: Date(timeIntervalSince1970: 2))
        let replacement = SavedLaunchSchedule(source: .rocketLaunchLive, launches: [], fetchedAt: Date(timeIntervalSince1970: 3))
        let cache = LaunchScheduleCache(fileURL: url)
        try await cache.save(first)
        try await cache.save(second)
        try await cache.save(replacement)
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(Set(restored.map(\.source)), [.rocketLaunchLive, .spaceX])
        XCTAssertEqual(restored.first(where: { $0.source == .rocketLaunchLive }), replacement)
        XCTAssertEqual(restored.first(where: { $0.source == .spaceX }), second)
    }

    func testCorruptFileIsDiscardedAndFreshDownloadsCanBeSaved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.dat")
        let original = Data("not JSON".utf8)
        try original.write(to: url)
        let cache = LaunchScheduleCache(fileURL: url)
        let replacement = SavedLaunchSchedule(source: .spaceX, launches: [], fetchedAt: .now)
        try await cache.save(replacement)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("schedule.dat.unreadable-") }
        XCTAssertTrue(backups.isEmpty)
        let restored = try await LaunchScheduleCache(fileURL: url).load()
        XCTAssertEqual(restored, [replacement])
    }
}

private actor DelayedReadLaunchCache: LaunchScheduleCaching {
    private let schedules: [SavedLaunchSchedule]
    private let onRead: @Sendable () -> Void
    private var pending: CheckedContinuation<Void, Never>?
    init(schedules: [SavedLaunchSchedule], onRead: @escaping @Sendable () -> Void) { self.schedules = schedules; self.onRead = onRead }
    func load() async -> [SavedLaunchSchedule] {
        await withCheckedContinuation { continuation in pending = continuation; onRead() }
        return schedules
    }
    func save(_ schedule: SavedLaunchSchedule) {}
    func finishRead() { pending?.resume(); pending = nil }
}

private actor FailingLaunchCache: LaunchScheduleCaching {
    private(set) var attempts = 0
    private let existing: [SavedLaunchSchedule]
    init(existing: [SavedLaunchSchedule] = []) { self.existing = existing }
    func load() -> [SavedLaunchSchedule] { existing }
    func save(_ schedule: SavedLaunchSchedule) throws { attempts += 1; throw CocoaError(.fileWriteNoPermission) }
}

private actor TransientLaunchCache: LaunchScheduleCaching {
    private(set) var attempts = 0
    private(set) var saved: SavedLaunchSchedule?
    func load() -> [SavedLaunchSchedule] { [] }
    func save(_ schedule: SavedLaunchSchedule) throws {
        attempts += 1
        if attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
        saved = schedule
    }
}

private actor SuspendedLaunchCache: LaunchScheduleCaching {
    private let onSave: @Sendable () -> Void
    private var pending: CheckedContinuation<Void, Never>?
    init(onSave: @escaping @Sendable () -> Void) { self.onSave = onSave }
    func load() -> [SavedLaunchSchedule] { [] }
    func save(_ schedule: SavedLaunchSchedule) async throws {
        await withCheckedContinuation { continuation in
            pending = continuation
            onSave()
        }
    }
    func finish() { pending?.resume(); pending = nil }
}

private actor OrderedLaunchCache: LaunchScheduleCaching {
    private let onFirstSave: @Sendable () -> Void
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var saved: [SavedLaunchSchedule] = []
    init(onFirstSave: @escaping @Sendable () -> Void) { self.onFirstSave = onFirstSave }
    func load() -> [SavedLaunchSchedule] { [] }
    func save(_ schedule: SavedLaunchSchedule) async throws {
        if saved.isEmpty {
            await withCheckedContinuation { continuation in
                pending = continuation
                onFirstSave()
            }
        }
        saved.append(schedule)
    }
    func finishFirst() { pending?.resume(); pending = nil }
}

private actor UnavailableLaunchCache: LaunchScheduleCaching {
    func load() throws -> [SavedLaunchSchedule] { throw CocoaError(.fileReadNoPermission) }
    func save(_ schedule: SavedLaunchSchedule) throws { throw CocoaError(.fileWriteNoPermission) }
}

private actor RetryLaunchCache: LaunchScheduleCaching {
    let schedule: SavedLaunchSchedule
    private(set) var readCount = 0
    init(schedule: SavedLaunchSchedule) { self.schedule = schedule }
    func load() throws -> [SavedLaunchSchedule] {
        readCount += 1
        if readCount == 1 { throw CocoaError(.fileReadNoPermission) }
        return [schedule]
    }
    func save(_ schedule: SavedLaunchSchedule) throws { throw CocoaError(.fileWriteNoPermission) }
}
