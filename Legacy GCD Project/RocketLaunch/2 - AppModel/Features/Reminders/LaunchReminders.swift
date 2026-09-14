import Foundation
import UserNotifications

struct LaunchReminder: Identifiable, Codable, Equatable {
    var id: String { launch.id }
    var launch: RocketLaunch
    let notificationID: String
    let minutesBefore: Int
    let fireDate: Date
    var issue: String?
    var status: Status = .scheduled
    enum Status: String, Codable { case pending, scheduled, failed }

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
enum ReminderSaveOutcome: Equatable { case saved, superseded }

enum ReminderError: Error { case unknownTime, tooLate, denied, limit, launchUnavailable, invalidLeadTime }

/// Callbacks may arrive on any queue. The feature must re-enter its state queue.
protocol LaunchNotificationClient {
    func schedule(id: String, title: String, date: Date, askPermission: Bool, completion: @escaping (Result<Void, Error>) -> Void)
    func cancel(_ id: String, completion: @escaping () -> Void)
}

final class LocalLaunchNotifications: LaunchNotificationClient {
    private let queue = DispatchQueue(label: "rocketlaunch.notifications")
    // Accessed only on queue; constructing the dependency graph has no system side effects.
    private lazy var center = UNUserNotificationCenter.current()
    private var permissionWaiters: [(Result<Void, Error>) -> Void] = []
    private var checkingPermission = false
    private var mayAskPermission = false

    private func authorize(askPermission: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        permissionWaiters.append(completion)
        mayAskPermission = mayAskPermission || askPermission
        guard !checkingPermission else { return }
        checkingPermission = true
        center.getNotificationSettings { settings in
            self.queue.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.finishPermission(.success(()))
                case .notDetermined where self.mayAskPermission:
                    self.center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
                        self.queue.async {
                            if let error { self.finishPermission(.failure(error)) }
                            else { self.finishPermission(allowed ? .success(()) : .failure(ReminderError.denied)) }
                        }
                    }
                default: self.finishPermission(.failure(ReminderError.denied))
                }
            }
        }
    }
    private func finishPermission(_ result: Result<Void, Error>) {
        let waiters = permissionWaiters
        permissionWaiters.removeAll(); checkingPermission = false; mayAskPermission = false
        waiters.forEach { $0(result) }
    }
    func schedule(id: String, title: String, date: Date, askPermission: Bool,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            self.authorize(askPermission: askPermission) { result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success:
                    let content = UNMutableNotificationContent()
                    content.title = "Launch coming up"; content.body = title; content.sound = .default
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                    components.timeZone = Calendar.current.timeZone
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                        completion(error.map { .failure($0) } ?? .success(()))
                    }
                }
            }
        }
    }
    func cancel(_ id: String, completion: @escaping () -> Void) {
        queue.async { self.center.removePendingNotificationRequests(withIdentifiers: [id]); completion() }
    }
}

struct RemindersSnapshot: Equatable {
    let revision: UInt64
    let reminders: [LaunchReminder]
    static let initial = Self(revision: 0, reminders: [])
}

enum ReminderStorage { case memory, standard, suite(String) }
