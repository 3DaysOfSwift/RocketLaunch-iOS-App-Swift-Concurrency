import Foundation
import Observation

@MainActor @Observable
final class ReminderViewModel {
    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let feature: any RemindersFeatureAPI
    @ObservationIgnored private var action: Task<Void, Never>?
    init(feature: any RemindersFeatureAPI = AppModel.shared.reminders) { self.feature = feature }
    var reminders: [LaunchReminder] { feature.reminders }
    func contains(_ id: String) -> Bool { reminders.contains { $0.id == id && $0.issue == nil && $0.fireDate > Date() } }
    func save(_ launch: RocketLaunch, minutesBefore: Int) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            do { try await feature.save(launch, minutesBefore: minutesBefore) }
            catch {
                switch error {
                case ReminderError.denied: self?.errorMessage = "Allow notifications for RocketLaunch in Settings to receive reminders."
                case ReminderError.unknownTime: self?.errorMessage = "An exact launch time is needed to set a reminder."
                case ReminderError.tooLate: self?.errorMessage = "That reminder time has already passed. Choose a shorter lead time or another launch."
                case ReminderError.limit: self?.errorMessage = "Remove an existing reminder before adding another."
                default: self?.errorMessage = "The reminder couldn’t be saved. Please try again."
                }
            }
            self?.isBusy = false; self?.action = nil
        }
    }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            await feature.remove(id)
            self?.isBusy = false; self?.action = nil
        }
    }
    deinit { action?.cancel() }
}
