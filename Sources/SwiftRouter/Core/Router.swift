import Foundation

@MainActor public final class Router {
    public static let shared = Router()

    let registry = RouteRegistry()
    let routeTable = RouteTable()
    let matcher = URLMatcher()

    var beforeGuards: [any NavigationGuard] = []
    var deepLinkFactories: [ObjectIdentifier: (RouteParameters) throws -> any Route] = [:]
    var afterHooks: [@MainActor (RouteLocation, RouteLocation?) -> Void] = []
    /// The last confirmed screen navigation — the `from` handed to guards.
    public private(set) var currentLocation: RouteLocation?

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

    public func register<R: DeepLinkable>(_ type: R.Type,
                                          guards: [any NavigationGuard] = [],
                                          factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        registry.register(type, guards: guards, factory: factory)
        matcher.register(R.pattern, target: .routeType(ObjectIdentifier(type)))
        deepLinkFactories[ObjectIdentifier(type)] = { parameters in try R(parameters: parameters) }
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

// MARK: - Guards

extension Router {
    public func addGuard(_ navigationGuard: any NavigationGuard) {
        beforeGuards.append(navigationGuard)
    }

    /// vue-router's `beforeEach`, Swift flavor: return a decision instead of
    /// calling `next(...)` — `.allow`, `.cancel`, or `.redirect(...)`.
    public func beforeEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) async -> GuardDecision) {
        addGuard(ClosureGuard(body: body))
    }

    /// Fires after every confirmed navigation (including handled actions).
    public func afterEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) -> Void) {
        afterHooks.append(body)
    }
}

struct ClosureGuard: NavigationGuard {
    let body: @MainActor (RouteLocation, RouteLocation?) async -> GuardDecision

    @MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision {
        await body(to, from)
    }
}

// MARK: - Navigation pipeline

extension Router {
    static let maxRedirectDepth = 8

    struct ResolvedDestination {
        enum Kind {
            case typed(RouteRegistry.Entry, any Route)
            case component(@MainActor (RouteLocation) -> PlatformViewController)
            case action(@MainActor (RouteLocation) -> Bool)
            case redirect(RedirectTarget)
        }

        let kind: Kind
        let location: RouteLocation
    }

    // MARK: Public verbs

    public func navigate(to route: some Route, via transition: RouteTransition? = nil) async throws {
        _ = try await navigateCore(try typedDestination(for: route), transitionOverride: transition, redirectDepth: 0)
    }

    @discardableResult
    public func navigate(name: String, params: [String: String] = [:], query: [String: String] = [:],
                         context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool {
        let destination = try namedDestination(name: name, params: params, query: query, context: context)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }

    @discardableResult
    public func navigate(path: String, query: [String: String] = [:],
                         context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool {
        let destination = try pathDestination(path: path, query: query, context: context, url: nil)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }

    public func push(_ route: some Route, animated: Bool = true) {
        fireAndForget { try await self.navigate(to: route, via: .push(animated: animated)) }
    }

    public func present(_ route: some Route, style: ModalStyle = .automatic, animated: Bool = true) {
        fireAndForget {
            try await self.navigate(to: route, via: .present(PresentationConfig(style: style, animated: animated)))
        }
    }

    public func push(name: String, params: [String: String] = [:], query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(name: name, params: params, query: query, context: context) }
    }

    public func push(path: String, query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(path: path, query: query, context: context) }
    }

