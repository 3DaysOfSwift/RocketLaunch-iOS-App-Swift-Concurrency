import XCTest
import Observation
@testable import RocketLaunch

final class LaunchScheduleViewModelTests: XCTestCase {
    @MainActor func testNewViewModelDoesNotRefreshAnAlreadyLoadedFeature() async throws {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        await scenario.prepare(.loaded(try LaunchFixtures.launches()[0]))
        let viewModel = LaunchScheduleViewModel(feature: feature)
        defer { viewModel.cancelRefresh() }
        XCTAssertTrue(viewModel.hasLaunch)
        await viewModel.loadIfNeeded().value
        let requests = await scenario.repository.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(viewModel.hasLaunch)
    }

    @MainActor func testCountryIsTheLaunchLocationAndMissingMissionIsExplicit() async throws {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await scenario.prepare(.loaded(try LaunchFixtures.launches()[3]))
        XCTAssertEqual(viewModel.country, "China")
        XCTAssertEqual(viewModel.provider, "China")
        XCTAssertEqual(viewModel.launchTitle, "Mission to be announced")
        XCTAssertTrue(viewModel.missionSummary.contains("haven’t been published"))
    }

    @MainActor func testEstimatedTimeDoesNotPresentAnExactLocalTime() async throws {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await scenario.prepare(.loaded(try LaunchFixtures.launches()[2]))
        XCTAssertEqual(viewModel.launchTime, "Dec 08")
        XCTAssertTrue(viewModel.timingNote.contains("Exact time not announced"))
    }

    @MainActor func testInitialStateDoesNotStartNetworking() async {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        XCTAssertFalse(viewModel.hasLaunch)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.launchName, "None")
        let requests = await scenario.repository.requestCount
        XCTAssertEqual(requests, 0)
    }
    @MainActor func testAsyncIntentIsDirectlyAwaitable() async {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await viewModel.refresh()
        let requests = await scenario.repository.requestCount
        XCTAssertEqual(requests, 1)
    }
    @MainActor func testLoadedValuesReadAuthoritativeFeatureState() async throws {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.loaded(launch))
        XCTAssertTrue(viewModel.hasLaunch)
        XCTAssertEqual(viewModel.launchName, launch.name)
        XCTAssertEqual(viewModel.mission, launch.primaryMissionDescription)
    }
    @MainActor func testMissingMissionHasPresentationFallback() async {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await scenario.prepare(.loaded(RocketLaunch(id: 1, name: "Launch", missions: [], estimatedDate: .init(month: nil, day: nil, year: nil))))
        XCTAssertEqual(viewModel.mission, "None")
    }
    @MainActor func testEmptyAndLoadingStatesAreDistinct() async {
        let began = expectation(description: "request pending")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let refresh = viewModel.requestRefresh()
        await waitFor([began])
        XCTAssertTrue(viewModel.isLoading); XCTAssertFalse(viewModel.isEmpty)
        await repository.complete(0, with: .success([]))
        await refresh.value
        XCTAssertTrue(viewModel.isEmpty); XCTAssertFalse(viewModel.isLoading); XCTAssertFalse(viewModel.hasLaunch)
    }
    @MainActor func testRecoverableFailureRetainsLaunchAndExposesMessage() async throws {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.failed(.offline, previous: launch))
        XCTAssertTrue(viewModel.hasLaunch)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.launchName, launch.name)
    }
    @MainActor func testTwoViewModelsObserveTheSameConcreteFeature() async throws {
        let scenario = LaunchScenario()
        let shared = scenario.feature
        let first = LaunchScheduleViewModel(feature: shared)
        let second = LaunchScheduleViewModel(feature: shared)
        let firstChanged = expectation(description: "first observes")
        let secondChanged = expectation(description: "second observes")
        withObservationTracking { _ = first.launchName } onChange: { firstChanged.fulfill() }
        withObservationTracking { _ = second.launchName } onChange: { secondChanged.fulfill() }
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        await scenario.prepare(.loaded(launch))
        await waitFor([firstChanged, secondChanged])
        XCTAssertEqual(first.launchName, launch.name)
        XCTAssertEqual(second.launchName, launch.name)
    }
    @MainActor func testRepeatedScreenRefreshKeepsCurrentTask() async {
        let began = expectation(description: "request started")
        let finished = expectation(description: "transport finished")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let first = viewModel.requestRefresh()
        await waitFor([began])
        let second = viewModel.requestRefresh()
        await repository.complete(0)
        await first.value
        await second.value
        await waitFor([finished])
        let count = await repository.requestCount
        let cancellations = await repository.cancellations
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cancellations[0], false)
    }
    @MainActor func testScreenDisappearanceCancelsRefresh() async {
        let began = expectation(description: "request started")
        let finished = expectation(description: "transport finished")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let request = viewModel.requestRefresh()
        await waitFor([began])
        viewModel.cancelRefresh()
        await request.value
        await repository.complete(0)
        await waitFor([finished])
        let cancellations = await repository.cancellations
        XCTAssertEqual(cancellations[0], true)
        XCTAssertEqual(feature.state, .idle)
    }
    @MainActor func testOwnerReleaseCancelsWithoutTaskRetainingViewModel() async {
        let began = expectation(description: "request started")
        let finished = expectation(description: "transport finished")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        var viewModel: LaunchScheduleViewModel? = LaunchScheduleViewModel(feature: feature)
        weak var weakViewModel = viewModel
        let request = viewModel?.requestRefresh()
        await waitFor([began])
        viewModel = nil
        XCTAssertNil(weakViewModel)
        await request?.value
        await repository.complete(0)
        await waitFor([finished])
        let cancellations = await repository.cancellations
        XCTAssertEqual(cancellations[0], true)
    }
}

