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

    func testDecodesTheFourLaunchAnswersAndMinutePrecisionUTC() throws {
        let launch = try XCTUnwrap(LaunchFixtures.launches().first)
        XCTAssertEqual(launch.details.provider, "SpaceX")
        XCTAssertEqual(launch.details.vehicle, "Falcon 9")
        XCTAssertEqual(launch.details.country, "United States")
        XCTAssertEqual(launch.details.site, "Cape Canaveral SFS")
        XCTAssertEqual(launch.details.plannedTime, Date(timeIntervalSince1970: 1701921600))
        XCTAssertEqual(launch.details.missionDescription, "90th SpaceX mission of 2023.")
    }

    func testTimestampSupportsSecondsAndFractionalSeconds() throws {
        for timestamp in ["2023-12-07T04:00:00Z", "2023-12-07T04:00:00.000Z"] {
            var page = try JSONSerialization.jsonObject(with: LaunchFixtures.data()) as! [String: Any]
            var launches = page["result"] as! [[String: Any]]
            launches[0]["t0"] = timestamp
            page["result"] = launches
            let result = try RocketLaunchAPI.decodeResponse(JSONSerialization.data(withJSONObject: page))
            XCTAssertEqual(result[0].details.plannedTime, Date(timeIntervalSince1970: 1701921600))
        }
    }

    func testUnknownTimeRemainsAnEstimateWithoutInventingMidnight() throws {
        let launch = try LaunchFixtures.launches()[2]
        XCTAssertNil(launch.details.plannedTime)
        XCTAssertEqual(launch.details.estimatedDateLabel, "Dec 08")
    }

    private func decode(_ date: [String: Any]) throws -> [RocketLaunch] {
        try RocketLaunchAPI.decodeResponse(LaunchFixtures.data(estimatedDate: date))
    }
}
