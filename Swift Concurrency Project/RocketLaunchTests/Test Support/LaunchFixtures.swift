import Foundation
import Observation
import XCTest
@testable import RocketLaunch

private final class FixtureBundle {}

enum LaunchFixtures {
    static func data() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundle.self)
        #endif
        guard let url = bundle.url(forResource: "launch-response", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
    static func data(estimatedDate: [String: Any]) throws -> Data {
        var page = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        var launches = page["result"] as! [[String: Any]]
        launches[0]["est_date"] = estimatedDate
        page["result"] = launches
        return try JSONSerialization.data(withJSONObject: page)
    }
    static func launches() throws -> [RocketLaunch] { try RocketLaunchAPI.decodeResponse(data()) }
}

/// Deliberately ignores cancellation until the test releases a response. This
/// verifies publication safety even when external work cannot stop immediately.
actor ControlledLaunchRepository: LaunchRepository {
    private var pending: [Int: CheckedContinuation<[RocketLaunch], any Error>] = [:]
    private(set) var requestCount = 0
    private let onRequest: @Sendable (Int) -> Void
    init(onRequest: @escaping @Sendable (Int) -> Void = { _ in }) { self.onRequest = onRequest }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        let index = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            onRequest(index)
        }
    }
    func complete(_ index: Int, with result: Result<[RocketLaunch], any Error>) {
        guard let continuation = pending.removeValue(forKey: index) else { preconditionFailure("No pending request") }
        continuation.resume(with: result)
    }
}

/// Drives the real Feature through an isolated repository for presentation scenarios.
@MainActor
final class LaunchScenario {
    let repository = PresentationLaunchRepository()
    let feature: LaunchScheduleFeature
    init() {
        feature = LaunchScheduleFeature(sources: [.init(id: .rocketLaunchLive, repository: repository)],
            now: { Date(timeIntervalSince1970: 1_600_000_000) })
    }
    func prepare(_ state: LaunchScheduleState) async {
        switch state {
        case .loaded(let launch):
            await repository.respond(.success([launch]))
        case .empty:
            await repository.respond(.success([]))
        case .failed(_, let previous):
            if let previous {
                await repository.respond(.success([previous]))
                await feature.refresh()
            }
            await repository.respond(.failure(URLError(.notConnectedToInternet)))
        case .idle, .loading:
            XCTFail("Use a controlled repository to test pending work")
            return
        }
        await feature.refresh()
    }
}

actor PresentationLaunchRepository: LaunchRepository {
    private var result: Result<[RocketLaunch], any Error> = .success([])
    private(set) var requestCount = 0
    func respond(_ result: Result<[RocketLaunch], any Error>) { self.result = result }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        requestCount += 1
        return try result.get()
    }
}

actor LifecycleRepository: LaunchRepository {
    private let onRequest: @Sendable () -> Void
    private let onFinish: @Sendable () -> Void
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0
    private(set) var cancellations: [Int: Bool] = [:]
    init(onRequest: @escaping @Sendable () -> Void, onFinish: @escaping @Sendable () -> Void) {
        self.onRequest = onRequest
        self.onFinish = onFinish
    }
    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        let index = requestCount
        requestCount += 1
        await withCheckedContinuation { continuation in
            pending[index] = continuation
            onRequest()
        }
        cancellations[index] = Task.isCancelled
        onFinish()
        try Task.checkCancellation()
        return []
    }
    func complete(_ index: Int) { pending.removeValue(forKey: index)?.resume() }
}

@MainActor
func waitFor(_ expectations: [XCTestExpectation], file: StaticString = #filePath, line: UInt = #line) async {
    let result = await XCTWaiter.fulfillment(of: expectations, timeout: 3)
    XCTAssertEqual(result, .completed, file: file, line: line)
}

/// Mutable deterministic clock used across test and feature actors.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
