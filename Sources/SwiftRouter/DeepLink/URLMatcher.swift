import Foundation

enum MatchTarget: Equatable {
    case routeType(ObjectIdentifier)
    case record(Int)
}

struct URLMatchResult: Equatable {
    let pattern: RoutePattern
    let target: MatchTarget
    /// Concrete matched path (host + path segments), e.g. "/user/42". No query.
    let path: String
    let pathValues: [String: String]
    let queryValues: [String: String]
}

/// Pattern registry + matching engine. UIKit-free; owned by `Router` and
/// confined to the main actor through it.
final class URLMatcher {
    private struct Entry {
        let pattern: RoutePattern
        let target: MatchTarget
    }

    private var entries: [Entry] = []

    /// Traps in debug when `pattern` would be ambiguous with an existing
    /// registration; in release the first registration wins (the new one
    /// is ignored).
    func register(_ pattern: RoutePattern, target: MatchTarget) {
        if let existing = firstConflict(with: pattern) {
            assertionFailure("SwiftRouter: pattern \(pattern) conflicts with already-registered \(existing) — first registration wins.")
            return
        }
        entries.append(Entry(pattern: pattern, target: target))
    }

    func firstConflict(with pattern: RoutePattern) -> RoutePattern? {
        entries.first { Self.conflict($0.pattern, pattern) }?.pattern
    }

    func match(_ url: URL) -> URLMatchResult? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return match(components)
    }

    func match(pathOrURL: String) -> URLMatchResult? {
        guard let components = URLComponents(string: pathOrURL) else { return nil }
        return match(components)
    }

    private func match(_ components: URLComponents) -> URLMatchResult? {
        var segments: [String] = []
        if let host = components.host, !host.isEmpty { segments.append(host) }
        segments += components.path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return nil }
        let scheme = components.scheme?.lowercased()

        let candidates = entries.filter { Self.matches($0.pattern, scheme: scheme, segments: segments) }
        guard var best = candidates.first else { return nil }
        for candidate in candidates.dropFirst() where Self.beats(candidate.pattern, best.pattern) {
            best = candidate
        }

        var pathValues: [String: String] = [:]
        for (segment, raw) in zip(best.pattern.segments, segments) {
            if case .placeholder(let name, _) = segment { pathValues[name] = raw }
        }
        var queryValues: [String: String] = [:]
        for item in components.queryItems ?? [] where queryValues[item.name] == nil {
            queryValues[item.name] = item.value ?? ""
        }
        return URLMatchResult(
            pattern: best.pattern,
            target: best.target,
            path: "/" + segments.joined(separator: "/"),
            pathValues: pathValues,
            queryValues: queryValues
        )
    }

    private static func matches(_ pattern: RoutePattern, scheme: String?, segments: [String]) -> Bool {
        if let requiredScheme = pattern.scheme, requiredScheme != scheme { return false }
        guard pattern.segments.count == segments.count else { return false }
        return zip(pattern.segments, segments).allSatisfy { segment, raw in
            switch segment {
            case .literal(let text): text == raw
            case .placeholder(_, let type): type.matches(raw)
            }
        }
    }

    /// Segment-by-segment, left to right: literal beats placeholder.
    private static func beats(_ a: RoutePattern, _ b: RoutePattern) -> Bool {
        for (left, right) in zip(a.segments, b.segments) {
            switch (left, right) {
            case (.literal, .placeholder): return true
            case (.placeholder, .literal): return false
            default: continue
            }
        }
        return false
    }

    /// Two patterns conflict when some URL would match both and precedence
    /// cannot break the tie — same segment count, overlapping schemes, and
    /// every position pairing same-category segments that overlap.
    private static func conflict(_ a: RoutePattern, _ b: RoutePattern) -> Bool {
        guard a.segments.count == b.segments.count else { return false }
        if let schemeA = a.scheme, let schemeB = b.scheme, schemeA != schemeB { return false }
        for (left, right) in zip(a.segments, b.segments) {
            switch (left, right) {
            case (.literal(let l), .literal(let r)):
                if l != r { return false }
            case (.placeholder(_, let l), .placeholder(_, let r)):
                if !l.intersects(r) { return false }
            default:
                return false // literal vs placeholder — precedence resolves it
            }
        }
        return true
    }
}

extension RoutePattern.ParameterType {
    /// Whether two placeholder types can accept a common raw value.
    func intersects(_ other: Self) -> Bool {
        if self == other { return true }
        if self == .string || other == .string { return true }
        return Set([self, other]) == [.int, .double] // any int also parses as a double
    }
}
