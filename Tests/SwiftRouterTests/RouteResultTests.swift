import Testing
@testable import SwiftRouter

private struct ColorPicker: ResultRoute {
    typealias Result = String
}

@MainActor
struct RouteResultTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func finishResolvesResultAndDismisses() async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        captured?.finish("red")
        let value = try await task.value
        #expect(value == "red")
        #expect(spy.dismissed.count == 1)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
    }

    @Test func secondFinishIsIgnored() async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        captured?.finish("red")
        captured?.finish("blue")
        let value = try await task.value
        #expect(value == "red")
        #expect(spy.dismissed.count == 1)
    }

    @Test func deallocationWithoutFinishResolvesNil() async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        spy.removeAll() // drop the only strong reference to the presented VC
        let value = try await task.value
        #expect(value == nil)
        #expect(spy.dismissed.isEmpty)
    }

    @Test func guardCancellationThrowsBeforePresenting() async {
        router.register(ColorPicker.self) { _, _ in PlatformViewController() }
        router.beforeEach { _, _ in .cancel }
        await #expect(throws: RouterError.guardCancelled) {
            _ = try await self.router.present(forResult: ColorPicker())
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func finishIsNoOpForPlainNavigations() async throws {
        struct Plain: Route {}
        var captured: RoutingContext?
        router.register(Plain.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        try await router.navigate(to: Plain())
        captured?.finish("ignored") // must not crash or dismiss
        #expect(spy.dismissed.isEmpty)
    }
}
