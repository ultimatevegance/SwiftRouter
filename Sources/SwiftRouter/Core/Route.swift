/// Marker protocol for navigable destinations. Routes are plain value types —
/// no inheritance, no registration strings at call sites.
///
/// ```swift
/// struct UserDetail: Route {
///     let id: Int
/// }
///
/// router.register(UserDetail.self) { route, _ in
///     UserViewController(userID: route.id)
/// }
/// router.push(UserDetail(id: 42))
/// ```
public protocol Route: Sendable {
    /// The transition `navigate(to:)` uses when no explicit `via:` is given.
    /// Defaults to `.push()`.
    ///
    /// ```swift
    /// struct SettingsRoute: Route {
    ///     @MainActor static var preferredTransition: RouteTransition {
    ///         .present(PresentationConfig(style: .formSheet))
    ///     }
    /// }
    /// ```
    @MainActor static var preferredTransition: RouteTransition { get }
}

extension Route {
    @MainActor public static var preferredTransition: RouteTransition { .push() }
}
