import Foundation
import Observation

@MainActor @Observable
final class ReminderViewModel {
    var showingLaunch = false
    func showLaunch(_ launch: RocketLaunch) {
        feature.selectLaunch(launch, in: .reminders)
        showingLaunch = true
    }

    private(set) var isBusy = false
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private var action: Task<Void, Never>?
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.feature = feature }
    var writeError: String? { feature.reminderWriteError }
    var storageError: String? { feature.reminderStorageError }
    var reminders: [LaunchReminder] { feature.reminders }
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    @discardableResult
    func loadIfNeeded() -> Task<Void, Never> {
        if let pending = loadTask { return pending }
        let feature = feature
        let task = Task { [weak self] in
            await feature.loadRemindersIfNeeded()
            self?.loadTask = nil
        }
        loadTask = task
        return task
    }
    func retryWrite() {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            await feature.retryReminderWrite()
            self?.isBusy = false
            self?.action = nil
        }
    }
    func contains(_ id: String) -> Bool { feature.hasActiveReminder(for: id) }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            await feature.removeReminder(id)
            self?.isBusy = false; self?.action = nil
        }
    }
    deinit { loadTask?.cancel(); action?.cancel() }
}
