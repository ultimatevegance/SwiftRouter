import Testing
@testable import SwiftRouter

private struct FeatureRoute: Route {}

private struct FeatureModule: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(FeatureRoute.self) { _, _ in PlatformViewController() }
        router.addRoutes([RouteRecord(name: "feature_home", path: "/feature") { _ in PlatformViewController() }])
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
}
