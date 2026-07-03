import Testing
@testable import SwiftRouter

private struct UserDetail: Route { let id: Int }
private struct Unregistered: Route {}

@MainActor
struct RouterResolutionTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func resolvesRegisteredRoute() throws {
        final class UserVC: PlatformViewController { var id = 0 }
        router.register(UserDetail.self) { route, _ in
            let vc = UserVC(); vc.id = route.id; return vc
        }
        let vc = try router.viewController(for: UserDetail(id: 42))
        #expect((vc as? UserVC)?.id == 42)
    }

    @Test func unregisteredRouteThrows() {
        #expect(throws: RouterError.notRegistered(routeType: "Unregistered")) {
            try self.router.viewController(for: Unregistered())
        }
    }

    @Test func independentInstancesAreIsolated() {
        let other = Router(navigationPerformer: SpyNavigationPerformer())
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(throws: RouterError.self) { try other.viewController(for: UserDetail(id: 1)) }
    }

    @Test func sharedSingletonIsStable() {
        #expect(Router.shared === Router.shared)
    }

    @Test func defaultPerformerThrowsWithoutUIKitContext() {
        // On macOS (test host) the default performer has no navigation context.
        #if !canImport(UIKit)
        let bare = Router()
        bare.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(throws: RouterError.noNavigationContext) {
            try bare.navigationPerformer.perform(.push(animated: false), viewController: PlatformViewController())
        }
        #endif
    }

    @Test func addRoutesPopulatesTable() {
        router.addRoutes([
            RouteRecord(name: "tabbar", path: "/tabbar") { _ in PlatformViewController() },
            RouteRecord(name: "login", path: "/login") { _ in PlatformViewController() },
        ])
        #expect(router.routeTable.record(named: "tabbar") != nil)
        #expect(router.routeTable.record(named: "login") != nil)
    }
}
