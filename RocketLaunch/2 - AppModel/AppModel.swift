import Foundation

/// Constructs the shared graph. The screen requests an initial load when it appears.
@MainActor
struct AppModel {
    static let shared = AppModel.live()
    let launchSchedule: any LaunchScheduleFeatureAPI

    let reminders: any RemindersFeatureAPI

    init(launchSchedule: any LaunchScheduleFeatureAPI, reminders: any RemindersFeatureAPI = RemindersFeature()) {
        self.launchSchedule = launchSchedule
        self.reminders = reminders
    }

    static func live() -> AppModel {
        let endpoint = URL(string: "https://fdo.rocketlaunch.live/json/launches/next/5")!
        let repository = RocketLaunchAPI(session: .shared, endpoint: endpoint)
        let libraryURL = URL(string: "https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=50&mode=normal&hide_recent_previous=true")!
        let library = LaunchLibraryAPI(session: .shared, endpoint: libraryURL)
        let spaceX = SpaceXAPI(session: .shared, endpoint: URL(string: "https://api.spacexdata.com/v5/launches/query")!)
        let reminders = RemindersFeature(defaults: .standard)
        return AppModel(launchSchedule: LaunchScheduleFeature(sources: [
            .init(id: .rocketLaunchLive, repository: repository),
            .init(id: .launchLibrary, repository: library, minimumRefreshInterval: 300),
            .init(id: .spaceX, repository: spaceX, minimumRefreshInterval: 60)
        ], onRefresh: { await reminders.reconcile($0) }), reminders: reminders)
    }
}
