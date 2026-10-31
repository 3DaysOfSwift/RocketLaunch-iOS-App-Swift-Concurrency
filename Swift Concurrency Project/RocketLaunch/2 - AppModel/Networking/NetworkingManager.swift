import Foundation

/// Performs transport work away from the Main Actor. Providers own decoding.
actor NetworkingManager {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
