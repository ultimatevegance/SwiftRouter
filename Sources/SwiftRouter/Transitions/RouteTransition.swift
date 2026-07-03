/// Modal presentation style, mapped to `UIModalPresentationStyle` at
/// presentation time. Kept UIKit-free so the pipeline tests off-device.
public enum ModalStyle: Sendable, Equatable {
    /// UIKit's automatic presentation style.
    case automatic
    /// Full-screen presentation.
    case fullScreen
    /// Page sheet presentation.
    case pageSheet
    /// Form sheet presentation.
    case formSheet
    /// Presentation over the current full-screen context.
    case overFullScreen
}

/// Sheet detents (iOS 15 vocabulary), mapped to
/// `UISheetPresentationController.Detent` at presentation time.
public enum SheetDetent: Sendable, Equatable {
    /// Medium sheet height.
    case medium
    /// Large sheet height.
    case large
}

/// Configuration for `.present` transitions: modal style, optional sheet
/// detents, and animation.
///
/// ```swift
/// .present(PresentationConfig(style: .pageSheet, detents: [.medium, .large]))
/// ```
public struct PresentationConfig: Sendable, Equatable {
    public var style: ModalStyle
    /// When set (and the presented controller has a sheet), constrains the
    /// sheet to these detents.
    public var detents: [SheetDetent]?
    /// Whether the modal presentation is animated.
    public var animated: Bool

    /// Creates modal presentation configuration.
    public init(style: ModalStyle = .automatic, detents: [SheetDetent]? = nil, animated: Bool = true) {
        self.style = style
        self.detents = detents
        self.animated = animated
    }
}

/// Full custom control over how a resolved view controller enters the screen.
///
/// Used via `RouteTransition.custom(_:)`; the default performer hands you the
/// destination and the current top-most controller and gets out of the way.
@MainActor public protocol RouteTransitioning {
    /// Put `viewController` on screen however you like. `source` is the
    /// current top-most controller (nil when no window exists yet).
    func perform(_ viewController: PlatformViewController, from source: PlatformViewController?) throws
}

/// How a destination enters the screen.
///
/// Swift enums can't default their associated values, so each case has a
/// same-name static function with the conventional defaults: `.push()`,
/// `.present()`, `.replace()`, `.replaceRoot()`.
public enum RouteTransition {
    /// Push onto the nearest navigation controller.
    case push(animated: Bool)
    /// Present modally with the given configuration.
    case present(PresentationConfig)
    /// Swap the top of the current navigation stack (`history.replaceState` analog).
    case replace(animated: Bool)
    /// Swap the key window's root view controller.
    case replaceRoot(animated: Bool)
    /// Delegate entirely to a `RouteTransitioning` implementation.
    case custom(any RouteTransitioning)

    /// `.push(animated: true)`
    public static func push() -> RouteTransition { .push(animated: true) }
    /// `.present(PresentationConfig())`
    public static func present() -> RouteTransition { .present(PresentationConfig()) }
    /// `.replace(animated: true)`
    public static func replace() -> RouteTransition { .replace(animated: true) }
    /// `.replaceRoot(animated: false)`
    public static func replaceRoot() -> RouteTransition { .replaceRoot(animated: false) }
}

/// The concrete transition handed to `NavigationPerforming` after the
/// route's preferred/meta transition has been resolved.
public enum ResolvedTransition {
    /// Push onto a navigation controller.
    case push(animated: Bool)
    /// Present modally with concrete configuration.
    case present(PresentationConfig)
    /// Replace the top item of the current navigation stack.
    case replace(animated: Bool)
    /// Replace the key window's root view controller.
    case replaceRoot(animated: Bool)
    /// Run custom transition code.
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
