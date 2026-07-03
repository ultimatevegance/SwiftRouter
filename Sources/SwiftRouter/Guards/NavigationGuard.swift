/// Where a redirect decision or a redirect record sends the navigation.
public enum RedirectTarget: Sendable {
    /// A concrete path, matched against the route table and deep-link
    /// patterns — `.path("/login")`.
    case path(String)
    /// A named record with path parameters — `.name("novel_detail", params: ["id": "1"])`.
    case name(String, params: [String: String])
    /// A typed route value — `.route(LoginRoute())`.
    case route(any Route)

    /// A named record without parameters — `.name("login")`.
    public static func name(_ name: String) -> RedirectTarget { .name(name, params: [:]) }
}

/// What a guard decided about a navigation.
///
/// Guards either allow the request, cancel it, or send it to a different
/// destination through the same pipeline.
public enum GuardDecision: Sendable {
    /// Let the navigation proceed to the next guard (or the screen).
    case allow
    /// Block the navigation. Async APIs throw `RouterError.guardCancelled`;
    /// fire-and-forget verbs stay silent.
    case cancel
    /// Abandon this navigation and run the full pipeline (guards included)
    /// for the target instead. Chains are capped at 8 hops.
    case redirect(RedirectTarget)
}

/// Intercepts navigations before a destination is performed.
///
/// Global guards (`Router.beforeEach` / `Router.addGuard`) run in registration
/// order, then typed per-route guards. Guards run for every navigation —
/// typed, named, path-based, and deep links alike.
///
/// ```swift
/// struct AuthGuard: NavigationGuard {
///     func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision {
///         guard to.meta.requiresAuth else { return .allow }
///         return await AccountService.shared.isLoggedIn ? .allow : .redirect(.name("login"))
///     }
/// }
/// ```
public protocol NavigationGuard: Sendable {
    /// Inspect `to` (the resolved destination — typed navigations expose the
    /// route value as `to.route`, deep links expose `to.url`) and decide.
    /// `from` is the router's last confirmed location, nil on first navigation.
    /// The call runs on the main actor but may suspend (auth checks, token
    /// refresh).
    @MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision
}
