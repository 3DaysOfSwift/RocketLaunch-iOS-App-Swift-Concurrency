import Foundation
import Observation
import UserNotifications

@MainActor
protocol RemindersFeatureAPI: AnyObject {
    var reminders: [LaunchReminder] { get }
    func save(_ launch: RocketLaunch, minutesBefore: Int) async throws
    func remove(_ id: String) async
    func reconcile(_ launches: [RocketLaunch]) async
}

@MainActor @Observable
final class RemindersFeature: RemindersFeatureAPI {
    private(set) var reminders: [LaunchReminder]
    @ObservationIgnored private let client: any LaunchNotificationClient
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var operations: [String: UUID] = [:]
    private static let storageKey = "rocketlaunch.reminders.v1"

    init(client: any LaunchNotificationClient = LocalLaunchNotifications(), defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init) {
        self.client = client; self.defaults = defaults; self.now = now
        reminders = defaults?.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([LaunchReminder].self, from: $0) } ?? []
    }

    func save(_ launch: RocketLaunch, minutesBefore: Int = 15) async throws {
        try await schedule(launch, minutesBefore: minutesBefore, askPermission: true)
    }

    private func schedule(_ launch: RocketLaunch, minutesBefore: Int, askPermission: Bool) async throws {
        let token = UUID(); operations[launch.id] = token
        defer { if operations[launch.id] == token { operations[launch.id] = nil } }
        guard let time = launch.details.plannedTime else { throw ReminderError.unknownTime }
        let fireDate = time.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > now() else { throw ReminderError.tooLate }
        guard reminders.count < 50 || reminders.contains(where: { $0.id == launch.id }) else { throw ReminderError.limit }
        let notificationID = "rocketlaunch." + token.uuidString
        do {
            try await client.schedule(id: notificationID, title: launch.name, date: fireDate, askPermission: askPermission)
        } catch {
            if operations[launch.id] == token { operations[launch.id] = nil }
            throw error
        }
        guard operations[launch.id] == token else { await client.cancel(notificationID); return }
        operations[launch.id] = nil
        let old = reminders.first(where: { $0.id == launch.id })
        reminders.removeAll { $0.id == launch.id }
        reminders.append(.init(launch: launch, notificationID: notificationID, minutesBefore: minutesBefore, fireDate: fireDate, issue: nil))
        reminders.sort { $0.fireDate < $1.fireDate }; persist()
        if let old { await client.cancel(old.notificationID) }
    }

    func remove(_ id: String) async {
        operations[id] = nil
        let existing = reminders.first(where: { $0.id == id })
        reminders.removeAll { $0.id == id }; persist()
        if let existing { await client.cancel(existing.notificationID) }
    }

    func reconcile(_ launches: [RocketLaunch]) async {
        for launch in launches {
            guard let old = reminders.first(where: { $0.id == launch.id }),
                  old.launch.details.plannedTime != launch.details.plannedTime else { continue }
            do { try await schedule(launch, minutesBefore: old.minutesBefore, askPermission: false) }
            catch {
                guard operations[launch.id] == nil,
                      let index = reminders.firstIndex(where: { $0.id == launch.id && $0.notificationID == old.notificationID && $0.launch == old.launch }) else { continue }
                reminders[index].issue = "Launch time changed. Open this launch to set a new reminder."
                reminders[index].launch = launch
                persist()
                await client.cancel(old.notificationID)
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) { defaults?.set(data, forKey: Self.storageKey) }
    }
}

struct LaunchReminder: Identifiable, Codable, Equatable, Sendable {
    var id: String { launch.id }
    var launch: RocketLaunch
    let notificationID: String
    let minutesBefore: Int
    let fireDate: Date
    var issue: String?
}

enum ReminderError: Error { case unknownTime, tooLate, denied, limit }

protocol LaunchNotificationClient: Sendable {
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws
    func cancel(_ id: String) async
}

actor LocalLaunchNotifications: LaunchNotificationClient {
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && askPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw ReminderError.denied }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            throw ReminderError.denied
        }
        let content = UNMutableNotificationContent()
        content.title = "Launch coming up"
        content.body = title
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = Calendar.current.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    func cancel(_ id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
