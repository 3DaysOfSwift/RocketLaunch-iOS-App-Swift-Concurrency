import XCTest
@testable import RocketLaunch

@MainActor
final class UpdatesViewModelTests: XCTestCase {
    func testRepeatedRefreshSharesTaskAndScreenCancellationReachesProvider() async {
        let started = expectation(description: "Changes refresh started")
        let finished = expectation(description: "Changes refresh settled")
        let repository = LifecycleRepository(onRequest: { started.fulfill() }, onFinish: { finished.fulfill() })
        let feature = LaunchScheduleFeature(repository: repository)
        let viewModel = UpdatesViewModel(feature: feature)
        let first = viewModel.requestRefresh()
        await waitFor([started])
        XCTAssertEqual(viewModel.requestRefresh(), first)
        viewModel.cancelRefresh()
        await first.value
        await repository.complete(0)
        await waitFor([finished])
        let count = await repository.requestCount
        let cancelled = await repository.cancellations
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cancelled[0], true)
        XCTAssertTrue(viewModel.updates.isEmpty)
    }

    func testRefreshDisplaysChangesRecordedBySharedFeature() async {
        let scenario = LaunchScenario()
        let initial = RocketLaunch(id: 42, name: "Launch", missions: [], estimatedDate: .init(month: 1, day: 1, year: 2030))
        await scenario.prepare(.loaded(initial))
        let viewModel = UpdatesViewModel(feature: scenario.feature)
        XCTAssertTrue(viewModel.updates.isEmpty)
        let updated = RocketLaunch(id: 42, name: "Launch", missions: [.init(name: "Mission", description: "New mission")], estimatedDate: initial.estimatedDate)
        await scenario.repository.respond(.success([updated]))
        await viewModel.requestRefresh().value
        XCTAssertEqual(viewModel.updates.count, 1)
        XCTAssertEqual(viewModel.updates.first?.previous, initial)
        XCTAssertEqual(viewModel.updates.first?.launch, updated)
        XCTAssertEqual(viewModel.updates, scenario.feature.updates)
    }
}
