import XCTest
@testable import RocketLaunch

final class LaunchScheduleViewModelTests: XCTestCase {
    @MainActor func testInitialStateDoesNotStartNetworking() {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        XCTAssertFalse(viewModel.receivedNextRocketLaunch)
        XCTAssertEqual(viewModel.launchName, "None")
        XCTAssertEqual(viewModel.mission, "None")
        XCTAssertTrue(feature.completions.isEmpty)
    }

    @MainActor func testRefreshPublishesLaunchNameAndMission() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        viewModel.refresh()
        XCTAssertEqual(feature.completions.count, 1)
        feature.completions[0](.success(launch))
        await drainMainQueue()
        XCTAssertTrue(viewModel.receivedNextRocketLaunch)
        XCTAssertEqual(viewModel.launchName, launch.name)
        XCTAssertEqual(viewModel.mission, launch.missions.first?.description ?? "None")
    }

    @MainActor func testFailureLeavesInitialStateAvailableForRetry() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.refresh()
        feature.completions[0](.failure(.networkingError))
        await drainMainQueue()
        XCTAssertFalse(viewModel.receivedNextRocketLaunch)
        viewModel.refresh()
        XCTAssertEqual(feature.completions.count, 2)
    }

    @MainActor func testFailureAfterSuccessRetainsDisplayedLaunch() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        viewModel.refresh()
        feature.completions[0](.success(launch))
        await drainMainQueue()
        viewModel.refresh()
        feature.completions[1](.failure(.networkingError))
        await drainMainQueue()
        XCTAssertTrue(viewModel.receivedNextRocketLaunch)
        XCTAssertEqual(viewModel.launchName, launch.name)
    }

    // Characterises DEF-003; the async migration will introduce an honest empty state.
    @MainActor func testLegacyEmptyResponseEntersReceivedStateWithPlaceholders() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.refresh()
        feature.completions[0](.success(nil))
        await drainMainQueue()
        XCTAssertTrue(viewModel.receivedNextRocketLaunch)
        XCTAssertEqual(viewModel.launchName, "None")
        XCTAssertEqual(viewModel.mission, "None")
    }

    // Characterises DEF-002 with explicitly controlled completion order, without sleeps.
    @MainActor func testLegacyOlderResponseCanOverwriteNewerResponse() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launches = try LaunchFixtures.launches()
        viewModel.refresh()
        viewModel.refresh()
        feature.completions[1](.success(launches[1]))
        await drainMainQueue()
        XCTAssertEqual(viewModel.launchName, launches[1].name)
        feature.completions[0](.success(launches[0]))
        await drainMainQueue()
        XCTAssertEqual(viewModel.launchName, launches[0].name)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
