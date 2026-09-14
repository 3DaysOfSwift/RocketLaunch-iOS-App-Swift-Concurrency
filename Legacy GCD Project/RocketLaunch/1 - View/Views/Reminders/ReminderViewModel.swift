import Foundation
import Observation

@Observable
final class ReminderViewModel {
    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let feature: LaunchScheduleFeatureAPI
    @ObservationIgnored private var observation: CancellationToken?
    private(set) var snapshot: RemindersSnapshot = .initial
    var reminders: [LaunchReminder] { snapshot.reminders }
    init(feature: LaunchScheduleFeatureAPI = AppModel.shared.launchSchedule) { self.feature = feature }
    func startObserving() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard observation == nil else { return }
        observation = feature.observeReminders { [weak self] value in self?.apply(value) }
    }
    func stopObserving() { observation?.cancel(); observation = nil }
    private func apply(_ value: RemindersSnapshot) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard value.revision >= snapshot.revision else { return }
        snapshot = value
    }
    func contains(_ id: String) -> Bool {
        reminders.contains { $0.id == id && $0.status == .scheduled && $0.issue == nil && $0.fireDate > Date() }
    }
    func save(_ launchID: String, minutesBefore: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isBusy else { return }
        isBusy = true
        // Committed model intent outlives this screen. The callback holds the ViewModel weakly.
        feature.setReminder(for: launchID, minutesBefore: minutesBefore) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.superseded): self.errorMessage = "The reminder changed while saving. Check Reminders for its latest status."
            case .success(.saved): break
            case .failure(let error):
                switch error {
                case ReminderError.launchUnavailable: self.errorMessage = "Refresh the schedule and open the launch again before setting a reminder."
                case ReminderError.invalidLeadTime: self.errorMessage = "Choose 5, 15 or 60 minutes before launch."
                case ReminderError.denied: self.errorMessage = "Allow notifications for RocketLaunch in Settings to receive reminders."
                case ReminderError.unknownTime: self.errorMessage = "An exact launch time is needed to set a reminder."
                case ReminderError.tooLate: self.errorMessage = "That reminder time has already passed. Choose a shorter lead time or another launch."
                case ReminderError.limit: self.errorMessage = "Remove an existing reminder before adding another."
                default: self.errorMessage = "The reminder couldn’t be saved. Please try again."
                }
            }
            self.finishAction()
        }
    }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        feature.removeReminder(id) { [weak self] in self?.finishAction() }
    }
    private func finishAction() {
        feature.getReminderSnapshot { [weak self] value in
            self?.apply(value); self?.isBusy = false
        }
    }
    deinit { observation?.cancel() }
}
