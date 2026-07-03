import Testing
@testable import SwiftRouter

@MainActor
struct GuardTypeTests {
    @Test func metaDefaults() {
        let meta = RouteMeta()
        #expect(meta.transition == nil)
        #expect(meta.requiresAuth == false)
        #expect(meta.tabIndex == nil)
        #expect(meta.userInfo.isEmpty)
    }

    @Test func redirectNameSugarUsesEmptyParams() {
        guard case .name(let name, let params) = RedirectTarget.name("login") else {
            Issue.record("expected .name"); return
        }
        #expect(name == "login")
        #expect(params.isEmpty)
    }

    @Test func closureGuardConformance() async {
        struct AllowAll: NavigationGuard {
            func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision { .allow }
        }
        let location = RouteLocation(name: "a", path: "/a", params: [:], query: [:], context: nil,
                                     meta: RouteMeta(), url: nil, route: nil, parameters: nil)
        let decision = await AllowAll().check(to: location, from: nil)
        guard case .allow = decision else { Issue.record("expected .allow"); return }
        #expect(location.context == nil)
    }
}
