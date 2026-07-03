import Foundation

/// A URL/path pattern such as `"myapp://user/<int:id>"` or `"/novel/:id"`.
///
/// Segment syntax:
/// - `user` — literal
/// - `:id` — colon placeholder (string-typed)
/// - `<int:id>`, `<string:name>`, `<double:lat>`, `<bool:flag>`, `<uuid:token>` — typed placeholders
/// - `<name>` — bare placeholder, defaults to string
///
/// A pattern with a scheme (`myapp://…`) matches only that scheme; without
/// one it matches any scheme and plain paths. The host counts as the first
/// segment (`myapp://user/42` → `user`, `42`). Matching precedence: literal
/// beats placeholder, compared segment by segment left to right.
///
/// Usually built from a string literal:
/// ```swift
/// static let pattern: RoutePattern = "myapp://user/<int:id>"
/// ```
public struct RoutePattern: Sendable, Equatable, ExpressibleByStringLiteral {
    /// Supported placeholder types in route patterns.
    public enum ParameterType: String, Sendable, Hashable {
        /// A signed integer segment.
        case int
        /// Any non-empty string segment.
        case string
        /// A floating-point segment.
        case double
        /// A boolean segment (`true` or `false`, case-insensitive).
        case bool
        /// A UUID segment.
        case uuid
    }

    /// One parsed path segment.
    public enum Segment: Sendable, Equatable {
        /// A literal segment that must match exactly.
        case literal(String)
        /// A captured segment validated against `type`.
        case placeholder(name: String, type: ParameterType)
    }

    /// Pattern parsing failures.
    public enum ParseError: Error, Equatable {
        /// The pattern contained no usable segments.
        case emptyPattern
        /// A placeholder segment such as `<>` or `<int:>` has no name.
        case emptyPlaceholder(segment: String)
        /// A typed placeholder used a type other than int, string, double,
        /// bool, or uuid.
        case unknownPlaceholderType(String, segment: String)
        /// The segment contains malformed placeholder syntax.
        case malformedSegment(String)
        /// Patterns describe only the path shape; query values are matched
        /// separately.
        case queryNotAllowed(String)
    }

    /// nil means the pattern matches any scheme (including plain paths).
    public let scheme: String?
    /// Parsed host/path segments. For URLs, the host is treated as the first
    /// segment.
    public let segments: [Segment]

    /// Parses and validates a route pattern string.
    public init(parsing pattern: String) throws {
        guard !pattern.isEmpty else { throw ParseError.emptyPattern }
        guard !pattern.contains("?") else { throw ParseError.queryNotAllowed(pattern) }
        var remainder = pattern[...]
        if let range = remainder.range(of: "://") {
            let schemePart = String(remainder[..<range.lowerBound])
            guard !schemePart.isEmpty else { throw ParseError.malformedSegment(pattern) }
            scheme = schemePart.lowercased()
            remainder = remainder[range.upperBound...]
        } else {
            scheme = nil
        }
        let rawSegments = remainder.split(separator: "/").map(String.init)
        guard !rawSegments.isEmpty else { throw ParseError.emptyPattern }
        segments = try rawSegments.map(Self.parseSegment)
    }

    /// Traps in debug on invalid syntax (programmer error, fail fast). In
    /// release, falls back to a single-literal pattern so behavior stays
    /// deterministic.
    public init(stringLiteral value: String) {
        do {
            self = try RoutePattern(parsing: value)
        } catch {
            assertionFailure("SwiftRouter: invalid route pattern '\(value)': \(error)")
            scheme = nil
            segments = [.literal(value)]
        }
    }

    private static func parseSegment(_ raw: String) throws -> Segment {
        if raw.hasPrefix(":") {
            let name = String(raw.dropFirst())
            guard !name.isEmpty, !name.contains(":") else { throw ParseError.malformedSegment(raw) }
            return .placeholder(name: name, type: .string)
        }
        if raw.hasPrefix("<") || raw.hasSuffix(">") {
            guard raw.hasPrefix("<"), raw.hasSuffix(">"), raw.count > 2 else {
                throw ParseError.malformedSegment(raw)
            }
            let inner = String(raw.dropFirst().dropLast())
            guard !inner.contains("<"), !inner.contains(">") else { throw ParseError.malformedSegment(raw) }
            let parts = inner.split(separator: ":", omittingEmptySubsequences: false)
            switch parts.count {
            case 1:
                let name = String(parts[0])
                guard !name.isEmpty else { throw ParseError.emptyPlaceholder(segment: raw) }
                return .placeholder(name: name, type: .string)
            case 2:
                let typeRaw = String(parts[0])
                let name = String(parts[1])
                guard !name.isEmpty else { throw ParseError.emptyPlaceholder(segment: raw) }
                guard let type = ParameterType(rawValue: typeRaw) else {
                    throw ParseError.unknownPlaceholderType(typeRaw, segment: raw)
                }
                return .placeholder(name: name, type: type)
            default:
                throw ParseError.malformedSegment(raw)
            }
        }
        guard !raw.contains("<"), !raw.contains(">") else { throw ParseError.malformedSegment(raw) }
        return .literal(raw)
    }
}

extension RoutePattern.ParameterType {
    /// Single source of truth for what raw text each placeholder type accepts.
    func matches(_ raw: String) -> Bool {
        switch self {
        case .string: true
        case .int: Int(raw) != nil
        case .double: Double(raw) != nil
        case .bool: ["true", "false"].contains(raw.lowercased())
        case .uuid: UUID(uuidString: raw) != nil
        }
    }
}
