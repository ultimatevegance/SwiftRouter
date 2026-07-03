@testable import SwiftRouter

@MainActor
final class SpyNavigationPerformer: NavigationPerforming {
    private(set) var performed: [(transition: ResolvedTransition, viewController: PlatformViewController)] = []
    private(set) var dismissed: [(viewController: PlatformViewController, animated: Bool)] = []
    private(set) var backCalls: [Bool] = []
    private(set) var switchTabCalls: [Int] = []
    var errorToThrow: Error?
    var backResult = true
    var switchTabResult = true

    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws {
        if let errorToThrow { throw errorToThrow }
        performed.append((transition, viewController))
    }

    func dismiss(_ viewController: PlatformViewController, animated: Bool) {
        dismissed.append((viewController, animated))
    }

    func back(animated: Bool) -> Bool {
        backCalls.append(animated)
        return backResult
    }

    func switchTab(index: Int) -> Bool {
        switchTabCalls.append(index)
        return switchTabResult
    }

    func removeAll() {
        performed.removeAll()
    }
}

/// Records the order guards ran in.
@MainActor
final class GuardLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

struct RecordingGuard: NavigationGuard {
    let name: String
    let log: GuardLog
    var decision: GuardDecision = .allow

    func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision {
        log.append(name)
        return decision
    }
}

/// Polls the main actor until `condition` is true (or ~1000 yields pass).
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1000 where !condition() {
        await Task.yield()
    }
}
