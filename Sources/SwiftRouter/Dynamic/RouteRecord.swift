/// One row of the dynamic route table — vue-router's route record.
/// Exactly one of component / action / redirect, enforced by the initializers.
public struct RouteRecord {
    enum Content {
        case component(@MainActor (RouteLocation) -> PlatformViewController)
        case action(@MainActor (RouteLocation) -> Bool)
        case redirect(RedirectTarget)
    }

    public let name: String?
    public let meta: RouteMeta
    let pattern: RoutePattern
    let content: Content

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

    /// A declarative redirect, resolved before guards run (vue semantics).
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
