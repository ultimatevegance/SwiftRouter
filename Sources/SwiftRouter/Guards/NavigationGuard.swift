/// Where a redirect decision or a redirect record sends the navigation.
public enum RedirectTarget: Sendable {
    case path(String)
    case name(String, params: [String: String])
    case route(any Route)

    public static func name(_ name: String) -> RedirectTarget { .name(name, params: [:]) }
}

public enum GuardDecision: Sendable {
    case allow
    case cancel
    case redirect(RedirectTarget)
}

/// Intercepts navigations, vue-router style. Global guards (`beforeEach` /
/// `addGuard`) run in registration order, then typed per-route guards.
public protocol NavigationGuard: Sendable {
    @MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision
}
