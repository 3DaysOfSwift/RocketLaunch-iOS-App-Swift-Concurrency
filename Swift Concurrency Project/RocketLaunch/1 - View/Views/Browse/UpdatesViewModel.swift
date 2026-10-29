import Foundation
import Observation

@MainActor @Observable
final class UpdatesViewModel {
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(feature: LaunchScheduleFeature = AppModel.shared.launchSchedule) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }
    var updates: [LaunchUpdate] { feature.updates }
    @discardableResult
    func requestRefresh() -> Task<Void, Never> { refreshTasks.request() }
    func cancelRefresh() { refreshTasks.cancel() }
}
