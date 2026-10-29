import Foundation
import Observation

@MainActor @Observable
final class UpcomingViewModel {
    let filters = BrowseViewModel()
    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private let refreshTasks: LaunchRefreshTasks
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) {
        self.feature = feature
        refreshTasks = LaunchRefreshTasks(feature: feature)
    }
    var operators: [LaunchOperator] { feature.operators }
    var launches: [RocketLaunch] { filters.launches(in: feature.snapshot.upcomingLaunches) }
    var countries: [String] { filters.countries(in: operators) }
    var sources: [LaunchSourceSnapshot] { feature.sources }
    var isLoading: Bool { if case .loading = feature.state { return true }; return false }
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> { refreshTasks.request(source: source) }
    func cancelRefresh() { refreshTasks.cancel() }
}
