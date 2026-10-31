import Foundation

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
    private let legacyURL: URL?

    init(fileURL: URL, legacyURL: URL? = nil) { self.fileURL = fileURL; self.legacyURL = legacyURL }

    static func standard() -> LaunchScheduleCache {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LaunchScheduleCache(fileURL: directory.appendingPathComponent("LaunchSchedule.dat"),
                                   legacyURL: directory.appendingPathComponent("LaunchSchedule.json"))
    }

    func load() throws -> [SavedLaunchSchedule] {
        guard let url = existingURL() else { return [] }
        let data = try Data(contentsOf: url)
        let schedules: [SavedLaunchSchedule]
        if url == legacyURL || data.first == UInt8(ascii: "[") {
            schedules = try JSONDecoder().decode([SavedLaunchSchedule].self, from: data)
        } else {
            schedules = try BinaryLaunchSchedules.decode(data)
        }
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
        } catch is DecodingError {
            try preserveUnreadableCache()
            existing = []
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

    private func existingURL() -> URL? {
        if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }
        if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) { return legacyURL }
        return nil
    }

    /// A downloaded schedule is replaceable, but retain a damaged file for recovery.
    private func preserveUnreadableCache() throws {
        guard let original = existingURL() else { throw LaunchRepositoryError.invalidData }
        let backup = original.deletingLastPathComponent()
            .appendingPathComponent("\(original.lastPathComponent).unreadable-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: original, to: backup)
    }
}

