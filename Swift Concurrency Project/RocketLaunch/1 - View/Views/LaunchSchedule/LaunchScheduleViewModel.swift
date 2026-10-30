import Foundation
import Observation

@MainActor
@Observable
final class LaunchScheduleViewModel {
    var showingLaunch = false
    private(set) var selectedLaunch: RocketLaunch?
    func showLaunch(_ launch: RocketLaunch) {
        selectedLaunch = launch
        showingLaunch = true
    }

    @ObservationIgnored private let feature: LaunchScheduleFeature
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var sourceTasks: [LaunchSourceID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sourceRequestIDs: [LaunchSourceID: UUID] = [:]

    @ObservationIgnored private let settingsFeature: SettingsFeature

    init(feature: LaunchScheduleFeature = AppModel.shared.launchScheduleFeature,
         settingsFeature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.feature = feature
        self.settingsFeature = settingsFeature
    }

    func selectNextTheme() { settingsFeature.selectNextTheme() }

    var snapshot: LaunchScheduleSnapshot { feature.snapshot }
    var upcomingLaunches: [RocketLaunch] { snapshot.upcomingLaunches }

    var launchName: String { snapshot.state.launch?.name ?? String(localized: "None") }
    var mission: String { snapshot.state.launch?.primaryMissionDescription ?? String(localized: "None") }
    private var detail: LaunchPresentation { .init(launch: snapshot.state.launch) }
    var launchTitle: String { detail.launchTitle }
    var missionSummary: String { detail.missionSummary }
    var provider: String { detail.provider }
    var vehicle: String { detail.vehicle }
    var country: String { detail.country }
    var site: String { detail.site }
    var launchTime: String { detail.launchTime }
    var timingNote: String { detail.timingNote }
    /// Only presentation ticks every second; the feature retains ownership of launch selection.
    func countdown(at date: Date) -> CountdownPresentation {
        switch currentLaunch?.details.countdown(at: date) ?? .timeUnconfirmed {
        case .remaining(let interval):
            // Round up so the last fraction of a second never reads zero before the deadline.
            let seconds = Int(interval.rounded(.up))
            let days = seconds / 86_400
            let clock = String(format: "%02d:%02d:%02d", (seconds / 3_600) % 24,
                               (seconds / 60) % 60, seconds % 60)
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour, .minute, .second]
            formatter.unitsStyle = .full
            let spokenTime = formatter.string(from: TimeInterval(seconds)) ?? clock
            let dayLabel = days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
            return CountdownPresentation(clock: clock,
                days: days > 0 ? dayLabel : nil,
                status: String(localized: "Until scheduled launch"),
                accessibilityText: String(localized: "\(spokenTime) until scheduled launch"))
        case .timeUnconfirmed:
            return CountdownPresentation(clock: nil, days: nil,
                status: String(localized: "Time unconfirmed"),
                accessibilityText: String(localized: "Exact launch time has not been announced"))
        case .awaitingUpdate:
            return CountdownPresentation(clock: nil, days: nil,
                status: String(localized: "Awaiting update"),
                accessibilityText: String(localized: "Scheduled time has passed. Awaiting an updated schedule."))
        }
    }

    var missionPreview: String? {
        let description = currentLaunch?.details.missionDescription ?? currentLaunch?.primaryMissionDescription
        guard let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return description
    }

    @discardableResult
    func loadIfNeeded() -> Task<Void, Never> { startRefresh(onlyIfNeeded: true) }
    var operators: [LaunchOperator] { snapshot.operators }
    var currentLaunch: RocketLaunch? { snapshot.state.launch }
    var updates: [LaunchUpdate] { snapshot.updates }
    var sources: [LaunchSourceSnapshot] { snapshot.sources }
    func updateNextLaunch() { feature.updateNextLaunch() }
    func launches(for operatorID: String) -> [RocketLaunch] {
        feature.launches(for: operatorID)
    }
    func relevantSources(for operatorID: String?) -> [LaunchSourceSnapshot] {
        feature.sources(for: operatorID)
    }
    func canRetry(_ source: LaunchSourceSnapshot) -> Bool { SourceStatusPresentation.canRetry(source) }
    func sourceMessage(_ source: LaunchSourceSnapshot) -> String { SourceStatusPresentation.message(source) }
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

    /// Directly awaitable for callers that already own their task lifetime.
    func refresh() async {
        await feature.refresh()
    }

    /// The screen owns replaceable work through its ViewModel, never through View state.
    @discardableResult
    func requestRefresh(source: LaunchSourceID? = nil) -> Task<Void, Never> {
        if let source {
            if let active = refreshTask ?? sourceTasks[source] { return active }
            let id = UUID(); sourceRequestIDs[source] = id
            let feature = feature
            let task = Task { [weak self] in
                await feature.refresh(source: source)
                guard self?.sourceRequestIDs[source] == id else { return }
                self?.sourceTasks[source] = nil; self?.sourceRequestIDs[source] = nil
            }
            sourceTasks[source] = task
            return task
        }
        return startRefresh(onlyIfNeeded: false)
    }

    private func startRefresh(onlyIfNeeded: Bool) -> Task<Void, Never> {
        if let active = refreshTask { return active }
        let id = UUID()
        refreshID = id
        let feature = feature
        let task = Task { [weak self] in
            if onlyIfNeeded { await feature.loadIfNeeded() }
            else { await feature.refresh() }
            guard self?.refreshID == id else { return }
            self?.refreshTask = nil
            self?.refreshID = nil
        }
        refreshTask = task
        return task
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

/// Formats a launch snapshot for display; owns no Feature or interaction state.
@MainActor
struct LaunchPresentation {
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

/// Display values for the visor; carries no independent launch state or timer.
struct CountdownPresentation {
    let clock: String?
    let days: String?
    let status: String
    let accessibilityText: String
}
