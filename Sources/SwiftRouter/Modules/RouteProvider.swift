/// Feature modules implement this to register their routes.
///
/// Modules depend only on SwiftRouter, never on each other — cross-feature
/// navigation goes through shared route declarations or URLs/paths.
///
/// ```swift
/// struct NovelFeature: RouteProvider {
///     func registerRoutes(in router: Router) {
///         router.register(NovelDetail.self) { route, _ in NovelDetailViewController(id: route.id) }
///         router.addRoutes([RouteRecord(name: "novel_list", path: "/novel/list") { _ in NovelListViewController() }])
///     }
/// }
///
/// router.install(NovelFeature())
/// ```
public protocol RouteProvider {
    /// Called by `Router.install(_:)`; register typed routes and records here.
    @MainActor func registerRoutes(in router: Router)
}

extension Router {
    /// Install a feature module's routes.
    public func install(_ provider: some RouteProvider) {
        provider.registerRoutes(in: self)
    }
}
