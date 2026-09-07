import Foundation

actor LaunchLibraryAPI: LaunchRepository {
    private let session: URLSession
    private let endpoint: URL
    init(session: URLSession, endpoint: URL) { self.session = session; self.endpoint = endpoint }

    func fetchUpcomingLaunches() async throws -> [RocketLaunch] {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LaunchRepositoryError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LaunchRepositoryError.httpStatus(response.statusCode) }
        let launches: [RocketLaunch]
        do { launches = try Self.decodeResponse(data) } catch { throw LaunchRepositoryError.invalidData }
        try Task.checkCancellation()
        return launches
    }

    static func decodeResponse(_ data: Data) throws -> [RocketLaunch] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let dateParser = ISO8601DateFormatter()
        let utc = TimeZone(secondsFromGMT: 0)!
        return try response.results.compactMap { item in
            if ["Success", "Failure", "Partial Failure", "In Flight"].contains(item.status?.name ?? "") { return nil }
            var date: Date?
            if let net = item.net {
                dateParser.formatOptions = [.withInternetDateTime]
                date = dateParser.date(from: net)
                if date == nil {
                    dateParser.formatOptions.insert(.withFractionalSeconds)
                    date = dateParser.date(from: net)
                }
                guard date != nil else { throw LaunchRepositoryError.invalidData }
            }
            let precise = ["Minute", "Second"].contains(item.net_precision?.name ?? "")
            let dateLabel: String?
            if let date {
                // Preserve the provider's stated precision; never invent a clock time.
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = utc
                switch item.net_precision?.name {
                case "Year":
                    formatter.dateFormat = "yyyy"; dateLabel = formatter.string(from: date)
                case "Month":
                    formatter.dateFormat = "MMMM yyyy"; dateLabel = formatter.string(from: date)
                case "Quarter", "Half Year":
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
                    let month = calendar.component(.month, from: date)
                    let year = calendar.component(.year, from: date)
                    dateLabel = item.net_precision?.name == "Quarter" ? "Q\((month - 1) / 3 + 1) \(year)" : "H\((month - 1) / 6 + 1) \(year)"
                case "Day", "Hour", "Minute", "Second":
                    formatter.dateFormat = "d MMM yyyy"; dateLabel = formatter.string(from: date)
                default: dateLabel = nil
                }
            } else { dateLabel = nil }
            let missionName = item.mission?.name ?? item.name
            return RocketLaunch(id: item.id, source: .launchLibrary, name: missionName,
                missions: [LaunchMission(name: missionName, description: item.mission?.description)],
                estimatedDate: .init(month: nil, day: nil, year: nil),
                details: .init(provider: item.launch_service_provider?.name,
                    vehicle: item.rocket?.configuration?.name, country: item.pad?.country?.name,
                    site: item.pad?.location?.name, plannedTime: precise ? date : nil, sortTime: date,
                    estimatedDateLabel: dateLabel, missionDescription: item.mission?.description))
        }
    }
}

private struct Response: Decodable { let results: [LaunchPayload] }
private struct LaunchPayload: Decodable {
    let id: String
    let name: String
    let net: String?
    let net_precision: NamedPayload?
    let status: NamedPayload?
    let launch_service_provider: NamedPayload?
    let rocket: RocketPayload?
    let mission: MissionPayload?
    let pad: PadPayload?
}
private struct NamedPayload: Decodable { let name: String? }
private struct RocketPayload: Decodable { let configuration: NamedPayload? }
private struct MissionPayload: Decodable { let name: String?; let description: String? }
private struct PadPayload: Decodable { let country: NamedPayload?; let location: NamedPayload? }
