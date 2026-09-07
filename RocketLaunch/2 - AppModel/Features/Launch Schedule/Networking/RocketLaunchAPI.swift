import Foundation

/// URL loading suspends; decoding stays on this actor, outside the Main Actor.
actor RocketLaunchAPI: LaunchRepository {
    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession, endpoint: URL) {
        self.session = session
        self.endpoint = endpoint
    }

    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: endpoint)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw LaunchRepositoryError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LaunchRepositoryError.httpStatus(response.statusCode)
        }
        let launches: [RocketLaunch]
        do { launches = try Self.decodeResponse(data) }
        catch { throw LaunchRepositoryError.invalidData }
        try Task.checkCancellation()
        return launches
    }

    /// Shared by the production repository and its fixture regression tests.
    static func decodeResponse(_ data: Data) throws -> [RocketLaunch] {
        try JSONDecoder().decode(Response.self, from: data).result.map { payload in
            RocketLaunch(id: payload.id, name: payload.name,
                         missions: payload.missions.map { LaunchMission(name: $0.name, description: $0.description) },
                         estimatedDate: EstimatedLaunchDate(month: payload.estimatedDate.month,
                                                            day: payload.estimatedDate.day,
                                                            year: payload.estimatedDate.year))
        }
    }
}

// Decode only fields owned by this feature. Optional date components remain
// unknown, and genuinely malformed values still fail decoding.
private struct Response: Decodable {
    let result: [LaunchPayload]
}
private struct LaunchPayload: Decodable {
    let id: Int
    let name: String
    let missions: [MissionPayload]
    let estimatedDate: DatePayload
    enum CodingKeys: String, CodingKey {
        case id, name, missions
        case estimatedDate = "est_date"
    }
}
private struct MissionPayload: Decodable {
    let name: String
    let description: String?
}
private struct DatePayload: Decodable {
    let month: Int?
    let day: Int?
    let year: Int?
}
