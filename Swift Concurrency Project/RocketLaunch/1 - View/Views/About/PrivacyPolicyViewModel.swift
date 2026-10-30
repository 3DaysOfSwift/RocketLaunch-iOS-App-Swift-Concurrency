import Foundation
import Observation

@MainActor @Observable
final class PrivacyPolicyViewModel {
    private(set) var text = ""
    @ObservationIgnored private let feature: SettingsFeature
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var hasLoaded = false

    init(feature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.feature = feature
    }

    /// The screen's SwiftUI task owns this operation's lifetime.
    func load() async {
        guard !hasLoaded, !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        do {
            let policy = try await feature.loadPrivacyPolicy()
            try Task.checkCancellation()
            guard requestID == id else { return }
            text = policy
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, requestID == id, !(error is CancellationError) else { return }
            text = "The privacy policy could not be loaded. Please consult the project’s PRIVACY.md document."
        }
    }
}
