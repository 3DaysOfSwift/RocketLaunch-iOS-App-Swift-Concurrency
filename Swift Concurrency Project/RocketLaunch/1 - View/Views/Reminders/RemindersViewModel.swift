import Foundation
import Observation

@MainActor @Observable
final class RemindersViewModel {
    var showingLaunch = false
    private(set) var selectedLaunch: RocketLaunch?
    func showLaunch(_ launch: RocketLaunch) {
        selectedLaunch = launch
        showingLaunch = true
    }

    private(set) var isBusy = false
    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var actionID: UUID?
    private enum Intent: Equatable { case retry, remove(String) }
    @ObservationIgnored private var currentIntent: Intent?
    init(launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.launchScheduleFeature = launchScheduleFeature }
    var writeError: String? { launchScheduleFeature.reminderWriteError }
    var storageError: String? { launchScheduleFeature.reminderStorageError }
    var reminders: [LaunchReminder] { launchScheduleFeature.reminders }
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    @discardableResult
    func loadIfNeeded() -> Task<Void, Never> {
        if let pending = loadTask { return pending }
        let launchScheduleFeature = launchScheduleFeature
        let task = Task { [weak self] in
            await launchScheduleFeature.loadRemindersIfNeeded()
            self?.loadTask = nil
        }
        loadTask = task
        return task
    }
    @discardableResult
    func retryWrite() -> Task<Void, Never> {
        enqueue(.retry) { await $0.retryReminderWrite() }
    }
    func contains(_ id: String) -> Bool { launchScheduleFeature.hasActiveReminder(for: id) }
    func reminderTimeHasPassed(_ reminder: LaunchReminder) -> Bool { launchScheduleFeature.reminderTimeHasPassed(reminder) }
    @discardableResult
    func remove(_ id: String) -> Task<Void, Never> {
        enqueue(.remove(id)) { await $0.removeReminder(id) }
    }
    private func enqueue(_ intent: Intent, _ operation: @escaping @MainActor (LaunchScheduleFeature) async -> Void) -> Task<Void, Never> {
        if currentIntent == intent, let action { return action }
        let previous = action
        let id = UUID()
        actionID = id
        currentIntent = intent
        isBusy = true
        let launchScheduleFeature = launchScheduleFeature
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation(launchScheduleFeature)
            guard self?.actionID == id else { return }
            self?.isBusy = false
            self?.action = nil
            self?.actionID = nil
            self?.currentIntent = nil
        }
        action = task
        return task
    }
    // Accepted edits must finish even if their screen disappears.
    deinit { loadTask?.cancel() }
}
