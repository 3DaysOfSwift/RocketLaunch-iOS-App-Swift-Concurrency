import XCTest
import UserNotifications
@testable import RocketLaunch

@MainActor
final class LocalLaunchNotificationsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 2_000_000_000)

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
    enum Failure: Error { case permission }
    struct Installed: Equatable, Sendable {
        let id: String
        let title: String
        let date: Date
    }
    private let status: UNAuthorizationStatus
    private let onPermission: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<Void, Never>?
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
    func add(id: String, title: String, date: Date) {
        events.append("add:" + id)
        installed.append(.init(id: id, title: title, date: date))
    }
    func remove(_ id: String) {
        events.append("remove:" + id)
        installed.removeAll { $0.id == id }
    }
}
