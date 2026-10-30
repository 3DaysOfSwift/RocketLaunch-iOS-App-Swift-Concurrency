import Foundation
import Observation

@MainActor @Observable
final class UpcomingViewModel {
    var showingLaunch = false
    func showLaunch(_ launch: RocketLaunch) {
        feature.selectLaunch(launch, in: .upcoming)
        showingLaunch = true
    }

    var filters = BrowseFilters()
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }
    var operators: [LaunchOperator] { feature.operators }
    var launches: [RocketLaunch] { feature.launches(matching: filters.query) }
    var countries: [String] { feature.launchCountries }
    var sources: [LaunchSourceSnapshot] { feature.sources }
    var isLoading: Bool { if case .loading = feature.state { return true }; return false }
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> { refreshTasks.request(source: source) }
    func cancelRefresh() { refreshTasks.cancel() }
}
