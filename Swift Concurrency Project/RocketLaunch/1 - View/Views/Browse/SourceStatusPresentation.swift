import Foundation

enum SourceStatusPresentation {
    static func canRetry(_ source: LaunchSourceSnapshot, at date: Date = .now) -> Bool {
        source.canRefresh(at: date)
    }
    static func retryTime(_ date: Date) -> String {
        "Refresh available after \(date.formatted(date: .omitted, time: .shortened))"
    }
    static func cooldown(_ deadline: Date, at date: Date) -> String {
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    static func refreshInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return String(localized: "No refresh cooldown") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        guard let duration = formatter.string(from: interval) else { return String(localized: "Refresh cooldown applies") }
        return "Refresh cooldown: \(duration)"
    }
    static func message(_ source: LaunchSourceSnapshot, at date: Date = .now) -> String {
        switch source.phase {
        case .idle: return String(localized: "Waiting for data")
        case .loading: return String(localized: "Updating…")
        case .loaded:
            if source.isOutdated(at: date) {
                return String(localized: "Downloaded schedule is outdated · Excluded from Next")
            }
            return source.fetchedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened)) · \(source.launches.count) launches" } ?? "Updated"
        case .failed:
            if source.failure == .storage {
                return String(localized: "Couldn’t save the downloaded schedule · Try again")
            }
            guard !source.launches.isEmpty else { return String(localized: "Refresh failed · No data available") }
            guard let fetchedAt = source.fetchedAt else { return String(localized: "Refresh failed · Showing previous data") }
            return "Refresh failed · Showing schedule saved \(fetchedAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}
