#if canImport(UIKit)
import ObjectiveC
import UIKit
#endif

/// One-shot channel connecting a presented screen's `finish` back to the
/// `present(forResult:)` continuation. Always completes: `finish` resolves
/// the value; the dealloc sentinel resolves nil.
@MainActor final class ResultChannel {
    private var continuation: CheckedContinuation<(any Sendable)?, Never>?
    private var pendingValue: (any Sendable)??
    private var isResolved = false
    /// Dismissal hook installed by the router after presentation.
    var onResolve: (@MainActor () -> Void)?

    func attach(_ continuation: CheckedContinuation<(any Sendable)?, Never>) {
        if let pendingValue {
            continuation.resume(returning: pendingValue)
            return
        }
        self.continuation = continuation
    }

    func resolve(_ value: (any Sendable)?) {
        guard !isResolved else { return }
        isResolved = true
        if let continuation {
            continuation.resume(returning: value)
            self.continuation = nil
        } else {
            pendingValue = value
        }
        onResolve?()
        onResolve = nil
    }
}

/// Rides along on the presented view controller; when the screen deallocates
/// without finishing, resolves the channel with nil. View controllers
/// deallocate on the main thread, so `assumeIsolated` is sound.
final class DeallocSentinel {
    private let channel: @Sendable () -> ResultChannel?

    @MainActor init(channel: ResultChannel) {
        self.channel = { [weak channel] in channel }
    }

    deinit {
        let channel = channel
        MainActor.assumeIsolated {
            channel()?.resolve(nil)
        }
    }
}

#if canImport(UIKit)
private nonisolated(unsafe) var sentinelKey: UInt8 = 0

@MainActor func bindDeallocSignal(from viewController: PlatformViewController, to channel: ResultChannel) {
    objc_setAssociatedObject(viewController, &sentinelKey, DeallocSentinel(channel: channel), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
#else
@MainActor func bindDeallocSignal(from viewController: PlatformViewController, to channel: ResultChannel) {
    viewController._swiftRouterResultSentinel = DeallocSentinel(channel: channel)
}
#endif
