import Foundation
import Testing
@testable import SwiftRouter

private struct UserDetail: Route, DeepLinkable {
    let id: Int
    static let pattern: RoutePattern = "myapp://user/<int:id>"
    init(parameters: RouteParameters) throws { id = try parameters.int("id") }
    init(id: Int) { self.id = id }
}

private struct StrictRoute: Route, DeepLinkable {
    let token: String
    static let pattern: RoutePattern = "myapp://strict/<int:id>"
    init(parameters: RouteParameters) throws { token = try parameters.string("token") }
}

@MainActor
struct DeepLinkTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func openConstructsTypedRouteThroughPipeline() async throws {
        var captured: (route: UserDetail, context: RoutingContext)?
        router.register(UserDetail.self) { route, context in
            captured = (route, context)
            return PlatformViewController()
        }
        let handled = try await router.open(URL(string: "myapp://user/42?ref=email")!)
        #expect(handled == true)
        #expect(captured?.route.id == 42)
        #expect(captured?.context.url?.absoluteString == "myapp://user/42?ref=email")
        #expect(captured?.context.parameters?.stringIfPresent("ref") == "email")
        #expect(spy.performed.count == 1)
    }

    /// Forces the synchronous fire-and-forget overload — in an async context
    /// Swift would otherwise resolve `open(_:)` to the async variant.
    private func syncOpen(_ url: String) -> Bool {
        router.open(URL(string: url)!)
    }

    @Test func syncOpenReturnsMatchAndNavigatesEventually() async {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(syncOpen("myapp://user/7") == true)
        #expect(syncOpen("myapp://user/abc") == false)
        #expect(syncOpen("myapp://nope") == false)
        await waitUntil { !spy.performed.isEmpty }
        #expect(spy.performed.count == 1)
    }

    @Test func guardsApplyToDeepLinks() async {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            #expect(to.url != nil)
            #expect(to.route is UserDetail)
            #expect(to.params["id"] == "9")
            return .cancel
        }
        await #expect(throws: RouterError.guardCancelled) {
            try await self.router.open(URL(string: "myapp://user/9")!)
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func unmatchedURLThrowsOnAsyncOpen() async {
        await #expect(throws: RouterError.notRegistered(routeType: "myapp://nope")) {
            try await self.router.open(URL(string: "myapp://nope")!)
        }
    }

    @Test func initFailurePropagates() async {
        router.register(StrictRoute.self) { _, _ in PlatformViewController() }
        await #expect(throws: RouterError.parameterMissing(name: "token")) {
            try await self.router.open(URL(string: "myapp://strict/1")!)
        }
        let handled = try? await router.open(URL(string: "myapp://strict/1?token=abc")!)
        #expect(handled == true)
    }

    @Test func literalRecordBeatsTypedPlaceholderPattern() async throws {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        var settingsHit = false
        router.addRoutes([
            RouteRecord(name: "user_settings", path: "myapp://user/settings") { _ in
                settingsHit = true
                return PlatformViewController()
            }
        ])
        _ = try await router.open(URL(string: "myapp://user/settings")!)
        #expect(settingsHit == true)
    }

    @Test func pathNavigationReachesTypedDeepLinkables() async throws {
        var captured: UserDetail?
        router.register(UserDetail.self) { route, _ in
            captured = route
            return PlatformViewController()
        }
        let handled = try await router.navigate(path: "myapp://user/5")
        #expect(handled == true)
        #expect(captured?.id == 5)
    }
}
