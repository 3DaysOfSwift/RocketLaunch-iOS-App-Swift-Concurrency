import XCTest
@testable import RocketLaunch

@MainActor
final class UpcomingViewModelTests: XCTestCase {
    func testFiltersDoNotMutateSharedSchedule() async throws {
        let scenario = LaunchScenario()
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.loaded(launch))
        let first = UpcomingViewModel(feature: scenario.feature)
        let second = UpcomingViewModel(feature: scenario.feature)
        XCTAssertEqual(first.launches, [launch])
        first.filters.search = "no matching mission"
        XCTAssertTrue(first.launches.isEmpty)
        XCTAssertEqual(second.launches, [launch])
        XCTAssertEqual(scenario.feature.snapshot.upcomingLaunches, [launch])
        first.filters.search = ""
        XCTAssertEqual(first.launches, [launch])
    }

    func testRepeatedRefreshSharesWorkAndDisappearanceCancelsIt() async {
        let started = expectation(description: "transport started")
        let ended = expectation(description: "transport ended")
        let repository = LifecycleRepository(onRequest: { started.fulfill() }, onFinish: { ended.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = UpcomingViewModel(feature: feature)
        let first = viewModel.requestRefresh()
        await waitFor([started])
        let repeated = viewModel.requestRefresh()
        viewModel.cancelRefresh()
        await first.value
        await repeated.value
        await repository.complete(0)
        await waitFor([ended])
        let requests = await repository.requestCount
        let cancelled = await repository.cancellations
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(cancelled[0], true)
        XCTAssertFalse(viewModel.isLoading)
    }
}
