/// A route whose presented screen produces a value. `present(forResult:)`
/// suspends until the screen calls `context.finish(_:)` (→ the value) or is
/// dismissed/deallocated without finishing (→ nil — cancellation is not an error).
public protocol ResultRoute: Route {
    associatedtype Result: Sendable
}
