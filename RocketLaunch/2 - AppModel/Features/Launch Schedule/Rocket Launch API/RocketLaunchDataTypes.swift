import Foundation

/// Domain values shared by the feature and any interface that presents it.
struct RocketLaunch: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let missions: [LaunchMission]
    let estimatedDate: EstimatedLaunchDate

    let details: LaunchDetails

    init(id: Int, name: String, missions: [LaunchMission], estimatedDate: EstimatedLaunchDate, details: LaunchDetails = LaunchDetails()) {
        self.id = id; self.name = name; self.missions = missions
        self.estimatedDate = estimatedDate; self.details = details
    }

    var primaryMissionDescription: String? { missions.first?.description }
}

struct LaunchMission: Equatable, Sendable {
    let name: String
    let description: String?
}

struct EstimatedLaunchDate: Equatable, Sendable {
    let month: Int?
    let day: Int?
    let year: Int?
}

struct LaunchDetails: Equatable, Sendable {
    let provider: String?
    let vehicle: String?
    let country: String?
    let site: String?
    let plannedTime: Date?
    let estimatedDateLabel: String?
    let missionDescription: String?

    init(provider: String? = nil, vehicle: String? = nil, country: String? = nil,
         site: String? = nil, plannedTime: Date? = nil, estimatedDateLabel: String? = nil,
         missionDescription: String? = nil) {
        self.provider = provider; self.vehicle = vehicle; self.country = country; self.site = site
        self.plannedTime = plannedTime; self.estimatedDateLabel = estimatedDateLabel
        self.missionDescription = missionDescription
    }
}
