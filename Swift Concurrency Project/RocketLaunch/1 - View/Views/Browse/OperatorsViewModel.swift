import Foundation
import Observation

@MainActor @Observable
final class OperatorsViewModel {
    let filters = BrowseViewModel()
    @ObservationIgnored private let feature: LaunchScheduleFeature
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.feature = feature }
    var operators: [LaunchOperator] { feature.operators(matching: filters.query) }
    var countries: [String] { feature.launchCountries }
    var isLoading: Bool { if case .loading = feature.state { return true }; return false }
}
