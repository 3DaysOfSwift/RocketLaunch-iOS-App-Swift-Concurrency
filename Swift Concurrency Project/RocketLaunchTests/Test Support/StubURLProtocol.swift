import Foundation

/// URLProtocol callbacks may arrive on different threads. All mutable fixture
/// storage is protected by Store.lock; the protocol subclass adds no mutable state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var data: Data?
        var error: (any Error)?
        var statusCode = 200
        var waitsForCancellation = false
        var onStart: (@Sendable () -> Void)?
        var onStop: (@Sendable () -> Void)?
    }
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: Response] = [:]
        func set(_ response: Response?, for id: String) {
            lock.lock(); defer { lock.unlock() }
            responses[id] = response
        }
        func get(_ id: String) -> Response? {
            lock.lock(); defer { lock.unlock() }
            return responses[id]
        }
    }
    private static let store = Store()
    private static let key = "X-RocketLaunch-Test"
    static func session(response: Response) -> (URLSession, String) {
        let id = UUID().uuidString
        store.set(response, for: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [key: id]
        return (URLSession(configuration: configuration), id)
    }
    static func remove(_ id: String) { store.set(nil, for: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let response = Self.store.get(request.value(forHTTPHeaderField: Self.key) ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        response.onStart?()
        if response.waitsForCancellation { return }
        if let error = response.error { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if let data = response.data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.store.get(request.value(forHTTPHeaderField: Self.key) ?? "")?.onStop?()
    }
}
