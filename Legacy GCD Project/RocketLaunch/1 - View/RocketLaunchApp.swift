import SwiftUI

@main
struct RocketLaunchApp: App {
    @State private var themeManager = ThemeManager(defaults: .standard)

    var body: some Scene {
        WindowGroup {
            // Hosted unit tests inject their own features; keep live networking dormant.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                ContentView().environment(themeManager)
            } else {
                Color.clear
            }
        }
    }
}
