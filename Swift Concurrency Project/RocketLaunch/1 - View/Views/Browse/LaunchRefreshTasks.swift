import Foundation

/// Retains one screen's refresh intents. The Feature owns shared provider work.
@MainActor
final class LaunchRefreshTasks {
    private enum Scope: Hashable { case all; case source(LaunchSourceID) }
    private let feature: LaunchScheduleFeature
    private var tasks: [Scope: Task<Void, Never>] = [:]
    private var identities: [Scope: UUID] = [:]
    init(feature: LaunchScheduleFeature) { self.feature = feature }

    @discardableResult
    func request(source: LaunchSourceID? = nil) -> Task<Void, Never> {
        let scope = source.map(Scope.source) ?? .all
        if let current = tasks[.all] ?? tasks[scope] { return current }
        let identity = UUID()
        identities[scope] = identity
        let feature = feature
        let task = Task { [weak self] in
            if let source { await feature.refresh(source: source) }
            else { await feature.refresh() }
            guard self?.identities[scope] == identity else { return }
            self?.tasks[scope] = nil
            self?.identities[scope] = nil
        }
        tasks[scope] = task
        return task
    }

    func cancel() {
        identities.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
    isolated deinit { tasks.values.forEach { $0.cancel() } }
}
