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

@MainActor @Observable
final class ControlledLaunchFeature: LaunchScheduleFeatureAPI {
    private(set) var state: LaunchScheduleState = .idle
    private(set) var refreshCount = 0
    func setState(_ state: LaunchScheduleState) { self.state = state }
    func refresh() async { refreshCount += 1 }
}

@MainActor
final class LifecycleFeature: LaunchScheduleFeatureAPI {
    let state: LaunchScheduleState = .idle
    var pending: [CheckedContinuation<Void, Never>] = []
    var cancellations: [Int: Bool] = [:]
    var onRequest: (Int) -> Void = { _ in }
    var onFinish: (Int) -> Void = { _ in }
    func refresh() async {
        let index = pending.count
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            onRequest(index)
        }
        cancellations[index] = Task.isCancelled
        onFinish(index)
    }
    func complete(_ index: Int) { pending[index].resume() }
}

@MainActor
func waitFor(_ expectations: [XCTestExpectation], file: StaticString = #filePath, line: UInt = #line) async {
    let result = await XCTWaiter.fulfillment(of: expectations, timeout: 3)
    XCTAssertEqual(result, .completed, file: file, line: line)
}
