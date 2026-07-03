import Foundation

/// Handed to typed route factories during resolution.
@MainActor public struct RoutingContext {
    /// The external URL that triggered this navigation, when it came through `open(url:)`.
    public let url: URL?
    /// Parameters extracted from a deep link or dynamic path navigation.
    public let parameters: RouteParameters?
    let resultChannel: ResultChannel?

    init(url: URL? = nil, parameters: RouteParameters? = nil, resultChannel: ResultChannel? = nil) {
        self.url = url
        self.parameters = parameters
        self.resultChannel = resultChannel
    }

    /// Complete a result-producing navigation: the awaited `present(forResult:)`
    /// resolves with `result` and the screen is dismissed. No-op when this
    /// navigation wasn't started with `present(forResult:)`.
    public func finish(_ result: any Sendable) {
        resultChannel?.resolve(result)
    }
}
