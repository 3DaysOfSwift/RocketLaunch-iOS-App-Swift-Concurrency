import Foundation
import Observation

@MainActor @Observable
final class UpdatesViewModel {
    var showingLaunch = false
    private(set) var selectedLaunch: RocketLaunch?
    func showLaunch(_ launch: RocketLaunch) {
        selectedLaunch = launch
        showingLaunch = true
    }

    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.launchScheduleFeature = launchScheduleFeature
        refreshTasks = LaunchRefreshTasks(feature: launchScheduleFeature)
    }
    var sources: [LaunchSourceSnapshot] { launchScheduleFeature.sources }
    var updates: [LaunchUpdate] { launchScheduleFeature.updates }
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> { refreshTasks.request(source: source) }
    func cancelRefresh() { refreshTasks.cancel() }
}
