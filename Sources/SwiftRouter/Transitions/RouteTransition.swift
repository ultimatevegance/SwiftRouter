public enum ModalStyle: Sendable, Equatable {
    case automatic, fullScreen, pageSheet, formSheet, overFullScreen
}

public enum SheetDetent: Sendable, Equatable {
    case medium, large
}

public struct PresentationConfig: Sendable, Equatable {
    public var style: ModalStyle
    public var detents: [SheetDetent]?
    public var animated: Bool

    public init(style: ModalStyle = .automatic, detents: [SheetDetent]? = nil, animated: Bool = true) {
        self.style = style
        self.detents = detents
        self.animated = animated
    }
}

/// Full custom control over how a resolved view controller enters the screen.
@MainActor public protocol RouteTransitioning {
    func perform(_ viewController: PlatformViewController, from source: PlatformViewController?) throws
}

public enum RouteTransition {
    case push(animated: Bool)
    case present(PresentationConfig)
    /// Swap the top of the current navigation stack (`history.replaceState` analog).
    case replace(animated: Bool)
    case replaceRoot(animated: Bool)
    case custom(any RouteTransitioning)

    public static func push() -> RouteTransition { .push(animated: true) }
    public static func present() -> RouteTransition { .present(PresentationConfig()) }
    public static func replace() -> RouteTransition { .replace(animated: true) }
    public static func replaceRoot() -> RouteTransition { .replaceRoot(animated: false) }
}

/// The concrete transition handed to `NavigationPerforming` after the
/// route's preferred/meta transition has been resolved.
public enum ResolvedTransition {
    case push(animated: Bool)
    case present(PresentationConfig)
    case replace(animated: Bool)
    case replaceRoot(animated: Bool)
    case custom(any RouteTransitioning)
}

extension RouteTransition {
    var resolved: ResolvedTransition {
        switch self {
        case .push(let animated): .push(animated: animated)
        case .present(let config): .present(config)
        case .replace(let animated): .replace(animated: animated)
        case .replaceRoot(let animated): .replaceRoot(animated: animated)
        case .custom(let transitioning): .custom(transitioning)
        }
    }
}
