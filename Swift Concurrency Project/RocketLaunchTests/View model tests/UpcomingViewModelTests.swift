import XCTest
@testable import RocketLaunch

@MainActor
final class UpcomingViewModelTests: XCTestCase {
    func testIndependentScreenSelectionsSurviveSharedFeatureRefresh() async throws {
        let launches = try LaunchFixtures.launches()
        let firstLaunch = try XCTUnwrap(launches.first)
        let secondLaunch = try XCTUnwrap(launches.dropFirst().first)
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(firstLaunch))
        let firstScreen = UpcomingViewModel(launchScheduleFeature: scenario.feature)
        let secondScreen = UpcomingViewModel(launchScheduleFeature: scenario.feature)
        firstScreen.showLaunch(firstLaunch)
        secondScreen.showLaunch(secondLaunch)
        let firstDetail = UpcomingLaunchDetailViewModel(launch: try XCTUnwrap(firstScreen.selectedLaunch), launchScheduleFeature: scenario.feature)
        let secondDetail = UpcomingLaunchDetailViewModel(launch: try XCTUnwrap(secondScreen.selectedLaunch), launchScheduleFeature: scenario.feature)

        await scenario.repository.respond(.success([]))
        await firstScreen.requestRefresh().value
        XCTAssertEqual(firstDetail.launch, firstLaunch)
        XCTAssertEqual(secondDetail.launch, secondLaunch)
        XCTAssertEqual(firstScreen.selectedLaunch, firstLaunch)
        XCTAssertEqual(secondScreen.selectedLaunch, secondLaunch)
    }

    func testFiltersDoNotMutateSharedSchedule() async throws {
        let scenario = LaunchScenario()
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.loaded(launch))
        let first = UpcomingViewModel(launchScheduleFeature: scenario.feature)
        let second = UpcomingViewModel(launchScheduleFeature: scenario.feature)
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
        let viewModel = UpcomingViewModel(launchScheduleFeature: feature)
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

    func testCancelledRefreshCanRestartAndRepeatedIntentRetainsReplacementTask() async throws {
        let started = expectation(description: "original transport started")
        let restarted = expectation(description: "replacement transport started")
        let repository = ControlledLaunchRepository { index in
            if index == 0 { started.fulfill() }
            else if index == 1 { restarted.fulfill() }
            else { XCTFail("Repeated refresh created an extra transport request") }
        }
        let feature = LaunchScheduleFeature(
            sources: [.init(id: .rocketLaunchLive, repository: repository)],
            now: { Date(timeIntervalSince1970: 1_600_000_000) })
        let viewModel = UpcomingViewModel(launchScheduleFeature: feature)
        let launches = try LaunchFixtures.launches()
        let originalLaunch = try XCTUnwrap(launches.first)
        let replacementLaunch = try XCTUnwrap(launches.dropFirst().first)

        let original = viewModel.requestRefresh()
        await waitFor([started])
        viewModel.cancelRefresh()
        await original.value
        let replacement = viewModel.requestRefresh()
        await waitFor([restarted])
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(viewModel.requestRefresh(), replacement)

        await repository.complete(1, with: .success([replacementLaunch]))
        await replacement.value
        XCTAssertEqual(viewModel.launches, [replacementLaunch])
        XCTAssertFalse(viewModel.isLoading)

        // Release the abandoned transport so the fixture retains no continuation.
        await repository.complete(0, with: .success([originalLaunch]))
        let count = await repository.requestCount
        XCTAssertEqual(count, 2)
    }

}
