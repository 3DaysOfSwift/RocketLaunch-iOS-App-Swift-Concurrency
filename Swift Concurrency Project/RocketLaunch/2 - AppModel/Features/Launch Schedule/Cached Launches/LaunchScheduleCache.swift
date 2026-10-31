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
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    static func standard() -> LaunchScheduleCache {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LaunchScheduleCache(fileURL: directory.appendingPathComponent("LaunchSchedule.dat"))
    }

    func load() throws -> [SavedLaunchSchedule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let schedules = try BinaryLaunchSchedules.decode(Data(contentsOf: fileURL))
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
        let existing: [SavedLaunchSchedule]
        do {
            existing = try load()
        } catch LaunchRepositoryError.invalidData {
            try preserveUnreadableCache()
            existing = []
        }
        var schedules = existing
        schedules.removeAll { $0.source == schedule.source }
        schedules.append(schedule)
        let data = try BinaryLaunchSchedules.encode(schedules)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// A downloaded schedule is replaceable, but retain a damaged file for recovery.
    private func preserveUnreadableCache() throws {
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).unreadable-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fileURL, to: backup)
    }
}

