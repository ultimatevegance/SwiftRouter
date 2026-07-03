/// A route that external URLs can construct.
///
/// Registering a `DeepLinkable` automatically registers its pattern;
/// `Router.open(_:)` builds the typed route via `init(parameters:)` and feeds
/// it through the same pipeline — guards and transitions apply identically.
///
/// ```swift
/// struct UserDetail: Route, DeepLinkable {
///     let id: Int
///     static let pattern: RoutePattern = "myapp://user/<int:id>"
///     init(parameters: RouteParameters) throws { id = try parameters.int("id") }
///     init(id: Int) { self.id = id }
/// }
///
/// // SceneDelegate:
/// router.open(url)   // constructs UserDetail(id:) when the URL matches
/// ```
public protocol DeepLinkable: Route {
    /// The URL/path shape that constructs this route. See `RoutePattern` for
    /// the placeholder syntax.
    static var pattern: RoutePattern { get }
    /// Builds the route from matched path placeholders and query items.
    /// Throw `RouterError.parameterMissing` / `.parameterTypeMismatch` (the
    /// typed accessors on `RouteParameters` do this for you) to reject a URL.
    init(parameters: RouteParameters) throws
}
