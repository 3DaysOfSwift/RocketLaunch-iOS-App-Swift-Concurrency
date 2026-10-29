import Foundation
import Observation

@MainActor @Observable
final class UpdatesViewModel {
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }
    var sources: [LaunchSourceSnapshot] { feature.sources }
    var updates: [LaunchUpdate] { feature.updates }
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> { refreshTasks.request(source: source) }
    func cancelRefresh() { refreshTasks.cancel() }
}
