import Foundation
import Observation

@MainActor @Observable
final class UpcomingViewModel {
    var showingLaunch = false
    private(set) var selectedLaunch: RocketLaunch?
    func showLaunch(_ launch: RocketLaunch) {
        selectedLaunch = launch
        showingLaunch = true
    }

    var filters = BrowseFilters()
    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.launchScheduleFeature = launchScheduleFeature
        refreshTasks = LaunchRefreshTasks(feature: launchScheduleFeature)
    }
    var operators: [LaunchOperator] { launchScheduleFeature.operators }
    var launches: [RocketLaunch] { launchScheduleFeature.launches(matching: filters.query) }
    var countries: [String] { launchScheduleFeature.launchCountries }
    func presentation(for launch: RocketLaunch) -> LaunchPresentation { .init(launch: launch) }
    var sources: [LaunchSourceSnapshot] { launchScheduleFeature.sources }
    var isLoading: Bool { if case .loading = launchScheduleFeature.state { return true }; return false }
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> { refreshTasks.request(source: source) }
    func cancelRefresh() { refreshTasks.cancel() }
}
