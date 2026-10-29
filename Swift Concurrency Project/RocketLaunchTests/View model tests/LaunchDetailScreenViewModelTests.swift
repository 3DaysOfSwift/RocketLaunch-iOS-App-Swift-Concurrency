import XCTest
@testable import RocketLaunch

@MainActor
final class LaunchDetailScreenViewModelTests: XCTestCase {
    func testFailureIsOwnedByTheScreenThatRequestedIt() async {
        let feature = LaunchScheduleFeature(sources: [])
        let first = LaunchDetailScreenViewModel(feature: feature)
        let second = LaunchDetailScreenViewModel(feature: feature)
        await first.save("missing", minutesBefore: 15).value
        XCTAssertEqual(first.errorMessage, "Refresh the schedule and open the launch again before setting a reminder.")
        XCTAssertNil(second.errorMessage)
        XCTAssertFalse(first.isBusy)
        XCTAssertFalse(second.isBusy)
        XCTAssertFalse(first.contains("missing"))
    }

    func testCancellationBeforeDispatchDoesNotPresentAnError() async {
        let feature = LaunchScheduleFeature(sources: [])
        let viewModel = LaunchDetailScreenViewModel(feature: feature)
        let save = viewModel.save("missing", minutesBefore: 15)
        save.cancel()
        await save.value
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertTrue(feature.reminders.isEmpty)
    }

    func testReleasingScreenCancelsItsPendingSave() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        var screen: LaunchDetailScreenViewModel? = LaunchDetailScreenViewModel(feature: feature)
        weak var released = screen
        let save = try XCTUnwrap(screen?.save("missing", minutesBefore: 15))
        screen = nil
        XCTAssertNil(released)
        XCTAssertTrue(save.isCancelled)
        await save.value
        XCTAssertTrue(feature.reminders.isEmpty)
    }
}
