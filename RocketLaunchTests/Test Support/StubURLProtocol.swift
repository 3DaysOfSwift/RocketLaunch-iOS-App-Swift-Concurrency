import Foundation

/// Each ephemeral session has its own identifier. The lock protects URL loading
/// callbacks so tests never share a response or depend on the live service.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var data: Data?
        var error: Error?
        var statusCode = 200
    }
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static let key = "X-RocketLaunch-Test"

    static func session(response: Response) -> (URLSession, String) {
        let identifier = UUID().uuidString
        lock.lock()
        responses[identifier] = response
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [key: identifier]
        return (URLSession(configuration: configuration), identifier)
    }

    static func remove(_ identifier: String) {
        lock.lock()
        responses.removeValue(forKey: identifier)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let identifier = request.value(forHTTPHeaderField: Self.key) ?? ""
        Self.lock.lock()
        let response = Self.responses[identifier]
        Self.lock.unlock()
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if let data = response.data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
