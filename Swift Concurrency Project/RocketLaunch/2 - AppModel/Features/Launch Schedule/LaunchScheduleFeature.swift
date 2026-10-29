import Foundation
import Observation

/// Owns observable application state. Network decoding and persistence use service actors.
@MainActor @Observable
final class LaunchScheduleFeature {
    private(set) var state: LaunchScheduleState = .idle
    private(set) var sources: [LaunchSourceSnapshot]
    private(set) var operators: [LaunchOperator] = []
    private(set) var nextLaunch: RocketLaunch?
    private(set) var updates: [LaunchUpdate] = []
    private let configurations: [LaunchSourceConfiguration]
    private let now: @Sendable () -> Date
    private let waitForScheduleTick: @Sendable () async throws -> Void
    @ObservationIgnored private var scheduleMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleMonitorID: UUID?
    @ObservationIgnored private var scheduleMonitorCallers: [UUID: CheckedContinuation<Void, Never>] = [:]
    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
        let previous: LaunchSourceSnapshot
        var waiters: [UUID: CheckedContinuation<Void, Never>]
    }
    @ObservationIgnored private var requests: [LaunchSourceID: Request] = [:]
    @ObservationIgnored private var reminderEffectTasks: [UUID: Task<Void, Never>] = [:]

    convenience init(repository: any LaunchRepository) {
        self.init(sources: [.init(id: .rocketLaunchLive, repository: repository)])
    }

    init(sources: [LaunchSourceConfiguration], now: @escaping @Sendable () -> Date = { Date() }, notificationClient: any LaunchNotificationClient = LocalLaunchNotifications(), reminderStorage: ReminderStorage = .memory, reminderPersistence: (any ReminderPersisting)? = nil, waitForScheduleTick: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(60)) }) {
        precondition(Set(sources.map(\.id)).count == sources.count)
        self.configurations = sources; self.now = now
        self.waitForScheduleTick = waitForScheduleTick
        self.notificationClient = notificationClient; self.reminderPersistence = reminderPersistence ?? ReminderPersistence(storage: reminderStorage)
        self.sources = sources.map { LaunchSourceSnapshot(id: $0.id) }
        self.lastPublished = .init(revision: 0, state: .idle, nextLaunch: nil, sources: self.sources, operators: [], upcomingLaunches: [], updates: [])
    }

    @ObservationIgnored private var lastPublished: LaunchScheduleSnapshot?
    @ObservationIgnored private var revision: UInt64 = 0
    private var upcomingLaunches: [RocketLaunch] = []
    @ObservationIgnored private var observers: [UUID: AsyncStream<LaunchScheduleSnapshot>.Continuation] = [:]
    var snapshot: LaunchScheduleSnapshot {
        .init(revision: revision, state: state, nextLaunch: nextLaunch, sources: sources, operators: operators,
              upcomingLaunches: upcomingLaunches, updates: updates)
    }
    func launches(for operatorID: String) -> [RocketLaunch] {
        operators.first(where: { $0.id == operatorID })?.launches ?? []
    }

    func sources(for operatorID: String?) -> [LaunchSourceSnapshot] {
        guard let operatorID else { return sources }
        let knownSources = operators.first(where: { $0.id == operatorID })?.sourceIDs ?? []
        return sources.filter {
            if $0.id == .spaceX { return operatorID == "spacex" }
            return $0.fetchedAt == nil || knownSources.contains($0.id)
        }
    }

    func launches(matching query: LaunchBrowseQuery) -> [RocketLaunch] {
        query.launches(in: upcomingLaunches)
    }

    func operators(matching query: LaunchBrowseQuery) -> [LaunchOperator] {
        query.operators(in: operators)
    }

    var launchCountries: [String] {
        LaunchBrowseQuery().countries(in: operators)
    }

    func snapshots() -> AsyncStream<LaunchScheduleSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LaunchScheduleSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        // Registration and initial delivery are one actor-isolated operation.
        continuation.yield(snapshot)
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish() {
        guard snapshot != lastPublished else { return }
        revision += 1
        let value = snapshot
        lastPublished = value
        for observer in observers.values { observer.yield(value) }
    }
    deinit {
        scheduleMonitorTask?.cancel()
        for caller in scheduleMonitorCallers.values { caller.resume() }
        for observer in observers.values { observer.finish() }
        for observer in reminderObservers.values { observer.finish() }
        for request in requests.values {
            request.task.cancel()
            for waiter in request.waiters.values { waiter.resume() }
        }
    }

    /// Join active initial work or request only providers with no settled result.
    func loadIfNeeded() async {
        let unfinished = sources.filter { $0.phase == .idle || $0.phase == .loading }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for source in unfinished { group.addTask { await self.refresh(source: source, onlyIfNeeded: true) } }
        }
    }

    /// Child callers share each provider's active request and publish independently.
    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for configuration in configurations {
                group.addTask { await self.refresh(source: configuration.id) }
            }
        }
    }

    func refresh(source: LaunchSourceID) async {
        await refresh(source: source, onlyIfNeeded: false)
    }

    private func refresh(source: LaunchSourceID, onlyIfNeeded: Bool) async {
        await loadRemindersIfNeeded()
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerRefresh(source: source, onlyIfNeeded: onlyIfNeeded, waiterID: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelRefresh(source: source, waiterID: waiterID) }
        }
    }

    private func registerRefresh(source: LaunchSourceID, onlyIfNeeded: Bool, waiterID: UUID, continuation: CheckedContinuation<Void, Never>) {
        guard !Task.isCancelled,
              let index = sources.firstIndex(where: { $0.id == source }),
              let configuration = configurations.first(where: { $0.id == source }) else { continuation.resume(); return }
        // Joining existing work does not make another HTTP request or bypass cooldown.
        if requests[source] != nil {
            requests[source]?.waiters[waiterID] = continuation
            return
        }
        // A child task may start after another caller has already loaded this source.
        // Recheck the initial-load policy here, without a suspension before registration.
        if onlyIfNeeded, sources[index].phase != .idle {
            continuation.resume()
            return
        }
        if let retryAt = sources[index].nextRefreshAt, now() < retryAt { continuation.resume(); return }
        let previous = sources[index]
        let id = UUID()
        sources[index].phase = .loading
        sources[index].nextRefreshAt = now().addingTimeInterval(configuration.minimumRefreshInterval)
        updateNextLaunch()
        let repository = configuration.repository
        let task = Task { [weak self] in
            let result: Result<[RocketLaunch], any Error>
            do {
                let launches = try await repository.fetchUpcomingLaunches()
                try Task.checkCancellation()
                result = .success(launches)
            } catch { result = .failure(error) }
            self?.completeRefresh(source: source, id: id, result: result)
        }
        requests[source] = Request(id: id, task: task, previous: previous, waiters: [waiterID: continuation])
    }

    private func cancelRefresh(source: LaunchSourceID, waiterID: UUID) {
        guard var request = requests[source], let waiter = request.waiters.removeValue(forKey: waiterID) else { return }
        if request.waiters.isEmpty {
            // Detach ownership now; a new screen need not wait for canceled transport.
            requests[source] = nil
            request.task.cancel()
            if let index = sources.firstIndex(where: { $0.id == source }) { sources[index] = request.previous }
            updateNextLaunch()
        } else { requests[source] = request }
        waiter.resume()
    }

    private func completeRefresh(source: LaunchSourceID, id: UUID, result: Result<[RocketLaunch], any Error>) {
        guard let request = requests[source], request.id == id,
              let index = sources.firstIndex(where: { $0.id == source }) else { return }
        var effects: [ReminderEffect] = []
        switch result {
        case .success(let launches):
            recordChanges(from: sources[index].launches, to: launches)
            sources[index].launches = launches
            sources[index].fetchedAt = now()
            sources[index].phase = .loaded
            rebuildOperators()
            // Cache and desired reminders change in one uninterrupted actor operation.
            effects = reconcileReminders(with: launches)
        case .failure(let error):
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                sources[index] = request.previous
            } else { sources[index].phase = .failed(Self.failure(for: error)) }
        }
        updateNextLaunch()
        // Download ownership ends with the atomic model commit. Notification delivery
        // has its own lifetime and cannot keep subsequent refreshes joined to old data.
        requests[source] = nil
        startReminderEffects(effects)
        for waiter in request.waiters.values { waiter.resume() }
    }

    private func startReminderEffects(_ effects: [ReminderEffect]) {
        guard !effects.isEmpty else { return }
        let id = UUID()
        // Retain the model until these external effects settle and stale IDs are
        // cleaned up. Screen cancellation must not abandon committed reminder intent.
        let persistence = reminderPersistenceTask
        reminderEffectTasks[id] = Task {
            await persistence?.value
            await withTaskGroup(of: Void.self) { group in
                for effect in effects {
                    group.addTask { _ = try? await self.deliverReminder(effect, askPermission: false) }
                }
            }
            self.reminderEffectTasks[id] = nil
        }
    }

    /// Foreground callers share one timer. Each awaits its own cancellation;
    /// the last departing caller stops monitoring without cancelling downloads.
    func monitorScheduleTime() async {
        let callerID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(); return }
                scheduleMonitorCallers[callerID] = continuation
                guard scheduleMonitorTask == nil else { return }
                let monitorID = UUID()
                scheduleMonitorID = monitorID
                updateNextLaunch()
                let waitForTick = waitForScheduleTick
                scheduleMonitorTask = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            try await waitForTick()
                            try Task.checkCancellation()
                            guard let self, self.scheduleMonitorID == monitorID else { return }
                            self.updateNextLaunch()
                        }
                    } catch {
                        // Cancellation is the normal end of the timer's lifetime.
                    }
                    self?.finishScheduleMonitor(monitorID)
                }
            }
        } onCancel: {
            Task { await self.removeScheduleMonitorCaller(callerID) }
        }
    }

    private func removeScheduleMonitorCaller(_ id: UUID) {
        guard let caller = scheduleMonitorCallers.removeValue(forKey: id) else { return }
        if scheduleMonitorCallers.isEmpty {
            scheduleMonitorID = nil
            scheduleMonitorTask?.cancel()
            scheduleMonitorTask = nil
        }
        caller.resume()
    }

    private func finishScheduleMonitor(_ id: UUID) {
        guard scheduleMonitorID == id else { return }
        scheduleMonitorID = nil
        scheduleMonitorTask = nil
        let callers = scheduleMonitorCallers.values
        scheduleMonitorCallers.removeAll()
        for caller in callers { caller.resume() }
    }

    func updateNextLaunch() {
        let currentTime = now()
        // Expiring a cooldown is a meaningful UI change, even when launches did not change.
        for index in sources.indices {
            if let deadline = sources[index].nextRefreshAt, deadline <= currentTime {
                sources[index].nextRefreshAt = nil
            }
        }
        upcomingLaunches = LaunchScheduleSnapshot.upcoming(from: sources.flatMap(\.launches), now: currentTime)
        let eligible = LaunchScheduleSnapshot.upcoming(
            from: sources.filter { if case .failed = $0.phase { return false }; return true }.flatMap(\.launches),
            now: currentTime)
        let future = eligible.filter { ($0.details.plannedTime ?? .distantPast) >= currentTime }
        nextLaunch = future.min { $0.details.plannedTime! < $1.details.plannedTime! }
            ?? eligible.first(where: { $0.details.plannedTime == nil })
        if let nextLaunch { state = sources.contains(where: { $0.phase == .loading }) ? .loading(previous: nextLaunch) : .loaded(nextLaunch) }
        else if sources.contains(where: { $0.phase == .loading }) { state = .loading(previous: state.launch) }
        else if let failure = sources.compactMap({ snapshot -> LaunchLoadFailure? in
            if case .failed(let failure) = snapshot.phase { return failure }; return nil
        }).first { state = .failed(failure, previous: state.launch) }
        else if sources.allSatisfy({ $0.phase == .idle }) { state = .idle }
        else { state = .empty }
        publish()
    }

    private func rebuildOperators() {
        let all = sources.flatMap(\.launches)
        let grouped = Dictionary(grouping: all) { LaunchOperator.key(for: $0.details.provider) }
        // Retain discovered operators for this session, even after an empty response.
        let existingIDs = Set(operators.map(\.id))
        for key in grouped.keys.sorted() where !existingIDs.contains(key) {
            let name = LaunchOperator.canonicalName(grouped[key]?.first?.details.provider)
            operators.append(LaunchOperator(id: key, name: name, launches: []))
        }
        for index in operators.indices {
            operators[index].sourceIDs.formUnion((grouped[operators[index].id] ?? []).map(\.source))
            operators[index].launches = (grouped[operators[index].id] ?? []).sorted {
                let lhs = $0.details.sortTime ?? $0.details.plannedTime ?? .distantFuture
                let rhs = $1.details.sortTime ?? $1.details.plannedTime ?? .distantFuture
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
        }
    }

    private func recordChanges(from old: [RocketLaunch], to new: [RocketLaunch]) {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for launch in new {
            guard let previous = oldByID[launch.id] else { continue }
            let timeChanged = previous.details.plannedTime != launch.details.plannedTime
                || previous.details.estimatedDateLabel != launch.details.estimatedDateLabel
            let missionChanged = previous.name != launch.name || previous.details.missionDescription != launch.details.missionDescription
                || previous.missions != launch.missions
            guard timeChanged || missionChanged else { continue }
            updates.insert(LaunchUpdate(id: UUID(), detectedAt: now(), previous: previous, launch: launch, timeChanged: timeChanged), at: 0)
        }
        updates = Array(updates.prefix(100))
    }

    private let notificationClient: any LaunchNotificationClient
    private let reminderPersistence: any ReminderPersisting
    @ObservationIgnored private var reminderLoadTask: Task<[LaunchReminder], any Error>?
    @ObservationIgnored private var reminderPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var reminderLoadID: UUID?
    private(set) var reminderStorageError: String?
    @ObservationIgnored private var remindersLoaded = false
    private(set) var reminders: [LaunchReminder] = []

    func hasActiveReminder(for launchID: String) -> Bool {
        reminders.contains {
            $0.id == launchID && $0.status == .scheduled && $0.issue == nil && $0.fireDate > now()
        }
    }
    @ObservationIgnored private var userSaveCounts: [String: Int] = [:]
    private var reminderRevision: UInt64 = 0
    @ObservationIgnored private var reminderObservers: [UUID: AsyncStream<RemindersSnapshot>.Continuation] = [:]

    var reminderSnapshot: RemindersSnapshot {
        get async {
            await loadRemindersIfNeeded()
            return currentReminderSnapshot
        }
    }
    private var currentReminderSnapshot: RemindersSnapshot {
        .init(revision: reminderRevision, reminders: reminders)
    }
    func reminderSnapshots() async -> AsyncStream<RemindersSnapshot> {
        await loadRemindersIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<RemindersSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        reminderObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeReminderObserver(id) } }
        continuation.yield(currentReminderSnapshot)
        return stream
    }
    private func removeReminderObserver(_ id: UUID) { reminderObservers[id] = nil }
    func loadRemindersIfNeeded() async {
        guard !remindersLoaded else { return }
        let task: Task<[LaunchReminder], any Error>
        let id: UUID
        if let pending = reminderLoadTask, let pendingID = reminderLoadID {
            task = pending
            id = pendingID
        } else {
            let persistence = reminderPersistence
            task = Task { try await persistence.load() }
            id = UUID()
            reminderLoadTask = task
            reminderLoadID = id
        }
        let result = await task.result
        // Only the current read may publish or clear its handle. Joining callers
        // must not restore old data or overwrite the result of a later retry.
        guard reminderLoadID == id else { return }
        reminderLoadTask = nil
        reminderLoadID = nil
        switch result {
        case .success(let stored):
            reminders = stored
            remindersLoaded = true
            reminderStorageError = nil
            for index in reminders.indices where reminders[index].status == .pending {
                reminders[index].status = .failed
                reminders[index].issue = "Scheduling was interrupted. Set this reminder again."
            }
            reminderRevision += 1
            let snapshot = currentReminderSnapshot
            for observer in reminderObservers.values { observer.yield(snapshot) }
        case .failure:
            reminderStorageError = "Saved reminders could not be read. Your stored data has been kept. Retry before changing reminders."
        }
    }
    @discardableResult
    private func persistReminders() -> Task<Void, Never> {
        reminderRevision += 1
        let value = currentReminderSnapshot
        let previous = reminderPersistenceTask
        let persistence = reminderPersistence
        // Queue immutable snapshots in mutation order. Actor message arrival alone
        // does not guarantee the order of tasks created by successive mutations.
        let task = Task {
            await previous?.value
            await persistence.save(value.reminders)
        }
        reminderPersistenceTask = task
        for observer in reminderObservers.values { observer.yield(value) }
        return task
    }

    private struct ReminderEffect: Sendable {
        let desired: LaunchReminder
        let previousNotificationID: String?
        var mayRequestPermission = false
    }

    @discardableResult
    func setReminder(for launchID: String, minutesBefore: Int = 15) async throws -> ReminderSaveOutcome {
        // Reject abandoned intent before changing desired state or external notifications.
        // Once admitted, delivery must settle honestly even if the caller cancels later.
        try Task.checkCancellation()
        await loadRemindersIfNeeded()
        try Task.checkCancellation()
        guard remindersLoaded else { throw ReminderError.storageUnavailable }
        guard let launch = sources.lazy.flatMap(\.launches).first(where: { $0.id == launchID }) else { throw ReminderError.launchUnavailable }
        guard [5, 15, 60].contains(minutesBefore) else { throw ReminderError.invalidLeadTime }
        guard let time = launch.details.plannedTime else { throw ReminderError.unknownTime }
        let fireDate = time.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > now() else { throw ReminderError.tooLate }
        guard reminders.count < 50 || reminders.contains(where: { $0.id == launchID }) else { throw ReminderError.limit }
        let effect = prepareReminder(launch: launch, minutesBefore: minutesBefore, fireDate: fireDate)
        let persistence = persistReminders()
        userSaveCounts[launchID, default: 0] += 1
        defer {
            let remaining = (userSaveCounts[launchID] ?? 1) - 1
            userSaveCounts[launchID] = remaining == 0 ? nil : remaining
        }
        await persistence.value
        return try await deliverReminder(effect, askPermission: true)
    }

    /// Lookup, validation and desired-state replacement happen before any await.
    private func prepareReminder(launch: RocketLaunch, minutesBefore: Int, fireDate: Date) -> ReminderEffect {
        let old = reminders.first(where: { $0.id == launch.id })
        let desired = LaunchReminder(launch: launch, notificationID: "rocketlaunch." + UUID().uuidString,
            minutesBefore: minutesBefore, fireDate: fireDate, issue: nil, status: .pending)
        reminders.removeAll { $0.id == launch.id }
        reminders.append(desired)
        reminders.sort { $0.fireDate < $1.fireDate }
        return .init(desired: desired, previousNotificationID: old?.notificationID, mayRequestPermission: (userSaveCounts[launch.id] ?? 0) > 0)
    }

    private func reconcileReminders(with launches: [RocketLaunch]) -> [ReminderEffect] {
        var effects: [ReminderEffect] = []
        var changed = false
        for launch in launches {
            guard let old = reminders.first(where: { $0.id == launch.id }), old.launch != launch else { continue }
            changed = true
            if old.launch.details.plannedTime == launch.details.plannedTime {
                if let index = reminders.firstIndex(where: { $0.id == launch.id }) { reminders[index].launch = launch }
                continue
            }
            let fireDate = launch.details.plannedTime?.addingTimeInterval(-Double(old.minutesBefore) * 60)
            var effect = prepareReminder(launch: launch, minutesBefore: old.minutesBefore, fireDate: fireDate ?? old.fireDate)
            if fireDate == nil || fireDate! <= now() {
                let index = reminders.firstIndex(where: { $0.id == launch.id })!
                reminders[index].status = .failed
                reminders[index].issue = "Launch time changed. Open this launch to set a new reminder."
                effect = .init(desired: reminders[index], previousNotificationID: old.notificationID)
            }
            effects.append(effect)
        }
        if changed { persistReminders() }
        return effects
    }

    private func deliverReminder(_ effect: ReminderEffect, askPermission: Bool) async throws -> ReminderSaveOutcome {
        let desired = effect.desired
        if let oldID = effect.previousNotificationID { await notificationClient.cancel(oldID) }
        guard reminders.contains(where: { $0.notificationID == desired.notificationID }) else { return .superseded }
        guard desired.status == .pending else { return .superseded }
        do {
            try await notificationClient.schedule(id: desired.notificationID, title: desired.launch.name,
                date: desired.fireDate, askPermission: askPermission || effect.mayRequestPermission)
            guard let index = reminders.firstIndex(where: { $0.notificationID == desired.notificationID }) else {
                await notificationClient.cancel(desired.notificationID)
                return .superseded
            }
            guard desired.fireDate > now() else { throw ReminderError.tooLate }
            reminders[index].status = .scheduled
            let persistence = persistReminders()
            await persistence.value
            return reminders.contains(where: { $0.notificationID == desired.notificationID }) ? .saved : .superseded
        } catch {
            let current = reminders.firstIndex(where: { $0.notificationID == desired.notificationID })
            if let index = current {
                reminders[index].status = .failed
                reminders[index].issue = "The notification could not be scheduled. Set this reminder again."
                await persistReminders().value
            }
            await notificationClient.cancel(desired.notificationID)
            guard reminders.contains(where: { $0.notificationID == desired.notificationID }) else { return .superseded }
            throw error
        }
    }

    func removeReminder(_ launchID: String) async {
        // Reject abandoned intent before committing deletion. Once removed,
        // persistence and notification cleanup must both settle.
        guard !Task.isCancelled else { return }
        await loadRemindersIfNeeded()
        guard !Task.isCancelled, remindersLoaded else { return }
        guard let old = reminders.first(where: { $0.id == launchID }) else { return }
        reminders.removeAll { $0.id == launchID }
        await persistReminders().value
        await notificationClient.cancel(old.notificationID)
    }

    private static func failure(for error: any Error) -> LaunchLoadFailure {
        if let error = error as? LaunchRepositoryError {
            switch error {
            case .invalidResponse: return .invalidResponse
            case .httpStatus(let status): return .server(statusCode: status)
            case .invalidData: return .invalidData
            }
        }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet: return .offline
        case .timedOut: return .timedOut
        default: return .network
        }
    }
}

