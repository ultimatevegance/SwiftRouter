public enum RouterError: Error, Equatable, Sendable {
    case notRegistered(routeType: String)
    case parameterMissing(name: String)
    case parameterTypeMismatch(name: String, expected: String, actual: String)
    case guardCancelled
    case redirectLoopDetected(depth: Int)
    case noNavigationContext
}
