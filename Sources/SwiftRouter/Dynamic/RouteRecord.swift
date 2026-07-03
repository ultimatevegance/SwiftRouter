/// One row of the dynamic route table.
/// Exactly one of component / action / redirect, enforced by the initializers.
///
/// ```swift
/// router.addRoutes([
///     RouteRecord(name: "novel_detail", path: "/novel/:id") { location in
///         NovelDetailViewController(id: location.params["id"] ?? "")
///     },
///     RouteRecord(name: "reading", path: "/reading", action: { location in
///         openReader(novelID: location.query["novel_id"]); return true
///     }),
///     RouteRecord(name: "old_page", path: "/old", redirect: .path("/novel/list")),
/// ])
/// ```
public struct RouteRecord {
    enum Content {
        case component(@MainActor (RouteLocation) -> PlatformViewController)
        case action(@MainActor (RouteLocation) -> Bool)
        case redirect(RedirectTarget)
    }

    /// Optional route name used by `navigate(name:)`, `push(name:)`,
    /// `replace(name:)`, redirects, and `switchTab(name:)`.
    public let name: String?
    /// Metadata exposed on `RouteLocation` and used for default transitions
    /// and tab selection.
    public let meta: RouteMeta
    let pattern: RoutePattern
    let content: Content

    /// Creates a record that resolves to a view controller.
    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                component: @escaping @MainActor (RouteLocation) -> PlatformViewController) {
        self.init(name: name, path: path, meta: meta, content: .component(component))
    }

    /// A handler route: runs after guards, performs no transition.
    /// Its Bool is the "handled" result.
    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                action: @escaping @MainActor (RouteLocation) -> Bool) {
        self.init(name: name, path: path, meta: meta, content: .action(action))
    }

    /// A declarative redirect, resolved before guards run.
    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                redirect: RedirectTarget) {
        self.init(name: name, path: path, meta: meta, content: .redirect(redirect))
    }

    private init(name: String?, path: String, meta: RouteMeta, content: Content) {
        self.name = name
        self.meta = meta
        self.pattern = RoutePattern(stringLiteral: path)
        self.content = content
    }
}
