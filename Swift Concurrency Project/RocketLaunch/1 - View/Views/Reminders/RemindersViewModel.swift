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
    func retryWrite() {
        enqueue { await $0.retryReminderWrite() }
    }
    func contains(_ id: String) -> Bool { launchScheduleFeature.hasActiveReminder(for: id) }
    func reminderTimeHasPassed(_ reminder: LaunchReminder) -> Bool { launchScheduleFeature.reminderTimeHasPassed(reminder) }
    func remove(_ id: String) {
        enqueue { await $0.removeReminder(id) }
    }
    private func enqueue(_ operation: @escaping @MainActor (LaunchScheduleFeature) async -> Void) {
        let previous = action
        let id = UUID()
        actionID = id
        isBusy = true
        let launchScheduleFeature = launchScheduleFeature
        action = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation(launchScheduleFeature)
            guard self?.actionID == id else { return }
            self?.isBusy = false
            self?.action = nil
            self?.actionID = nil
        }
    }
    // Accepted edits must finish even if their screen disappears.
    deinit { loadTask?.cancel() }
}