extension LaunchScheduleViewModelTests {
    @MainActor func testFeatureObservationUpdatesViewModelBeforeSlowerProviderFinishes() async throws {
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
        defer { viewModel.cancelRefresh() }
        viewModel.requestRefresh()
        await waitFor([aStarted, bStarted])
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
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        await scenario.prepare(.loaded(countdownLaunch(at: deadline)))
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-90_061)).clock, "01:01:01")
        XCTAssertNotNil(viewModel.countdown(at: deadline.addingTimeInterval(-90_061)).days)
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-1.1)).clock, "00:00:02")
        XCTAssertEqual(viewModel.countdown(at: deadline.addingTimeInterval(-0.1)).clock, "00:00:01")
        XCTAssertNil(viewModel.countdown(at: deadline).clock)
        XCTAssertEqual(viewModel.countdown(at: deadline).status, "Awaiting update")
        XCTAssertNil(viewModel.countdown(at: deadline.addingTimeInterval(60)).clock)
        let requests = await scenario.repository.requestCount
        XCTAssertEqual(requests, 1, "Presentation ticks must not add requests after initial loading")
    }

    @MainActor func testEstimateDoesNotBecomeCountdownAndReplacementUpdatesDeadline() async {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await scenario.prepare(.loaded(countdownLaunch(at: nil, sortTime: now.addingTimeInterval(600))))
        XCTAssertNil(viewModel.countdown(at: now).clock)
        XCTAssertEqual(viewModel.countdown(at: now).status, "Time unconfirmed")
        await scenario.prepare(.loaded(countdownLaunch(at: now.addingTimeInterval(600))))
        XCTAssertEqual(viewModel.countdown(at: now).clock, "00:10:00")
        await scenario.prepare(.loaded(countdownLaunch(at: now.addingTimeInterval(3_600))))
        XCTAssertEqual(viewModel.countdown(at: now).clock, "01:00:00")
    }

    @MainActor func testMissingMissionDoesNotFillCompactCardWithPlaceholderParagraph() async {
        let scenario = LaunchScenario()
        let feature = scenario.feature
        let viewModel = LaunchScheduleViewModel(feature: feature)
        await scenario.prepare(.loaded(countdownLaunch(at: nil)))
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
        let began = expectation(description: "two providers started")
        began.expectedFulfillmentCount = 2
        let a = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: {})
        let b = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: {})
        let feature = LaunchScheduleFeature(sources: [.init(id: .spaceX, repository: a), .init(id: .launchLibrary, repository: b)])
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let first = viewModel.requestRefresh(source: .spaceX)
        let duplicate = viewModel.requestRefresh(source: .spaceX)
        let other = viewModel.requestRefresh(source: .launchLibrary)
        await waitFor([began])
        await a.complete(0); await b.complete(0)
        await first.value; await duplicate.value; await other.value
        let aCount = await a.requestCount, bCount = await b.requestCount
        let aCancelled = await a.cancellations, bCancelled = await b.cancellations
        XCTAssertEqual(aCount, 1); XCTAssertEqual(bCount, 1)
        XCTAssertEqual(aCancelled[0], false); XCTAssertEqual(bCancelled[0], false)
    }

    @MainActor func testLeavingScreenCancelsProviderRefresh() async {
        let began = expectation(description: "provider started")
        let finished = expectation(description: "provider finished")
        let repository = LifecycleRepository(onRequest: { began.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(sources: [.init(id: .spaceX, repository: repository)])
        let viewModel = LaunchScheduleViewModel(feature: feature)
        let request = viewModel.requestRefresh(source: .spaceX)
        await waitFor([began])
        viewModel.cancelRefresh()
        await request.value
        await repository.complete(0)
        await waitFor([finished])
        let cancellations = await repository.cancellations
        XCTAssertEqual(cancellations[0], true)
    }
}
