import Foundation

/// All deliveries are asynchronous on the main queue. State never leaves its serial queue mutably.
protocol LaunchScheduleFeatureAPI: AnyObject {
    func getSnapshot(_ completion: @escaping (LaunchScheduleSnapshot) -> Void)
    func observe(_ observer: @escaping (LaunchScheduleSnapshot) -> Void) -> CancellationToken
    @discardableResult func loadIfNeeded(completion: @escaping () -> Void) -> CancellationToken
    @discardableResult func refresh(completion: @escaping () -> Void) -> CancellationToken
    @discardableResult func refresh(source: LaunchSourceID, completion: @escaping () -> Void) -> CancellationToken
    func updateNextLaunch()
    func getReminderSnapshot(_ completion: @escaping (RemindersSnapshot) -> Void)
    func observeReminders(_ observer: @escaping (RemindersSnapshot) -> Void) -> CancellationToken
    func setReminder(for launchID: String, minutesBefore: Int, completion: @escaping (Result<ReminderSaveOutcome, Error>) -> Void)
    func removeReminder(_ launchID: String, completion: @escaping () -> Void)
}

/// Every mutable property below is confined to queue. Callbacks re-enter it before inspecting state.
final class LaunchScheduleFeature: LaunchScheduleFeatureAPI {
    private let queue = DispatchQueue(label: "rocketlaunch.feature", qos: .userInitiated)
    private var state: LaunchScheduleState = .idle
    private var sources: [LaunchSourceSnapshot]
    private var operators: [LaunchOperator] = []
    private var nextLaunch: RocketLaunch?
    private var updates: [LaunchUpdate] = []
    private let configurations: [LaunchSourceConfiguration]
    private let now: () -> Date
    private struct Request {
        let id: UUID
        let token: CancellationToken
        let previous: LaunchSourceSnapshot
        var waiters: [UUID: () -> Void]
    }
    private var requests: [LaunchSourceID: Request] = [:]
    private var lastPublished: LaunchScheduleSnapshot?
    private var revision: UInt64 = 0
    private var upcomingLaunches: [RocketLaunch] = []
    private var observers: [UUID: (LaunchScheduleSnapshot) -> Void] = [:]

