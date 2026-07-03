/// Marker protocol for navigable destinations. Routes are plain value types.
public protocol Route: Sendable {
    /// The transition `navigate(to:)` uses when no explicit `via:` is given.
    @MainActor static var preferredTransition: RouteTransition { get }
}

extension Route {
    @MainActor public static var preferredTransition: RouteTransition { .push() }
}
