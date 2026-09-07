import Foundation
import UserNotifications

protocol RemindersFeatureAPI: AnyObject, Sendable {
    var snapshot: RemindersSnapshot { get async }
    func snapshots() async -> AsyncStream<RemindersSnapshot>
    @discardableResult func save(_ launch: RocketLaunch, minutesBefore: Int) async throws -> ReminderSaveOutcome
    func remove(_ id: String) async
    func reconcile(_ update: LaunchSourceUpdate) async
}

actor RemindersFeature: RemindersFeatureAPI {
    private(set) var reminders: [LaunchReminder] = []
    private let client: any LaunchNotificationClient
    private var defaults: UserDefaults?
    private let storage: ReminderStorage
    private var hasLoaded = false
    private let now: @Sendable () -> Date
    private struct PendingOperation {
        let token: UUID
        let launch: RocketLaunch
    }
    private var operations: [String: PendingOperation] = [:]
    private static let storageKey = "rocketlaunch.reminders.v1"

    init(client: any LaunchNotificationClient = LocalLaunchNotifications(), storage: ReminderStorage = .memory, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.storage = storage; self.now = now
    }

    private var revision: UInt64 = 0
    private var observers: [UUID: AsyncStream<RemindersSnapshot>.Continuation] = [:]
    var snapshot: RemindersSnapshot {
        loadIfNeeded()
        return .init(revision: revision, reminders: reminders)
    }
    func snapshots() -> AsyncStream<RemindersSnapshot> {
        loadIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<RemindersSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        continuation.yield(snapshot)
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish() {
        revision += 1
        let value = snapshot
        for observer in observers.values { observer.yield(value) }
    }
    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        switch storage {
        case .memory: defaults = nil
        case .standard: defaults = .standard
        case .suite(let name): defaults = UserDefaults(suiteName: name)
        }
        reminders = defaults?.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([LaunchReminder].self, from: $0) } ?? []
    }
    deinit { for observer in observers.values { observer.finish() } }

    @discardableResult
    func save(_ launch: RocketLaunch, minutesBefore: Int = 15) async throws -> ReminderSaveOutcome {
        loadIfNeeded()
        return try await schedule(launch, minutesBefore: minutesBefore, askPermission: true)
    }

    private func schedule(_ launch: RocketLaunch, minutesBefore: Int, askPermission: Bool, update: LaunchSourceUpdate? = nil) async throws -> ReminderSaveOutcome {
        let occupied = Set(reminders.map(\.id)).union(operations.keys)
        // Even a replacement with an unknown time supersedes the older operation.
        let token = UUID(); operations[launch.id] = .init(token: token, launch: launch)
        defer { if operations[launch.id]?.token == token { operations[launch.id] = nil } }
        guard let time = launch.details.plannedTime else { throw ReminderError.unknownTime }
        let fireDate = time.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > now() else { throw ReminderError.tooLate }
        // Reserve a logical slot before awaiting the notification service. Replacements
        // reuse their launch's slot; concurrent additions cannot both claim slot 50.
        guard occupied.count < 50 || occupied.contains(launch.id) else { throw ReminderError.limit }
        let notificationID = "rocketlaunch." + token.uuidString
        do {
            try await client.schedule(id: notificationID, title: launch.name, date: fireDate, askPermission: askPermission)
        } catch {
            guard operations[launch.id]?.token == token, isCurrent(update) else {
                await client.cancel(notificationID)
                return .superseded
            }
            throw error
        }
        guard operations[launch.id]?.token == token, isCurrent(update) else {
            await client.cancel(notificationID)
            return .superseded
        }
        operations[launch.id] = nil
        let old = reminders.first(where: { $0.id == launch.id })
        reminders.removeAll { $0.id == launch.id }
        reminders.append(.init(launch: launch, notificationID: notificationID, minutesBefore: minutesBefore, fireDate: fireDate, issue: nil))
        reminders.sort { $0.fireDate < $1.fireDate }; persist()
        if let old { await client.cancel(old.notificationID) }
        return .saved
    }

    func remove(_ id: String) async {
        loadIfNeeded()
        operations[id] = nil
        let existing = reminders.first(where: { $0.id == id })
        reminders.removeAll { $0.id == id }; persist()
        if let existing { await client.cancel(existing.notificationID) }
    }

    private var sourceRevisions: [LaunchSourceID: UInt64] = [:]
    private func isCurrent(_ update: LaunchSourceUpdate?) -> Bool {
        guard let update else { return true } // An explicit user command has its own operation token.
        return sourceRevisions[update.source] == update.revision
    }

    func reconcile(_ update: LaunchSourceUpdate) async {
        loadIfNeeded()
        guard sourceRevisions[update.source].map({ update.revision > $0 }) ?? true else { return }
        sourceRevisions[update.source] = update.revision
        // Invalidate every changed pending save before suspending for any existing
        // reminder. First saves may still be awaiting notification permission and
        // therefore have no persisted record for the reconciliation loop to find.
        for launch in update.launches where launch.source == update.source {
            if let pending = operations[launch.id],
               pending.launch.details.plannedTime != launch.details.plannedTime {
                operations[launch.id] = nil
            }
        }
        for launch in update.launches where launch.source == update.source {
            // A newer response supersedes this entire reconciliation, including a
            // suspended reschedule when the newer time matches the saved reminder.
            guard isCurrent(update) else { return }
            guard let old = reminders.first(where: { $0.id == launch.id }),
                  old.launch.details.plannedTime != launch.details.plannedTime else { continue }
            do { _ = try await schedule(launch, minutesBefore: old.minutesBefore, askPermission: false, update: update) }
            catch {
                guard isCurrent(update), operations[launch.id] == nil,
                      let index = reminders.firstIndex(where: { $0.id == launch.id && $0.notificationID == old.notificationID && $0.launch == old.launch }) else { continue }
                reminders[index].issue = "Launch time changed. Open this launch to set a new reminder."
                reminders[index].launch = launch
                persist()
                await client.cancel(old.notificationID)
            }
        }
    }

    private func persist() {
        publish()
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

/// Saved means this command committed; superseded means it did not commit.
enum ReminderSaveOutcome: Equatable, Sendable { case saved, superseded }

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

struct RemindersSnapshot: Equatable, Sendable {
    let revision: UInt64
    let reminders: [LaunchReminder]
    static let initial = Self(revision: 0, reminders: [])
}

enum ReminderStorage: Sendable { case memory, standard, suite(String) }
