import XCTest
@testable import RocketLaunch

@MainActor
final class OperatorLaunchesViewModelTests: XCTestCase {
    func testOperatorLaunchesReflectSharedFeatureWithoutCopyingState() async throws {
        let scenario = LaunchScenario()
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.loaded(launch))
        let viewModel = OperatorLaunchesViewModel(feature: scenario.feature)
        let group = try XCTUnwrap(scenario.feature.operators.first)
        XCTAssertEqual(viewModel.launches(for: group.id), group.launches)
        XCTAssertTrue(viewModel.launches(for: "unknown").isEmpty)
        await scenario.repository.respond(.success([]))
        await viewModel.requestRefresh(source: .rocketLaunchLive).value
        XCTAssertTrue(viewModel.launches(for: group.id).isEmpty)
    }

    func testOnlySpaceXOperatorIncludesSpaceXSourceBeforeLoading() {
        let feature = LaunchScheduleFeature(sources: [
            .init(id: .spaceX, repository: PresentationLaunchRepository()),
            .init(id: .launchLibrary, repository: PresentationLaunchRepository())
        ])
        let viewModel = OperatorLaunchesViewModel(feature: feature)
        XCTAssertEqual(viewModel.relevantSources(for: "spacex").map(\.id), [.spaceX, .launchLibrary])
        XCTAssertEqual(viewModel.relevantSources(for: "other").map(\.id), [.launchLibrary])
    }

    func testRepeatedSourceRefreshIsOwnedAndCancelledByThisScreen() async {
        let started = expectation(description: "Provider started")
        let finished = expectation(description: "Provider finished")
        let repository = LifecycleRepository(onRequest: { started.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = OperatorLaunchesViewModel(feature: feature)
        let first = viewModel.requestRefresh(source: .rocketLaunchLive)
        await waitFor([started])
        let repeated = viewModel.requestRefresh(source: .rocketLaunchLive)
        viewModel.cancelRefresh()
        await first.value
        await repeated.value
        await repository.complete(0)
        await waitFor([finished])
        let count = await repository.requestCount
        let cancelled = await repository.cancellations
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cancelled[0], true)
    }
}
