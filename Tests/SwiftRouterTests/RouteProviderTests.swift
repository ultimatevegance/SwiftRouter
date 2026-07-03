import Testing
@testable import SwiftRouter

private struct FeatureRoute: Route {}

private struct FeatureModule: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(FeatureRoute.self) { _, _ in PlatformViewController() }
        router.addRoutes([RouteRecord(name: "feature_home", path: "/feature") { _ in PlatformViewController() }])
    }
}

private struct OtherFeatureRoute: Route {}

private struct OtherFeatureModule: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(OtherFeatureRoute.self) { _, _ in PlatformViewController() }
        router.addRoutes([RouteRecord(name: "other_home", path: "/other") { _ in PlatformViewController() }])
    }
}

@MainActor
struct RouteProviderTests {
    @Test func installRegistersModuleRoutes() async throws {
        let spy = SpyNavigationPerformer()
        let router = Router(navigationPerformer: spy)
        router.install(FeatureModule())
        try await router.navigate(to: FeatureRoute())
        _ = try await router.navigate(path: "/feature")
        #expect(spy.performed.count == 2)
    }

    @Test func installAllRegistersModulesInOrder() async throws {
        let spy = SpyNavigationPerformer()
        let router = Router(navigationPerformer: spy)
        router.installAll([FeatureModule(), OtherFeatureModule()])
        try await router.navigate(to: FeatureRoute())
        try await router.navigate(to: OtherFeatureRoute())
        _ = try await router.navigate(path: "/feature")
        _ = try await router.navigate(path: "/other")
        #expect(spy.performed.count == 4)
    }
}
