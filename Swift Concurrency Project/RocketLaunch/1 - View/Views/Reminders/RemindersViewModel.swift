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
        guard !isBusy else { return }
        isBusy = true
        let launchScheduleFeature = launchScheduleFeature
        action = Task { [weak self] in
            await launchScheduleFeature.retryReminderWrite()
            self?.isBusy = false
            self?.action = nil
        }
    }
    func contains(_ id: String) -> Bool { launchScheduleFeature.hasActiveReminder(for: id) }
    func reminderTimeHasPassed(_ reminder: LaunchReminder) -> Bool { launchScheduleFeature.reminderTimeHasPassed(reminder) }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        let launchScheduleFeature = launchScheduleFeature
        action = Task { [weak self] in
            await launchScheduleFeature.removeReminder(id)
            self?.isBusy = false; self?.action = nil
        }
    }
    deinit { loadTask?.cancel(); action?.cancel() }
}
