import Foundation

/// Domain values shared by the feature and any interface that presents it.
struct RocketLaunch: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let source: LaunchSourceID
    let name: String
    let missions: [LaunchMission]
    let estimatedDate: EstimatedLaunchDate

    let details: LaunchDetails

    init(id: Int, name: String, missions: [LaunchMission], estimatedDate: EstimatedLaunchDate, details: LaunchDetails = LaunchDetails()) {
        self.init(id: String(id), source: .rocketLaunchLive, name: name, missions: missions, estimatedDate: estimatedDate, details: details)
    }

    init(id: String, source: LaunchSourceID, name: String, missions: [LaunchMission], estimatedDate: EstimatedLaunchDate, details: LaunchDetails) {
        self.id = source.rawValue + ":" + id; self.source = source
        self.name = name; self.missions = missions
        self.estimatedDate = estimatedDate; self.details = details
    }

    var primaryMissionDescription: String? { missions.first?.description }
}

struct LaunchMission: Equatable, Sendable, Codable {
    let name: String
    let description: String?
}

struct EstimatedLaunchDate: Equatable, Sendable, Codable {
    let month: Int?
    let day: Int?
    let year: Int?
}

struct LaunchDetails: Equatable, Sendable, Codable {
    let provider: String?
    let vehicle: String?
    let country: String?
    let site: String?
    let plannedTime: Date?
    let sortTime: Date?
    let estimatedDateLabel: String?
    let missionDescription: String?
    let watchURL: URL?
    let detailsURL: URL?

    init(provider: String? = nil, vehicle: String? = nil, country: String? = nil,
         site: String? = nil, plannedTime: Date? = nil, sortTime: Date? = nil, estimatedDateLabel: String? = nil,
         missionDescription: String? = nil, watchURL: URL? = nil, detailsURL: URL? = nil) {
        self.provider = provider; self.vehicle = vehicle; self.country = country; self.site = site
        self.sortTime = sortTime
        self.plannedTime = plannedTime; self.estimatedDateLabel = estimatedDateLabel
        self.missionDescription = missionDescription
        self.watchURL = watchURL; self.detailsURL = detailsURL
    }
}

/// External links must be actual web destinations, not arbitrary URL schemes.
func launchWebURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value),
          ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
    return url
}

/// A scheduled time is not evidence of liftoff. Estimated dates never become a clock countdown.
enum LaunchCountdown: Equatable, Sendable {
    case remaining(TimeInterval)
    case timeUnconfirmed
    case awaitingUpdate
}

extension LaunchDetails {
    func countdown(at now: Date) -> LaunchCountdown {
        guard let plannedTime else { return .timeUnconfirmed }
        let remaining = plannedTime.timeIntervalSince(now)
        return remaining > 0 ? .remaining(remaining) : .awaitingUpdate
    }
}


/// Value query rules shared by every presentation of the launch catalogue.
struct LaunchBrowseQuery: Sendable {
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