enum LaunchLoadFailure: Equatable, Sendable {
    case offline, timedOut, invalidResponse, invalidData, network
    case server(statusCode: Int)
}

enum LaunchScheduleState: Equatable, Sendable {
    case idle
    case loading(previous: RocketLaunch?)
    case loaded(RocketLaunch)
    case empty
    case failed(LaunchLoadFailure, previous: RocketLaunch?)

    var launch: RocketLaunch? {
        switch self {
        case .loaded(let launch): launch
        case .loading(let previous), .failed(_, let previous): previous
        case .idle, .empty: nil
        }
    }
}

enum LaunchSourceID: String, Sendable, Codable, CaseIterable, Identifiable {
    case rocketLaunchLive, launchLibrary, spaceX
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rocketLaunchLive: "RocketLaunch.Live"
        case .launchLibrary: "Launch Library"
        case .spaceX: "SpaceX API"
        }
    }
}

struct LaunchSourceConfiguration: Sendable {
    let id: LaunchSourceID
    let repository: any LaunchRepository
    var minimumRefreshInterval: TimeInterval = 0
}

struct LaunchSourceSnapshot: Equatable, Sendable, Identifiable {
    let id: LaunchSourceID
    var launches: [RocketLaunch] = []
    var fetchedAt: Date?
    var nextRefreshAt: Date?
    var phase: Phase = .idle
    enum Phase: Equatable, Sendable { case idle, loading, loaded, failed(LaunchLoadFailure) }
}

