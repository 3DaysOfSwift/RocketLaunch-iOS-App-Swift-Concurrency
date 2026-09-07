import XCTest
@testable import RocketLaunch

final class LaunchDecodingTests: XCTestCase {
    func testCompleteResponseDecodesAllLaunches() throws {
        let page = try RocketLaunchAPI.decodeResponse(LaunchFixtures.data())
        XCTAssertEqual(page.count, 5)
        XCTAssertEqual(page.first?.name, "Starlink-126 (6-33)")
    }

    func testNullDayPreservesKnownMonthAndYear() throws {
        let page = try decode(["month": 9, "day": NSNull(), "year": 2026])
        XCTAssertNil(page[0].estimatedDate.day)
        XCTAssertEqual(page[0].estimatedDate.month, 9)
        XCTAssertEqual(page[0].estimatedDate.year, 2026)
    }

    func testEntirelyUnknownDateDoesNotDiscardLaunch() throws {
        let page = try decode(["month": NSNull(), "day": NSNull(), "year": NSNull()])
        XCTAssertNil(page[0].estimatedDate.month)
        XCTAssertNil(page[0].estimatedDate.day)
        XCTAssertNil(page[0].estimatedDate.year)
        XCTAssertEqual(page[0].name, "Starlink-126 (6-33)")
    }

    func testOmittedDateComponentsDecodeAsUnknown() throws {
        let page = try decode([:])
        XCTAssertNil(page[0].estimatedDate.month)
        XCTAssertNil(page[0].estimatedDate.day)
        XCTAssertNil(page[0].estimatedDate.year)
    }

    func testInvalidDateTypeRemainsADecodingError() throws {
        XCTAssertThrowsError(try decode(["month": "invalid", "day": 1, "year": 2026])) { error in
            guard case DecodingError.typeMismatch = error else {
                return XCTFail("Expected type mismatch, got \(error)")
            }
        }
    }

    private func decode(_ date: [String: Any]) throws -> [RocketLaunch] {
        try RocketLaunchAPI.decodeResponse(LaunchFixtures.data(estimatedDate: date))
    }
}
