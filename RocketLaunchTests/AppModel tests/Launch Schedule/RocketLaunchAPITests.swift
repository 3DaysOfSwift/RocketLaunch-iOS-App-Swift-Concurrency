import XCTest
@testable import RocketLaunch

final class RocketLaunchAPITests: XCTestCase {
    func testDecodesResponseThroughRealAsyncNetworkingBoundary() async throws {
        let expected = try LaunchFixtures.launches()
        let actual = try await fetch(.init(data: LaunchFixtures.data()))
        XCTAssertEqual(actual, expected)
    }
    func testMalformedResponseIsInvalidData() async throws {
        do { _ = try await fetch(.init(data: Data("not JSON".utf8))); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? LaunchRepositoryError, .invalidData) }
    }
    func testTransportErrorIsPreserved() async throws {
        do { _ = try await fetch(.init(error: URLError(.notConnectedToInternet))); XCTFail("Expected failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
    func testHTTPFailureIsRejectedEvenWithDecodableBody() async throws {
        do { _ = try await fetch(.init(data: LaunchFixtures.data(), statusCode: 503)); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? LaunchRepositoryError, .httpStatus(503)) }
    }
    func testEmptyLaunchArrayIsValid() async throws {
        let launches = try await fetch(.init(data: Data(#"{"result":[]}"#.utf8)))
        XCTAssertTrue(launches.isEmpty)
    }
    func testNullDatesDecodeThroughTheRepository() async throws {
        let data = try LaunchFixtures.data(estimatedDate: ["month": NSNull(), "day": NSNull(), "year": NSNull()])
        let launches = try await fetch(.init(data: data))
        let launch = try XCTUnwrap(launches.first)
        XCTAssertNil(launch.estimatedDate.day)
        XCTAssertNil(launch.estimatedDate.month)
        XCTAssertNil(launch.estimatedDate.year)
    }
    @MainActor func testTaskCancellationStopsRealURLSessionRequest() async throws {
        let started = expectation(description: "request starts")
        let stopped = expectation(description: "request stops")
        let (session, id) = StubURLProtocol.session(response: .init(waitsForCancellation: true, onStart: { started.fulfill() }, onStop: { stopped.fulfill() }))
        defer { session.invalidateAndCancel(); StubURLProtocol.remove(id) }
        let api = RocketLaunchAPI(session: session, endpoint: URL(string: "https://example.invalid/launches")!)
        let task = Task { try await api.fetchUpcomingLaunches() }
        await waitFor([started]); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await waitFor([stopped])
    }
    private func fetch(_ response: StubURLProtocol.Response) async throws -> [RocketLaunch] {
        let (session, id) = StubURLProtocol.session(response: response)
        defer { session.invalidateAndCancel(); StubURLProtocol.remove(id) }
        return try await RocketLaunchAPI(session: session, endpoint: URL(string: "https://example.invalid/launches")!).fetchUpcomingLaunches()
    }
}