    convenience init(repository: LaunchRepository) {
        self.init(sources: [.init(id: .rocketLaunchLive, repository: repository)])
    }
    init(sources: [LaunchSourceConfiguration], now: @escaping () -> Date = Date.init,
         notificationClient: LaunchNotificationClient = LocalLaunchNotifications(), reminderStorage: ReminderStorage = .memory) {
        precondition(Set(sources.map(\.id)).count == sources.count)
        self.configurations = sources; self.now = now
        self.notificationClient = notificationClient; self.reminderStorage = reminderStorage
        self.sources = sources.map { LaunchSourceSnapshot(id: $0.id) }
        lastPublished = .init(revision: 0, state: .idle, nextLaunch: nil, sources: self.sources, operators: [], upcomingLaunches: [], updates: [])
    }
    private var snapshot: LaunchScheduleSnapshot {
        dispatchPrecondition(condition: .onQueue(queue))
        return .init(revision: revision, state: state, nextLaunch: nextLaunch, sources: sources,
                     operators: operators, upcomingLaunches: upcomingLaunches, updates: updates)
    }
    func getSnapshot(_ completion: @escaping (LaunchScheduleSnapshot) -> Void) {
        queue.async { let value = self.snapshot; DispatchQueue.main.async { completion(value) } }
    }
    func observe(_ observer: @escaping (LaunchScheduleSnapshot) -> Void) -> CancellationToken {
        let id = UUID(), token = CancellationToken()
        queue.async {
            guard !token.isCancelled else { return }
            let deliver: (LaunchScheduleSnapshot) -> Void = { value in
                DispatchQueue.main.async { if !token.isCancelled { observer(value) } }
            }
            self.observers[id] = deliver
            deliver(self.snapshot)
        }
        token.onCancel { [weak self] in self?.queue.async { [weak self] in self?.observers[id] = nil } }
        return token
    }
    private func publish() {
        guard snapshot != lastPublished else { return }
        revision += 1
        let value = snapshot; lastPublished = value
        for observer in observers.values { observer(value) }
    }
    @discardableResult
    func loadIfNeeded(completion: @escaping () -> Void = {}) -> CancellationToken {
        refreshAll(onlyIfNeeded: true, completion: completion)
    }
    @discardableResult
    func refresh(completion: @escaping () -> Void = {}) -> CancellationToken {
        refreshAll(onlyIfNeeded: false, completion: completion)
    }
    private func refreshAll(onlyIfNeeded: Bool, completion: @escaping () -> Void) -> CancellationToken {
        let token = CancellationToken()
        queue.async {
            let ids = self.sources.filter { !onlyIfNeeded || $0.phase == .idle || $0.phase == .loading }.map(\.id)
            let group = DispatchGroup()
            for id in ids {
                group.enter()
                let child = self.refresh(source: id) { group.leave() }
                token.onCancel { child.cancel() }
            }
            // notify never blocks the queue. Each source still publishes as soon as it completes.
            group.notify(queue: .main, execute: completion)
        }
        return token
    }
    @discardableResult
    func refresh(source: LaunchSourceID, completion: @escaping () -> Void = {}) -> CancellationToken {
        let waiterID = UUID(), token = CancellationToken()
        queue.async {
            let finish = { DispatchQueue.main.async(execute: completion) }
            guard !token.isCancelled else { finish(); return }
            self.registerRefresh(source: source, waiterID: waiterID, completion: finish)
        }
        token.onCancel { [weak self] in
            self?.queue.async { [weak self] in self?.cancelRefresh(source: source, waiterID: waiterID) }
        }
        return token
    }
    private func registerRefresh(source: LaunchSourceID, waiterID: UUID, completion: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let index = sources.firstIndex(where: { $0.id == source }),
              let configuration = configurations.first(where: { $0.id == source }) else { completion(); return }
        if requests[source] != nil { requests[source]?.waiters[waiterID] = completion; return }
        if let deadline = sources[index].nextRefreshAt, now() < deadline { completion(); return }
        let previous = sources[index], id = UUID()
        sources[index].phase = .loading
        sources[index].nextRefreshAt = now().addingTimeInterval(configuration.minimumRefreshInterval)
        recomputeNextLaunch()
        let token = configuration.repository.fetchUpcomingLaunches { [weak self] result in
            // Even a synchronous repository callback cannot race request registration.
            self?.queue.async { [weak self] in self?.completeRefresh(source: source, id: id, result: result) }
        }
        requests[source] = .init(id: id, token: token, previous: previous, waiters: [waiterID: completion])
    }
    private func cancelRefresh(source: LaunchSourceID, waiterID: UUID) {
        guard var request = requests[source], let finish = request.waiters.removeValue(forKey: waiterID) else { return }
        if request.waiters.isEmpty {
            requests[source] = nil
            request.token.cancel()
            if let index = sources.firstIndex(where: { $0.id == source }) { sources[index] = request.previous }
            recomputeNextLaunch()
        } else { requests[source] = request }
        finish()
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
            // Cache and desired reminders change in one uninterrupted serial-queue operation.
            effects = reconcileReminders(with: launches)
        case .failure(let error):
            if (error as? URLError)?.code == .cancelled {
                sources[index] = request.previous
            } else { sources[index].phase = .failed(Self.failure(for: error)) }
        }
        recomputeNextLaunch()
        // Download ownership ends with the atomic model commit. Notification delivery
        // has its own lifetime and cannot keep subsequent refreshes joined to old data.
        requests[source] = nil
        startReminderEffects(effects)
        for waiter in request.waiters.values { waiter() }
    }

    private func startReminderEffects(_ effects: [ReminderEffect]) {
        // Callback chains retain committed intent until system delivery and obsolete-ID cleanup settle.
        for effect in effects { deliverReminder(effect, askPermission: false) { _ in } }
    }
    func updateNextLaunch() { queue.async { self.recomputeNextLaunch() } }
    /// Stored output is recalculated only on model events, never in a View getter.
    private func recomputeNextLaunch() {
        dispatchPrecondition(condition: .onQueue(queue))
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

    private let notificationClient: LaunchNotificationClient
    private let reminderStorage: ReminderStorage
    private var reminderDefaults: UserDefaults?
    private var remindersLoaded = false
    private var reminders: [LaunchReminder] = []
    private var userSaveCounts: [String: Int] = [:]
    private var reminderRevision: UInt64 = 0
    private var reminderObservers: [UUID: (RemindersSnapshot) -> Void] = [:]
    private var reminderSnapshot: RemindersSnapshot {
        dispatchPrecondition(condition: .onQueue(queue))
        loadRemindersIfNeeded()
        return .init(revision: reminderRevision, reminders: reminders)
    }
    func getReminderSnapshot(_ completion: @escaping (RemindersSnapshot) -> Void) {
        queue.async { let value = self.reminderSnapshot; DispatchQueue.main.async { completion(value) } }
    }
    func observeReminders(_ observer: @escaping (RemindersSnapshot) -> Void) -> CancellationToken {
        let id = UUID(), token = CancellationToken()
        queue.async {
            guard !token.isCancelled else { return }
            let deliver: (RemindersSnapshot) -> Void = { value in
                DispatchQueue.main.async { if !token.isCancelled { observer(value) } }
            }
            self.reminderObservers[id] = deliver
            deliver(self.reminderSnapshot)
        }
        token.onCancel { [weak self] in self?.queue.async { [weak self] in self?.reminderObservers[id] = nil } }
        return token
    }
    private func loadRemindersIfNeeded() {
        guard !remindersLoaded else { return }
        remindersLoaded = true
        switch reminderStorage {
        case .memory: reminderDefaults = nil
        case .standard: reminderDefaults = .standard
        case .suite(let name): reminderDefaults = UserDefaults(suiteName: name)
        }
        reminders = reminderDefaults?.data(forKey: "rocketlaunch.reminders.v1")
            .flatMap { try? JSONDecoder().decode([LaunchReminder].self, from: $0) } ?? []
        // An interrupted external operation is not evidence of successful delivery.
        for index in reminders.indices where reminders[index].status == .pending {
            reminders[index].status = .failed
            reminders[index].issue = "Scheduling was interrupted. Set this reminder again."
        }
    }
    private func persistReminders() {
        reminderRevision += 1
        let value = reminderSnapshot
        if let data = try? JSONEncoder().encode(reminders) { reminderDefaults?.set(data, forKey: "rocketlaunch.reminders.v1") }
        for observer in reminderObservers.values { observer(value) }
    }

    private struct ReminderEffect {
        let desired: LaunchReminder
        let previousNotificationID: String?
        var mayRequestPermission = false
    }

    func setReminder(for launchID: String, minutesBefore: Int = 15,
                     completion: @escaping (Result<ReminderSaveOutcome, Error>) -> Void) {
        queue.async {
            do {
                let effect = try self.validateAndPrepare(launchID: launchID, minutesBefore: minutesBefore)
                self.userSaveCounts[launchID, default: 0] += 1
                self.deliverReminder(effect, askPermission: true) { result in
                    let remaining = (self.userSaveCounts[launchID] ?? 1) - 1
                    self.userSaveCounts[launchID] = remaining == 0 ? nil : remaining
                    DispatchQueue.main.async { completion(result) }
                }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func validateAndPrepare(launchID: String, minutesBefore: Int) throws -> ReminderEffect {
        loadRemindersIfNeeded()
        guard let launch = sources.lazy.flatMap(\.launches).first(where: { $0.id == launchID }) else { throw ReminderError.launchUnavailable }
        guard [5, 15, 60].contains(minutesBefore) else { throw ReminderError.invalidLeadTime }
        guard let time = launch.details.plannedTime else { throw ReminderError.unknownTime }
        let fireDate = time.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > now() else { throw ReminderError.tooLate }
        guard reminders.count < 50 || reminders.contains(where: { $0.id == launchID }) else { throw ReminderError.limit }
        let effect = prepareReminder(launch: launch, minutesBefore: minutesBefore, fireDate: fireDate)
        persistReminders()
        return effect
    }
    /// Lookup, validation and desired-state replacement happen in one uninterrupted serial-queue operation.
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
        loadRemindersIfNeeded()
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

    /// Completion runs on the feature queue. Every system callback re-enters that queue.
    private func deliverReminder(_ effect: ReminderEffect, askPermission: Bool,
                                 completion: @escaping (Result<ReminderSaveOutcome, Error>) -> Void) {
        let desired = effect.desired
        let schedule = {
            guard self.reminders.contains(where: { $0.notificationID == desired.notificationID }),
                  desired.status == .pending else { completion(.success(.superseded)); return }
            self.notificationClient.schedule(id: desired.notificationID, title: desired.launch.name,
                date: desired.fireDate, askPermission: askPermission || effect.mayRequestPermission) { result in
                self.queue.async {
                    guard let index = self.reminders.firstIndex(where: { $0.notificationID == desired.notificationID }) else {
                        self.notificationClient.cancel(desired.notificationID) {
                            self.queue.async { completion(.success(.superseded)) }
                        }
                        return
                    }
                    let error: Error?
                    switch result {
                    case .success: error = desired.fireDate > self.now() ? nil : ReminderError.tooLate
                    case .failure(let failure): error = failure
                    }
                    if let error {
                        self.reminders[index].status = .failed
                        self.reminders[index].issue = "The notification could not be scheduled. Set this reminder again."
                        self.persistReminders()
                        self.notificationClient.cancel(desired.notificationID) {
                            self.queue.async {
                                let current = self.reminders.contains { $0.notificationID == desired.notificationID }
                                completion(current ? .failure(error) : .success(.superseded))
                            }
                        }
                    } else {
                        self.reminders[index].status = .scheduled
                        self.persistReminders()
                        completion(.success(.saved))
                    }
                }
            }
        }
        if let oldID = effect.previousNotificationID {
            notificationClient.cancel(oldID) { self.queue.async(execute: schedule) }
        } else { schedule() }
    }
    func removeReminder(_ launchID: String, completion: @escaping () -> Void = {}) {
        queue.async {
            self.loadRemindersIfNeeded()
            guard let old = self.reminders.first(where: { $0.id == launchID }) else {
                DispatchQueue.main.async(execute: completion); return
            }
            self.reminders.removeAll { $0.id == launchID }
            self.persistReminders()
            self.notificationClient.cancel(old.notificationID) { DispatchQueue.main.async(execute: completion) }
        }
    }
    deinit {
        for request in requests.values {
            request.token.cancel()
            for finish in request.waiters.values { finish() }
        }
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

enum LaunchLoadFailure: Equatable {
    case offline, timedOut, invalidResponse, invalidData, network
    case server(statusCode: Int)
}

enum LaunchScheduleState: Equatable {
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

enum LaunchSourceID: String, Codable, CaseIterable, Identifiable {
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

struct LaunchSourceConfiguration {
    let id: LaunchSourceID
    let repository: any LaunchRepository
    var minimumRefreshInterval: TimeInterval = 0
}

struct LaunchSourceSnapshot: Equatable, Identifiable {
    let id: LaunchSourceID
    var launches: [RocketLaunch] = []
    var fetchedAt: Date?
    var nextRefreshAt: Date?
    var phase: Phase = .idle
    enum Phase: Equatable { case idle, loading, loaded, failed(LaunchLoadFailure) }
}

struct LaunchOperator: Equatable, Identifiable {
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

struct LaunchUpdate: Identifiable, Equatable {
    let id: UUID
    let detectedAt: Date
    let previous: RocketLaunch
    let launch: RocketLaunch
    let timeChanged: Bool
}

/// Immutable UI projection. The feature queue retains authoritative mutable state.
struct LaunchScheduleSnapshot: Equatable {
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
