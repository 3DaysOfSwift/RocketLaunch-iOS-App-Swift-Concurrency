import XCTest
@testable import RocketLaunch

final class RocketLaunchAPITests: XCTestCase {
    func testDecodesResponseThroughRealNetworkingBoundary() throws {
        let launches = try LaunchFixtures.launches()
        check(response: .init(data: try LaunchFixtures.data())) { result in
            XCTAssertEqual(try result.get().map(\.id), launches.map(\.id))
        }
    }

    func testMalformedResponseReachesCallerAsDecodingFailure() {
        check(response: .init(data: Data("not JSON".utf8))) { result in
            guard case .failure(.decodingFailure) = result else {
                return XCTFail("Expected decoding failure")
            }
        }
    }

    func testTransportFailureReachesCaller() {
        check(response: .init(error: URLError(.notConnectedToInternet))) { result in
            guard case .failure(.networkingError) = result else {
                return XCTFail("Expected networking error")
            }
        }
    }

    func testNullDatesDecodeThroughTheRepository() throws {
        let data = try LaunchFixtures.data(estimatedDate: ["month": NSNull(), "day": NSNull(), "year": NSNull()])
        check(response: .init(data: data)) { result in
            let launch = try XCTUnwrap(result.get().first)
            XCTAssertNil(launch.est_date.day)
            XCTAssertNil(launch.est_date.month)
            XCTAssertNil(launch.est_date.year)
        }
    }

    private func check(response: StubURLProtocol.Response, assertions: @escaping (Result<[RocketLaunch], RocketLaunchAPIError>) throws -> Void) {
        let (session, identifier) = StubURLProtocol.session(response: response)
        defer { session.invalidateAndCancel(); StubURLProtocol.remove(identifier) }
        let api = RocketLaunchAPI(networkManager: NetworkManager(session: session))
        let completed = expectation(description: "Repository completes exactly once")
        completed.assertForOverFulfill = true
        api.fetchUpcomingLaunches { result in
            do { try assertions(result) }
            catch { XCTFail("Unexpected result: \(error)") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
    }
}