    public func replace(name: String, params: [String: String] = [:], query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(name: name, params: params, query: query, context: context, via: .replace()) }
    }

    public func replace(path: String, query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(path: path, query: query, context: context, via: .replace()) }
    }

    /// Pop the navigation stack, else dismiss. Returns whether anything happened.
    @discardableResult
    public func back(animated: Bool = true) -> Bool {
        navigationPerformer.back(animated: animated)
    }

    /// Select the tab declared by the named record's `meta.tabIndex`.
    @discardableResult
    public func switchTab(name: String) -> Bool {
        guard let record = routeTable.record(named: name), let tabIndex = record.meta.tabIndex else { return false }
        return navigationPerformer.switchTab(index: tabIndex)
    }

    // MARK: Destination building

    func typedDestination(for route: any Route) throws -> ResolvedDestination {
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        let location = RouteLocation(name: String(describing: type(of: route)), path: "", params: [:], query: [:],
                                     context: nil, meta: RouteMeta(), url: nil, route: route, parameters: nil)
        return ResolvedDestination(kind: .typed(entry, route), location: location)
    }

    private func namedDestination(name: String, params: [String: String], query: [String: String],
                                  context: Any?) throws -> ResolvedDestination {
        guard let record = routeTable.record(named: name) else {
            throw RouterError.notRegistered(routeType: "route named '\(name)'")
        }
        let path = try routeTable.path(for: record, params: params)
        let location = RouteLocation(name: record.name, path: path, params: params, query: query,
                                     context: context, meta: record.meta, url: nil, route: nil,
                                     parameters: RouteParameters(pathValues: params, queryValues: query))
        return ResolvedDestination(kind: kind(of: record), location: location)
    }

    func pathDestination(path: String, query: [String: String], context: Any?, url: URL?) throws -> ResolvedDestination {
        let matched: URLMatchResult? = if let url { matcher.match(url) } else { matcher.match(pathOrURL: path) }
        guard let match = matched else { throw RouterError.notRegistered(routeType: path) }
        let mergedQuery = match.queryValues.merging(query) { _, explicit in explicit }
        let parameters = RouteParameters(pathValues: match.pathValues, queryValues: mergedQuery)
        switch match.target {
        case .record(let index):
            let record = routeTable.record(at: index)
            let location = RouteLocation(name: record.name, path: match.path, params: match.pathValues,
                                         query: mergedQuery, context: context, meta: record.meta,
                                         url: url, route: nil, parameters: parameters)
            return ResolvedDestination(kind: kind(of: record), location: location)
        case .routeType(let id):
            return try deepLinkDestination(typeID: id, match: match, mergedQuery: mergedQuery,
                                           parameters: parameters, context: context, url: url)
        }
    }

    /// Builds a typed destination from a matched deep-link pattern.
    func deepLinkDestination(typeID: ObjectIdentifier, match: URLMatchResult, mergedQuery: [String: String],
                             parameters: RouteParameters, context: Any?, url: URL?) throws -> ResolvedDestination {
        guard let makeRoute = deepLinkFactories[typeID] else {
            throw RouterError.notRegistered(routeType: match.path)
        }
        let route = try makeRoute(parameters)
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        let location = RouteLocation(name: String(describing: type(of: route)), path: match.path,
                                     params: match.pathValues, query: mergedQuery, context: context,
                                     meta: RouteMeta(), url: url, route: route, parameters: parameters)
        return ResolvedDestination(kind: .typed(entry, route), location: location)
    }

    private func kind(of record: RouteRecord) -> ResolvedDestination.Kind {
        switch record.content {
        case .component(let make): .component(make)
        case .action(let action): .action(action)
        case .redirect(let target): .redirect(target)
        }
    }

    private func resolve(_ target: RedirectTarget, context: Any?) throws -> ResolvedDestination {
        switch target {
        case .route(let route):
            return try typedDestination(for: route)
        case .name(let name, let params):
            return try namedDestination(name: name, params: params, query: [:], context: context)
        case .path(let path):
            return try pathDestination(path: path, query: [:], context: context, url: nil)
        }
    }

    // MARK: Core

    @discardableResult
    func navigateCore(_ destination: ResolvedDestination, transitionOverride: RouteTransition?,
                      redirectDepth: Int, resultChannel: ResultChannel? = nil) async throws -> Bool {
        var destination = destination
        var depth = redirectDepth

        // Declarative record redirects resolve before guards (vue semantics).
        while case .redirect(let target) = destination.kind {
            depth += 1
            if depth > Self.maxRedirectDepth { throw RouterError.redirectLoopDetected(depth: depth) }
            destination = try resolve(target, context: destination.location.context)
        }

        let from = currentLocation
        let perRouteGuards: [any NavigationGuard] = if case .typed(let entry, _) = destination.kind { entry.guards } else { [] }
        for navigationGuard in beforeGuards + perRouteGuards {
            switch await navigationGuard.check(to: destination.location, from: from) {
            case .allow:
                continue
            case .cancel:
                throw RouterError.guardCancelled
            case .redirect(let target):
                if depth + 1 > Self.maxRedirectDepth { throw RouterError.redirectLoopDetected(depth: depth + 1) }
                let next = try resolve(target, context: destination.location.context)
                return try await navigateCore(next, transitionOverride: nil, redirectDepth: depth + 1,
                                              resultChannel: resultChannel)
            }
        }

        switch destination.kind {
        case .redirect:
            preconditionFailure("record redirects are resolved before guards")
        case .action(let action):
            let handled = action(destination.location)
            if handled { runAfterHooks(to: destination.location, from: from) }
            return handled
        case .component(let make):
            let viewController = make(destination.location)
            try performTransition(viewController, location: destination.location, from: from,
                                  transitionOverride: transitionOverride, preferred: nil,
                                  resultChannel: resultChannel)
            return true
        case .typed(let entry, let route):
            let context = RoutingContext(url: destination.location.url, parameters: destination.location.parameters,
                                         resultChannel: resultChannel)
            let viewController = try entry.factory(route, context)
            try performTransition(viewController, location: destination.location, from: from,
                                  transitionOverride: transitionOverride,
                                  preferred: type(of: route).preferredTransition,
                                  resultChannel: resultChannel)
            return true
        }
    }

    private func performTransition(_ viewController: PlatformViewController, location: RouteLocation,
                                   from: RouteLocation?, transitionOverride: RouteTransition?,
                                   preferred: RouteTransition?, resultChannel: ResultChannel? = nil) throws {
        let transition = transitionOverride ?? location.meta.transition ?? preferred ?? .push()
        let resolved = transition.resolved
        try navigationPerformer.perform(resolved, viewController: viewController)
        if let resultChannel {
            let performer = navigationPerformer
            let animated: Bool = if case .present(let config) = resolved { config.animated } else { true }
            resultChannel.onResolve = { [weak viewController] in
                guard let viewController else { return }
                performer.dismiss(viewController, animated: animated)
            }
            bindDeallocSignal(from: viewController, to: resultChannel)
        }
        currentLocation = location
        runAfterHooks(to: location, from: from)
    }

    private func runAfterHooks(to: RouteLocation, from: RouteLocation?) {
        for hook in afterHooks {
            hook(to, from)
        }
    }

    /// Convenience verbs swallow guard cancellations (a blocked navigation is
    /// not a crash) and surface real failures in DEBUG builds.
    func fireAndForget(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch RouterError.guardCancelled {
                // Silent by design.
            } catch {
                #if DEBUG
                print("SwiftRouter: navigation failed — \(error)")
                #endif
            }
        }
    }
}

