/// Type-keyed factory storage for the typed layer.
@MainActor final class RouteRegistry {
    struct Entry {
        let factory: (any Route, RoutingContext) throws -> PlatformViewController
        let guards: [any NavigationGuard]
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func register<R: Route>(_ type: R.Type,
                            guards: [any NavigationGuard],
                            factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        let key = ObjectIdentifier(type)
        if entries[key] != nil {
            #if DEBUG
            print("SwiftRouter warning: factory for \(type) was already registered — replacing (last wins).")
            #endif
        }
        entries[key] = Entry(
            factory: { route, context in
                guard let typed = route as? R else {
                    throw RouterError.notRegistered(routeType: String(describing: Swift.type(of: route)))
                }
                return factory(typed, context)
            },
            guards: guards
        )
    }

    func entry(for routeType: any Route.Type) -> Entry? {
        entries[ObjectIdentifier(routeType)]
    }
}
