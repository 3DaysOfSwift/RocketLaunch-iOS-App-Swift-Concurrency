import Foundation

protocol PrivacyPolicyLoading: Sendable {
    func load() async throws -> String
}

/// Reads immutable bundled content on its own actor, without retaining a copy.
actor BundledPrivacyPolicyLoader: PrivacyPolicyLoading {
    private let fileURL: URL?

    init(fileURL: URL? = nil) { self.fileURL = fileURL }

    func load() throws -> String {
        try Task.checkCancellation()
        guard let url = fileURL ?? Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
