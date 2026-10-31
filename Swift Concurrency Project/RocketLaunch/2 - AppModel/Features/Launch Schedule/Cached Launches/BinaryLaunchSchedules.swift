import Foundation

/// Versioned binary snapshots. Values are encoded explicitly, never as Swift memory.
enum BinaryLaunchSchedules {
    private static let magic = Data("RKTSCHE1".utf8)
    private static let limit = 50_000_000

    static func encode(_ schedules: [SavedLaunchSchedule]) throws -> Data {
        var writer = Writer()
        writer.data.append(magic)
        try writer.count(schedules.count)
        for schedule in schedules {
            try writer.string(schedule.source.rawValue)
            try writer.date(schedule.fetchedAt)
            try writer.count(schedule.launches.count)
            for launch in schedule.launches {
                let prefix = launch.source.rawValue + ":"
                guard launch.source == schedule.source, launch.id.hasPrefix(prefix) else { throw LaunchRepositoryError.invalidData }
                try writer.string(String(launch.id.dropFirst(prefix.count)))
                try writer.string(launch.name)
                try writer.count(launch.missions.count)
                for mission in launch.missions {
                    try writer.string(mission.name)
                    try writer.optionalString(mission.description)
                }
                try writer.optionalInteger(launch.estimatedDate.month)
                try writer.optionalInteger(launch.estimatedDate.day)
                try writer.optionalInteger(launch.estimatedDate.year)
                let details = launch.details
                try writer.optionalString(details.provider)
                try writer.optionalString(details.vehicle)
                try writer.optionalString(details.country)
                try writer.optionalString(details.site)
                try writer.optionalDate(details.plannedTime)
                try writer.optionalDate(details.sortTime)
                try writer.optionalString(details.estimatedDateLabel)
                try writer.optionalString(details.missionDescription)
                try writer.optionalString(details.watchURL?.absoluteString)
                try writer.optionalString(details.detailsURL?.absoluteString)
            }
        }
        guard writer.data.count <= limit else { throw LaunchRepositoryError.invalidData }
        return writer.data
    }

    static func decode(_ data: Data) throws -> [SavedLaunchSchedule] {
        guard data.count <= limit, data.starts(with: magic) else { throw LaunchRepositoryError.invalidData }
        var reader = Reader(data: data, offset: magic.count)
        let sourceCount = try reader.count(maximum: LaunchSourceID.allCases.count)
        var schedules: [SavedLaunchSchedule] = []
        for _ in 0..<sourceCount {
            guard let source = LaunchSourceID(rawValue: try reader.string()) else { throw LaunchRepositoryError.invalidData }
            let fetchedAt = try reader.date()
            let launchCount = try reader.count(maximum: 100_000)
            var launches: [RocketLaunch] = []
            for _ in 0..<launchCount {
                let id = try reader.string()
                let name = try reader.string()
                let missionCount = try reader.count(maximum: 100_000)
                var missions: [LaunchMission] = []
                for _ in 0..<missionCount {
                    missions.append(try LaunchMission(name: reader.string(), description: reader.optionalString()))
                }
                let estimated = try EstimatedLaunchDate(month: reader.optionalInteger(), day: reader.optionalInteger(), year: reader.optionalInteger())
                let provider = try reader.optionalString()
                let vehicle = try reader.optionalString()
                let country = try reader.optionalString()
                let site = try reader.optionalString()
                let planned = try reader.optionalDate()
                let sort = try reader.optionalDate()
                let estimatedLabel = try reader.optionalString()
                let missionDescription = try reader.optionalString()
                let watch = try reader.optionalURL()
                let detailsURL = try reader.optionalURL()
                launches.append(RocketLaunch(id: id, source: source, name: name, missions: missions, estimatedDate: estimated,
                    details: .init(provider: provider, vehicle: vehicle, country: country, site: site,
                                   plannedTime: planned, sortTime: sort, estimatedDateLabel: estimatedLabel,
                                   missionDescription: missionDescription, watchURL: watch, detailsURL: detailsURL)))
            }
            schedules.append(.init(source: source, launches: launches, fetchedAt: fetchedAt))
        }
        guard reader.offset == data.count, Set(schedules.map(\.source)).count == schedules.count else {
            throw LaunchRepositoryError.invalidData
        }
        return schedules
    }

    private struct Writer {
        var data = Data()
        mutating func word(_ value: UInt64) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        mutating func count(_ value: Int) throws {
            guard value >= 0, value <= BinaryLaunchSchedules.limit else { throw LaunchRepositoryError.invalidData }
            word(UInt64(value))
        }
        mutating func string(_ value: String) throws {
            let bytes = Data(value.utf8)
            try count(bytes.count)
            data.append(bytes)
        }
        mutating func optionalString(_ value: String?) throws {
            word(value == nil ? 0 : 1)
            if let value { try string(value) }
        }
        mutating func date(_ value: Date) throws {
            let seconds = value.timeIntervalSinceReferenceDate
            guard seconds.isFinite else { throw LaunchRepositoryError.invalidData }
            word(seconds.bitPattern)
        }
        mutating func optionalDate(_ value: Date?) throws {
            word(value == nil ? 0 : 1)
            if let value { try date(value) }
        }
        mutating func optionalInteger(_ value: Int?) throws {
            word(value == nil ? 0 : 1)
            if let value { word(UInt64(bitPattern: Int64(value))) }
        }
    }

    private struct Reader {
        let data: Data
        var offset: Int
        mutating func word() throws -> UInt64 {
            guard offset <= data.count, data.count - offset >= 8 else { throw LaunchRepositoryError.invalidData }
            let value = data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
            offset += 8
            return value
        }
        mutating func count(maximum: Int) throws -> Int {
            let value = try word()
            guard value <= UInt64(maximum), value <= UInt64(data.count - offset) else { throw LaunchRepositoryError.invalidData }
            return Int(value)
        }
        mutating func string() throws -> String {
            let length = try count(maximum: BinaryLaunchSchedules.limit)
            let end = offset + length
            guard let value = String(data: data.subdata(in: offset..<end), encoding: .utf8) else { throw LaunchRepositoryError.invalidData }
            offset = end
            return value
        }
        mutating func present() throws -> Bool {
            switch try word() { case 0: return false; case 1: return true; default: throw LaunchRepositoryError.invalidData }
        }
        mutating func optionalString() throws -> String? { try present() ? string() : nil }
        mutating func date() throws -> Date {
            let seconds = Double(bitPattern: try word())
            guard seconds.isFinite else { throw LaunchRepositoryError.invalidData }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        mutating func optionalDate() throws -> Date? { try present() ? date() : nil }
        mutating func optionalInteger() throws -> Int? {
            guard try present() else { return nil }
            guard let value = Int(exactly: Int64(bitPattern: try word())) else { throw LaunchRepositoryError.invalidData }
            return value
        }
        mutating func optionalURL() throws -> URL? {
            guard let value = try optionalString() else { return nil }
            guard let url = URL(string: value) else { throw LaunchRepositoryError.invalidData }
            return url
        }
    }
}
