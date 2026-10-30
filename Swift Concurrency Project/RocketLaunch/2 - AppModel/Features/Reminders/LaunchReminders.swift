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
    let obsoleteNotificationIDs: [String]
    enum Status: String, Codable, Sendable { case pending, scheduled, failed, deletionPending }

    func hasPassed(at date: Date) -> Bool { fireDate <= date }

    init(launch: RocketLaunch, notificationID: String, minutesBefore: Int, fireDate: Date, issue: String?, status: Status = .scheduled, obsoleteNotificationIDs: [String] = []) {
        self.launch = launch; self.notificationID = notificationID; self.minutesBefore = minutesBefore
        self.fireDate = fireDate; self.issue = issue; self.status = status
        self.obsoleteNotificationIDs = obsoleteNotificationIDs
    }
    func replacing(launch: RocketLaunch? = nil, status: Status? = nil, issue: String?? = nil, obsoleteNotificationIDs: [String]? = nil) -> LaunchReminder {
        LaunchReminder(launch: launch ?? self.launch, notificationID: notificationID,
            minutesBefore: minutesBefore, fireDate: fireDate, issue: issue ?? self.issue,
            status: status ?? self.status, obsoleteNotificationIDs: obsoleteNotificationIDs ?? self.obsoleteNotificationIDs)
    }
    private enum CodingKeys: String, CodingKey { case launch, notificationID, minutesBefore, fireDate, issue, status, obsoleteNotificationIDs }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launch = try values.decode(RocketLaunch.self, forKey: .launch)
        notificationID = try values.decode(String.self, forKey: .notificationID)
        minutesBefore = try values.decode(Int.self, forKey: .minutesBefore)
        fireDate = try values.decode(Date.self, forKey: .fireDate)
        issue = try values.decodeIfPresent(String.self, forKey: .issue)
        status = try values.decodeIfPresent(Status.self, forKey: .status) ?? (issue == nil ? .scheduled : .failed)
        obsoleteNotificationIDs = try values.decodeIfPresent([String].self, forKey: .obsoleteNotificationIDs) ?? []
    }
}

/// Saved confirms accepted scheduling, not alert delivery; superseded means newer desired state replaced it.
enum ReminderSaveOutcome: Equatable, Sendable { case saved, superseded }

enum ReminderError: Error { case unknownTime, tooLate, denied, limit, launchUnavailable, invalidLeadTime, storageUnavailable, storageWriteFailed, launchTimeChanged }

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

enum ReminderStorage: Sendable { case memory, standard, suite(String), file(URL, legacySuite: String) }

/// Serializes stored reminder snapshots without owning the application's live state.
protocol ReminderPersisting: Sendable {
    func load() async throws -> [LaunchReminder]
    func save(_ reminders: [LaunchReminder]) async throws
}

actor ReminderPersistence: ReminderPersisting {
    enum StorageError: Error { case unavailable }
    private let storage: ReminderStorage
    private var defaults: UserDefaults?
    private var memoryData: Data?
    private var fileURL: URL?
    private var opened = false
    private static let fileCreatedKey = "rocketlaunch.reminders.fileCreated.v1"

    init(storage: ReminderStorage) { self.storage = storage }

    private func openIfNeeded() throws {
        guard !opened else { return }
        switch storage {
        case .memory: defaults = nil
        case .standard:
            defaults = .standard
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileURL = directory.appendingPathComponent("RocketLaunch", isDirectory: true).appendingPathComponent("reminders-v1.json")
        case .suite(let name):
            guard let suite = UserDefaults(suiteName: name) else { throw StorageError.unavailable }
            defaults = suite
        case .file(let url, let name):
            guard let suite = UserDefaults(suiteName: name) else { throw StorageError.unavailable }
            defaults = suite
            fileURL = url
        }
        opened = true
    }

    func load() throws -> [LaunchReminder] {
        try openIfNeeded()
        let data: Data?
        switch storage {
        case .memory: data = memoryData
        case .suite: data = defaults?.data(forKey: "rocketlaunch.reminders.v1")
        case .standard, .file:
            guard let fileURL else { throw StorageError.unavailable }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                data = try Data(contentsOf: fileURL)
            } else if defaults?.bool(forKey: Self.fileCreatedKey) == true {
                // The legacy backup is no longer current once file storage has been used.
                throw StorageError.unavailable
            } else if let legacyValue = defaults?.object(forKey: "rocketlaunch.reminders.v1") {
                guard let legacy = legacyValue as? Data else { throw StorageError.unavailable }
                // Validate before copying and retain the old value as a recovery backup.
                _ = try JSONDecoder().decode([LaunchReminder].self, from: legacy)
                try writeFile(legacy, to: fileURL)
                data = legacy
            } else { data = nil }
        }
        guard let data else { return [] }
        let reminders = try JSONDecoder().decode([LaunchReminder].self, from: data)
        switch storage {
        case .standard, .file: defaults?.set(true, forKey: Self.fileCreatedKey)
        case .memory, .suite: break
        }
        return reminders
    }

    private func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func save(_ reminders: [LaunchReminder]) throws {
        try openIfNeeded()
        let data = try JSONEncoder().encode(reminders)
        switch storage {
        case .memory: memoryData = data
        case .suite: defaults?.set(data, forKey: "rocketlaunch.reminders.v1")
        case .standard, .file:
            guard let fileURL else { throw StorageError.unavailable }
            try writeFile(data, to: fileURL)
            defaults?.set(true, forKey: Self.fileCreatedKey)
        }
    }
}
