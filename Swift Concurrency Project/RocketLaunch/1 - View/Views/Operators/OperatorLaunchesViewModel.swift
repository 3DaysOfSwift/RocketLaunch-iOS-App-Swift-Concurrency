import Foundation
import Observation

@MainActor @Observable
final class OperatorLaunchesViewModel {
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks

    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }

    func launches(for operatorID: String) -> [RocketLaunch] {
        feature.launches(for: operatorID)
    }

    func relevantSources(for operatorID: String) -> [LaunchSourceSnapshot] {
        feature.sources(for: operatorID)
    }

    @discardableResult
    func requestRefresh(source: LaunchSourceID) -> Task<Void, Never> {
        refreshTasks.request(source: source)
    }

    func cancelRefresh() { refreshTasks.cancel() }
}
