import Foundation
import Observation

@MainActor
@Observable
final class LaunchScheduleViewModel {
    @ObservationIgnored private let feature: any LaunchScheduleFeatureAPI
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var sourceTasks: [LaunchSourceID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sourceRequestIDs: [LaunchSourceID: UUID] = [:]

    init(feature: any LaunchScheduleFeatureAPI = AppModel.shared.launchSchedule) { self.feature = feature }

    var launchName: String { feature.state.launch?.name ?? String(localized: "None") }
    var mission: String { feature.state.launch?.primaryMissionDescription ?? String(localized: "None") }
    private var detail: LaunchDetailViewModel { .init(launch: feature.state.launch) }
    var launchTitle: String { detail.launchTitle }
    var missionSummary: String { detail.missionSummary }
    var provider: String { detail.provider }
    var vehicle: String { detail.vehicle }
    var country: String { detail.country }
    var site: String { detail.site }
    var launchTime: String { detail.launchTime }
    var timingNote: String { detail.timingNote }
    func loadIfNeeded() {
        guard refreshTask == nil, case .idle = feature.state else { return }
        requestRefresh()
    }
    var operators: [LaunchOperator] { feature.operators }
    func tabTitle(for launchOperator: LaunchOperator) -> String {
        let name = launchOperator.name
        return name.count > 12 ? String(name.prefix(10)) + "…" : name
    }
    var currentLaunch: RocketLaunch? { feature.state.launch }
    var updates: [LaunchUpdate] { feature.updates }
    var sources: [LaunchSourceSnapshot] { feature.sources }
    func updateNextLaunch() { feature.updateNextLaunch() }
    func launches(for operatorID: String) -> [RocketLaunch] {
        feature.operators.first(where: { $0.id == operatorID })?.launches ?? []
    }
    func relevantSources(for operatorID: String?) -> [LaunchSourceSnapshot] {
        guard let operatorID else { return sources }
        let knownSources = feature.operators.first(where: { $0.id == operatorID })?.sourceIDs ?? []
        return sources.filter {
            if $0.id == .spaceX { return operatorID == "spacex" }
            return $0.fetchedAt == nil || knownSources.contains($0.id)
        }
    }
    func canRetry(_ source: LaunchSourceSnapshot) -> Bool {
        source.phase != .loading && (source.nextRefreshAt.map { $0 <= Date() } ?? true)
    }
    func sourceMessage(_ source: LaunchSourceSnapshot) -> String {
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
    var hasLaunch: Bool { feature.state.launch != nil }
    var isLoading: Bool {
        if case .loading = feature.state { return true }
        return false
    }
    var isEmpty: Bool { feature.state == .empty }
    var errorMessage: String? {
        guard case .failed(let failure, _) = feature.state else { return nil }
        switch failure {
        case .offline: return String(localized: "You’re offline. Connect to the internet and try again.")
        case .timedOut: return String(localized: "The request timed out. Please try again.")
        case .server: return String(localized: "The launch service is unavailable. Please try again later.")
        case .invalidData, .invalidResponse: return String(localized: "The launch service returned an unexpected response. Please try again later.")
        case .network: return String(localized: "Couldn’t load launches. Please try again.")
        }
    }

    /// Directly awaitable for callers that already own their task lifetime.
    func refresh() async { await feature.refresh() }

    /// The screen owns replaceable work through its ViewModel, never through View state.
    func requestRefresh(source: LaunchSourceID? = nil) {
        if let source {
            sourceTasks[source]?.cancel()
            let id = UUID(); sourceRequestIDs[source] = id
            let feature = feature
            sourceTasks[source] = Task { [weak self] in
                await feature.refresh(source: source)
                guard self?.sourceRequestIDs[source] == id else { return }
                self?.sourceTasks[source] = nil; self?.sourceRequestIDs[source] = nil
            }
            return
        }
        refreshTask?.cancel()
        let id = UUID()
        refreshID = id
        let feature = feature
        refreshTask = Task { [weak self] in
            await feature.refresh()
            guard self?.refreshID == id else { return }
            self?.refreshTask = nil
            self?.refreshID = nil
        }
    }

    func monitorTime() async {
        while !Task.isCancelled {
            feature.updateNextLaunch()
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }

    func cancelRefresh() {
        sourceTasks.values.forEach { $0.cancel() }
        sourceTasks.removeAll(); sourceRequestIDs.removeAll()
        refreshID = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit { refreshTask?.cancel(); sourceTasks.values.forEach { $0.cancel() } }
}

@MainActor
struct LaunchDetailViewModel {
    let launch: RocketLaunch?
    var launchTitle: String {
        guard let name = launch?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.uppercased() != "TBD" else { return String(localized: "Mission to be announced") }
        return name
    }
    var missionSummary: String {
        guard let description = launch?.details.missionDescription ?? launch?.primaryMissionDescription,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Mission details haven’t been published yet. Check back closer to launch.")
        }
        return description
    }
    var provider: String { known(launch?.details.provider) }
    var vehicle: String { known(launch?.details.vehicle) }
    var country: String { known(launch?.details.country) }
    var site: String { known(launch?.details.site) }
    var launchTime: String {
        guard let details = launch?.details else { return String(localized: "To be announced") }
        if let date = details.plannedTime {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return known(details.estimatedDateLabel)
    }
    var timingNote: String {
        guard let date = launch?.details.plannedTime else {
            return String(localized: "Estimated date · Exact time not announced")
        }
        if date < Date() { return String(localized: "Scheduled time has passed · Awaiting an updated schedule") }
        return String(localized: "Your local time · Schedule may change")
    }
    private func known(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.uppercased() != "TBD" else { return String(localized: "To be announced") }
        return value
    }
}
