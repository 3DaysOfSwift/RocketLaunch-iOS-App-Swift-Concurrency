import Foundation
import Observation
import XCTest
@testable import RocketLaunch

@MainActor
final class ReminderViewModelTests: XCTestCase {
    func testScreensObserveRestoredRemindersAndRemovalFromSharedFeature() async throws {
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let stored = LaunchReminder(launch: launch, notificationID: "saved-reminder",
            minutesBefore: 15, fireDate: Date().addingTimeInterval(3600), issue: nil)
        let persistence = ReminderScreenPersistence(reminders: [stored])
        let feature = LaunchScheduleFeature(sources: [],
            notificationClient: ReminderScreenNotifications(), reminderPersistence: persistence)
        let first = ReminderViewModel(feature: feature)
        let second = ReminderViewModel(feature: feature)
        let details = LaunchDetailScreenViewModel(feature: feature)
        XCTAssertTrue(first.reminders.isEmpty)
        let restored = expectation(description: "second screen observes restored state")
        withObservationTracking { _ = second.reminders } onChange: { restored.fulfill() }
        let firstLoad = first.loadIfNeeded()
        let secondLoad = second.loadIfNeeded()
        await firstLoad.value
        await secondLoad.value
        await waitFor([restored])
        XCTAssertEqual(first.reminders, [stored])
        XCTAssertEqual(second.reminders, [stored])
        XCTAssertTrue(second.contains(launch.id))
        XCTAssertTrue(details.contains(launch.id))
        let loadCount = await persistence.loadCount
        XCTAssertEqual(loadCount, 1)

        let removed = expectation(description: "second screen observes removal")
        withObservationTracking { _ = second.reminders } onChange: { removed.fulfill() }
        await feature.removeReminder(launch.id)
        await waitFor([removed])
        XCTAssertTrue(first.reminders.isEmpty)
        XCTAssertTrue(second.reminders.isEmpty)
        XCTAssertFalse(second.contains(launch.id))
        XCTAssertFalse(details.contains(launch.id))
        let saved = await persistence.reminders
        XCTAssertTrue(saved.isEmpty)
    }
}

private actor ReminderScreenPersistence: ReminderPersisting {
    private(set) var reminders: [LaunchReminder]
    private(set) var loadCount = 0
    init(reminders: [LaunchReminder]) { self.reminders = reminders }
    func load() async -> [LaunchReminder] { loadCount += 1; return reminders }
    func save(_ reminders: [LaunchReminder]) async { self.reminders = reminders }
}

private actor ReminderScreenNotifications: LaunchNotificationClient {
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {}
    func cancel(_ id: String) async {}
}
