import XCTest
@testable import RocketLaunch

@MainActor
final class PrivacyPolicyViewModelTests: XCTestCase {
    func testSuccessfulLoadIsReusedWithoutReadingAgain() async {
        let loader = PolicyFixture()
        let viewModel = PrivacyPolicyViewModel(loader: loader)
        await viewModel.load()
        await viewModel.load()
        XCTAssertEqual(viewModel.text, "Bundled policy")
        let reads = await loader.reads
        XCTAssertEqual(reads, 1)
    }

    func testFailureKeepsExistingMessageAndCanRetry() async {
        let loader = PolicyFixture(failFirst: true)
        let viewModel = PrivacyPolicyViewModel(loader: loader)
        await viewModel.load()
        XCTAssertEqual(viewModel.text, "The privacy policy could not be loaded. Please consult the project’s PRIVACY.md document.")
        await viewModel.load()
        XCTAssertEqual(viewModel.text, "Bundled policy")
    }

    func testCancelledCallerDoesNotPublishLatePolicyAndCanRetry() async {
        let started = expectation(description: "read started")
        let loader = HeldPolicyFixture(started: { started.fulfill() })
        let viewModel = PrivacyPolicyViewModel(loader: loader)
        let task = Task { await viewModel.load() }
        await waitFor([started])
        task.cancel()
        await loader.finish()
        await task.value
        XCTAssertEqual(viewModel.text, "")
        await viewModel.load()
        XCTAssertEqual(viewModel.text, "Current policy")
    }

    func testOlderReadCannotReplaceNewerPolicy() async {
        let started = expectation(description: "first read started")
        let loader = HeldPolicyFixture(started: { started.fulfill() })
        let viewModel = PrivacyPolicyViewModel(loader: loader)
        let olderRead = Task { await viewModel.load() }
        await waitFor([started])

        await viewModel.load()
        XCTAssertEqual(viewModel.text, "Current policy")
        await loader.finish()
        await olderRead.value
        XCTAssertEqual(viewModel.text, "Current policy")
    }

    func testBundledLoaderReadsPolicyFromApplicationBundle() async throws {
        let text = try await BundledPrivacyPolicyLoader().load()
        XCTAssertFalse(text.isEmpty)
    }

    func testMissingFileThrows() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await BundledPrivacyPolicyLoader(fileURL: url).load()
            XCTFail("Missing policy must report a loading failure")
        } catch { XCTAssertTrue(error is CocoaError) }
    }
}

private actor PolicyFixture: PrivacyPolicyLoading {
    private(set) var reads = 0
    let failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func load() throws -> String {
        XCTAssertFalse(Thread.isMainThread)
        reads += 1
        if failFirst && reads == 1 { throw CocoaError(.fileReadUnknown) }
        return "Bundled policy"
    }
}

private actor HeldPolicyFixture: PrivacyPolicyLoading {
    private let started: @Sendable () -> Void
    private var continuation: CheckedContinuation<String, Never>?
    private var reads = 0
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func load() async -> String {
        reads += 1
        if reads > 1 { return "Current policy" }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started()
        }
    }
    func finish() { continuation?.resume(returning: "Abandoned policy"); continuation = nil }
}
