import XCTest
@testable import RocketLaunch

@MainActor
final class UpdatesViewModelTests: XCTestCase {
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
