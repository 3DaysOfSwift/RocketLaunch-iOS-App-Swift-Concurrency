import Foundation
import Observation

@MainActor @Observable
final class OperatorLaunchesViewModel {
    var showingLaunch = false
    private(set) var selectedLaunch: RocketLaunch?
    func showLaunch(_ launch: RocketLaunch) {
        selectedLaunch = launch
        showingLaunch = true
    }

    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks

    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }

    var title: String { feature.selectedOperator?.name ?? "Operator" }
    var launches: [RocketLaunch] { feature.selectedOperator.map { launches(for: $0.id) } ?? [] }
    var sources: [LaunchSourceSnapshot] { feature.selectedOperator.map { relevantSources(for: $0.id) } ?? [] }

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
