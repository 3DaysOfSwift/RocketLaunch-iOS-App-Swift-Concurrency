import Foundation
import Observation

@MainActor @Observable
final class ReminderViewModel {
    var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let feature: any RemindersFeatureAPI
    @ObservationIgnored private var action: Task<Void, Never>?
    init(feature: any RemindersFeatureAPI = AppModel.shared.reminders) { self.feature = feature }
    private(set) var snapshot: RemindersSnapshot = .initial
    var reminders: [LaunchReminder] { snapshot.reminders }
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var observationID: UUID?
    func startObserving() {
        guard observationTask == nil else { return }
        let feature = feature
        let id = UUID(); observationID = id
        observationTask = Task { [weak self] in
            let stream = await feature.snapshots()
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
    func contains(_ id: String) -> Bool { reminders.contains { $0.id == id && $0.issue == nil && $0.fireDate > Date() } }
    func save(_ launch: RocketLaunch, minutesBefore: Int) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            do {
                let outcome = try await feature.save(launch, minutesBefore: minutesBefore)
                if outcome == .superseded {
                    self?.errorMessage = "This reminder changed while saving. Check the latest launch details before trying again."
                }
            }
            catch {
                switch error {
                case ReminderError.denied: self?.errorMessage = "Allow notifications for RocketLaunch in Settings to receive reminders."
                case ReminderError.unknownTime: self?.errorMessage = "An exact launch time is needed to set a reminder."
                case ReminderError.tooLate: self?.errorMessage = "That reminder time has already passed. Choose a shorter lead time or another launch."
                case ReminderError.limit: self?.errorMessage = "Remove an existing reminder before adding another."
                default: self?.errorMessage = "The reminder couldn’t be saved. Please try again."
                }
            }
            let value = await feature.snapshot
            self?.apply(value)
            self?.isBusy = false; self?.action = nil
        }
    }
    func remove(_ id: String) {
        guard !isBusy else { return }
        isBusy = true
        let feature = feature
        action = Task { [weak self] in
            await feature.remove(id)
            let value = await feature.snapshot
            self?.apply(value)
            self?.isBusy = false; self?.action = nil
        }
    }
    deinit { observationTask?.cancel(); action?.cancel() }
}
