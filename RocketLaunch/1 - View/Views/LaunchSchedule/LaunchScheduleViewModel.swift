import Foundation
import Observation

@MainActor
@Observable
final class LaunchScheduleViewModel {
    @ObservationIgnored private let feature: any LaunchScheduleFeatureAPI
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?

    init(feature: any LaunchScheduleFeatureAPI = AppModel.shared.launchSchedule) { self.feature = feature }

    var launchName: String { feature.state.launch?.name ?? String(localized: "None") }
    var mission: String { feature.state.launch?.primaryMissionDescription ?? String(localized: "None") }
    var launchTitle: String {
        guard let name = feature.state.launch?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.uppercased() != "TBD" else { return String(localized: "Mission to be announced") }
        return name
    }
    var missionSummary: String {
        guard let description = feature.state.launch?.details.missionDescription ?? feature.state.launch?.primaryMissionDescription,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Mission details haven’t been published yet. Check back closer to launch.")
        }
        return description
    }
    var provider: String { known(feature.state.launch?.details.provider) }
    var vehicle: String { known(feature.state.launch?.details.vehicle) }
    var country: String { known(feature.state.launch?.details.country) }
    var site: String { known(feature.state.launch?.details.site) }
    var launchTime: String {
        guard let details = feature.state.launch?.details else { return String(localized: "To be announced") }
        if let date = details.plannedTime {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return known(details.estimatedDateLabel)
    }
    var timingNote: String {
        guard let date = feature.state.launch?.details.plannedTime else {
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
    func loadIfNeeded() {
        guard refreshTask == nil, case .idle = feature.state else { return }
        requestRefresh()
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
    func requestRefresh() {
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

    func cancelRefresh() {
        refreshID = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit { refreshTask?.cancel() }
}
