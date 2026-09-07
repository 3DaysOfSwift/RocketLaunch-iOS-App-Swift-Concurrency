import Foundation

/// Domain values shared by the feature and any interface that presents it.
struct RocketLaunch: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let missions: [LaunchMission]
    let estimatedDate: EstimatedLaunchDate

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
