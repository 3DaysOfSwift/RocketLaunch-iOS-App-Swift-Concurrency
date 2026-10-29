import XCTest
import Observation
@testable import RocketLaunch

final class LaunchScheduleViewModelTests: XCTestCase {
    @MainActor func testNewViewModelDoesNotRefreshAnAlreadyLoadedFeature() async throws {
        let feature = ControlledLaunchFeature()
        feature.setState(.loaded(try LaunchFixtures.launches()[0]))
        let checked = expectation(description: "Feature evaluated initial load")
        feature.onInitialLoad = { checked.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        defer { viewModel.cancelRefresh(); viewModel.stopObserving() }
        XCTAssertEqual(viewModel.snapshot.state, .idle)
        viewModel.loadIfNeeded()
        await waitFor([checked])
        XCTAssertEqual(feature.refreshCount, 0)
        await viewModel.synchronize()
        XCTAssertTrue(viewModel.hasLaunch)
    }

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
    @MainActor func testRepeatedScreenRefreshKeepsCurrentTask() async {
        let feature = LifecycleFeature()
        let first = expectation(description: "first starts")
        let finished = expectation(description: "finishes")
        feature.onRequest = { _ in first.fulfill() }
        feature.onFinish = { _ in finished.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        viewModel.requestRefresh(); await waitFor([first])
        viewModel.requestRefresh()
        XCTAssertEqual(feature.pending.count, 1)
        feature.complete(0); await waitFor([finished])
        XCTAssertEqual(feature.cancellations[0], false)
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
        ], now: { Date(timeIntervalSince1970: 1_700_000_000) }) // Before the fixture launch.
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


extension LaunchScheduleViewModelTests {
    @MainActor func testCountdownAdvancesAndWaitsForScheduleAtDeadline() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        feature.setState(.loaded(countdownLaunch(at: deadline)))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-90_061)).clock, "01:01:01")
        XCTAssertNotNil(viewModel.countdown(at: deadline.addingTimeInterval(-90_061)).days)
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-1.1)).clock, "00:00:02")
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-0.1)).clock, "00:00:01")
        XCTAssertNil(viewModel.countdown(at: deadline).clock)
        XCTAssertEqual(viewModel.countdown(at: deadline).status, "Awaiting update")
        XCTAssertNil(viewModel.countdown(at: deadline.addingTimeInterval(60)).clock)
        XCTAssertEqual(feature.refreshCount, 0, "A presentation tick must not start networking")
    }

    @MainActor func testEstimateDoesNotBecomeCountdownAndReplacementUpdatesDeadline() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        feature.setState(.loaded(countdownLaunch(at: nil, sortTime: now.addingTimeInterval(600))))
        await viewModel.synchronize()
        XCTAssertNil(viewModel.countdown(at: now).clock)
        XCTAssertEqual(viewModel.countdown(at: now).status, "Time unconfirmed")
        feature.setState(.loaded(countdownLaunch(at: now.addingTimeInterval(600))))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.countdown(at: now).clock, "00:10:00")
        feature.setState(.loaded(countdownLaunch(at: now.addingTimeInterval(3_600))))
        await viewModel.synchronize()
        XCTAssertEqual(viewModel.countdown(at: now).clock, "01:00:00")
    }

    @MainActor func testMissingMissionDoesNotFillCompactCardWithPlaceholderParagraph() async {
        let feature = ControlledLaunchFeature()
        let viewModel = LaunchScheduleViewModel(feature: feature)
        feature.setState(.loaded(countdownLaunch(at: nil)))
        await viewModel.synchronize()
        XCTAssertNil(viewModel.missionPreview)
        XCTAssertFalse(viewModel.missionSummary.isEmpty, "The detail screen retains its explanation")
    }

    private func countdownLaunch(at date: Date?, sortTime: Date? = nil) -> RocketLaunch {
        RocketLaunch(id: 99, name: "Mission", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: date, sortTime: sortTime))
    }
}


extension LaunchScheduleViewModelTests {
    @MainActor func testProviderRefreshCoalescesSameSourceAndAllowsIndependentSource() async {
        let feature = LifecycleFeature()
        let started = expectation(description: "Two distinct providers started")
        started.expectedFulfillmentCount = 2
        let finished = expectation(description: "Both provider requests finished")
        finished.expectedFulfillmentCount = 2
        feature.onRequest = { _ in started.fulfill() }
        feature.onFinish = { _ in finished.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        defer { viewModel.cancelRefresh(); viewModel.stopObserving() }
        viewModel.requestRefresh(source: .spaceX)
        viewModel.requestRefresh(source: .spaceX)
        viewModel.requestRefresh(source: .launchLibrary)
        await waitFor([started])
        XCTAssertEqual(feature.requestedSources.count, 2)
        XCTAssertEqual(Set(feature.requestedSources), [.spaceX, .launchLibrary])
        for index in feature.pending.indices { feature.complete(index) }
        await waitFor([finished])
        XCTAssertEqual(feature.cancellations.values.filter { $0 }.count, 0)
    }

    @MainActor func testLeavingScreenCancelsProviderRefresh() async {
        let feature = LifecycleFeature()
        let started = expectation(description: "Provider refresh started")
        let finished = expectation(description: "Cancelled provider returned")
        feature.onRequest = { _ in started.fulfill() }
        feature.onFinish = { _ in finished.fulfill() }
        let viewModel = LaunchScheduleViewModel(feature: feature)
        defer { viewModel.cancelRefresh(); viewModel.stopObserving() }
        viewModel.requestRefresh(source: .spaceX)
        await waitFor([started])
        viewModel.cancelRefresh()
        for index in feature.pending.indices { feature.complete(index) }
        await waitFor([finished])
        XCTAssertEqual(feature.cancellations[0], true)
    }
}
