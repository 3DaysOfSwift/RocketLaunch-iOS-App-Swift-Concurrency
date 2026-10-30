import XCTest
@testable import RocketLaunch

@MainActor
final class LaunchDetailViewModelTests: XCTestCase {
    func testFailureIsOwnedByTheScreenThatRequestedIt() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        let first = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
        let second = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
        await first.save("missing", minutesBefore: 15).value
        XCTAssertEqual(first.errorMessage, "Refresh the schedule and open the launch again before setting a reminder.")
        XCTAssertNil(second.errorMessage)
        XCTAssertFalse(first.isBusy)
        XCTAssertFalse(second.isBusy)
        XCTAssertFalse(first.contains("missing"))
    }

    func testCancellationBeforeDispatchDoesNotPresentAnError() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        let viewModel = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
        let save = viewModel.save("missing", minutesBefore: 15)
        save.cancel()
        await save.value
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertTrue(feature.reminders.isEmpty)
    }

    func testReleasingScreenCancelsItsPendingSave() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        var screen: LaunchDetailViewModel? = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
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
        let model = LaunchDetailViewModel(launch: selected, launchScheduleFeature: feature)
        model.minutesBefore = 60
        let otherScreen = LaunchDetailViewModel(launch: other, launchScheduleFeature: feature)
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
        let anotherScreen = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
        XCTAssertNil(anotherScreen.errorMessage)
        XCTAssertEqual(anotherScreen.minutesBefore, 15)
    }

    func testSelectedSaveCancelledBeforeDispatchDoesNotPresentFailure() async throws {
        let feature = LaunchScheduleFeature(sources: [])
        let model = LaunchDetailViewModel(launch: try XCTUnwrap(LaunchFixtures.launches().first), launchScheduleFeature: feature)
        let task = try XCTUnwrap(model.save())
        task.cancel()
        await task.value
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(feature.reminders.isEmpty)
    }

    func testSaveExplainsWhenDisplayedLaunchTimeIsOutOfDate() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let estimated = EstimatedLaunchDate(month: nil, day: nil, year: nil)
        let displayed = RocketLaunch(id: "stale", source: .rocketLaunchLive, name: "Launch",
            missions: [], estimatedDate: estimated, details: LaunchDetails(plannedTime: date))
        let latest = RocketLaunch(id: "stale", source: .rocketLaunchLive, name: "Launch",
            missions: [], estimatedDate: estimated, details: LaunchDetails(plannedTime: date.addingTimeInterval(3600)))
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(latest))
        let screen = LaunchDetailViewModel(launch: displayed, launchScheduleFeature: scenario.feature)
        let save = try XCTUnwrap(screen.save())
        await save.value
        XCTAssertEqual(screen.launch, displayed)
        XCTAssertEqual(screen.errorMessage, "The launch time has changed. Go back and open the latest launch before setting a reminder.")
        XCTAssertTrue(scenario.feature.reminders.isEmpty)
    }

    func testIndependentDetailsKeepTheirSnapshotsWhenCatalogueChanges() async throws {
        let records = try LaunchFixtures.launches()
        let first = try XCTUnwrap(records.first)
        let second = try XCTUnwrap(records.dropFirst().first)
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(first))
        let feature = scenario.feature
        let sceneOne = LaunchDetailViewModel(launch: first, launchScheduleFeature: feature)
        let sceneTwo = LaunchDetailViewModel(launch: second, launchScheduleFeature: feature)
        await scenario.repository.respond(.success([]))
        await feature.refresh()
        XCTAssertTrue(feature.sources.first?.launches.isEmpty == true)
        XCTAssertEqual(sceneOne.launch, first)
        XCTAssertEqual(sceneTwo.launch, second)
        XCTAssertNotEqual(sceneOne.launch?.id, sceneTwo.launch?.id)
    }

    func testEachSourceScreenHandsSelectionToItsOwnDestination() async throws {
        let records = try LaunchFixtures.launches()
        let first = try XCTUnwrap(records.first)
        let second = try XCTUnwrap(records.dropFirst().first)
        let scenario = LaunchScenario()
        await scenario.prepare(.loaded(first))
        let feature = scenario.feature
        let next = LaunchScheduleViewModel(launchScheduleFeature: feature)
        let upcoming = UpcomingViewModel(launchScheduleFeature: feature)
        let operators = OperatorsViewModel(launchScheduleFeature: feature)
        let updates = UpdatesViewModel(launchScheduleFeature: feature)
        let reminders = RemindersViewModel(launchScheduleFeature: feature)
        next.showLaunch(first)
        upcoming.showLaunch(second)
        updates.showLaunch(first)
        reminders.showLaunch(second)
        let selectedOperator = try XCTUnwrap(feature.operators.first)
        operators.showOperator(selectedOperator)
        let operatorScreen = OperatorLaunchesViewModel(operator: try XCTUnwrap(operators.selectedOperator), launchScheduleFeature: feature)
        XCTAssertTrue(operators.showingOperator)
        XCTAssertEqual(operatorScreen.title, selectedOperator.name)
        XCTAssertEqual(operatorScreen.launches, selectedOperator.launches)
        operatorScreen.showLaunch(first)
        XCTAssertTrue(next.showingLaunch && upcoming.showingLaunch && updates.showingLaunch
            && reminders.showingLaunch && operatorScreen.showingLaunch)
        let nextDetail = LaunchDetailViewModel(launch: try XCTUnwrap(next.selectedLaunch), launchScheduleFeature: feature)
        let upcomingDetail = UpcomingLaunchDetailViewModel(launch: try XCTUnwrap(upcoming.selectedLaunch), launchScheduleFeature: feature)
        XCTAssertEqual(nextDetail.launch, first)
        XCTAssertEqual(upcomingDetail.launch, second)
        XCTAssertEqual(OperatorLaunchDetailViewModel(launch: try XCTUnwrap(operatorScreen.selectedLaunch), launchScheduleFeature: feature).launch, first)
        XCTAssertEqual(UpdatedLaunchDetailViewModel(launch: try XCTUnwrap(updates.selectedLaunch), launchScheduleFeature: feature).launch, first)
        XCTAssertEqual(ReminderLaunchDetailViewModel(launch: try XCTUnwrap(reminders.selectedLaunch), launchScheduleFeature: feature).launch, second)
        upcoming.showingLaunch = false
        upcoming.showLaunch(first)
        XCTAssertEqual(upcomingDetail.launch, second)
        XCTAssertEqual(nextDetail.launch, first)
        XCTAssertEqual(ReminderLaunchDetailViewModel(launch: try XCTUnwrap(reminders.selectedLaunch), launchScheduleFeature: feature).launch, second)
        XCTAssertTrue(next.showingLaunch)
    }
}
