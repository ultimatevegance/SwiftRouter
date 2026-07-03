/// Seam between the routing pipeline and actual UIKit navigation.
/// Apps can substitute custom containers; tests inject a spy. Only
/// `perform` is required — the rest have sensible defaults.
@MainActor public protocol NavigationPerforming {
    /// Performs a resolved transition with the already-created destination
    /// view controller.
    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws
    /// Dismiss a presented view controller (used when a result route finishes).
    func dismiss(_ viewController: PlatformViewController, animated: Bool)
    /// Pop or dismiss the current screen. Returns whether anything happened.
    @discardableResult func back(animated: Bool) -> Bool
    /// Select a tab by index. Returns whether a tab container was found.
    @discardableResult func switchTab(index: Int) -> Bool
}

extension NavigationPerforming {
    /// Default dismissal behavior for UIKit; no-op on non-UIKit platforms.
    public func dismiss(_ viewController: PlatformViewController, animated: Bool) {
        #if canImport(UIKit)
        (viewController.presentingViewController ?? viewController).dismiss(animated: animated)
        #endif
    }

    /// Default back behavior for performers that do not support stacks.
    @discardableResult public func back(animated: Bool) -> Bool { false }

    /// Default tab behavior for performers that do not support tab containers.
    @discardableResult public func switchTab(index: Int) -> Bool { false }
}

/// Fallback performer for platforms (or setups) with no navigation container.
@MainActor struct UnavailableNavigationPerformer: NavigationPerforming {
    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws {
        throw RouterError.noNavigationContext
    }
}
