import Foundation

@MainActor public final class Router {
    public static let shared = Router()

    let registry = RouteRegistry()
    let routeTable = RouteTable()
    let matcher = URLMatcher()

    /// Performs the actual UIKit transitions. Replaceable for testing or
    /// custom navigation containers.
    public var navigationPerformer: NavigationPerforming

    public init(navigationPerformer: NavigationPerforming? = nil) {
        self.navigationPerformer = navigationPerformer ?? Self.defaultPerformer()
    }

    private static func defaultPerformer() -> NavigationPerforming {
        // The UIKit task swaps this for DefaultNavigationPerformer on iOS.
        UnavailableNavigationPerformer()
    }

    // MARK: - Registration

    public func register<R: Route>(_ type: R.Type,
                                   guards: [any NavigationGuard] = [],
                                   factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        registry.register(type, guards: guards, factory: factory)
    }

    /// Register the dynamic route table — vue-router's `createRouter` routes array.
    public func addRoutes(_ records: [RouteRecord]) {
        for record in records {
            routeTable.add(record, matcher: matcher)
        }
    }

    // MARK: - Resolution

    /// Resolve a route to its view controller without navigating — no guards,
    /// no transition. For embedding, tabs, and tests.
    public func viewController(for route: some Route) throws -> PlatformViewController {
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        return try entry.factory(route, RoutingContext())
    }
}
