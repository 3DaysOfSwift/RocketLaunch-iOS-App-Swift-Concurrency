import Foundation
import Observation

@MainActor @Observable
final class OperatorsViewModel {
    var showingOperator = false
    private(set) var selectedOperator: LaunchOperator?
    func showOperator(_ selected: LaunchOperator) {
        selectedOperator = selected
        showingOperator = true
    }

    var filters = BrowseFilters()
    @ObservationIgnored private let feature: LaunchScheduleFeature
    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.feature = feature }
    var operators: [LaunchOperator] { feature.operators(matching: filters.query) }
    var countries: [String] { feature.launchCountries }
    var isLoading: Bool { if case .loading = feature.state { return true }; return false }
}
