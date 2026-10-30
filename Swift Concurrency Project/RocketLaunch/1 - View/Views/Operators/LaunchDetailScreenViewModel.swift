import Foundation
import Observation

@MainActor @Observable
final class LaunchDetailScreenViewModel {
    var minutesBefore = 15
    var launch: RocketLaunch? { feature.selectedLaunch(in: .next) }
    var reminderSaved: Bool { launch.map { feature.hasActiveReminder(for: $0.id) } ?? false }

    @discardableResult
    func save() -> Task<Void, Never>? {
        guard let launch else { return nil }
        return save(launch.id, minutesBefore: minutesBefore)
    }

    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private var action: Task<Void, Never>?

    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.feature = feature }

    func contains(_ id: String) -> Bool {
        feature.hasActiveReminder(for: id)
    }

    @discardableResult
    func save(_ launchID: String, minutesBefore: Int) -> Task<Void, Never> {
        if let action { return action }
        errorMessage = nil
        isBusy = true
        let feature = feature
        let task = Task { [weak self] in
            do {
                let outcome = try await feature.setReminder(for: launchID, minutesBefore: minutesBefore)
                if outcome == .superseded {
                    self?.errorMessage = "The reminder changed while saving. Check Reminders for its latest status."
                }
            }
            catch is CancellationError {}
            catch {
                switch error {
                case ReminderError.launchUnavailable: self?.errorMessage = "Refresh the schedule and open the launch again before setting a reminder."
                case ReminderError.invalidLeadTime: self?.errorMessage = "Choose 5, 15 or 60 minutes before launch."
                case ReminderError.storageWriteFailed: self?.errorMessage = "The reminder could not be saved. Open Reminders to retry saving, then set the alert again."
                case ReminderError.storageUnavailable: self?.errorMessage = "Saved reminders could not be read. Open Reminders and retry loading before saving another alert."
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
