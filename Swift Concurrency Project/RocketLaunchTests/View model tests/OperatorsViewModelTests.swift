import XCTest
@testable import RocketLaunch

@MainActor
final class OperatorsViewModelTests: XCTestCase {
    func testFilteringOneScreenDoesNotHideOtherScreensOperators() async throws {
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(try XCTUnwrap(LaunchFixtures.launches().first)))
        let first = OperatorsViewModel(launchScheduleFeature: scenario.feature)
        let second = OperatorsViewModel(launchScheduleFeature: scenario.feature)
        XCTAssertFalse(first.operators.isEmpty)
        let original = first.operators.map(\.id)
        first.filters.search = "nonexistent operator"
        XCTAssertTrue(first.operators.isEmpty)
        XCTAssertEqual(second.operators.map(\.id), original)
        first.filters.search = ""
        XCTAssertEqual(first.operators.map(\.id), original)
        XCTAssertFalse(first.isLoading)
    }
}
