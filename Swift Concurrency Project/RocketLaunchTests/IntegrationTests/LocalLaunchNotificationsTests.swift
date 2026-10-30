import XCTest
import UserNotifications
@testable import RocketLaunch

@MainActor
final class LocalLaunchNotificationsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 2_000_000_000)

    func testSystemNotificationIsInstalledAndRemoved() async throws {
        let center = UNUserNotificationCenter.current()
        #if CFA_NOTIFICATION_SYSTEM_TEST
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        }
        #endif
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Notification permission is not granted for the test host.")
        }
        let id = "cfa-notification-test-" + UUID().uuidString
        defer { center.removePendingNotificationRequests(withIdentifiers: [id]) }
        let system = SystemLaunchNotifications()
        let date = Date().addingTimeInterval(3600)
        try await system.add(id: id, title: "Test launch", date: date)
        let pending = await center.pendingNotificationRequests()
        let request = try XCTUnwrap(pending.first { $0.identifier == id })
        XCTAssertEqual(request.content.body, "Test launch")
        XCTAssertNotNil(request.trigger as? UNCalendarNotificationTrigger)
        await system.remove(id)
        var remaining = await center.pendingNotificationRequests()
        for _ in 0..<20 where remaining.contains(where: { $0.identifier == id }) {
            try await Task.sleep(for: .milliseconds(100))
            remaining = await center.pendingNotificationRequests()
        }
        XCTAssertFalse(remaining.contains { $0.identifier == id })
    }

    func testFeatureSaveAndDeleteCoordinateWithSystemQueue() async throws {
        let center = UNUserNotificationCenter.current()
        #if CFA_NOTIFICATION_SYSTEM_TEST
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        }
        #endif
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Notification permission is not granted for the test host.")
        }
        let now = Date()
        let launch = RocketLaunch(id: "system-test-" + UUID().uuidString,
            source: .rocketLaunchLive, name: "Test launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: now.addingTimeInterval(7200)))
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive,
            repository: NotificationLaunchRepository(launch: launch))], now: { now })
        await feature.refresh()
        let result = try await feature.setReminder(for: launch.id, minutesBefore: 15)
        XCTAssertEqual(result, .saved)
        let reminder = try XCTUnwrap(feature.reminders.first)
        defer { center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationID]) }
        XCTAssertEqual(reminder.status, .scheduled)
        let installed = await center.pendingNotificationRequests()
        XCTAssertTrue(installed.contains { $0.identifier == reminder.notificationID })
        let replacementResult = try await feature.setReminder(for: launch.id, minutesBefore: 5)
        XCTAssertEqual(replacementResult, .saved)
        let replacement = try XCTUnwrap(feature.reminders.first)
        defer { center.removePendingNotificationRequests(withIdentifiers: [replacement.notificationID]) }
        XCTAssertNotEqual(replacement.notificationID, reminder.notificationID)
        var pending = await center.pendingNotificationRequests()
        for _ in 0..<20 where pending.contains(where: { $0.identifier == reminder.notificationID }) {
            try await Task.sleep(for: .milliseconds(100))
            pending = await center.pendingNotificationRequests()
        }
        XCTAssertFalse(pending.contains { $0.identifier == reminder.notificationID })
        XCTAssertTrue(pending.contains { $0.identifier == replacement.notificationID })
        await feature.removeReminder(launch.id)
        XCTAssertTrue(feature.reminders.isEmpty)
        pending = await center.pendingNotificationRequests()
        for _ in 0..<20 where pending.contains(where: { $0.identifier == replacement.notificationID }) {
            try await Task.sleep(for: .milliseconds(100))
            pending = await center.pendingNotificationRequests()
        }
        XCTAssertFalse(pending.contains { $0.identifier == replacement.notificationID })
    }

    func testFileBackedReminderSurvivesFeatureRecreationAndRemovesSystemNotification() async throws {
        let center = UNUserNotificationCenter.current()
        #if CFA_NOTIFICATION_SYSTEM_TEST
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        }
        #endif
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Notification permission is not granted for the test host.")
        }

        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        let suite = "rocket-integration-" + identifier
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let storage = ReminderStorage.file(directory.appendingPathComponent("reminders.json"), legacySuite: suite)
        let now = Date()
        let launch = RocketLaunch(id: identifier, source: .rocketLaunchLive, name: "Test launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: now.addingTimeInterval(7200)))
        let repository = NotificationLaunchRepository(launch: launch)
        let sources: [LaunchSourceConfiguration] = [.init(id: .rocketLaunchLive, repository: repository)]
        let feature = LaunchScheduleFeature(sources: sources, now: { now }, reminderStorage: storage)
        await feature.refresh()
        try await feature.setReminder(for: launch.id, minutesBefore: 15)
        let saved = try XCTUnwrap(feature.reminders.first)
        defer { center.removePendingNotificationRequests(withIdentifiers: [saved.notificationID]) }
        XCTAssertEqual(saved.status, .scheduled)
        let installed = await center.pendingNotificationRequests()
        XCTAssertTrue(installed.contains { $0.identifier == saved.notificationID })

        let restored = LaunchScheduleFeature(sources: sources, now: { now }, reminderStorage: storage)
        await restored.loadRemindersIfNeeded()
        XCTAssertEqual(restored.reminders, [saved])
        await restored.removeReminder(launch.id)
        XCTAssertTrue(restored.reminders.isEmpty)
        let loadedAfterRemoval = try await ReminderPersistence(storage: storage).load()
        XCTAssertTrue(loadedAfterRemoval.isEmpty)
        var pending = await center.pendingNotificationRequests()
        for _ in 0..<20 where pending.contains(where: { $0.identifier == saved.notificationID }) {
            try await Task.sleep(for: .milliseconds(100))
            pending = await center.pendingNotificationRequests()
        }
        XCTAssertFalse(pending.contains { $0.identifier == saved.notificationID })
    }

    func testProviderTimeChangeReplacesSystemNotification() async throws {
        let center = UNUserNotificationCenter.current()
        #if CFA_NOTIFICATION_SYSTEM_TEST
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        }
        #endif
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Notification permission is not granted for the test host.")
        }
        let now = Date()
        let id = "provider-test-" + UUID().uuidString
        let estimated = EstimatedLaunchDate(month: nil, day: nil, year: nil)
        let first = RocketLaunch(id: id, source: .rocketLaunchLive, name: "Test launch", missions: [],
            estimatedDate: estimated, details: LaunchDetails(plannedTime: now.addingTimeInterval(7200)))
        let updated = RocketLaunch(id: id, source: .rocketLaunchLive, name: "Test launch", missions: [],
            estimatedDate: estimated, details: LaunchDetails(plannedTime: now.addingTimeInterval(10800)))
        let repository = NotificationLaunchRepository(launch: first)
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)], now: { now })
        await feature.refresh()
        try await feature.setReminder(for: first.id, minutesBefore: 15)
        let original = try XCTUnwrap(feature.reminders.first)
        defer { center.removePendingNotificationRequests(withIdentifiers: [original.notificationID]) }
        await repository.update(updated)
        await feature.refresh()
        for _ in 0..<50 {
            if let current = feature.reminders.first, current.notificationID != original.notificationID, current.status == .scheduled { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let replacement = try XCTUnwrap(feature.reminders.first)
        defer { center.removePendingNotificationRequests(withIdentifiers: [replacement.notificationID]) }
        XCTAssertNotEqual(replacement.notificationID, original.notificationID)
        XCTAssertEqual(replacement.status, .scheduled)
        XCTAssertEqual(replacement.fireDate, now.addingTimeInterval(10800 - 900))
        var pending = await center.pendingNotificationRequests()
        for _ in 0..<20 where pending.contains(where: { $0.identifier == original.notificationID }) {
            try await Task.sleep(for: .milliseconds(100))
            pending = await center.pendingNotificationRequests()
        }
        XCTAssertFalse(pending.contains { $0.identifier == original.notificationID })
        XCTAssertTrue(pending.contains { $0.identifier == replacement.notificationID })
    }

    func testDetailScreensShowSavedReminderAndKeepTheirOwnEdits() async throws {
        let system = NotificationSystemStub(status: .authorized)
        let (feature, launch) = await reminderFeature(system: system)
        try await feature.setReminder(for: launch.id, minutesBefore: 5)
        let next = LaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        let schedule = UpcomingLaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        let operators = OperatorLaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        let changes = UpdatedLaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        let reminders = ReminderLaunchDetailViewModel(launch: launch, launchScheduleFeature: feature)
        XCTAssertEqual([next.minutesBefore, schedule.minutesBefore, operators.minutesBefore,
                        changes.minutesBefore, reminders.minutesBefore], [5, 5, 5, 5, 5])
        next.minutesBefore = 15
        try await feature.setReminder(for: launch.id, minutesBefore: 60)
        XCTAssertEqual(next.minutesBefore, 15)
        XCTAssertEqual(schedule.minutesBefore, 60)
        XCTAssertEqual(reminders.minutesBefore, 60)
    }

    func testPermissionFailureCanRetryAndInstallThenCancel() async throws {
        let system = NotificationSystemStub()
        let client = LocalLaunchNotifications(system: system)
        await system.failPermission()
        do {
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
            XCTFail("Expected permission error")
        } catch NotificationSystemStub.Failure.permission {}
        let failedEvents = await system.events
        XCTAssertEqual(failedEvents, ["status", "permission"])
        await system.allowPermission()
        try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
        let installed = await system.installed
        XCTAssertEqual(installed, [.init(id: "one", title: "Launch", date: date)])
        await client.cancel("one")
        let remaining = await system.installed
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeclinedPromptCanBeRetried() async throws {
        let system = NotificationSystemStub()
        let client = LocalLaunchNotifications(system: system)
        await system.setPermissionGranted(false)
        do {
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
            XCTFail("Expected declined prompt")
        } catch ReminderError.denied {}
        let before = await system.installed
        XCTAssertTrue(before.isEmpty)
        await system.setPermissionGranted(true)
        try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
        let events = await system.events
        XCTAssertEqual(events, ["status", "permission", "status", "permission", "add:one"])
    }

    func testDeniedPermissionNeverInstallsNotification() async throws {
        let system = NotificationSystemStub(status: .denied)
        let client = LocalLaunchNotifications(system: system)
        do {
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
            XCTFail("Expected denial")
        } catch ReminderError.denied {}
        let events = await system.events
        XCTAssertEqual(events, ["status"])
    }

    func testBackgroundSchedulingNeverPromptsForUndecidedPermission() async throws {
        let system = NotificationSystemStub()
        let client = LocalLaunchNotifications(system: system)
        do {
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: false)
            XCTFail("Expected denial without a prompt")
        } catch ReminderError.denied {}
        let events = await system.events
        XCTAssertEqual(events, ["status"])
    }

    func testExistingPermissionInstallsWithoutPrompt() async throws {
        for status in [UNAuthorizationStatus.authorized, .provisional] {
            let system = NotificationSystemStub(status: status)
            let client = LocalLaunchNotifications(system: system)
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
            let events = await system.events
            XCTAssertEqual(events, ["status", "add:one"])
        }
    }

    func testInstallationFailurePropagatesAndAllowsRetry() async throws {
        let system = NotificationSystemStub(status: .authorized)
        let client = LocalLaunchNotifications(system: system)
        await system.setInstallationFailure(true)
        do {
            try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
            XCTFail("Expected installation failure")
        } catch NotificationSystemStub.Failure.installation {}
        let failed = await system.installed
        XCTAssertTrue(failed.isEmpty)
        await system.setInstallationFailure(false)
        try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true)
        let installed = await system.installed
        XCTAssertEqual(installed, [.init(id: "one", title: "Launch", date: date)])
        let events = await system.events
        XCTAssertEqual(events, ["status", "add:one", "status", "add:one"])
    }

    func testCallerCancellationDuringPermissionKeepsAcceptedSaveConsistent() async throws {
        let requested = expectation(description: "permission pending")
        let system = NotificationSystemStub(onPermission: { requested.fulfill() })
        let (feature, launch) = await reminderFeature(system: system)
        let save = Task { try await feature.setReminder(for: launch.id, minutesBefore: 5) }
        await waitFor([requested])
        XCTAssertEqual(feature.reminders.first?.status, .pending)
        save.cancel()
        await system.finishPermission()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(feature.reminders.first?.status, .scheduled)
        let installed = await system.installed
        XCTAssertEqual(installed.map(\.id), feature.reminders.map(\.notificationID))
        XCTAssertEqual(installed.count, 1)
    }

    func testRemovalDuringPermissionCleansLateInstallation() async throws {
        let requested = expectation(description: "permission pending")
        let system = NotificationSystemStub(onPermission: { requested.fulfill() })
        let (feature, launch) = await reminderFeature(system: system)
        let save = Task { try await feature.setReminder(for: launch.id, minutesBefore: 5) }
        await waitFor([requested])
        await feature.removeReminder(launch.id)
        await system.finishPermission()
        let outcome = try await save.value
        XCTAssertEqual(outcome, .superseded)
        XCTAssertTrue(feature.reminders.isEmpty)
        let installed = await system.installed
        XCTAssertTrue(installed.isEmpty)
    }

    private func reminderFeature(system: NotificationSystemStub) async -> (LaunchScheduleFeature, RocketLaunch) {
        let now = date
        let launch = RocketLaunch(id: "permission", source: .rocketLaunchLive, name: "Launch", missions: [],
            estimatedDate: .init(month: nil, day: nil, year: nil),
            details: .init(plannedTime: now.addingTimeInterval(7200)))
        let feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: NotificationLaunchRepository(launch: launch))],
            now: { now }, notificationClient: LocalLaunchNotifications(system: system))
        await feature.refresh()
        return (feature, launch)
    }

    func testInstallationWaitsForPermissionResponse() async throws {
        let requested = expectation(description: "permission pending")
        let system = NotificationSystemStub(onPermission: { requested.fulfill() })
        let client = LocalLaunchNotifications(system: system)
        let task = Task { try await client.schedule(id: "one", title: "Launch", date: date, askPermission: true) }
        await waitFor([requested])
        let before = await system.installed
        XCTAssertTrue(before.isEmpty)
        await system.finishPermission()
        try await task.value
        let after = await system.installed
        XCTAssertEqual(after, [.init(id: "one", title: "Launch", date: date)])
    }
}

