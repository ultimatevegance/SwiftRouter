import Foundation

/// Route metadata. `requiresAuth` and `userInfo` are data for the app's own
/// guards; the router itself only interprets `transition` and `tabIndex`.
public struct RouteMeta {
    /// Transition used when the caller doesn't pass an explicit one. nil → `.push()`.
    public var transition: RouteTransition?
    public var requiresAuth: Bool
    /// Tab index selected by `switchTab(name:)` for this record.
    public var tabIndex: Int?
    public var userInfo: [String: Any]

    public init(transition: RouteTransition? = nil,
                requiresAuth: Bool = false,
                tabIndex: Int? = nil,
                userInfo: [String: Any] = [:]) {
        self.transition = transition
        self.requiresAuth = requiresAuth
        self.tabIndex = tabIndex
        self.userInfo = userInfo
    }
}

/// The resolved "where are we going" value handed to dynamic components,
/// actions, and navigation guards. Confined to the main actor via `Router`;
/// `context` may carry non-Sendable payloads (callbacks, model objects).
public struct RouteLocation {
    public let name: String?
    /// Concrete matched path, e.g. "/novel/123". Never includes query.
    public let path: String
    public let params: [String: String]
    public let query: [String: String]
    public let context: Any?
    public let meta: RouteMeta
    /// Non-nil when navigation came through `open(url:)`.
    public let url: URL?
    /// The typed route value when navigation began from the typed layer.
    public let route: (any Route)?
    let parameters: RouteParameters?

    init(name: String?, path: String, params: [String: String], query: [String: String],
         context: Any?, meta: RouteMeta, url: URL?, route: (any Route)?,
         parameters: RouteParameters?) {
        self.name = name
        self.path = path
        self.params = params
        self.query = query
        self.context = context
        self.meta = meta
        self.url = url
        self.route = route
        self.parameters = parameters
    }
}
