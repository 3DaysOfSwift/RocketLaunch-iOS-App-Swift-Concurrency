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

final class LaunchLibraryDecodingTests: XCTestCase {
    func testMapsOperatorCountryAndPreciseTime() throws {
        let launch = try XCTUnwrap(LaunchLibraryAPI.decodeResponse(fixture(precision: "Minute")).first)
        XCTAssertEqual(launch.source, .launchLibrary)
        XCTAssertEqual(launch.id, "launchLibrary:abc")
        XCTAssertEqual(launch.details.provider, "SpaceX")
        XCTAssertEqual(launch.details.country, "United States")
        XCTAssertNotNil(launch.details.plannedTime)
        XCTAssertEqual(launch.primaryMissionDescription, "Deploy satellites")
    }
    func testMonthPrecisionDoesNotInventAnExactTime() throws {
        let launch = try XCTUnwrap(LaunchLibraryAPI.decodeResponse(fixture(precision: "Month")).first)
        XCTAssertNil(launch.details.plannedTime)
        XCTAssertEqual(launch.details.estimatedDateLabel, "September 2026")
    }
    func testCompletedLaunchIsExcluded() throws {
        XCTAssertTrue(try LaunchLibraryAPI.decodeResponse(fixture(precision: "Minute", status: "Success")).isEmpty)
    }
    func testUnknownPrecisionDoesNotInventAnExactTime() throws {
        let launch = try LaunchLibraryAPI.decodeResponse(fixture(precision: "Unknown"))[0]
        XCTAssertNil(launch.details.plannedTime)
        XCTAssertNil(launch.details.estimatedDateLabel)
    }
    func testQuarterPreservesQuarterPrecision() throws {
        let launch = try LaunchLibraryAPI.decodeResponse(fixture(precision: "Quarter"))[0]
        XCTAssertNil(launch.details.plannedTime)
        XCTAssertEqual(launch.details.estimatedDateLabel, "Q3 2026")
    }
    private func fixture(precision: String, status: String = "Go for Launch") -> Data {
        Data("""
        {"results":[{"id":"abc","name":"Falcon 9 | Mission","net":"2026-09-09T09:00:00Z",
        "net_precision":{"name":"\(precision)"},"status":{"name":"\(status)"},
        "launch_service_provider":{"name":"SpaceX"},"rocket":{"configuration":{"name":"Falcon 9"}},
        "mission":{"name":"Mission","description":"Deploy satellites"},
        "pad":{"country":{"name":"United States"},"location":{"name":"Cape Canaveral"}}}]}
        """.utf8)
    }
}

final class SpaceXAPITests: XCTestCase {
    private func fixture(precision: String = "hour", upcoming: Bool = true) -> Data {
        Data("""
        {"docs":[{"id":"mission-id","name":"Example mission","upcoming":\(upcoming),
        "date_unix":1700000000,"date_precision":"\(precision)","details":"Deploy a satellite",
        "rocket":{"name":"Falcon 9"},"launchpad":{"full_name":"Cape Canaveral SLC-40"}}]}
        """.utf8)
    }
    func testDecodesPopulatedRocketAndPadWithoutInventingCountry() throws {
        let launch = try XCTUnwrap(SpaceXAPI.decodeResponse(fixture()).first)
        XCTAssertEqual(launch.id, "spaceX:mission-id")
        XCTAssertEqual(launch.details.provider, "SpaceX")
        XCTAssertEqual(launch.details.vehicle, "Falcon 9")
        XCTAssertEqual(launch.details.site, "Cape Canaveral SLC-40")
        XCTAssertNil(launch.details.country)
        XCTAssertNil(launch.details.plannedTime)
        XCTAssertEqual(launch.details.missionDescription, "Deploy a satellite")
    }
    func testMinutePrecisionMapsToAnExactTime() throws {
        XCTAssertEqual(try SpaceXAPI.decodeResponse(fixture(precision: "minute"))[0].details.plannedTime,
                       Date(timeIntervalSince1970: 1700000000))
    }
    func testPastMissionsMarkedNotUpcomingAreExcluded() throws {
        XCTAssertTrue(try SpaceXAPI.decodeResponse(fixture(upcoming: false)).isEmpty)
    }
    func testRequestQueriesUpcomingLaunchesAndPopulatesDetails() throws {
        let request = SpaceXAPI.request(endpoint: URL(string: "https://example.invalid/query")!)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
        XCTAssertEqual((body["query"] as? [String: Bool])?["upcoming"], true)
        XCTAssertEqual((body["options"] as? [String: Any])?["limit"] as? Int, 50)
    }
    func testHTTPFailureRemainsAnError() async throws {
        let (session, id) = StubURLProtocol.session(response: .init(data: fixture(), statusCode: 503))
        defer { session.invalidateAndCancel(); StubURLProtocol.remove(id) }
        let api = SpaceXAPI(session: session, endpoint: URL(string: "https://example.invalid/query")!)
        do { _ = try await api.fetchUpcomingLaunches(); XCTFail("Expected HTTP failure") }
        catch { XCTAssertEqual(error as? LaunchRepositoryError, .httpStatus(503)) }
    }
    @MainActor func testOutdatedScheduleIsCachedButCannotBecomeNext() async throws {
        let began = expectation(description: "began")
        let repository = ControlledLaunchRepository { _ in began.fulfill() }
        let feature = LaunchScheduleFeature(sources: [.init(id: .spaceX, repository: repository)], now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let records = try SpaceXAPI.decodeResponse(fixture(precision: "minute"))
        let task = Task { await feature.refresh() }; await waitFor([began])
        await repository.complete(0, with: .success(records)); await task.value
        let projection1 = await feature.snapshot
        XCTAssertEqual(projection1.sources[0].launches, records)
        let projection2 = await feature.snapshot
        XCTAssertEqual(projection2.operators.first?.name, "SpaceX")
        let projection3 = await feature.snapshot
        XCTAssertNil(projection3.nextLaunch)
        let projection4 = await feature.snapshot
        XCTAssertEqual(projection4.state, .empty)
    }
}
