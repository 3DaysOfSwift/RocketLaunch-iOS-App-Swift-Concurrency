import Foundation

/// A provider's last successfully downloaded schedule and its original fetch time.
struct SavedLaunchSchedule: Equatable, Sendable {
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
    private let fileURL: URL?

    init(fileURL: URL?) { self.fileURL = fileURL }

    static func standard() -> LaunchScheduleCache {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return LaunchScheduleCache(fileURL: directory?.appendingPathComponent("LaunchSchedule.dat"))
    }

    func load() throws -> [SavedLaunchSchedule] {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let schedules = try BinaryLaunchSchedules.decode(Data(contentsOf: fileURL))
            guard Set(schedules.map(\.source)).count == schedules.count,
                  schedules.allSatisfy({ schedule in schedule.launches.allSatisfy { $0.source == schedule.source } }) else {
                throw LaunchRepositoryError.invalidData
            }
            return schedules
        } catch LaunchRepositoryError.invalidData {
            // Downloaded schedules are replaceable. A later successful write can
            // also replace the file if removing this invalid cache is not possible.
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }

    func save(_ schedule: SavedLaunchSchedule) throws {
        try Task.checkCancellation()
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        guard schedule.launches.allSatisfy({ $0.source == schedule.source }) else {
            throw LaunchRepositoryError.invalidData
        }
        let existing = try load()
        var schedules = existing
        schedules.removeAll { $0.source == schedule.source }
        schedules.append(schedule)
        let data = try BinaryLaunchSchedules.encode(schedules)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

}

