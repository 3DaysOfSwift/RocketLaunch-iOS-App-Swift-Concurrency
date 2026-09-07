import XCTest
@testable import RocketLaunch

final class LaunchScheduleFeatureTests: XCTestCase {
    @MainActor func testConstructionDoesNotFetch() async {
        let repository = ControlledLaunchRepository()
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        XCTAssertEqual(launchSchedule.state, .idle)
        let count = await repository.requestCount
        XCTAssertEqual(count, 0)
    }

    @MainActor func testRefreshLoadsFirstReturnedLaunch() async throws {
        let began = expectation(description: "request")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let launchSchedule = LaunchScheduleFeature(repository: repository)
        let launches = try LaunchFixtures.launches()
        let task = Task { await launchSchedule.refresh() }
        await waitFor([began])
        XCTAssertEqual(launchSchedule.state, .loading(previous: nil))
        await repository.complete(0, with: .success(launches))
        await task.value
        XCTAssertEqual(launchSchedule.state, .loaded(launches[0]))
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
