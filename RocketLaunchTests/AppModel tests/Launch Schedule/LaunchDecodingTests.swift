import XCTest
@testable import RocketLaunch

final class LaunchDecodingTests: XCTestCase {
    func testCompleteResponseDecodesAllLaunches() throws {
        let page = try JSONDecoder().decode(SearchResultsPage.self, from: LaunchFixtures.data())
        XCTAssertEqual(page.result.count, 5)
        XCTAssertEqual(page.result.first?.name, "Starlink-126 (6-33)")
    }

    func testNullDayPreservesKnownMonthAndYear() throws {
        let page = try decode(["month": 9, "day": NSNull(), "year": 2026])
        XCTAssertNil(page.result[0].est_date.day)
        XCTAssertEqual(page.result[0].est_date.month, 9)
        XCTAssertEqual(page.result[0].est_date.year, 2026)
    }

    func testEntirelyUnknownDateDoesNotDiscardLaunch() throws {
        let page = try decode(["month": NSNull(), "day": NSNull(), "year": NSNull()])
        XCTAssertNil(page.result[0].est_date.month)
        XCTAssertNil(page.result[0].est_date.day)
        XCTAssertNil(page.result[0].est_date.year)
        XCTAssertEqual(page.result[0].name, "Starlink-126 (6-33)")
    }

    func testOmittedDateComponentsDecodeAsUnknown() throws {
        let page = try decode([:])
        XCTAssertNil(page.result[0].est_date.month)
        XCTAssertNil(page.result[0].est_date.day)
        XCTAssertNil(page.result[0].est_date.year)
    }

    func testInvalidDateTypeRemainsADecodingError() throws {
        XCTAssertThrowsError(try decode(["month": "invalid", "day": 1, "year": 2026])) { error in
            guard case DecodingError.typeMismatch = error else {
                return XCTFail("Expected type mismatch, got \(error)")
            }
        }
    }

    private func decode(_ date: [String: Any]) throws -> SearchResultsPage {
        try JSONDecoder().decode(SearchResultsPage.self, from: LaunchFixtures.data(estimatedDate: date))
    }
}
