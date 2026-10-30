import Foundation
import Observation

@MainActor @Observable
final class OperatorLaunchDetailViewModel {
    private var reminderDraftMinutes: Int?
    var minutesBefore: Int {
        get {
            reminderDraftMinutes ?? launch.flatMap { selected in
                launchScheduleFeature.reminders.first { $0.id == selected.id }?.minutesBefore
            } ?? 15
        }
        set { reminderDraftMinutes = newValue }
    }
    let launch: RocketLaunch?
    var reminderSaved: Bool { launch.map { launchScheduleFeature.hasActiveReminder(for: $0.id) } ?? false }

    @discardableResult
    func save() -> Task<Void, Never>? {
        guard let launch else { return nil }
        return save(launch.id, minutesBefore: minutesBefore, expectedLaunchTime: launch.details.plannedTime)
    }

    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    @ObservationIgnored private var action: Task<Void, Never>?

    init(launch: RocketLaunch, launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.launch = launch
        self.launchScheduleFeature = launchScheduleFeature
    }

    func contains(_ id: String) -> Bool {
        launchScheduleFeature.hasActiveReminder(for: id)
    }

    @discardableResult
    func save(_ launchID: String, minutesBefore: Int, expectedLaunchTime: Date? = nil) -> Task<Void, Never> {
        if let action { return action }
        errorMessage = nil
        isBusy = true
        let launchScheduleFeature = launchScheduleFeature
        let task = Task { [weak self] in
            do {
                let outcome = try await launchScheduleFeature.setReminder(for: launchID, minutesBefore: minutesBefore, expectedLaunchTime: expectedLaunchTime)
                if outcome == .superseded {
                    self?.errorMessage = "The reminder changed while saving. Check Reminders for its latest status."
                }
            }
            catch is CancellationError {}
            catch {
                switch error {
                case ReminderError.launchTimeChanged: self?.errorMessage = "The launch time has changed. Go back and open the latest launch before setting a reminder."
                case ReminderError.launchUnavailable: self?.errorMessage = "Refresh the schedule and open the launch again before setting a reminder."
                case ReminderError.invalidLeadTime: self?.errorMessage = "Choose 5, 15 or 60 minutes before launch."
                case ReminderError.storageWriteFailed: self?.errorMessage = "The reminder could not be saved. Open Reminders to retry and check its status."
                case ReminderError.storageUnavailable: self?.errorMessage = "Saved reminders could not be loaded or recovered. Open Reminders and retry before saving another alert."
                case ReminderError.denied: self?.errorMessage = "Allow notifications for RocketLaunch in Settings to receive reminders."
                case ReminderError.unknownTime: self?.errorMessage = "An exact launch time is needed to set a reminder."
                case ReminderError.tooLate: self?.errorMessage = "That reminder time has already passed. Choose a shorter lead time or another launch."
                case ReminderError.limit: self?.errorMessage = "Remove an existing reminder before adding another."
                default: self?.errorMessage = "The reminder couldn’t be saved. Please try again."
                }
            }
            self?.isBusy = false; self?.action = nil
        }
        action = task
        return task
    }

    deinit { action?.cancel() }
}
