import SwiftUI

@main
struct RocketLaunchApp: App {
    @UIApplicationDelegateAdaptor(RocketLaunchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let settingsFeature = AppModel.shared.settingsFeature

    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.appColourTheme, settingsFeature.selected)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await AppModel.shared.applicationDidBecomeActive()
                }
        }
    }
}

@MainActor
final class RocketLaunchAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Hosted tests construct isolated models without contacting production services.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return true }
        AppModel.shared.applicationDidFinishLaunching()
        return true
    }
}
