import Foundation

enum SourceStatusPresentation {
    static func canRetry(_ source: LaunchSourceSnapshot) -> Bool {
        source.phase != .loading && (source.nextRefreshAt.map { $0 <= Date() } ?? true)
    }
    static func message(_ source: LaunchSourceSnapshot) -> String {
        switch source.phase {
        case .idle: return String(localized: "Waiting for data")
        case .loading: return String(localized: "Updating…")
        case .loaded:
            if source.id == .spaceX, !source.launches.isEmpty,
               !source.launches.contains(where: { ($0.details.sortTime ?? .distantPast) >= Date() }) {
                return String(localized: "Downloaded schedule is outdated · Excluded from Next")
            }
            return source.fetchedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened)) · \(source.launches.count) launches" } ?? "Updated"
        case .failed:
            return source.launches.isEmpty ? String(localized: "Refresh failed · No data available") : String(localized: "Refresh failed · Showing previous data")
        }
    }
}
