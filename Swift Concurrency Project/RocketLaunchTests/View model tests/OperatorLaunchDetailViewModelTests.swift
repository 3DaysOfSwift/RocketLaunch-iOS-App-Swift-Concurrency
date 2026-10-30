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
        feature.selectLaunch(selected, in: .operators)
        let model = OperatorLaunchDetailViewModel(feature: feature)
        model.minutesBefore = 60
        for context in LaunchSelectionContext.allCases where context != .operators {
            feature.selectLaunch(other, in: context)
        }
        XCTAssertEqual(model.launch, selected)
        XCTAssertEqual(model.minutesBefore, 60)
        let save = try XCTUnwrap(model.save())
        await save.value
        // The selected snapshot is not in this empty catalogue. The real Feature
        // must validate it rather than schedule an obsolete record.
        XCTAssertEqual(model.errorMessage, "Refresh the schedule and open the launch again before setting a reminder.")
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(feature.reminders.isEmpty)
        let anotherScreen = OperatorLaunchDetailViewModel(feature: feature)
        XCTAssertNil(anotherScreen.errorMessage)
        XCTAssertEqual(anotherScreen.minutesBefore, 15)
    }

    func testNoSelectionDoesNotStartSaving() {
        let model = OperatorLaunchDetailViewModel(feature: LaunchScheduleFeature(sources: []))
        XCTAssertNil(model.launch)
        XCTAssertNil(model.save())
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
    }

    func testSelectedSaveCancelledBeforeDispatchDoesNotPresentFailure() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        feature.selectLaunch(try XCTUnwrap(LaunchFixtures.launches().first), in: .operators)
        let model = OperatorLaunchDetailViewModel(feature: feature)
        let task = try XCTUnwrap(model.save())
        task.cancel()
        await task.value
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(feature.reminders.isEmpty)
    }
}
