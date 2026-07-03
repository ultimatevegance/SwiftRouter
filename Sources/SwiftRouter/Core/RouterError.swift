/// Errors thrown by the routing pipeline.
///
/// Programmer errors (invalid pattern syntax, ambiguous patterns) are not
/// represented here — they trap at registration in debug builds. These cases
/// cover recoverable runtime conditions.
public enum RouterError: Error, Equatable, Sendable {
    /// No factory or record is registered for the requested route, name,
    /// path, or URL. The associated value names what was looked up.
    case notRegistered(routeType: String)
    /// A required parameter was absent — thrown by `RouteParameters`' typed
    /// accessors and by name-based navigation when a path placeholder is
    /// missing from `params`.
    case parameterMissing(name: String)
    /// A parameter was present but couldn't convert to the requested type
    /// (e.g. `"abc"` for `<int:id>`).
    case parameterTypeMismatch(name: String, expected: String, actual: String)
    /// A navigation guard returned `.cancel`. Thrown by the async APIs;
    /// fire-and-forget verbs swallow it — a blocked navigation is not a crash.
    case guardCancelled
    /// A redirect chain (guard redirects and record redirects combined)
    /// exceeded 8 hops.
    case redirectLoopDetected(depth: Int)
    /// No usable navigation target exists — no key window, no navigation
    /// controller for a push, or the platform has no UIKit.
    case noNavigationContext
}
