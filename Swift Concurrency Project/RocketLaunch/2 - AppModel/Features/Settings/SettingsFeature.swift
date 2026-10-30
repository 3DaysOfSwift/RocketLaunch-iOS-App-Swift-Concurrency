import Foundation
import Observation

enum AppColourTheme: String, CaseIterable, Identifiable, Sendable {
    case system, midnight, ocean, forest, sunset, nebula, lunar, crimson
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "System"
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .nebula: "Nebula"
        case .lunar: "Lunar"
        case .crimson: "Crimson"
        }
    }
}

protocol ThemePersisting: Sendable {
    func load() async throws -> AppColourTheme
    func save(_ theme: AppColourTheme) async throws
}

actor ThemePersistence: ThemePersisting {
    enum Storage: Sendable { case memory, standard, file(URL, legacySuite: String) }
    private let storage: Storage
    private var memoryTheme: AppColourTheme = .system
    private static let legacyKey = "rocketlaunch.colourTheme"
    private static let fileCreatedKey = "rocketlaunch.colourTheme.fileCreated.v1"

    init(storage: Storage) { self.storage = storage }

    private func fileAndDefaults() throws -> (URL, UserDefaults) {
        switch storage {
        case .memory: throw CocoaError(.fileNoSuchFile)
        case .standard:
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return (directory.appendingPathComponent("RocketLaunch", isDirectory: true).appendingPathComponent("theme.txt"), .standard)
        case .file(let url, let suite):
            guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileReadUnknown) }
            return (url, defaults)
        }
    }

    func load() throws -> AppColourTheme {
        if case .memory = storage { return memoryTheme }
        let (url, defaults) = try fileAndDefaults()
        if FileManager.default.fileExists(atPath: url.path) {
            let raw = try String(contentsOf: url, encoding: .utf8)
            guard let theme = AppColourTheme(rawValue: raw) else { throw CocoaError(.fileReadCorruptFile) }
            defaults.set(true, forKey: Self.fileCreatedKey)
            return theme
        }
        if defaults.bool(forKey: Self.fileCreatedKey) { throw CocoaError(.fileNoSuchFile) }
        if let value = defaults.object(forKey: Self.legacyKey) {
            guard let raw = value as? String else { throw CocoaError(.fileReadCorruptFile) }
            guard let theme = AppColourTheme(rawValue: raw) else { throw CocoaError(.fileReadCorruptFile) }
            try write(theme, to: url)
            defaults.set(true, forKey: Self.fileCreatedKey)
            return theme
        }
        return .system
    }

    private func write(_ theme: AppColourTheme, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(theme.rawValue.utf8).write(to: url, options: .atomic)
    }

    func save(_ theme: AppColourTheme) throws {
        if case .memory = storage { memoryTheme = theme; return }
        let (url, defaults) = try fileAndDefaults()
        try write(theme, to: url)
        defaults.set(true, forKey: Self.fileCreatedKey)
    }
}

@MainActor
@Observable
final class SettingsFeature {
    private(set) var selected: AppColourTheme = .system
    private(set) var storageError: String?
    var canRetryLoading: Bool { !loaded }
    @ObservationIgnored private let persistence: any ThemePersisting
    @ObservationIgnored private let privacyPolicyLoader: any PrivacyPolicyLoading
    @ObservationIgnored private var loadTask: Task<AppColourTheme, any Error>?
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(persistence: any ThemePersisting = ThemePersistence(storage: .memory),
         privacyPolicyLoader: any PrivacyPolicyLoading = BundledPrivacyPolicyLoader()) {
        self.persistence = persistence
        self.privacyPolicyLoader = privacyPolicyLoader
    }

    let spaceXURL = URL(string: "https://github.com/r-spacex/SpaceX-API")!
    let launchLibraryURL = URL(string: "https://thespacedevs.com/llapi")!
    let rocketLaunchURL = URL(string: "https://www.rocketlaunch.live")!

    func loadPrivacyPolicy() async throws -> String { try await privacyPolicyLoader.load() }

    func loadIfNeeded() async {
        guard !loaded else { return }
        let task: Task<AppColourTheme, any Error>
        let id: UUID
        if let existing = loadTask, let existingID = loadID { task = existing; id = existingID }
        else {
            let persistence = persistence
            id = UUID()
            loadID = id
            task = Task { try await persistence.load() }
            loadTask = task
        }
        let result = await task.result
        guard !loaded, loadID == id else { return }
        loadTask = nil
        loadID = nil
        switch result {
        case .success(let theme):
            selected = theme
            loaded = true
            storageError = nil
        case .failure:
            storageError = "Your saved theme could not be loaded. Please try again."
        }
    }

    private enum Change { case set(AppColourTheme), next }

    @discardableResult
    private func enqueue(_ change: Change) -> Task<Void, Never> {
        let previous = writeTask
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await self.loadIfNeeded()
            guard self.loaded else { return }
            let theme: AppColourTheme
            switch change {
            case .set(let choice): theme = choice
            case .next:
                let themes = AppColourTheme.allCases
                let index = themes.firstIndex(of: self.selected) ?? 0
                theme = themes[(index + 1) % themes.count]
            }
            do {
                try await self.persistence.save(theme)
                self.selected = theme
                self.storageError = nil
            } catch {
                self.storageError = "The theme could not be saved. Please choose it again."
            }
        }
        writeTask = task
        return task
    }

    @discardableResult func select(_ theme: AppColourTheme) -> Task<Void, Never> { enqueue(.set(theme)) }
    @discardableResult func selectNextTheme() -> Task<Void, Never> { enqueue(.next) }
}
