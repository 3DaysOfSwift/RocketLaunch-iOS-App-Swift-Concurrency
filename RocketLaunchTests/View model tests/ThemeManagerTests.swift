import XCTest
import Observation
@testable import RocketLaunch

final class ThemeManagerTests: XCTestCase {
    @MainActor func testDefaultThemeFollowsSystemPalette() async {
        XCTAssertEqual(ThemeManager().selected, .system)
    }
    @MainActor func testThemeChangesAreObservable() async {
        let manager = ThemeManager()
        let changed = expectation(description: "theme")
        withObservationTracking { _ = manager.selected } onChange: { changed.fulfill() }
        manager.select(.midnight)
        await waitFor([changed])
        XCTAssertEqual(manager.selected, .midnight)
    }
}
