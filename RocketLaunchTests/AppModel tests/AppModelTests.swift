import XCTest
@testable import RocketLaunch

final class AppModelTests: XCTestCase {
    func testRetainsProvidedFeatureWithoutStartingWork() {
        let feature = ControlledLaunchFeature()
        let appModel = AppModel(launchSchedule: feature)
        XCTAssertTrue((appModel.launchSchedule as? ControlledLaunchFeature) === feature)
        XCTAssertTrue(feature.completions.isEmpty)
    }

    func testIndependentApplicationGraphsDoNotShareFeatureRequests() {
        let firstFeature = ControlledLaunchFeature()
        let secondFeature = ControlledLaunchFeature()
        let first = AppModel(launchSchedule: firstFeature)
        _ = AppModel(launchSchedule: secondFeature)
        first.launchSchedule.refresh { _ in }
        XCTAssertEqual(firstFeature.completions.count, 1)
        XCTAssertTrue(secondFeature.completions.isEmpty)
    }
}
