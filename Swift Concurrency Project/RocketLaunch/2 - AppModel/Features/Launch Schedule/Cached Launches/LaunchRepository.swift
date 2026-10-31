import Foundation

protocol LaunchRepository: Sendable {
    func fetchUpcomingLaunches() async throws -> [RocketLaunch]
}

enum LaunchRepositoryError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidData
}

/// A provider's last successfully downloaded schedule and its original fetch time.
struct SavedLaunchSchedule: Codable, Equatable, Sendable {
    let source: LaunchSourceID
    let launches: [RocketLaunch]
    let fetchedAt: Date
}

protocol LaunchScheduleCaching: Sendable {
    func load() async throws -> [SavedLaunchSchedule]
    func save(_ schedule: SavedLaunchSchedule) async throws
}

/// Owns the on-disk representation; the Feature owns the live application state.
actor LaunchScheduleCache: LaunchScheduleCaching {
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    static func standard() -> LaunchScheduleCache {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LaunchScheduleCache(fileURL: directory.appendingPathComponent("LaunchSchedule.json"))
    }

    func load() throws -> [SavedLaunchSchedule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let schedules = try JSONDecoder().decode([SavedLaunchSchedule].self, from: Data(contentsOf: fileURL))
        guard Set(schedules.map(\.source)).count == schedules.count,
              schedules.allSatisfy({ schedule in schedule.launches.allSatisfy { $0.source == schedule.source } }) else {
            throw LaunchRepositoryError.invalidData
        }
        return schedules
    }

    func save(_ schedule: SavedLaunchSchedule) throws {
        try Task.checkCancellation()
        guard schedule.launches.allSatisfy({ $0.source == schedule.source }) else {
            throw LaunchRepositoryError.invalidData
        }
        var schedules = try load()
        schedules.removeAll { $0.source == schedule.source }
        schedules.append(schedule)
        let data = try JSONEncoder().encode(schedules)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
