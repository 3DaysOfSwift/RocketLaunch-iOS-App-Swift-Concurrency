import Foundation

/// Adapter for the community r-spacex API, not an official SpaceX service.
actor SpaceXAPI: LaunchRepository {
    private let session: URLSession
    private let endpoint: URL
    init(session: URLSession, endpoint: URL) { self.session = session; self.endpoint = endpoint }

    static func request(endpoint: URL) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(#"{"query":{"upcoming":true},"options":{"limit":50,"sort":{"date_unix":"asc"},"populate":[{"path":"rocket","select":"name"},{"path":"launchpad","select":"full_name locality region"}]}}"#.utf8)
        return request
    }

    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: Self.request(endpoint: endpoint))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LaunchRepositoryError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LaunchRepositoryError.httpStatus(response.statusCode) }
        let launches: [RocketLaunch]
        do { launches = try Self.decodeResponse(data) } catch { throw LaunchRepositoryError.invalidData }
        try Task.checkCancellation()
        return launches
    }

    static func decodeResponse(_ data: Data) throws -> [RocketLaunch] {
        try JSONDecoder().decode(Response.self, from: data).docs.filter(\.upcoming).map { payload in
            let date = payload.date_unix.map { Date(timeIntervalSince1970: $0) }
            let exact = ["minute", "second"].contains(payload.date_precision ?? "")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let label: String?
            switch payload.date_precision {
            case "year": formatter.dateFormat = "yyyy"; label = date.map(formatter.string)
            case "month": formatter.dateFormat = "MMMM yyyy"; label = date.map(formatter.string)
            case "day", "hour", "minute", "second": formatter.dateFormat = "d MMM yyyy"; label = date.map(formatter.string)
            default: label = nil
            }
            // The launchpad schema has locality/region, not a country. Do not
            // substitute the rocket manufacturer's country for launch country.
            return RocketLaunch(id: payload.id, source: .spaceX, name: payload.name,
                missions: [.init(name: payload.name, description: payload.details)],
                estimatedDate: .init(month: nil, day: nil, year: nil),
                details: .init(provider: "SpaceX", vehicle: payload.rocket?.name,
                    site: payload.launchpad?.full_name, plannedTime: exact ? date : nil,
                    sortTime: date, estimatedDateLabel: label, missionDescription: payload.details, watchURL: launchWebURL(payload.links?.webcast),
                    detailsURL: launchWebURL(payload.links?.article)))
        }
    }
}

private struct Response: Decodable { let docs: [LaunchPayload] }
private struct LaunchPayload: Decodable {
    let id: String
    let name: String
    let upcoming: Bool
    let date_unix: Double?
    let date_precision: String?
    let details: String?
    let rocket: RocketPayload?
    let launchpad: PadPayload?
    let links: LinksPayload?
}
private struct RocketPayload: Decodable { let name: String? }
private struct PadPayload: Decodable { let full_name: String? }

private struct LinksPayload: Decodable { let webcast: String?; let article: String? }
