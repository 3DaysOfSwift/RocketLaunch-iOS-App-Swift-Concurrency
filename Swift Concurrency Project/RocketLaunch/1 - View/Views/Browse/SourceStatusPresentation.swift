import Foundation

enum SourceStatusPresentation {
    static func canRetry(_ source: LaunchSourceSnapshot, at date: Date = .now) -> Bool {
        source.canRefresh(at: date)
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
            return source.launches.isEmpty ? String(localized: "Refresh failed · No data available") : String(localized: "Refresh failed · Showing previous data")
        }
    }
}
