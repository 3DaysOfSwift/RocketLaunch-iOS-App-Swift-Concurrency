import Foundation
import UserNotifications

struct LaunchReminder: Identifiable, Codable, Equatable, Sendable {
    var id: String { launch.id }
    let launch: RocketLaunch
    let notificationID: String
    let minutesBefore: Int
    let fireDate: Date
    let issue: String?
    let status: Status
    enum Status: String, Codable, Sendable { case pending, scheduled, failed }

    init(launch: RocketLaunch, notificationID: String, minutesBefore: Int, fireDate: Date, issue: String?, status: Status = .scheduled) {
        self.launch = launch; self.notificationID = notificationID; self.minutesBefore = minutesBefore
        self.fireDate = fireDate; self.issue = issue; self.status = status
    }
    func replacing(launch: RocketLaunch? = nil, status: Status? = nil, issue: String?? = nil) -> LaunchReminder {
        LaunchReminder(launch: launch ?? self.launch, notificationID: notificationID,
            minutesBefore: minutesBefore, fireDate: fireDate, issue: issue ?? self.issue,
            status: status ?? self.status)
    }
    private enum CodingKeys: String, CodingKey { case launch, notificationID, minutesBefore, fireDate, issue, status }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launch = try values.decode(RocketLaunch.self, forKey: .launch)
        notificationID = try values.decode(String.self, forKey: .notificationID)
        minutesBefore = try values.decode(Int.self, forKey: .minutesBefore)
        fireDate = try values.decode(Date.self, forKey: .fireDate)
        issue = try values.decodeIfPresent(String.self, forKey: .issue)
        status = try values.decodeIfPresent(Status.self, forKey: .status) ?? (issue == nil ? .scheduled : .failed)
    }
}

/// Saved confirms accepted scheduling, not alert delivery; superseded means newer desired state replaced it.
enum ReminderSaveOutcome: Equatable, Sendable { case saved, superseded }

enum ReminderError: Error { case unknownTime, tooLate, denied, limit, launchUnavailable, invalidLeadTime, storageUnavailable, storageWriteFailed }

protocol LaunchNotificationClient: Sendable {
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws
    func cancel(_ id: String) async
}

protocol LaunchNotificationSystem: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(id: String, title: String, date: Date) async throws
    func remove(_ id: String) async
}

struct SystemLaunchNotifications: LaunchNotificationSystem {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func add(id: String, title: String, date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Launch coming up"
        content.body = title
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = Calendar.current.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    func remove(_ id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

actor LocalLaunchNotifications: LaunchNotificationClient {
    private let system: any LaunchNotificationSystem
    init(system: any LaunchNotificationSystem = SystemLaunchNotifications()) { self.system = system }

    // Permission is an explicitly owned system operation, shared by overlapping effects.
    private var permissionRequest: Task<Bool, any Error>?
    private func authorize(askPermission: Bool) async throws {
        if let pending = permissionRequest {
            guard try await pending.value else { throw ReminderError.denied }
            return
        }
        let system = system
        if askPermission {
            let request = Task {
                let status = await system.authorizationStatus()
                if status == .notDetermined { return try await system.requestAuthorization() }
                return status == .authorized || status == .provisional
            }
            permissionRequest = request
            defer { permissionRequest = nil }
            guard try await request.value else { throw ReminderError.denied }
        } else {
            let status = await system.authorizationStatus()
            guard status == .authorized || status == .provisional else { throw ReminderError.denied }
        }
    }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        try await authorize(askPermission: askPermission)
        try await system.add(id: id, title: title, date: date)
    }
    func cancel(_ id: String) async { await system.remove(id) }
}

struct RemindersSnapshot: Equatable, Sendable {
    let revision: UInt64
    let reminders: [LaunchReminder]
    static let initial = Self(revision: 0, reminders: [])
}

enum ReminderStorage: Sendable { case memory, standard, suite(String) }

/// Serializes stored reminder snapshots without owning the application's live state.
protocol ReminderPersisting: Sendable {
    func load() async throws -> [LaunchReminder]
    func save(_ reminders: [LaunchReminder]) async throws
}

actor ReminderPersistence: ReminderPersisting {
    private let storage: ReminderStorage
    private var defaults: UserDefaults?
    private var opened = false

    init(storage: ReminderStorage) { self.storage = storage }

    private func openIfNeeded() {
        guard !opened else { return }
        opened = true
        switch storage {
        case .memory: defaults = nil
        case .standard: defaults = .standard
        case .suite(let name): defaults = UserDefaults(suiteName: name)
        }
    }

    func load() throws -> [LaunchReminder] {
        openIfNeeded()
        guard let data = defaults?.data(forKey: "rocketlaunch.reminders.v1") else { return [] }
        return try JSONDecoder().decode([LaunchReminder].self, from: data)
    }

    func save(_ reminders: [LaunchReminder]) throws {
        openIfNeeded()
        let data = try JSONEncoder().encode(reminders)
        defaults?.set(data, forKey: "rocketlaunch.reminders.v1")
    }
}