// MARK: - Route results

extension Router {
    /// Present a screen and suspend until it finishes with a value or is
    /// dismissed (→ nil). The factory's `RoutingContext` carries the
    /// `finish(_:)` handle.
    public func present<R: ResultRoute>(forResult route: R,
                                        config: PresentationConfig = PresentationConfig()) async throws -> R.Result? {
        let channel = ResultChannel()
        // Deliberately not holding the returned view controller here: its
        // only strong owners must be the presentation hierarchy, so the
        // dealloc sentinel can fire when the screen goes away.
        _ = try await navigateCore(try typedDestination(for: route), transitionOverride: .present(config),
                                   redirectDepth: 0, resultChannel: channel)
        let raw = await withCheckedContinuation { channel.attach($0) }
        guard let raw else { return nil }
        guard let typed = raw as? R.Result else {
            assertionFailure("SwiftRouter: finish(_:) called with \(type(of: raw)), expected \(R.Result.self)")
            return nil
        }
        return typed
    }
}

// MARK: - Deep links

extension Router {
    /// Synchronously reports whether `url` matches a registered pattern;
    /// the navigation itself runs fire-and-forget.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard matcher.match(url) != nil else { return false }
        // Type-construction or guard failures surface via fireAndForget's
        // DEBUG logging; the Bool only reports the match.
        fireAndForget { _ = try await self.open(url) }
        return true
    }

    /// Full-control variant: throws on no match, guard cancellation, or
    /// construction failure. Returns the action's Bool for action records.
    @discardableResult
    public func open(_ url: URL, via transition: RouteTransition? = nil) async throws -> Bool {
        guard matcher.match(url) != nil else {
            throw RouterError.notRegistered(routeType: url.absoluteString)
        }
        let destination = try pathDestination(path: url.absoluteString, query: [:], context: nil, url: url)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }
}
