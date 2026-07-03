import Testing
@testable import SwiftRouter

private struct Basic: Route {}
private struct Target: Route {}
private struct SheetRoute: Route {
    @MainActor static var preferredTransition: RouteTransition { .present(PresentationConfig(style: .formSheet)) }
}

@MainActor
struct NavigationPipelineTests {
    let spy = SpyNavigationPerformer()
    let log = GuardLog()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func navigateUsesPreferredTransitionWhenViaIsNil() async throws {
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: SheetRoute())
        guard case .present(let config) = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .formSheet)
    }

    @Test func viaOverridesPreferredTransition() async throws {
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: SheetRoute(), via: .push(animated: false))
        guard case .push(false) = spy.performed.first?.transition else {
            Issue.record("expected .push(animated: false)"); return
        }
    }

    @Test func metaTransitionAppliesForRecords() async throws {
        router.addRoutes([
            RouteRecord(name: "login", path: "/login", meta: RouteMeta(transition: .present())) { _ in PlatformViewController() }
        ])
        let handled = try await router.navigate(name: "login")
        #expect(handled == true)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
    }

    @Test func globalThenPerRouteGuardOrder() async throws {
        router.addGuard(RecordingGuard(name: "global1", log: log))
        router.beforeEach { [log] _, _ in
            log.append("global2")
            return .allow
        }
        router.register(Basic.self, guards: [RecordingGuard(name: "perRoute", log: log)]) { _, _ in PlatformViewController() }
        try await router.navigate(to: Basic())
        #expect(log.entries == ["global1", "global2", "perRoute"])
        #expect(spy.performed.count == 1)
    }

    @Test func cancelThrowsAndBlocksNavigation() async {
        router.addGuard(RecordingGuard(name: "deny", log: log, decision: .cancel))
        router.register(Basic.self) { _, _ in PlatformViewController() }
        await #expect(throws: RouterError.guardCancelled) {
            try await self.router.navigate(to: Basic())
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func guardRedirectGoesToTargetWithItsPreferredTransition() async throws {
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            to.route is Basic ? .redirect(.route(SheetRoute())) : .allow
        }
        try await router.navigate(to: Basic(), via: .push(animated: false))
        #expect(spy.performed.count == 1)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("redirect should use the target's preferred transition"); return
        }
    }

    @Test func redirectByNameAndPath() async throws {
        router.addRoutes([
            RouteRecord(name: "login", path: "/login") { _ in PlatformViewController() },
            RouteRecord(name: "detail", path: "/novel/:id") { _ in PlatformViewController() },
        ])
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.register(Target.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            if to.route is Basic { return .redirect(.name("login")) }
            if to.route is Target { return .redirect(.path("/novel/9")) }
            return .allow
        }
        try await router.navigate(to: Basic())
        try await router.navigate(to: Target())
        #expect(spy.performed.count == 2)
    }

    @Test func declarativeRecordRedirectResolvesBeforeGuards() async throws {
        router.addRoutes([
            RouteRecord(name: "old", path: "/old", redirect: .path("/new")),
            RouteRecord(name: "new", path: "/new") { _ in PlatformViewController() },
        ])
        router.beforeEach { [log] to, _ in
            log.append(to.path)
            return .allow
        }
        let handled = try await router.navigate(path: "/old")
        #expect(handled == true)
        #expect(log.entries == ["/new"]) // guards fired for the final destination only
        #expect(spy.performed.count == 1)
    }

    @Test func redirectLoopThrowsAtCap() async {
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.beforeEach { _, _ in .redirect(.route(Basic())) }
        await #expect(throws: RouterError.redirectLoopDetected(depth: 9)) {
            try await self.router.navigate(to: Basic())
        }
    }

    @Test func actionRecordRunsWithoutTransition() async throws {
        let actionLog = GuardLog()
        router.addRoutes([
            RouteRecord(name: "reading", path: "/reading", action: { [actionLog] location in
                actionLog.append(location.query["novel_id"] ?? "?")
                return true
            })
        ])
        let handled = try await router.navigate(path: "/reading?novel_id=1")
        #expect(handled == true)
        #expect(actionLog.entries == ["1"])
        #expect(spy.performed.isEmpty)
    }

    @Test func namedNavigationBuildsLocation() async throws {
        var captured: RouteLocation?
        router.addRoutes([
            RouteRecord(name: "novel_detail", path: "/novel/:id") { location in
                captured = location
                return PlatformViewController()
            }
        ])
        try await router.navigate(name: "novel_detail", params: ["id": "123"], query: ["from": "home"], context: "ctx")
        #expect(captured?.name == "novel_detail")
        #expect(captured?.path == "/novel/123")
        #expect(captured?.params["id"] == "123")
        #expect(captured?.query["from"] == "home")
        #expect(captured?.context as? String == "ctx")
    }

    @Test func unknownNameOrPathThrows() async {
        await #expect(throws: RouterError.notRegistered(routeType: "route named 'nope'")) {
            try await self.router.navigate(name: "nope")
        }
        await #expect(throws: RouterError.notRegistered(routeType: "/nope")) {
            try await self.router.navigate(path: "/nope")
        }
    }

    @Test func explicitQueryWinsOverInline() async throws {
        var captured: RouteLocation?
        router.addRoutes([
            RouteRecord(name: "a", path: "/a") { location in
                captured = location
                return PlatformViewController()
            }
        ])
        try await router.navigate(path: "/a?x=inline&y=keep", query: ["x": "explicit"])
        #expect(captured?.query == ["x": "explicit", "y": "keep"])
    }

    @Test func afterEachFiresWithFromLocation() async throws {
        let hookLog = GuardLog()
        router.addRoutes([
            RouteRecord(name: "a", path: "/a") { _ in PlatformViewController() },
            RouteRecord(name: "b", path: "/b") { _ in PlatformViewController() },
        ])
        router.afterEach { [hookLog] to, from in
            hookLog.append("\(from?.path ?? "nil")->\(to.path)")
        }
        try await router.navigate(path: "/a")
        try await router.navigate(path: "/b")
        #expect(hookLog.entries == ["nil->/a", "/a->/b"])
        #expect(router.currentLocation?.path == "/b")
    }

    @Test func pushConvenienceEventuallyPerforms() async {
        router.addRoutes([RouteRecord(name: "a", path: "/a") { _ in PlatformViewController() }])
        router.push(path: "/a")
        await waitUntil { !spy.performed.isEmpty }
        #expect(spy.performed.count == 1)
    }

    @Test func replaceConvenienceUsesReplaceTransition() async {
        router.addRoutes([RouteRecord(name: "tabbar", path: "/tabbar") { _ in PlatformViewController() }])
        router.replace(name: "tabbar")
        await waitUntil { !spy.performed.isEmpty }
        guard case .replace = spy.performed.first?.transition else {
            Issue.record("expected .replace"); return
        }
    }

    @Test func cancelledPushIsSilentlySwallowed() async {
        router.addGuard(RecordingGuard(name: "deny", log: log, decision: .cancel))
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.push(Basic())
        await waitUntil { !log.entries.isEmpty }
        for _ in 0..<50 { await Task.yield() }
        #expect(spy.performed.isEmpty)
    }

    @Test func backAndSwitchTabDelegateToPerformer() {
        router.addRoutes([
            RouteRecord(name: "me", path: "/me", meta: RouteMeta(tabIndex: 2)) { _ in PlatformViewController() },
            RouteRecord(name: "notab", path: "/notab") { _ in PlatformViewController() },
        ])
        #expect(router.back(animated: false) == true)
        #expect(spy.backCalls == [false])
        #expect(router.switchTab(name: "me") == true)
        #expect(spy.switchTabCalls == [2])
        #expect(router.switchTab(name: "notab") == false)   // no tabIndex in meta
        #expect(router.switchTab(name: "missing") == false) // unknown name
        #expect(spy.switchTabCalls == [2])
    }

    @Test func customTransitionReachesPerformer() async throws {
        @MainActor final class Recorder: RouteTransitioning {
            func perform(_ viewController: PlatformViewController, from source: PlatformViewController?) throws {}
        }
        let recorder = Recorder()
        router.register(Basic.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: Basic(), via: .custom(recorder))
        guard case .custom(let transitioning) = spy.performed.first?.transition else {
            Issue.record("expected .custom"); return
        }
        #expect(transitioning as AnyObject === recorder)
    }
}
