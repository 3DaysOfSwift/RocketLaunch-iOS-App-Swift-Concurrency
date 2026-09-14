import Foundation

/// Completion may arrive on any queue. The feature must marshal it to its state queue.
protocol LaunchRepository {
    @discardableResult
    func fetchUpcomingLaunches(completion: @escaping (Result<[RocketLaunch], Error>) -> Void) -> CancellationToken
}

enum LaunchRepositoryError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidData
}

/// Thread-safe cancellation registration. Cancellation before registration is supported.
/// Owners cancel explicitly; simply discarding a handle does not cancel committed work.
final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled { lock.unlock(); handler() }
        else { handlers.append(handler); lock.unlock() }
    }
    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let actions = handlers; handlers.removeAll()
        lock.unlock()
        actions.forEach { $0() }
    }
}

/// URLSession uses completion handlers; parsing is explicitly dispatched off the UI queue.
/// No semaphore or synchronous wait ties up a worker while the network is in flight.
enum LaunchHTTP {
    static func fetch(session: URLSession, request: URLRequest, queue: DispatchQueue,
                      decode: @escaping (Data) throws -> [RocketLaunch],
                      completion: @escaping (Result<[RocketLaunch], Error>) -> Void) -> CancellationToken {
        let token = CancellationToken()
        let task = session.dataTask(with: request) { data, response, error in
            queue.async {
                let result: Result<[RocketLaunch], Error>
                do {
                    if token.isCancelled { throw URLError(.cancelled) }
                    if let error { throw error }
                    guard let response = response as? HTTPURLResponse else { throw LaunchRepositoryError.invalidResponse }
                    guard (200..<300).contains(response.statusCode) else { throw LaunchRepositoryError.httpStatus(response.statusCode) }
                    guard let data else { throw LaunchRepositoryError.invalidData }
                    let launches: [RocketLaunch]
                    do { launches = try decode(data) } catch { throw LaunchRepositoryError.invalidData }
                    if token.isCancelled { throw URLError(.cancelled) }
                    result = .success(launches)
                } catch { result = .failure(error) }
                completion(result)
            }
        }
        token.onCancel { task.cancel() }
        task.resume()
        return token
    }
}
