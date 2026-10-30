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
    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks

    init(operator selected: LaunchOperator, launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.selectedOperator = selected
        self.launchScheduleFeature = launchScheduleFeature
        refreshTasks = LaunchRefreshTasks(feature: launchScheduleFeature)
    }

    var title: String { selectedOperator.name }
    var launches: [RocketLaunch] { launches(for: selectedOperator.id) }
    func presentation(for launch: RocketLaunch) -> LaunchPresentation { .init(launch: launch) }
    var sources: [LaunchSourceSnapshot] { relevantSources(for: selectedOperator.id) }

    func launches(for operatorID: String) -> [RocketLaunch] {
        launchScheduleFeature.launches(for: operatorID)
    }

    func relevantSources(for operatorID: String) -> [LaunchSourceSnapshot] {
        launchScheduleFeature.sources(for: operatorID)
    }

    @discardableResult
    func requestRefresh(source: LaunchSourceID) -> Task<Void, Never> {
        refreshTasks.request(source: source)
    }

    func cancelRefresh() { refreshTasks.cancel() }
}
