import Foundation
import Observation

@MainActor @Observable
final class OperatorsViewModel {
    let filters = BrowseViewModel()
    @ObservationIgnored private let feature: LaunchScheduleFeature
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.feature = feature }
    var operators: [LaunchOperator] { filters.operators(in: feature.operators) }
    var countries: [String] { filters.countries(in: feature.operators) }
    var isLoading: Bool { if case .loading = feature.state { return true }; return false }
}
