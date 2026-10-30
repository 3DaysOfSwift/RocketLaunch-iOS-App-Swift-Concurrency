import Foundation
import Observation
import XCTest
@testable import RocketLaunch

@MainActor
final class RemindersViewModelTests: XCTestCase {
    func testReminderTimeBoundaryComesFromFeatureClock() throws {
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        let reminder = LaunchReminder(launch: launch, notificationID: "deadline", minutesBefore: 5, fireDate: deadline, issue: nil)
        let before = RemindersViewModel(launchScheduleFeature: LaunchScheduleFeature(sources: [], now: { deadline.addingTimeInterval(-1) }))
        let atDeadline = RemindersViewModel(launchScheduleFeature: LaunchScheduleFeature(sources: [], now: { deadline }))
        XCTAssertFalse(before.reminderTimeHasPassed(reminder))
        XCTAssertTrue(atDeadline.reminderTimeHasPassed(reminder))
    }

    func testRepeatedRemovalSharesTheInFlightTask() async throws {
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let reminder = LaunchReminder(launch: launch, notificationID: launch.id, minutesBefore: 15,
            fireDate: Date().addingTimeInterval(3600), issue: nil)
        let started = expectation(description: "removal save started")
        let storage = HeldReminderScreenPersistence(reminders: [reminder], onSave: { started.fulfill() })
        let feature = LaunchScheduleFeature(sources: [], notificationClient: ReminderScreenNotifications(), reminderPersistence: storage)
        let screen = RemindersViewModel(launchScheduleFeature: feature)
        await screen.loadIfNeeded().value
        let first = screen.remove(launch.id)
        await fulfillment(of: [started], timeout: 2)
        let second = screen.remove(launch.id)
        XCTAssertEqual(first, second)
        await storage.release()
        await first.value
        XCTAssertTrue(screen.reminders.isEmpty)
    }

    func testDistinctRemovalsQueueWhileTheFirstSaveIsSuspended() async throws {
        let launches = try LaunchFixtures.launches()
        let first = try XCTUnwrap(launches.first)
        let second = try XCTUnwrap(launches.dropFirst().first)
        let saved = [first, second].map { launch in
            LaunchReminder(launch: launch, notificationID: launch.id, minutesBefore: 15,
                fireDate: Date().addingTimeInterval(3600), issue: nil)
        }
        let started = expectation(description: "first removal starts saving")
        let storage = HeldReminderScreenPersistence(reminders: saved, onSave: { started.fulfill() })
        let feature = LaunchScheduleFeature(sources: [], notificationClient: ReminderScreenNotifications(), reminderPersistence: storage)
        let screen = RemindersViewModel(launchScheduleFeature: feature)
        await screen.loadIfNeeded().value
        screen.remove(first.id)
        await fulfillment(of: [started], timeout: 2)
        screen.remove(second.id)
        XCTAssertTrue(screen.isBusy)
        await storage.release()
        for _ in 0..<100 where screen.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(screen.isBusy)
        XCTAssertTrue(screen.reminders.isEmpty)
        let stored = await storage.reminders
        XCTAssertTrue(stored.isEmpty)
    }

    func testQueuedRemovalsFinishAfterScreenIsReleased() async throws {
        let launches = try LaunchFixtures.launches()
        let first = try XCTUnwrap(launches.first)
        let second = try XCTUnwrap(launches.dropFirst().first)
        let saved = [first, second].map { launch in
            LaunchReminder(launch: launch, notificationID: launch.id, minutesBefore: 15,
                fireDate: Date().addingTimeInterval(3600), issue: nil)
        }
        let started = expectation(description: "first save started")
        let finished = expectation(description: "both removals persisted")
        let storage = HeldReminderScreenPersistence(reminders: saved, onSave: { started.fulfill() },
            onEmpty: { finished.fulfill() })
        let feature = LaunchScheduleFeature(sources: [], notificationClient: ReminderScreenNotifications(), reminderPersistence: storage)
        var screen: RemindersViewModel? = RemindersViewModel(launchScheduleFeature: feature)
        await screen?.loadIfNeeded().value
        screen?.remove(first.id)
        await fulfillment(of: [started], timeout: 2)
        screen?.remove(second.id)
        weak var released = screen
        screen = nil
        XCTAssertNil(released)
        await storage.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(feature.reminders.isEmpty)
    }

    func testScreensObserveRestoredRemindersAndRemovalFromSharedFeature() async throws {
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        let stored = LaunchReminder(launch: launch, notificationID: "saved-reminder",
            minutesBefore: 15, fireDate: Date().addingTimeInterval(3600), issue: nil)
        let persistence = ReminderScreenPersistence(reminders: [stored])
        let feature = LaunchScheduleFeature(sources: [],
            notificationClient: ReminderScreenNotifications(), reminderPersistence: persistence)
        let first = RemindersViewModel(launchScheduleFeature: feature)
        let second = RemindersViewModel(launchScheduleFeature: feature)
        let details = LaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
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

private actor HeldReminderScreenPersistence: ReminderPersisting {
    private(set) var reminders: [LaunchReminder]
    private var continuation: CheckedContinuation<Void, Never>?
    private var hold = true
    private let onSave: @Sendable () -> Void
    private let onEmpty: (@Sendable () -> Void)?
    init(reminders: [LaunchReminder], onSave: @escaping @Sendable () -> Void, onEmpty: (@Sendable () -> Void)? = nil) {
        self.reminders = reminders; self.onSave = onSave; self.onEmpty = onEmpty
    }
    func load() -> [LaunchReminder] { reminders }
    func save(_ reminders: [LaunchReminder]) async {
        if hold {
            hold = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onSave()
            }
        }
        self.reminders = reminders
        if reminders.isEmpty { onEmpty?() }
    }
    func release() { continuation?.resume(); continuation = nil }
}
