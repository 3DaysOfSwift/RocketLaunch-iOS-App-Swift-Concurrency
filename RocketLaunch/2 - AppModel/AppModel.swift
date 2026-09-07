import Foundation

/// Constructs the shared graph. The screen requests an initial load when it appears.
@MainActor
struct AppModel {
    static let shared = AppModel.live()
    let launchSchedule: any LaunchScheduleFeatureAPI

    init(launchSchedule: any LaunchScheduleFeatureAPI) { self.launchSchedule = launchSchedule }

    static func live() -> AppModel {
        let endpoint = URL(string: "https://fdo.rocketlaunch.live/json/launches/next/5")!
        let repository = RocketLaunchAPI(session: .shared, endpoint: endpoint)
        return AppModel(launchSchedule: LaunchScheduleFeature(repository: repository))
    }
}
