/// A route whose presented screen produces a value.
///
/// `Router.present(forResult:)` suspends until the screen calls
/// `context.finish(_:)` (→ the value) or is dismissed/deallocated without
/// finishing (→ nil — user cancellation is not an error).
///
/// ```swift
/// struct ColorPickerRoute: ResultRoute {
///     typealias Result = UIColor
/// }
///
/// let color = try await router.present(forResult: ColorPickerRoute())
/// // → UIColor? — nil when dismissed without choosing
/// ```
public protocol ResultRoute: Route {
    associatedtype Result: Sendable
}
