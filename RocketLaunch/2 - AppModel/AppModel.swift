import Foundation

/// Assembles application features without starting work.
struct AppModel {
    static let shared = AppModel.live()
    let launchSchedule: any LaunchScheduleFeature

    init(launchSchedule: any LaunchScheduleFeature) {
        self.launchSchedule = launchSchedule
    }

    static func live() -> AppModel {
        let network = NetworkManager(session: .shared)
        let repository = RocketLaunchAPI(networkManager: network)
        return AppModel(launchSchedule: LaunchScheduleManager(repository: repository))
    }
}
