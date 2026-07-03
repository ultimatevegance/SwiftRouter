import Testing
@testable import SwiftRouter

@MainActor
struct CoreTypesTests {
    @Test func pushSugarDefaultsToAnimated() {
        guard case .push(let animated) = RouteTransition.push() else {
            Issue.record("expected .push"); return
        }
        #expect(animated == true)
    }

    @Test func replaceRootSugarDefaultsToNotAnimated() {
        guard case .replaceRoot(let animated) = RouteTransition.replaceRoot() else {
            Issue.record("expected .replaceRoot"); return
        }
        #expect(animated == false)
    }

    @Test func presentationConfigDefaults() {
        let config = PresentationConfig()
        #expect(config.style == .automatic)
        #expect(config.detents == nil)
        #expect(config.animated == true)
    }

    @Test func resolvedMirrorsTransition() {
        guard case .present(let config) = RouteTransition.present(PresentationConfig(style: .formSheet)).resolved else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .formSheet)
    }

    @Test func routeDefaultsToPushTransition() {
        struct Dummy: Route {}
        guard case .push(let animated) = Dummy.preferredTransition else {
            Issue.record("expected .push"); return
        }
        #expect(animated == true)
    }

    @Test func routeCanOverridePreferredTransition() {
        struct Sheet: Route {
            @MainActor static var preferredTransition: RouteTransition { .present(PresentationConfig(style: .pageSheet)) }
        }
        guard case .present(let config) = Sheet.preferredTransition else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .pageSheet)
    }

    @Test func routerErrorEquality() {
        #expect(RouterError.guardCancelled == RouterError.guardCancelled)
        #expect(RouterError.notRegistered(routeType: "A") != RouterError.notRegistered(routeType: "B"))
    }
}
