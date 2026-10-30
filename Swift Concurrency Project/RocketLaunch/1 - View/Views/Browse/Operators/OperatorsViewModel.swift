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
    @ObservationIgnored private let launchScheduleFeature: LaunchScheduleFeature
    init(launchScheduleFeature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature) { self.launchScheduleFeature = launchScheduleFeature }
    var operators: [LaunchOperator] { launchScheduleFeature.operators(matching: filters.query) }
    var countries: [String] { launchScheduleFeature.launchCountries }
    var isLoading: Bool { if case .loading = launchScheduleFeature.state { return true }; return false }
}
