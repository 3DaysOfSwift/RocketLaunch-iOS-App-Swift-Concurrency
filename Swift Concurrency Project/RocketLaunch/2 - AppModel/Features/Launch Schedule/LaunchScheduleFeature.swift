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
    @ObservationIgnored private var pendingReminderEffects: [String: ReminderEffect] = [:]
    @ObservationIgnored private var pendingReminderRemovals: [String: String] = [:]

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
        startReminderLoadingIfNeeded()
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
        let current = sources[index]
        sources[index] = LaunchSourceSnapshot(id: current.id, launches: current.launches, fetchedAt: current.fetchedAt,
            nextRefreshAt: now().addingTimeInterval(configuration.minimumRefreshInterval), phase: .loading)
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
            let current = sources[index]
            sources[index] = LaunchSourceSnapshot(id: current.id, launches: launches, fetchedAt: now(),
                nextRefreshAt: current.nextRefreshAt, phase: .loaded)
            rebuildOperators()
            // Cache and desired reminders change in one uninterrupted actor operation.
            if remindersLoaded { effects = reconcileReminders(with: launches) }
        case .failure(let error):
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                sources[index] = request.previous
            } else {
                let current = sources[index]
                sources[index] = LaunchSourceSnapshot(id: current.id, launches: current.launches, fetchedAt: current.fetchedAt,
                    nextRefreshAt: current.nextRefreshAt, phase: .failed(Self.failure(for: error)))
            }
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
        for effect in effects {
            var tracked = effect
            tracked.isAutomatic = true
            pendingReminderEffects[effect.desired.id] = tracked
        }
        let id = UUID()
        // Retain the model until these external effects settle and stale IDs are
        // cleaned up. Screen cancellation must not abandon committed reminder intent.
        let persistence = reminderPersistenceTask
        reminderEffectTasks[id] = Task {
            if let persistence, !(await persistence.value) {
                self.reminderEffectTasks[id] = nil
                return
            }
            for effect in effects where self.pendingReminderEffects[effect.desired.id]?.desired.notificationID == effect.desired.notificationID {
                self.pendingReminderEffects[effect.desired.id] = nil
            }
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
                let current = sources[index]
                sources[index] = LaunchSourceSnapshot(id: current.id, launches: current.launches, fetchedAt: current.fetchedAt,
                    nextRefreshAt: nil, phase: current.phase)
            }
        }
        upcomingLaunches = LaunchScheduleSnapshot.upcoming(from: sources.flatMap(\.launches), now: currentTime)
        let eligible = LaunchScheduleSnapshot.upcoming(
            from: sources.filter { if case .failed = $0.phase { return false }; return true }.flatMap(\.launches),
            now: currentTime)
        let future = eligible.compactMap { launch -> (launch: RocketLaunch, time: Date)? in
            guard let time = launch.details.plannedTime, time >= currentTime else { return nil }
            return (launch, time)
        }
        nextLaunch = future.min { $0.time < $1.time }?.launch
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
        operators = operators.map { current in
            let launches = (grouped[current.id] ?? []).sorted {
                let lhs = $0.details.sortTime ?? $0.details.plannedTime ?? .distantFuture
                let rhs = $1.details.sortTime ?? $1.details.plannedTime ?? .distantFuture
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
            return LaunchOperator(id: current.id, name: current.name, launches: launches,
                sourceIDs: current.sourceIDs.union(launches.map(\.source)))
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
    @ObservationIgnored private var reminderBootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var reminderLoadTask: Task<[LaunchReminder], any Error>?
    @ObservationIgnored private var reminderPersistenceTask: Task<Bool, Never>?
    @ObservationIgnored private var reminderLoadID: UUID?
    private(set) var reminderStorageError: String?
    private(set) var reminderWriteError: String?
    @ObservationIgnored private var remindersLoaded = false
    private(set) var reminders: [LaunchReminder] = []
    @ObservationIgnored private var proposedReminders: [LaunchReminder] = []
    @ObservationIgnored private var lastEnqueuedReminders: [LaunchReminder] = []
    @ObservationIgnored private var confirmedPredecessors: [String: String] = [:]
    @ObservationIgnored private var confirmedDeletions: [String: String] = [:]
    @ObservationIgnored private var deletionCleanupRecords: [String: LaunchReminder] = [:]

    func hasActiveReminder(for launchID: String) -> Bool {
        reminders.contains {
            $0.id == launchID && $0.status == .scheduled && $0.issue == nil && !$0.hasPassed(at: now())
        }
    }

    func reminderTimeHasPassed(_ reminder: LaunchReminder) -> Bool {
        reminder.hasPassed(at: now())
    }
    @ObservationIgnored private var userSaveCounts: [String: Int] = [:]
    private var reminderRevision: UInt64 = 0
    private var confirmedReminderRevision: UInt64 = 0
    @ObservationIgnored private var reminderObservers: [UUID: AsyncStream<RemindersSnapshot>.Continuation] = [:]

    var reminderSnapshot: RemindersSnapshot {
        get async {
            await loadRemindersIfNeeded()
            return currentReminderSnapshot
        }
    }
    private var currentReminderSnapshot: RemindersSnapshot {
        .init(revision: confirmedReminderRevision, reminders: reminders)
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
    private func startReminderLoadingIfNeeded() {
        guard !remindersLoaded, reminderBootstrapTask == nil else { return }
        reminderBootstrapTask = Task { [weak self] in
            await self?.loadRemindersIfNeeded()
            self?.reminderBootstrapTask = nil
        }
    }

    func loadRemindersIfNeeded() async {
        guard !remindersLoaded else { return }
        let task: Task<[LaunchReminder], any Error>
        let id: UUID
        if let pending = reminderLoadTask, let pendingID = reminderLoadID {
            task = pending
            id = pendingID
        } else {
            let persistence = reminderPersistence
            let notifications = notificationClient
            task = Task {
                let stored = try await persistence.load()
                let recovered = stored.filter { $0.status != .deletionPending }.map { reminder in
                    if reminder.status == .pending {
                        return reminder.replacing(status: .failed, issue: "Scheduling was interrupted. Set this reminder again.", obsoleteNotificationIDs: [])
                    }
                    return reminder.replacing(obsoleteNotificationIDs: [])
                }
                if recovered != stored {
                    // Cleanup is idempotent; a failed write leaves the identifiers available on the next retry.
                    for reminder in stored {
                        var ids = Set(reminder.obsoleteNotificationIDs)
                        if reminder.status == .pending || reminder.status == .deletionPending { ids.insert(reminder.notificationID) }
                        for id in ids { await notifications.cancel(id) }
                    }
                    try await persistence.save(recovered)
                }
                return recovered
            }
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
            proposedReminders = stored
            reminders = stored
            remindersLoaded = true
            reminderStorageError = nil
            reminderRevision += 1
            reminders = proposedReminders
            lastEnqueuedReminders = proposedReminders
            confirmedReminderRevision = reminderRevision
            let snapshot = currentReminderSnapshot
            for observer in reminderObservers.values { observer.yield(snapshot) }
            // A provider may have completed while reminder storage was loading.
            for source in sources where source.phase == .loaded {
                startReminderEffects(reconcileReminders(with: source.launches))
            }
        case .failure:
            reminderStorageError = "Saved reminders could not be loaded or recovered. Your stored data has been kept. Retry before changing reminders."
        }
    }
    @discardableResult
    private func persistReminders() -> Task<Bool, Never> {
        reminderRevision += 1
        let revision = reminderRevision
        let before = Dictionary(lastEnqueuedReminders.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let after = Dictionary(proposedReminders.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let changedIDs = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        lastEnqueuedReminders = proposedReminders
        let previous = reminderPersistenceTask
        let persistence = reminderPersistence
        // Rebase each operation on the last successful write so a failed
        // proposal cannot leak into a later, unrelated operation.
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return false }
            var candidate = self.reminders
            candidate.removeAll { changedIDs.contains($0.id) }
            for id in changedIDs {
                if var updated = after[id] {
                    if let old = self.reminders.first(where: { $0.id == id }), old.notificationID != updated.notificationID {
                        let obsolete = Set(updated.obsoleteNotificationIDs + old.obsoleteNotificationIDs + [old.notificationID])
                        updated = updated.replacing(obsoleteNotificationIDs: obsolete.sorted())
                    }
                    candidate.append(updated)
                }
            }
            candidate.sort { $0.fireDate < $1.fireDate }
            var cleanup = self.deletionCleanupRecords
            for id in changedIDs where after[id] == nil {
                if let old = self.reminders.first(where: { $0.id == id }) {
                    cleanup[old.notificationID] = old.replacing(status: .deletionPending)
                }
            }
            do {
                try await persistence.save(candidate + Array(cleanup.values))
                self.deletionCleanupRecords = cleanup
                for id in changedIDs {
                    if let old = self.reminders.first(where: { $0.id == id }),
                       let new = candidate.first(where: { $0.id == id }),
                       old.notificationID != new.notificationID {
                        self.confirmedPredecessors[new.notificationID] = old.notificationID
                    } else if let old = self.reminders.first(where: { $0.id == id }),
                              !candidate.contains(where: { $0.id == id }) {
                        self.confirmedDeletions[id] = old.notificationID
                    }
                }
                self.reminders = candidate
                self.confirmedReminderRevision = revision
                let value = RemindersSnapshot(revision: revision, reminders: candidate)
                for observer in self.reminderObservers.values { observer.yield(value) }
                if self.reminderRevision == revision && self.pendingReminderEffects.isEmpty && self.pendingReminderRemovals.isEmpty { self.reminderWriteError = nil }
                return true
            } catch {
                for id in changedIDs {
                    guard let effect = self.pendingReminderEffects[id],
                          after[id]?.notificationID == effect.desired.notificationID,
                          self.proposedReminders.first(where: { $0.id == id })?.notificationID == effect.desired.notificationID else { continue }
                    self.proposedReminders.removeAll { $0.id == id }
                    if let confirmed = self.reminders.first(where: { $0.id == id }) {
                        self.proposedReminders.append(confirmed)
                    }
                    self.proposedReminders.sort { $0.fireDate < $1.fireDate }
                }
                self.reminderWriteError = "Reminder changes could not be saved. Retry the action."
                if self.reminderRevision == revision {
                    self.lastEnqueuedReminders = self.reminders
                }
                return false
            }
        }
        reminderPersistenceTask = task
        return task
    }

    private func finishDeletionCleanup(_ notificationID: String) async {
        let previous = reminderPersistenceTask
        let persistence = reminderPersistence
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self, let record = self.deletionCleanupRecords[notificationID] else { return true }
            for id in Set(record.obsoleteNotificationIDs + [notificationID]) {
                await self.notificationClient.cancel(id)
            }
            var remaining = self.deletionCleanupRecords
            remaining[notificationID] = nil
            do {
                try await persistence.save(self.reminders + Array(remaining.values))
                self.deletionCleanupRecords = remaining
                return true
            } catch {
                // The persisted record remains available for cleanup on the next launch.
                return false
            }
        }
        reminderPersistenceTask = task
        _ = await task.value
    }

    func retryReminderWrite() async {
        guard remindersLoaded, reminderWriteError != nil else { return }
        let removals = pendingReminderRemovals.filter { id, notificationID in
            reminders.first(where: { $0.id == id })?.notificationID == notificationID &&
            proposedReminders.first(where: { $0.id == id })?.notificationID == notificationID
        }
        for id in removals.keys { proposedReminders.removeAll { $0.id == id } }
        for effect in pendingReminderEffects.values {
            let current = proposedReminders.first(where: { $0.id == effect.desired.id })
            let confirmed = reminders.first(where: { $0.id == effect.desired.id })
            guard current?.notificationID == confirmed?.notificationID else { continue }
            proposedReminders.removeAll { $0.id == effect.desired.id }
            proposedReminders.append(effect.desired)
        }
        proposedReminders.sort { $0.fireDate < $1.fireDate }
        guard await persistReminders().value else {
            for (id, notificationID) in removals where !proposedReminders.contains(where: { $0.id == id }) {
                if let saved = reminders.first(where: { $0.id == id && $0.notificationID == notificationID }) {
                    proposedReminders.append(saved)
                }
            }
            proposedReminders.sort { $0.fireDate < $1.fireDate }
            return
        }
        for (id, notificationID) in removals where pendingReminderRemovals[id] == notificationID {
            guard !reminders.contains(where: { $0.id == id && $0.notificationID == notificationID }) else { continue }
            pendingReminderRemovals[id] = nil
            let cancelledID = confirmedDeletions.removeValue(forKey: id) ?? notificationID
            await notificationClient.cancel(cancelledID)
            await finishDeletionCleanup(cancelledID)
        }
        let effects = pendingReminderEffects.values.filter { effect in
            reminders.contains(where: { $0.notificationID == effect.desired.notificationID })
        }
        for effect in effects where pendingReminderEffects[effect.desired.id]?.desired.notificationID == effect.desired.notificationID {
            pendingReminderEffects[effect.desired.id] = nil
        }
        for effect in effects { _ = try? await deliverReminder(effect, askPermission: false) }
        if pendingReminderEffects.isEmpty, pendingReminderRemovals.isEmpty, reminders == proposedReminders { reminderWriteError = nil }
    }

    private struct ReminderEffect: Sendable {
        let desired: LaunchReminder
        let previousNotificationID: String?
        var mayRequestPermission = false
        var isAutomatic = false
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
        guard proposedReminders.count < 50 || proposedReminders.contains(where: { $0.id == launchID }) else { throw ReminderError.limit }
        let previousReminder = proposedReminders.first { $0.id == launchID }
        let effect = prepareReminder(launch: launch, minutesBefore: minutesBefore, fireDate: fireDate)
        // A new choice supersedes an earlier failed deletion, even if this write also fails.
        pendingReminderRemovals[launchID] = nil
        // Record the retry intent before the write can expose an error to the UI.
        pendingReminderEffects[launchID] = ReminderEffect(desired: effect.desired,
            previousNotificationID: effect.previousNotificationID, mayRequestPermission: true)
        let persistence = persistReminders()
        userSaveCounts[launchID, default: 0] += 1
        defer {
            let remaining = (userSaveCounts[launchID] ?? 1) - 1
            userSaveCounts[launchID] = remaining == 0 ? nil : remaining
        }
        guard await persistence.value else {
            if let index = proposedReminders.firstIndex(where: { $0.notificationID == effect.desired.notificationID }) {
                if let previousReminder { proposedReminders[index] = previousReminder }
                else { proposedReminders.remove(at: index) }
                proposedReminders.sort { $0.fireDate < $1.fireDate }
            }
            throw ReminderError.storageWriteFailed
        }
        if pendingReminderEffects[launchID]?.desired.notificationID == effect.desired.notificationID,
           proposedReminders.first(where: { $0.id == launchID })?.notificationID == effect.desired.notificationID {
            pendingReminderEffects[launchID] = nil
        }
        let outcome = try await deliverReminder(effect, askPermission: true)
        if pendingReminderEffects.isEmpty, pendingReminderRemovals.isEmpty, reminders == proposedReminders { reminderWriteError = nil }
        return outcome
    }

    /// Lookup, validation and desired-state replacement happen before any await.
    private func prepareReminder(launch: RocketLaunch, minutesBefore: Int, fireDate: Date) -> ReminderEffect {
        let old = proposedReminders.first(where: { $0.id == launch.id })
        let desired = LaunchReminder(launch: launch, notificationID: "rocketlaunch." + UUID().uuidString,
            minutesBefore: minutesBefore, fireDate: fireDate, issue: nil, status: .pending)
        proposedReminders.removeAll { $0.id == launch.id }
        proposedReminders.append(desired)
        proposedReminders.sort { $0.fireDate < $1.fireDate }
        return .init(desired: desired, previousNotificationID: old?.notificationID, mayRequestPermission: (userSaveCounts[launch.id] ?? 0) > 0)
    }

    private func reconcileReminders(with launches: [RocketLaunch]) -> [ReminderEffect] {
        var effects: [ReminderEffect] = []
        var changed = false
        var discardedStaleRetry = false
        for launch in launches {
            if let pending = pendingReminderEffects[launch.id], pending.isAutomatic,
               pending.desired.launch != launch,
               proposedReminders.first(where: { $0.id == launch.id })?.launch == launch {
                pendingReminderEffects[launch.id] = nil
                discardedStaleRetry = true
            }
            guard let old = proposedReminders.first(where: { $0.id == launch.id }), old.launch != launch else { continue }
            changed = true
            if old.launch.details.plannedTime == launch.details.plannedTime {
                if let index = proposedReminders.firstIndex(where: { $0.id == launch.id }) { proposedReminders[index] = proposedReminders[index].replacing(launch: launch) }
                continue
            }
            let fireDate = launch.details.plannedTime?.addingTimeInterval(-Double(old.minutesBefore) * 60)
            var effect = prepareReminder(launch: launch, minutesBefore: old.minutesBefore, fireDate: fireDate ?? old.fireDate)
            if fireDate.map({ $0 <= now() }) ?? true,
               let index = proposedReminders.firstIndex(where: { $0.id == launch.id }) {
                proposedReminders[index] = proposedReminders[index].replacing(status: .failed, issue: "Launch time changed. Open this launch to set a new reminder.")
                effect = .init(desired: proposedReminders[index], previousNotificationID: old.notificationID)
            }
            effects.append(effect)
        }
        if changed { persistReminders() }
        else if discardedStaleRetry, pendingReminderEffects.isEmpty, pendingReminderRemovals.isEmpty, proposedReminders == reminders {
            reminderWriteError = nil
        }
        return effects
    }

    private func deliverReminder(_ effect: ReminderEffect, askPermission: Bool) async throws -> ReminderSaveOutcome {
        let desired = effect.desired
        let oldID = confirmedPredecessors.removeValue(forKey: desired.notificationID) ?? effect.previousNotificationID
        let persisted = reminders.first(where: { $0.notificationID == desired.notificationID })
        var obsolete = Set(persisted?.obsoleteNotificationIDs ?? [])
        if let oldID { obsolete.insert(oldID) }
        for id in obsolete { await notificationClient.cancel(id) }
        guard proposedReminders.contains(where: { $0.notificationID == desired.notificationID }) else { return .superseded }
        guard desired.status == .pending else { return .superseded }
        do {
            try await notificationClient.schedule(id: desired.notificationID, title: desired.launch.name,
                date: desired.fireDate, askPermission: askPermission || effect.mayRequestPermission)
            guard let index = proposedReminders.firstIndex(where: { $0.notificationID == desired.notificationID }) else {
                await notificationClient.cancel(desired.notificationID)
                return .superseded
            }
            guard desired.fireDate > now() else { throw ReminderError.tooLate }
            proposedReminders[index] = proposedReminders[index].replacing(status: .scheduled, obsoleteNotificationIDs: [])
            let persistence = persistReminders()
            guard await persistence.value else { throw ReminderError.storageWriteFailed }
            return proposedReminders.contains(where: { $0.notificationID == desired.notificationID }) ? .saved : .superseded
        } catch {
            let current = proposedReminders.firstIndex(where: { $0.notificationID == desired.notificationID })
            if let index = current {
                proposedReminders[index] = proposedReminders[index].replacing(status: .failed, issue: "The notification could not be scheduled. Set this reminder again.")
                _ = await persistReminders().value
            }
            await notificationClient.cancel(desired.notificationID)
            guard proposedReminders.contains(where: { $0.notificationID == desired.notificationID }) else { return .superseded }
            throw error
        }
    }

    func removeReminder(_ launchID: String) async {
        // Reject abandoned intent before committing deletion. Once removed,
        // persistence and notification cleanup must both settle.
        guard !Task.isCancelled else { return }
        await loadRemindersIfNeeded()
        guard !Task.isCancelled, remindersLoaded else { return }
        guard let old = proposedReminders.first(where: { $0.id == launchID }) else { return }
        // A later removal supersedes any failed attempt to create or replace this reminder.
        pendingReminderEffects[launchID] = nil
        if let confirmed = reminders.first(where: { $0.id == launchID }) {
            pendingReminderRemovals[launchID] = confirmed.notificationID
        }
        proposedReminders.removeAll { $0.id == launchID }
        guard await persistReminders().value else {
            if !proposedReminders.contains(where: { $0.id == launchID }),
               let confirmed = reminders.first(where: { $0.id == launchID }) {
                pendingReminderRemovals[launchID] = confirmed.notificationID
                proposedReminders.append(confirmed)
                proposedReminders.sort { $0.fireDate < $1.fireDate }
            }
            return
        }
        if !proposedReminders.contains(where: { $0.id == launchID }) {
            pendingReminderRemovals[launchID] = nil
            pendingReminderEffects[launchID] = nil
            if pendingReminderEffects.isEmpty, pendingReminderRemovals.isEmpty, proposedReminders == reminders {
                reminderWriteError = nil
            }
        }
        let confirmedID = confirmedDeletions.removeValue(forKey: launchID) ?? old.notificationID
        await notificationClient.cancel(confirmedID)
        await finishDeletionCleanup(confirmedID)
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
    let launches: [RocketLaunch]
    let fetchedAt: Date?
    let nextRefreshAt: Date?
    let phase: Phase

    init(id: LaunchSourceID, launches: [RocketLaunch] = [], fetchedAt: Date? = nil,
         nextRefreshAt: Date? = nil, phase: Phase = .idle) {
        self.id = id; self.launches = launches; self.fetchedAt = fetchedAt
        self.nextRefreshAt = nextRefreshAt; self.phase = phase
    }
    enum Phase: Equatable, Sendable { case idle, loading, loaded, failed(LaunchLoadFailure) }
}

struct LaunchOperator: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let launches: [RocketLaunch]
    let sourceIDs: Set<LaunchSourceID>

    init(id: String, name: String, launches: [RocketLaunch], sourceIDs: Set<LaunchSourceID> = []) {
        self.id = id; self.name = name; self.launches = launches; self.sourceIDs = sourceIDs
    }
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

