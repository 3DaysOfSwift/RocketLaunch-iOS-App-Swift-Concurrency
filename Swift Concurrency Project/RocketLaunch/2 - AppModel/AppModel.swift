import Foundation

/// Constructs Features and starts application-wide loading at launch.
@MainActor
final class AppModel {
    static let shared = AppModel.live()
    let launchScheduleFeature: LaunchScheduleFeature
    let settingsFeature: SettingsFeature
    private var hasLaunched: Bool

    init(launchScheduleFeature: LaunchScheduleFeature, settingsFeature: SettingsFeature = SettingsFeature()) {
        self.launchScheduleFeature = launchScheduleFeature
        self.settingsFeature = settingsFeature
        self.hasLaunched = false
    }

    func applicationDidFinishLaunching() async {
        guard !hasLaunched else { return }
        hasLaunched = true
        async let reminders: Void = launchScheduleFeature.loadRemindersIfNeeded()
        async let launches: Void = launchScheduleFeature.loadIfNeeded()
        _ = await (reminders, launches)
    }

    func applicationDidBecomeActive() async {
        await launchScheduleFeature.monitorScheduleTime()
    }

    static func live() -> AppModel {
        let endpoint = URL(string: "https://fdo.rocketlaunch.live/json/launches/next/5")!
        let repository = RocketLaunchAPI(session: .shared, endpoint: endpoint)
        let libraryURL = URL(string: "https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=50&mode=normal&hide_recent_previous=true")!
        let library = LaunchLibraryAPI(session: .shared, endpoint: libraryURL)
        let spaceX = SpaceXAPI(session: .shared, endpoint: URL(string: "https://api.spacexdata.com/v5/launches/query")!)
        return AppModel(launchScheduleFeature: LaunchScheduleFeature(sources: [
            .init(id: .rocketLaunchLive, repository: repository),
            .init(id: .launchLibrary, repository: library, minimumRefreshInterval: 300),
            .init(id: .spaceX, repository: spaceX, minimumRefreshInterval: 60)
        ], reminderStorage: .standard), settingsFeature: SettingsFeature(defaults: .standard))
    }
}
