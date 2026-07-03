import Foundation

/// A URL/path pattern such as `"myapp://user/<int:id>"` or `"/novel/:id"`.
public struct RoutePattern: Sendable, Equatable, ExpressibleByStringLiteral {
    public enum ParameterType: String, Sendable, Hashable {
        case int, string, double, bool, uuid
    }

    public enum Segment: Sendable, Equatable {
        case literal(String)
        case placeholder(name: String, type: ParameterType)
    }

    public enum ParseError: Error, Equatable {
        case emptyPattern
        case emptyPlaceholder(segment: String)
        case unknownPlaceholderType(String, segment: String)
        case malformedSegment(String)
        case queryNotAllowed(String)
    }

    /// nil means the pattern matches any scheme (including plain paths).
    public let scheme: String?
    public let segments: [Segment]

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
