import XCTest
import Observation
@testable import RocketLaunch

final class LaunchScheduleViewModelTests: XCTestCase {
    @MainActor func testCountryIsTheLaunchLocationAndMissingMissionIsExplicit() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        feature.setState(.loaded(try LaunchFixtures.launches()[3]))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.country, "China")
        XCTAssertEqual(viewModel.provider, "China")
        XCTAssertEqual(viewModel.launchTitle, "Mission to be announced")
        XCTAssertTrue(viewModel.missionSummary.contains("haven’t been published"))
    }

    @MainActor func testEstimatedTimeDoesNotPresentAnExactLocalTime() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        feature.setState(.loaded(try LaunchFixtures.launches()[2]))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.launchTime, "Dec 08")
        XCTAssertTrue(viewModel.timingNote.contains("Exact time not announced"))
    }

    @MainActor func testInitialStateDoesNotStartNetworking() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        XCTAssertFalse(viewModel.hasLaunch)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.launchName, "None")
        XCTAssertEqual(feature.refreshCount, 0)
    }
    @MainActor func testAsyncIntentIsDirectlyAwaitable() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await viewModel.refresh()
        XCTAssertEqual(feature.refreshCount, 1)
    }
    @MainActor func testLoadedValuesReadAuthoritativeFeatureState() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        feature.setState(.loaded(launch))
        await viewModel.synchronize()
        XCTAssertTrue(viewModel.hasLaunch)
        XCTAssertEqual(viewModel.launchName, launch.name)
        XCTAssertEqual(viewModel.mission, launch.primaryMissionDescription)
    }
    @MainActor func testMissingMissionHasPresentationFallback() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        feature.setState(.loaded(RocketLaunch(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.mission, "None")
    }
    @MainActor func testEmptyAndLoadingStatesAreDistinct() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        feature.setState(.loading(previous: nil))
        await viewModel.synchronize()
        XCTAssertTrue(viewModel.isLoading); XCTAssertFalse(viewModel.isEmpty)
        feature.setState(.empty)
        await viewModel.synchronize()
        XCTAssertTrue(viewModel.isEmpty); XCTAssertFalse(viewModel.isLoading); XCTAssertFalse(viewModel.hasLaunch)
    }
    @MainActor func testRecoverableFailureRetainsLaunchAndExposesMessage() async throws {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        feature.setState(.failed(.offline, previous: launch))
        await viewModel.synchronize()
        XCTAssertTrue(viewModel.hasLaunch)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.launchName, launch.name)
    }
    @MainActor func testTwoViewModelsObserveTheSameFeatureThroughItsProtocol() async throws {
        let shared = ControlledLaunchFeature()
        let first = LaunchScheduleViewModel(feature: shared)
        let second = LaunchScheduleViewModel(feature: shared)
        let firstChanged = expectation(description: "first observes")
        let secondChanged = expectation(description: "second observes")
        withObservationTracking { _ = first.launchName } onChange: { firstChanged.fulfill() }
        withObservationTracking { _ = second.launchName } onChange: { secondChanged.fulfill() }
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        first.startObserving(); second.startObserving()
        defer { first.stopObserving(); second.stopObserving() }
        shared.setState(.loaded(launch))
        await waitFor([firstChanged, secondChanged])
        XCTAssertEqual(first.launchName, launch.name)
        XCTAssertEqual(second.launchName, launch.name)
    }
    @MainActor func testNewScreenRefreshCancelsPreviousTask() async {
        let feature = LifecycleFeature()
        let first = expectation(description: "first starts")
        let second = expectation(description: "second starts")
        let finished = expectation(description: "both finish"); finished.expectedFulfillmentCount = 2
        feature.onRequest = { index in (index == 0 ? first : second).fulfill() }
        feature.onFinish = { _ in finished.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.requestRefresh(); await waitFor([first])
        viewModel.requestRefresh(); await waitFor([second])
        feature.complete(0); feature.complete(1); await waitFor([finished])
        XCTAssertEqual(feature.cancellations[0], true)
        XCTAssertEqual(feature.cancellations[1], false)
    }
    @MainActor func testScreenDisappearanceCancelsRefresh() async {
        let feature = LifecycleFeature()
        let started = expectation(description: "starts")
        let finished = expectation(description: "finishes")
        feature.onRequest = { _ in started.fulfill() }; feature.onFinish = { _ in finished.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.requestRefresh(); await waitFor([started])
        viewModel.cancelRefresh(); feature.complete(0); await waitFor([finished])
        XCTAssertEqual(feature.cancellations[0], true)
    }
    @MainActor func testOwnerReleaseCancelsWithoutTaskRetainingViewModel() async {
        let feature = LifecycleFeature()
        let started = expectation(description: "starts")
        let finished = expectation(description: "finishes")
        feature.onRequest = { _ in started.fulfill() }; feature.onFinish = { _ in finished.fulfill() }
        var viewModel: LaunchScheduleViewModel? = LaunchScheduleViewModel(feature: feature)
        weak var weakViewModel = viewModel
        viewModel?.requestRefresh(); await waitFor([started])
        viewModel = nil
        XCTAssertNil(weakViewModel)
        feature.complete(0); await waitFor([finished])
        XCTAssertEqual(feature.cancellations[0], true)
    }
}

extension LaunchScheduleViewModelTests {
    @MainActor func testActorStreamUpdatesViewModelBeforeSlowerProviderFinishes() async throws {
        let aStarted = expectation(description: "First provider started")
        let bStarted = expectation(description: "Second provider started")
        let displayed = expectation(description: "First result reached observable ViewModel")
        let a = ControlledLaunchRepository { _ in aStarted.fulfill() }
        let b = ControlledLaunchRepository { _ in bStarted.fulfill() }
        let feature = LaunchScheduleFeature(sources: [
            .init(id: .rocketLaunchLive, repository: a),
            .init(id: .launchLibrary, repository: b)
        ])
        let viewModel = LaunchScheduleViewModel(feature: feature)
        defer { viewModel.cancelRefresh(); viewModel.stopObserving() }
        viewModel.requestRefresh()
        await waitFor([aStarted, bStarted])
        await viewModel.synchronize()
        withObservationTracking { _ = viewModel.currentLaunch } onChange: {
            MainActor.assertIsolated()
            displayed.fulfill()
        }
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await a.complete(0, with: .success([launch]))
        await waitFor([displayed])
        XCTAssertEqual(viewModel.currentLaunch, launch)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(viewModel.sources.first(where: { $0.id == .launchLibrary })?.phase, .loading)
        await b.complete(0, with: .success([]))
    }
}
