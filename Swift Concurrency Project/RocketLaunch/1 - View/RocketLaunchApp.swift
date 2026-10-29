import SwiftUI

@main
struct RocketLaunchApp: App {
    @UIApplicationDelegateAdaptor(RocketLaunchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var themeManager = ThemeManager(defaults: .standard)

    var body: some Scene {
        WindowGroup {
            // Hosted unit tests inject their own features; keep live networking dormant.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                ContentView().environment(themeManager)
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        await AppModel.shared.applicationDidBecomeActive()
                    }
            } else {
                Color.clear
            }
        }
    }
}

@MainActor
final class RocketLaunchAppDelegate: NSObject, UIApplicationDelegate {
    private var launchTask: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Hosted tests construct isolated models without contacting production services.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return true }
        launchTask = Task {
            await AppModel.shared.applicationDidFinishLaunching()
        }
        return true
    }

    deinit { launchTask?.cancel() }
}
