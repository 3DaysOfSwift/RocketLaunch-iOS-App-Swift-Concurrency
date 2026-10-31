import XCTest
@testable import RocketLaunch

@MainActor
final class AboutViewModelTests: XCTestCase {
    func testSourceLinksComeFromTheSettingsFeature() {
        let settings = SettingsFeature()
        let viewModel = AboutViewModel(settingsFeature: settings)
        XCTAssertEqual(viewModel.spaceXURL?.absoluteString, "https://github.com/r-spacex/SpaceX-API")
        XCTAssertEqual(viewModel.launchLibraryURL?.absoluteString, "https://thespacedevs.com/llapi")
        XCTAssertEqual(viewModel.rocketLaunchURL?.absoluteString, "https://www.rocketlaunch.live")
    }
}
