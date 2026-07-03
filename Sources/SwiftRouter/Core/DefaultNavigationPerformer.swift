#if canImport(UIKit)
import UIKit

/// Default UIKit performer: discovers the top-most view controller from the
/// key window (walking presented VCs and nav/tab containers), or uses a
/// pinned navigation controller.
@MainActor public final class DefaultNavigationPerformer: NavigationPerforming {
    private weak var pinnedNavigationController: UINavigationController?

    public init(pinnedNavigationController: UINavigationController? = nil) {
        self.pinnedNavigationController = pinnedNavigationController
    }

    public func perform(_ transition: ResolvedTransition, viewController: UIViewController) throws {
        switch transition {
        case .push(let animated):
            guard let navigationController = pushTarget() else { throw RouterError.noNavigationContext }
            navigationController.pushViewController(viewController, animated: animated)
        case .present(let config):
            guard let presenter = presentTarget() else { throw RouterError.noNavigationContext }
            Self.apply(config, to: viewController)
            presenter.present(viewController, animated: config.animated)
        case .replace(let animated):
            guard let navigationController = pushTarget() else { throw RouterError.noNavigationContext }
            var stack = navigationController.viewControllers
            if stack.isEmpty {
                stack = [viewController]
            } else {
                stack[stack.count - 1] = viewController
            }
            navigationController.setViewControllers(stack, animated: animated)
        case .replaceRoot(let animated):
            guard let window = Self.keyWindow() else { throw RouterError.noNavigationContext }
            window.rootViewController = viewController
            if animated {
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
            }
        case .custom(let transitioning):
            try transitioning.perform(viewController, from: presentTarget())
        }
    }

    public func dismiss(_ viewController: UIViewController, animated: Bool) {
        (viewController.presentingViewController ?? viewController).dismiss(animated: animated)
    }

    @discardableResult
    public func back(animated: Bool) -> Bool {
        guard let top = pinnedNavigationController ?? Self.topMostViewController() else { return false }
        if let navigationController = (top as? UINavigationController) ?? top.navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: animated)
            return true
        }
        if top.presentingViewController != nil {
            top.dismiss(animated: animated)
            return true
        }
        return false
    }

    @discardableResult
    public func switchTab(index: Int) -> Bool {
        var current = Self.keyWindow()?.rootViewController ?? pinnedNavigationController
        while let candidate = current {
            if let tabs = candidate as? UITabBarController {
                guard index >= 0, index < (tabs.viewControllers?.count ?? 0) else { return false }
                tabs.selectedIndex = index
                return true
            }
            if let presented = candidate.presentedViewController {
                current = presented
            } else if let navigation = candidate as? UINavigationController {
                current = navigation.visibleViewController
            } else {
                return false
            }
        }
        return false
    }

    private func pushTarget() -> UINavigationController? {
        if let pinnedNavigationController { return pinnedNavigationController }
        guard let top = Self.topMostViewController() else { return nil }
        return (top as? UINavigationController) ?? top.navigationController
    }

    private func presentTarget() -> UIViewController? {
        pinnedNavigationController ?? Self.topMostViewController()
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    static func topMostViewController() -> UIViewController? {
        guard var current = keyWindow()?.rootViewController else { return nil }
        while true {
            if let presented = current.presentedViewController {
                current = presented
            } else if let navigation = current as? UINavigationController, let visible = navigation.visibleViewController {
                current = visible
            } else if let tabs = current as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
            } else {
                return current
            }
        }
    }

    static func apply(_ config: PresentationConfig, to viewController: UIViewController) {
        viewController.modalPresentationStyle = config.style.uiKit
        if let detents = config.detents, let sheet = viewController.sheetPresentationController {
            sheet.detents = detents.map { detent in
                switch detent {
                case .medium: .medium()
                case .large: .large()
                }
            }
        }
    }
}

extension ModalStyle {
    var uiKit: UIModalPresentationStyle {
        switch self {
        case .automatic: .automatic
        case .fullScreen: .fullScreen
        case .pageSheet: .pageSheet
        case .formSheet: .formSheet
        case .overFullScreen: .overFullScreen
        }
    }
}

extension Router {
    /// Pin all future navigations to a specific navigation controller.
    public func pin(to navigationController: UINavigationController) {
        navigationPerformer = DefaultNavigationPerformer(pinnedNavigationController: navigationController)
    }
}
#endif
