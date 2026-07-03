/// A route that external URLs can construct. Registering a `DeepLinkable`
/// automatically registers its pattern; `open(url:)` builds the typed route
/// via `init(parameters:)` and feeds it through the same pipeline — guards
/// and transitions apply identically.
public protocol DeepLinkable: Route {
    static var pattern: RoutePattern { get }
    init(parameters: RouteParameters) throws
}
