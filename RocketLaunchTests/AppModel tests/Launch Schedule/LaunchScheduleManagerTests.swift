import XCTest
@testable import RocketLaunch

final class LaunchScheduleManagerTests: XCTestCase {
    func testConstructionDoesNotFetch() {
        let repository = ControlledLaunchRepository()
        _ = LaunchScheduleManager(repository: repository)
        XCTAssertTrue(repository.completions.isEmpty)
    }

    func testFirstReturnedLaunchIsSelected() throws {
        let repository = ControlledLaunchRepository()
        let manager = LaunchScheduleManager(repository: repository)
        let launches = try LaunchFixtures.launches()
        var selected: RocketLaunch?
        manager.refresh { selected = try? $0.get() }
        XCTAssertEqual(repository.completions.count, 1)
        repository.completions[0](.success(launches))
        XCTAssertEqual(selected?.id, launches[0].id)
    }

    func testEmptyResponseReturnsNoLaunch() {
        let repository = ControlledLaunchRepository()
        let manager = LaunchScheduleManager(repository: repository)
        var completed = false
        manager.refresh { result in
            completed = true
            guard case .success(nil) = result else { return XCTFail("Expected empty success") }
        }
        repository.completions[0](.success([]))
        XCTAssertTrue(completed)
    }

    func testRepositoryFailureReachesCaller() {
        let repository = ControlledLaunchRepository()
        let manager = LaunchScheduleManager(repository: repository)
        var failed = false
        manager.refresh { result in
            if case .failure(.networkingError) = result { failed = true }
        }
        repository.completions[0](.failure(.networkingError))
        XCTAssertTrue(failed)
    }

    // Characterises DEF-001; replace this expectation when the approved fix lands.
    func testLegacyRefreshGuardAllowsOverlappingRequests() {
        let repository = ControlledLaunchRepository()
        let manager = LaunchScheduleManager(repository: repository)
        manager.refresh { _ in }
        manager.refresh { _ in }
        XCTAssertEqual(repository.completions.count, 2)
    }
}
