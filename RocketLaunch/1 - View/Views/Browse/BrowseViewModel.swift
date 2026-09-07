import Foundation
import Observation

@MainActor @Observable
final class BrowseViewModel {
    var search = ""
    var operatorID = ""
    var country = ""

    func launches(in launches: [RocketLaunch]) -> [RocketLaunch] {
        launches.filter { launch in
            (operatorID.isEmpty || LaunchOperator.key(for: launch.details.provider) == operatorID)
                && (country.isEmpty || Self.countryName(launch.details.country) == country)
                && matches([launch.name, launch.details.provider, launch.details.vehicle, launch.details.missionDescription])
        }
    }

    func operators(in operators: [LaunchOperator]) -> [LaunchOperator] {
        operators.filter { matches([$0.name]) && (country.isEmpty || $0.launches.contains { Self.countryName($0.details.country) == country }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func countries(in operators: [LaunchOperator]) -> [String] {
        Set(operators.flatMap(\.launches).compactMap { Self.countryName($0.details.country) }.filter { !$0.isEmpty }).sorted()
    }

    static func countryName(_ name: String?) -> String? {
        switch name {
        case "USA", "US", "United States of America": return "United States"
        default: return name
        }
    }

    private func matches(_ values: [String?]) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
