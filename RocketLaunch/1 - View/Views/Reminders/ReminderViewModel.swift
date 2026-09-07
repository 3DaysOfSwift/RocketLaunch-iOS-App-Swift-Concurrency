import Foundation
import Observation

@MainActor @Observable
final class ReminderViewModel {
    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let feature: any LaunchScheduleFeatureAPI
    @ObservationIgnored private var action: Task<Void, Never>?
    init(feature: any LaunchScheduleFeatureAPI = AppModel.shared.launchSchedule) { self.feature = feature }
    private(set) var snapshot: RemindersSnapshot = .initial
    var reminders: [LaunchReminder] { snapshot.reminders }
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var observationID: UUID?
    func startObserving() {
        guard observationTask == nil else { return }
        let feature = feature
        let id = UUID(); observationID = id
        observationTask = Task { [weak self] in
            let stream = await feature.reminderSnapshots()
            for await value in stream {
                guard !Task.isCancelled, self?.observationID == id else { break }
                self?.apply(value)
            }
        }
    }
    func stopObserving() {
        observationID = nil
        observationTask?.cancel(); observationTask = nil
    }
    private func apply(_ value: RemindersSnapshot) {
        guard value.revision >= snapshot.revision else { return }
        snapshot = value
    }
    func contains(_ id: String) -> Bool { reminders.contains { $0.id == id && $0.status == .scheduled && $0.issue == nil && $0.fireDate > Date() } }
    func save(_ launchID: String, minutesBefore: Int) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            do {
                let outcome = try await feature.setReminder(for: launchID, minutesBefore: minutesBefore)
                if outcome == .superseded {
                    self?.errorMessage = "The reminder changed while saving. Check Reminders for its latest status."
                }
            }
            catch {
                switch error {
                case ReminderError.launchUnavailable: self?.errorMessage = "Refresh the schedule and open the launch again before setting a reminder."
                case ReminderError.invalidLeadTime: self?.errorMessage = "Choose 5, 15 or 60 minutes before launch."
                case ReminderError.denied: self?.errorMessage = "Allow notifications for RocketLaunch in Settings to receive reminders."
                case ReminderError.unknownTime: self?.errorMessage = "An exact launch time is needed to set a reminder."
                case ReminderError.tooLate: self?.errorMessage = "That reminder time has already passed. Choose a shorter lead time or another launch."
                case ReminderError.limit: self?.errorMessage = "Remove an existing reminder before adding another."
                default: self?.errorMessage = "The reminder couldn’t be saved. Please try again."
                }
            }
            let value = await feature.reminderSnapshot
            self?.apply(value)
            self?.isBusy = false; self?.action = nil
        }
    }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            await feature.removeReminder(id)
            let value = await feature.reminderSnapshot
            self?.apply(value)
            self?.isBusy = false; self?.action = nil
        }
    }
    deinit { observationTask?.cancel(); action?.cancel() }
}
