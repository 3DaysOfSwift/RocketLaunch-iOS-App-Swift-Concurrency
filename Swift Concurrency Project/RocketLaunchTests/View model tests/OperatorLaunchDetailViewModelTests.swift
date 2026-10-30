import XCTest
@testable import RocketLaunch

@MainActor
final class OperatorLaunchDetailViewModelTests: XCTestCase {

    func testSelectionIsIndependentFromOtherTabsAndSaveUsesSelectedRecord() async throws {
        let records = try LaunchFixtures.launches()
        let selected = try XCTUnwrap(records.first)
        let other = try XCTUnwrap(records.dropFirst().first)
        XCTAssertNotEqual(selected.id, other.id)
        let feature = LaunchScheduleFeature(sources: [])
        let model = OperatorLaunchDetailViewModel(launch: selected, launchScheduleFeature: feature)
        model.minutesBefore = 60
        let otherScreen = OperatorLaunchDetailViewModel(launch: other, launchScheduleFeature: feature)
        XCTAssertEqual(otherScreen.launch, other)
        XCTAssertEqual(model.launch, selected)
        XCTAssertEqual(model.minutesBefore, 60)
        let save = try XCTUnwrap(model.save())
        await save.value
        // The selected snapshot is not in this empty catalogue. The real Feature
        // must validate it rather than schedule an obsolete record.
        XCTAssertEqual(model.errorMessage, "Refresh the schedule and open the launch again before setting a reminder.")
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(feature.reminders.isEmpty)
        let anotherScreen = OperatorLaunchDetailViewModel(launch: other, launchScheduleFeature: feature)
        XCTAssertNil(anotherScreen.errorMessage)
        XCTAssertEqual(anotherScreen.minutesBefore, 15)
    }

    func testSelectedSaveCancelledBeforeDispatchDoesNotPresentFailure() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let model = OperatorLaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        let task = try XCTUnwrap(model.save())
        task.cancel()
        await task.value
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(feature.reminders.isEmpty)
    }
}
