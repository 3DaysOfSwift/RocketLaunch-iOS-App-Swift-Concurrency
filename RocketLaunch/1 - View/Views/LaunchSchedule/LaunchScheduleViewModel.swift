import Foundation
import Observation

@MainActor
@Observable
final class LaunchScheduleViewModel {
    @ObservationIgnored private let feature: any LaunchScheduleFeature
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?

    init(feature: any LaunchScheduleFeature = AppModel.shared.launchSchedule) { self.feature = feature }

    var launchName: String { feature.state.launch?.name ?? String(localized: "None") }
    var mission: String { feature.state.launch?.primaryMissionDescription ?? String(localized: "None") }
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
