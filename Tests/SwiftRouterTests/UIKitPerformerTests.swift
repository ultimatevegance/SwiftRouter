#if canImport(UIKit)
import Testing
import UIKit
@testable import SwiftRouter

private struct SimRoute: Route {}

@MainActor
struct UIKitPerformerTests {
    @Test func pinnedPushUsesNavigationController() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let performer = DefaultNavigationPerformer(pinnedNavigationController: navigation)
        let destination = UIViewController()
        try performer.perform(.push(animated: false), viewController: destination)
        #expect(navigation.viewControllers.last === destination)
    }

    @Test func replaceSwapsTopOfStack() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(UIViewController(), animated: false)
        let performer = DefaultNavigationPerformer(pinnedNavigationController: navigation)
        let replacement = UIViewController()
        try performer.perform(.replace(animated: false), viewController: replacement)
        #expect(navigation.viewControllers == [root, replacement])
    }

    @Test func applyConfigSetsModalStyle() {
        let viewController = UIViewController()
        DefaultNavigationPerformer.apply(PresentationConfig(style: .formSheet), to: viewController)
        #expect(viewController.modalPresentationStyle == .formSheet)
    }

    @Test func routerEndToEndPushViaPin() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let router = Router()
        router.pin(to: navigation)
        router.register(SimRoute.self) { _, _ in UIViewController() }
        try await router.navigate(to: SimRoute(), via: .push(animated: false))
        #expect(navigation.viewControllers.count == 2)
    }

    @Test func dynamicRecordEndToEndViaPin() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let router = Router()
        router.pin(to: navigation)
        router.addRoutes([RouteRecord(name: "novel", path: "/novel/:id") { _ in UIViewController() }])
        _ = try await router.navigate(name: "novel", params: ["id": "1"])
        #expect(navigation.viewControllers.count == 2)
    }
}
#endif
