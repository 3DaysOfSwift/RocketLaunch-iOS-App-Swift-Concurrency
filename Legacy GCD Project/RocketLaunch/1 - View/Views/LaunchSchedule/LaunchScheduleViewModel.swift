import Foundation
import Observation

/// UI-owned object: every entry and delivery must execute on the main queue.
@Observable
final class LaunchScheduleViewModel {
    @ObservationIgnored private let feature: LaunchScheduleFeatureAPI
    @ObservationIgnored private var refreshToken: CancellationToken?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var sourceTokens: [LaunchSourceID: CancellationToken] = [:]
    @ObservationIgnored private var sourceIDs: [LaunchSourceID: UUID] = [:]
    @ObservationIgnored private var observation: CancellationToken?
    @ObservationIgnored private var clock: DispatchSourceTimer?
    private(set) var snapshot: LaunchScheduleSnapshot = .initial
    var upcomingLaunches: [RocketLaunch] { snapshot.upcomingLaunches }
    init(feature: LaunchScheduleFeatureAPI = AppModel.shared.launchSchedule) { self.feature = feature }
    func startObserving() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard observation == nil else { return }
        observation = feature.observe { [weak self] value in self?.apply(value) }
    }
    func stopObserving() {
        observation?.cancel(); observation = nil
        clock?.cancel(); clock = nil
    }
    func synchronize(completion: @escaping () -> Void = {}) {
        feature.getSnapshot { [weak self] value in self?.apply(value); completion() }
    }
    private func apply(_ value: LaunchScheduleSnapshot) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard value.revision >= snapshot.revision else { return }
        snapshot = value
    }
    func loadIfNeeded() { startObserving(); startRefresh(onlyIfNeeded: true) }
    func updateNextLaunch() { feature.updateNextLaunch() }
    func monitorTime() {
        guard clock == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 60, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.feature.updateNextLaunch() }
        clock = timer
        timer.resume()
    }
    var launchName: String { snapshot.state.launch?.name ?? String(localized: "None") }
    var mission: String { snapshot.state.launch?.primaryMissionDescription ?? String(localized: "None") }
    private var detail: LaunchDetailViewModel { .init(launch: snapshot.state.launch) }
    var launchTitle: String { detail.launchTitle }
    var missionSummary: String { detail.missionSummary }
    var provider: String { detail.provider }
    var vehicle: String { detail.vehicle }
    var country: String { detail.country }
    var site: String { detail.site }
    var launchTime: String { detail.launchTime }
    var timingNote: String { detail.timingNote }
    var operators: [LaunchOperator] { snapshot.operators }
    var currentLaunch: RocketLaunch? { snapshot.state.launch }
    var updates: [LaunchUpdate] { snapshot.updates }
    var sources: [LaunchSourceSnapshot] { snapshot.sources }
    func launches(for operatorID: String) -> [RocketLaunch] {
        snapshot.operators.first(where: { $0.id == operatorID })?.launches ?? []
    }
    func relevantSources(for operatorID: String?) -> [LaunchSourceSnapshot] {
        guard let operatorID else { return sources }
        let knownSources = snapshot.operators.first(where: { $0.id == operatorID })?.sourceIDs ?? []
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
    var hasLaunch: Bool { snapshot.state.launch != nil }
    var isLoading: Bool {
        if case .loading = snapshot.state { return true }
        return false
    }
    var isEmpty: Bool { snapshot.state == .empty }
    var errorMessage: String? {
        guard case .failed(let failure, _) = snapshot.state else { return nil }
        switch failure {
        case .offline: return String(localized: "You’re offline. Connect to the internet and try again.")
        case .timedOut: return String(localized: "The request timed out. Please try again.")
        case .server: return String(localized: "The launch service is unavailable. Please try again later.")
        case .invalidData, .invalidResponse: return String(localized: "The launch service returned an unexpected response. Please try again later.")
        case .network: return String(localized: "Couldn’t load launches. Please try again.")
        }
    }

    func requestRefresh(source: LaunchSourceID? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        startObserving()
        guard let source else { startRefresh(onlyIfNeeded: false); return }
        guard sourceTokens[source] == nil, refreshToken == nil else { return }
        let id = UUID(); sourceIDs[source] = id
        sourceTokens[source] = feature.refresh(source: source) { [weak self] in
            guard let self, self.sourceIDs[source] == id else { return }
            self.sourceTokens[source] = nil; self.sourceIDs[source] = nil
            self.synchronize()
        }
    }
    private func startRefresh(onlyIfNeeded: Bool) {
        guard refreshToken == nil else { return }
        let id = UUID(); refreshID = id
        let completed = { [weak self] in
            guard let self, self.refreshID == id else { return }
            self.refreshToken = nil; self.refreshID = nil
            self.synchronize()
        }
        refreshToken = onlyIfNeeded ? feature.loadIfNeeded(completion: completed) : feature.refresh(completion: completed)
    }
    func cancelRefresh() {
        sourceIDs.removeAll(); refreshID = nil
        sourceTokens.values.forEach { $0.cancel() }; sourceTokens.removeAll()
        refreshToken?.cancel(); refreshToken = nil
    }
    deinit {
        observation?.cancel(); clock?.cancel(); refreshToken?.cancel()
        sourceTokens.values.forEach { $0.cancel() }
    }
}

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
