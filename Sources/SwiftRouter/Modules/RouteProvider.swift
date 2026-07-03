/// Feature modules implement this to register their routes. Modules depend
/// only on SwiftRouter, never on each other — cross-feature navigation goes
/// through shared route declarations or URLs/paths.
public protocol RouteProvider {
    @MainActor func registerRoutes(in router: Router)
}

extension Router {
    /// Install a feature module's routes.
    public func install(_ provider: some RouteProvider) {
        provider.registerRoutes(in: self)
    }
}
