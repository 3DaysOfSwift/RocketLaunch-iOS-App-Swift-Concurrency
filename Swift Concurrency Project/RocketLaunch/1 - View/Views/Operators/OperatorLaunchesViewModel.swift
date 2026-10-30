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

    private let selectedOperator: LaunchOperator
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks

    init(operator selected: LaunchOperator, feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.selectedOperator = selected
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }

    var title: String { selectedOperator.name }
    var launches: [RocketLaunch] { launches(for: selectedOperator.id) }
    var sources: [LaunchSourceSnapshot] { relevantSources(for: selectedOperator.id) }

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
