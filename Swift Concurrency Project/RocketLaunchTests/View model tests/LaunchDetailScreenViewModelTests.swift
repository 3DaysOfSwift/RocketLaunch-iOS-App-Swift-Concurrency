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

    func testSelectionIsIndependentFromOtherTabsAndSaveUsesSelectedRecord() async throws {
        let records = try LaunchFixtures.launches()
        let selected = try XCTUnwrap(records.first)
        let other = try XCTUnwrap(records.dropFirst().first)
        XCTAssertNotEqual(selected.id, other.id)
        let feature = LaunchScheduleFeature(sources: [])
        feature.selectLaunch(selected, in: .next)
        let model = LaunchDetailScreenViewModel(feature: feature)
        model.minutesBefore = 60
        for context in LaunchSelectionContext.allCases where context != .next {
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
        let anotherScreen = LaunchDetailScreenViewModel(feature: feature)
        XCTAssertNil(anotherScreen.errorMessage)
        XCTAssertEqual(anotherScreen.minutesBefore, 15)
    }

    func testNoSelectionDoesNotStartSaving() {
        let model = LaunchDetailScreenViewModel(feature: LaunchScheduleFeature(sources: []))
        XCTAssertNil(model.launch)
        XCTAssertNil(model.save())
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
    }

    func testSelectedSaveCancelledBeforeDispatchDoesNotPresentFailure() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        feature.selectLaunch(try XCTUnwrap(LaunchFixtures.launches().first), in: .next)
        let model = LaunchDetailScreenViewModel(feature: feature)
        let task = try XCTUnwrap(model.save())
        task.cancel()
        await task.value
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(feature.reminders.isEmpty)
    }

    func testEachSourceScreenHandsSelectionToItsOwnDestination() async throws {
        let records = try LaunchFixtures.launches()
        let first = try XCTUnwrap(records.first)
        let second = try XCTUnwrap(records.dropFirst().first)
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(first))
        let feature = scenario.feature
        let next = LaunchScheduleViewModel(feature: feature)
        let upcoming = UpcomingViewModel(feature: feature)
        let operators = OperatorsViewModel(feature: feature)
        let operatorScreen = OperatorLaunchesViewModel(feature: feature)
        let updates = UpdatesViewModel(feature: feature)
        let reminders = ReminderViewModel(feature: feature)
        next.showLaunch(first)
        upcoming.showLaunch(second)
        updates.showLaunch(first)
        reminders.showLaunch(second)
        let selectedOperator = try XCTUnwrap(feature.operators.first)
        operators.showOperator(selectedOperator)
        XCTAssertTrue(operators.showingOperator)
        XCTAssertEqual(operatorScreen.title, selectedOperator.name)
        XCTAssertEqual(operatorScreen.launches, selectedOperator.launches)
        operatorScreen.showLaunch(first)
        XCTAssertTrue(next.showingLaunch && upcoming.showingLaunch && updates.showingLaunch
            && reminders.showingLaunch && operatorScreen.showingLaunch)
        let nextDetail = LaunchDetailScreenViewModel(feature: feature)
        let upcomingDetail = UpcomingLaunchDetailViewModel(feature: feature)
        XCTAssertEqual(nextDetail.launch, first)
        XCTAssertEqual(upcomingDetail.launch, second)
        XCTAssertEqual(OperatorLaunchDetailViewModel(feature: feature).launch, first)
        XCTAssertEqual(UpdatedLaunchDetailViewModel(feature: feature).launch, first)
        XCTAssertEqual(ReminderLaunchDetailViewModel(feature: feature).launch, second)
        upcoming.showingLaunch = false
        upcoming.showLaunch(first)
        XCTAssertEqual(upcomingDetail.launch, first)
        XCTAssertEqual(nextDetail.launch, first)
        XCTAssertEqual(ReminderLaunchDetailViewModel(feature: feature).launch, second)
        XCTAssertTrue(next.showingLaunch)
    }
}