private actor NotificationSystemStub: LaunchNotificationSystem {
    enum Failure: Error { case permission, installation }
    struct Installed: Equatable, Sendable {
        let id: String
        let title: String
        let date: Date
    }
    private let status: UNAuthorizationStatus
    private let onPermission: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<Void, Never>?
    private var installationFails = false
    func setInstallationFailure(_ value: Bool) { installationFails = value }
    private var permissionFails = false
    private var permissionGranted = true
    private(set) var events: [String] = []
    private(set) var installed: [Installed] = []
    init(status: UNAuthorizationStatus = .notDetermined, onPermission: (@Sendable () -> Void)? = nil) {
        self.status = status
        self.onPermission = onPermission
    }
    func setPermissionGranted(_ value: Bool) { permissionGranted = value }
    func failPermission() { permissionFails = true }
    func allowPermission() { permissionFails = false }
    func finishPermission() { pending?.resume(); pending = nil }
    func authorizationStatus() -> UNAuthorizationStatus { events.append("status"); return status }
    func requestAuthorization() async throws -> Bool {
        events.append("permission")
        if let onPermission {
            await withCheckedContinuation { pending = $0; onPermission() }
        }
        if permissionFails { throw Failure.permission }
        return permissionGranted
    }
    func add(id: String, title: String, date: Date) throws {
        events.append("add:" + id)
        if installationFails { throw Failure.installation }
        installed.append(.init(id: id, title: title, date: date))
    }
    func remove(_ id: String) {
        events.append("remove:" + id)
        installed.removeAll { $0.id == id }
    }
}

private actor NotificationLaunchRepository: LaunchRepository {
    private var launch: RocketLaunch
    init(launch: RocketLaunch) { self.launch = launch }
    func update(_ launch: RocketLaunch) { self.launch = launch }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] { [launch] }
}
