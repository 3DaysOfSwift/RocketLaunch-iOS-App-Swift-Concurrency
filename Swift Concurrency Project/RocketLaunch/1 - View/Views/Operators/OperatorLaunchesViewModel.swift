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
        feature.operators.first(where: { $0.id == operatorID })?.launches ?? []
    }

    func relevantSources(for operatorID: String) -> [LaunchSourceSnapshot] {
        let knownSources = feature.operators.first(where: { $0.id == operatorID })?.sourceIDs ?? []
        return feature.sources.filter {
            if $0.id == .spaceX { return operatorID == "spacex" }
            return $0.fetchedAt == nil || knownSources.contains($0.id)
        }
    }

    @discardableResult
    func requestRefresh(source: LaunchSourceID) -> Task<Void, Never> {
        refreshTasks.request(source: source)
    }

    func cancelRefresh() { refreshTasks.cancel() }
}