struct LaunchOperator: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    var launches: [RocketLaunch]
    var sourceIDs: Set<LaunchSourceID> = []
    static func canonicalName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "", "tbd", "unknown operator": return "Unknown operator"
        case "china aerospace science and technology corporation", "casc": return "CASC"
        case "china aerospace science and industry corporation", "casic": return "CASIC"
        case "space exploration technologies", "spacex": return "SpaceX"
        case "united launch alliance", "ula": return "ULA"
        case "indian space research organization", "isro": return "ISRO"
        case "japan aerospace exploration agency", "jaxa": return "JAXA"
        default: return trimmed
        }
    }
    static func key(for name: String?) -> String {
        canonicalName(name).lowercased()
    }
}

struct LaunchUpdate: Identifiable, Equatable, Sendable {
    let id: UUID
    let detectedAt: Date
    let previous: RocketLaunch
    let launch: RocketLaunch
    let timeChanged: Bool
}

/// Immutable UI projection. The MainActor Feature retains authoritative mutable state.
struct LaunchScheduleSnapshot: Equatable, Sendable {
    let revision: UInt64
    let state: LaunchScheduleState
    let nextLaunch: RocketLaunch?
    let sources: [LaunchSourceSnapshot]
    let operators: [LaunchOperator]
    let upcomingLaunches: [RocketLaunch]
    let updates: [LaunchUpdate]
    static let initial = Self(revision: 0, state: .idle, nextLaunch: nil, sources: [], operators: [], upcomingLaunches: [], updates: [])

    // Shared policy, executed by the feature when its data or clock changes.
    static func upcoming(from launches: [RocketLaunch], now: Date) -> [RocketLaunch] {
        launches.filter { launch in
            launch.source == .spaceX ? (launch.details.sortTime ?? .distantPast) >= now
                : (launch.details.plannedTime ?? .distantFuture) >= now
        }.sorted {
            let lhs = $0.details.sortTime ?? $0.details.plannedTime ?? .distantFuture
            let rhs = $1.details.sortTime ?? $1.details.plannedTime ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }
}
