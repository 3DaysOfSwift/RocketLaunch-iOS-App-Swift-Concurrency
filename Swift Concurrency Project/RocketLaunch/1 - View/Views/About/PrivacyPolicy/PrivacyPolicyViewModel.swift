import Foundation
import Observation

@MainActor @Observable
final class PrivacyPolicyViewModel {
    private(set) var text = ""
    private(set) var loadError: String?
    @ObservationIgnored private let settingsFeature: SettingsFeature
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    init(settingsFeature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.settingsFeature = settingsFeature
    }

    @discardableResult
    func retry() -> Task<Void, Never> {
        if let retryTask { return retryTask }
        let task = Task { [weak self] in
            await self?.load()
            self?.retryTask = nil
        }
        retryTask = task
        return task
    }

    deinit { retryTask?.cancel() }

    /// The screen's SwiftUI task owns this operation's lifetime.
    func load() async {
        guard !hasLoaded, !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        do {
            let policy = try await settingsFeature.loadPrivacyPolicy()
            try Task.checkCancellation()
            guard requestID == id else { return }
            text = policy
            loadError = nil
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, requestID == id, !(error is CancellationError) else { return }
            loadError = "The privacy policy could not be loaded. Please try again."
        }
    }
}
