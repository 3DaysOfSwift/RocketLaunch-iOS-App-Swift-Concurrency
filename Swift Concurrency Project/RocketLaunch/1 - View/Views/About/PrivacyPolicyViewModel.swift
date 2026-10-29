import Foundation
import Observation

@MainActor @Observable
final class PrivacyPolicyViewModel {
    private(set) var text = ""
    @ObservationIgnored private let loader: any PrivacyPolicyLoading
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var hasLoaded = false

    init(loader: any PrivacyPolicyLoading = BundledPrivacyPolicyLoader()) {
        self.loader = loader
    }

    /// The screen's SwiftUI task owns this operation's lifetime.
    func load() async {
        guard !hasLoaded, !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        do {
            let policy = try await loader.load()
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
