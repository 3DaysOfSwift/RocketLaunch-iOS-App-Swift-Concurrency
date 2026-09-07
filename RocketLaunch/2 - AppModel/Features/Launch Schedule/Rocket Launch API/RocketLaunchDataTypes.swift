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
