import Foundation
import UserNotifications

struct LaunchReminder: Identifiable, Codable, Equatable, Sendable {
    var id: String { launch.id }
    var launch: RocketLaunch
    let notificationID: String
    let minutesBefore: Int
    let fireDate: Date
    var issue: String?
    var status: Status = .scheduled
    enum Status: String, Codable, Sendable { case pending, scheduled, failed }

    init(launch: RocketLaunch, notificationID: String, minutesBefore: Int, fireDate: Date, issue: String?, status: Status = .scheduled) {
        self.launch = launch; self.notificationID = notificationID; self.minutesBefore = minutesBefore
        self.fireDate = fireDate; self.issue = issue; self.status = status
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

enum ReminderError: Error { case unknownTime, tooLate, denied, limit, launchUnavailable, invalidLeadTime }

protocol LaunchNotificationClient: Sendable {
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws
    func cancel(_ id: String) async
}

actor LocalLaunchNotifications: LaunchNotificationClient {
    // Permission is an explicitly owned system operation, shared by overlapping effects.
    private var permissionRequest: Task<Bool, any Error>?
    private func authorize(askPermission: Bool) async throws {
        if let pending = permissionRequest {
            guard try await pending.value else { throw ReminderError.denied }
            return
        }
        let center = UNUserNotificationCenter.current()
        if askPermission {
            let request = Task {
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    return try await center.requestAuthorization(options: [.alert, .sound])
                }
                return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
            permissionRequest = request
            defer { permissionRequest = nil }
            guard try await request.value else { throw ReminderError.denied }
        } else {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { throw ReminderError.denied }
        }
    }
    func schedule(id: String, title: String, date: Date, askPermission: Bool) async throws {
        try await authorize(askPermission: askPermission)
        let content = UNMutableNotificationContent()
        content.title = "Launch coming up"
        content.body = title
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = Calendar.current.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    func cancel(_ id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

struct RemindersSnapshot: Equatable, Sendable {
    let revision: UInt64
    let reminders: [LaunchReminder]
    static let initial = Self(revision: 0, reminders: [])
}

enum ReminderStorage: Sendable { case memory, standard, suite(String) }
