import Foundation

/// Handed to typed route factories during resolution.
@MainActor public struct RoutingContext {
    /// The external URL that triggered this navigation, when it came through `open(url:)`.
    public let url: URL?
    /// Parameters extracted from a deep link or dynamic path navigation.
    public let parameters: RouteParameters?

    init(url: URL? = nil, parameters: RouteParameters? = nil) {
        self.url = url
        self.parameters = parameters
    }
}
