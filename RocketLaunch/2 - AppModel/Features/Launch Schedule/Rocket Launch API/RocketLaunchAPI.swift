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

    private static func parseLaunchTime(_ value: String) throws -> Date {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: value) { return date }
        let minutes = DateFormatter()
        minutes.locale = Locale(identifier: "en_US_POSIX")
        minutes.timeZone = TimeZone(secondsFromGMT: 0)
        minutes.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        minutes.isLenient = false
        if let date = minutes.date(from: value) { return date }
        throw LaunchRepositoryError.invalidData
    }

    /// Shared by the production repository and its fixture regression tests.
    static func decodeResponse(_ data: Data) throws -> [RocketLaunch] {
        try JSONDecoder().decode(Response.self, from: data).result.map { payload in
            RocketLaunch(id: payload.id, name: payload.name,
                         missions: payload.missions.map { LaunchMission(name: $0.name, description: $0.description) },
                         estimatedDate: EstimatedLaunchDate(month: payload.estimatedDate.month,
                                                            day: payload.estimatedDate.day,
                                                            year: payload.estimatedDate.year),
                         details: LaunchDetails(provider: payload.provider?.name, vehicle: payload.vehicle?.name,
                            country: payload.pad?.location?.country, site: payload.pad?.location?.name,
                            plannedTime: try payload.t0.map(Self.parseLaunchTime),
                            estimatedDateLabel: payload.dateLabel, missionDescription: payload.missionDescription))
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
    let provider: NamedPayload?
    let vehicle: NamedPayload?
    let pad: PadPayload?
    let t0: String?
    let dateLabel: String?
    let missionDescription: String?
    enum CodingKeys: String, CodingKey {
        case id, name, missions, provider, vehicle, pad, t0
        case dateLabel = "date_str"
        case missionDescription = "mission_description"
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

private struct NamedPayload: Decodable { let name: String? }
private struct PadPayload: Decodable { let location: LocationPayload? }
private struct LocationPayload: Decodable { let name: String?; let country: String? }
