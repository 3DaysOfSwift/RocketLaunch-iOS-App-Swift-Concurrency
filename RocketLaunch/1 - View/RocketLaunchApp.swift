import SwiftUI

@main
struct RocketLaunchApp: App {
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(themeManager)
        }
    }
}
