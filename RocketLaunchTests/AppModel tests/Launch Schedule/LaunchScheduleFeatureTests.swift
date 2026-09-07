import XCTest
import Observation
@testable import RocketLaunch

final class LaunchScheduleFeatureTests: XCTestCase {
    @MainActor func testConstructionDoesNotFetch() async {
        let repository = ControlledLaunchRepository()
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        XCTAssertEqual(launchSchedule.state, .idle)
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
        XCTAssertEqual(launchSchedule.state, .loading(previous: nil))
        await repository.complete(0, with: .success(launches))
        await task.value
        XCTAssertEqual(launchSchedule.state, .loaded(launches[2]))
        XCTAssertEqual(launchSchedule.sources[0].launches, launches)
    }

    @MainActor func testEmptyResponseHasAnHonestEmptyState() async {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let task = Task { await launchSchedule.refresh() }
        await waitFor([began])
        await repository.complete(0, with: .success([]))
        await task.value
        XCTAssertEqual(launchSchedule.state, .empty)
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
            XCTAssertEqual(launchSchedule.state, .failed(failure, previous: nil))
        }
    }

    @MainActor func testFailureRetainsLastLaunchAndRetryCanReplaceIt() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let third = expectation(description: "third")
        let repository = ControlledLaunchRepository { index in
            [first, second, third][index].fulfill()
        }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let launches = try LaunchFixtures.launches()
        let initial = Task { await launchSchedule.refresh() }
        await waitFor([first]); await repository.complete(0, with: .success([launches[0]])); await initial.value
        let failed = Task { await launchSchedule.refresh() }
        await waitFor([second])
        XCTAssertEqual(launchSchedule.state, .loading(previous: launches[0]))
        await repository.complete(1, with: .failure(URLError(.notConnectedToInternet))); await failed.value
        XCTAssertEqual(launchSchedule.state, .failed(.offline, previous: launches[0]))
        let retry = Task { await launchSchedule.refresh() }
        await waitFor([third]); await repository.complete(2, with: .success([launches[1]])); await retry.value
        XCTAssertEqual(launchSchedule.state, .loaded(launches[1]))
    }

    @MainActor func testOlderSuccessCannotOverwriteNewerSuccess() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let launches = try LaunchFixtures.launches()
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        await repository.complete(1, with: .success([launches[1]])); await new.value
        await repository.complete(0, with: .success([launches[0]])); await old.value
        XCTAssertEqual(launchSchedule.state, .loaded(launches[1]))
    }

    @MainActor func testOlderFailureCannotOverwriteNewerSuccess() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        await repository.complete(1, with: .success([launch])); await new.value
        await repository.complete(0, with: .failure(URLError(.timedOut))); await old.value
        XCTAssertEqual(launchSchedule.state, .loaded(launch))
    }

    @MainActor func testCancelledSuccessDoesNotPublishOrLeaveLoadingState() async throws {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let task = Task { await launchSchedule.refresh() }; await waitFor([began])
        task.cancel()
        await repository.complete(0, with: .success(try LaunchFixtures.launches())); await task.value
        XCTAssertEqual(launchSchedule.state, .idle)
    }

    @MainActor func testCancellingReplacementRestoresLastSettledState() async throws {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        let repository = ControlledLaunchRepository { index in (index == 0 ? first : second).fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let old = Task { await launchSchedule.refresh() }; await waitFor([first])
        let new = Task { await launchSchedule.refresh() }; await waitFor([second])
        new.cancel()
        await repository.complete(1, with: .failure(CancellationError())); await new.value
        await repository.complete(0, with: .success(try LaunchFixtures.launches())); await old.value
        XCTAssertEqual(launchSchedule.state, .idle)
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
        withObservationTracking { _ = feature.operators } onChange: { published.fulfill() }
        await a.complete(0, with: .success([first]))
        await waitFor([published])
        XCTAssertEqual(feature.nextLaunch, first)
        XCTAssertEqual(feature.operators.map(\.name), ["SpaceX"])
        XCTAssertEqual(feature.sources[1].phase, .loading)
        await b.complete(0, with: .success([second])); await task.value
        XCTAssertEqual(feature.nextLaunch, second)
        XCTAssertEqual(feature.operators.map(\.name), ["SpaceX", "Blue Origin"])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(feature.sources[0].launches, [first])
        XCTAssertEqual(feature.sources[1].launches, [second])
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
        XCTAssertEqual(feature.sources[0].phase, .failed(.timedOut))
        XCTAssertEqual(feature.state, .loaded(expected))
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
        XCTAssertNil(feature.nextLaunch)
        XCTAssertEqual(feature.state, .empty)
        XCTAssertEqual(feature.operators.map(\.name), ["SpaceX"])
        XCTAssertTrue(feature.operators[0].launches.isEmpty)
        XCTAssertEqual(feature.operators[0].sourceIDs, [.rocketLaunchLive])
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
        XCTAssertEqual(feature.operators[0].launches, [record])
        XCTAssertEqual(feature.sources[0].phase, .failed(.offline))
        XCTAssertNil(feature.nextLaunch)
        XCTAssertEqual(feature.state, .failed(.offline, previous: record))
    }

    @MainActor func testStoredNextChangesWhenTimePassesWithoutARequest() async {
        let started = expectation(description: "started")
        let repository = ControlledLaunchRepository { _ in started.fulfill() }
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { clock })
        let first = launch("1", .rocketLaunchLive, "SpaceX", clock.addingTimeInterval(60))
        let second = launch("2", .rocketLaunchLive, "SpaceX", clock.addingTimeInterval(120))
        let task = Task { await feature.refresh() }; await waitFor([started])
        await repository.complete(0, with: .success([first, second])); await task.value
        XCTAssertEqual(feature.nextLaunch, first)
        clock = clock.addingTimeInterval(90); feature.updateNextLaunch()
        XCTAssertEqual(feature.nextLaunch, second)
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
        XCTAssertEqual(feature.operators[0].launches, [early, late])
        XCTAssertNil(feature.operators[0].launches[0].details.plannedTime)
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
