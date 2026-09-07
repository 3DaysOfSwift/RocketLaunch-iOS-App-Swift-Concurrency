import XCTest
@testable import RocketLaunch

final class AppModelTests: XCTestCase {
    @MainActor func testRetainsProvidedFeatureWithoutStartingWork() async {
        let feature = ControlledLaunchFeature()
        let appModel = AppModel(launchSchedule: feature)
        XCTAssertTrue(appModel.launchSchedule === feature)
        XCTAssertEqual(feature.refreshCount, 0)
    }
    @MainActor func testIndependentApplicationGraphsDoNotShareFeatureRequests() async {
        let firstFeature = ControlledLaunchFeature()
        let secondFeature = ControlledLaunchFeature()
        let first = AppModel(launchSchedule: firstFeature)
        _ = AppModel(launchSchedule: secondFeature)
        await first.launchSchedule.refresh()
        XCTAssertEqual(firstFeature.refreshCount, 1)
        XCTAssertEqual(secondFeature.refreshCount, 0)
    }
}
