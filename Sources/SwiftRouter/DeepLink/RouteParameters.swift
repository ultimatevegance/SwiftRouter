import Foundation

/// Merged view of path placeholder values and URL query items.
/// Path values win on key collision.
///
/// Two accessor families:
/// - Throwing (`int`, `double`, `bool`, `uuid`, `string`) — for required
///   values; throw `RouterError.parameterMissing` / `.parameterTypeMismatch`.
/// - `…IfPresent` — for optional values (typically query items); return nil
///   on missing *or* mismatched values, never throw.
///
/// ```swift
/// init(parameters: RouteParameters) throws {
///     id = try parameters.int("id")               // required path placeholder
///     referrer = parameters.stringIfPresent("ref") // optional query item
/// }
/// ```
public struct RouteParameters: Sendable, Equatable {
    private let values: [String: String]

    /// Creates a merged parameter view. Path values take precedence over query
    /// values when both dictionaries contain the same key.
    public init(pathValues: [String: String] = [:], queryValues: [String: String] = [:]) {
        values = queryValues.merging(pathValues) { _, path in path }
    }

    /// Whether no path or query values are available.
    public var isEmpty: Bool { values.isEmpty }

    /// Returns a required string value.
    public func string(_ name: String) throws -> String {
        guard let raw = values[name] else { throw RouterError.parameterMissing(name: name) }
        return raw
    }

    /// Returns a required integer value.
    public func int(_ name: String) throws -> Int { try convert(name, expected: "Int", Int.init) }
    /// Returns a required floating-point value.
    public func double(_ name: String) throws -> Double { try convert(name, expected: "Double", Double.init) }
    /// Returns a required boolean value (`true` or `false`, case-insensitive).
    public func bool(_ name: String) throws -> Bool { try convert(name, expected: "Bool", Self.parseBool) }
    /// Returns a required UUID value.
    public func uuid(_ name: String) throws -> UUID { try convert(name, expected: "UUID") { UUID(uuidString: $0) } }

    /// `IfPresent` variants return nil on missing OR mismatched values.
    public func stringIfPresent(_ name: String) -> String? { values[name] }
    /// Returns an optional integer value.
    public func intIfPresent(_ name: String) -> Int? { values[name].flatMap(Int.init) }
    /// Returns an optional floating-point value.
    public func doubleIfPresent(_ name: String) -> Double? { values[name].flatMap(Double.init) }
    /// Returns an optional boolean value.
    public func boolIfPresent(_ name: String) -> Bool? { values[name].flatMap(Self.parseBool) }
    /// Returns an optional UUID value.
    public func uuidIfPresent(_ name: String) -> UUID? { values[name].flatMap { UUID(uuidString: $0) } }

    private func convert<T>(_ name: String, expected: String, _ transform: (String) -> T?) throws -> T {
        let raw = try string(name)
        guard let value = transform(raw) else {
            throw RouterError.parameterTypeMismatch(name: name, expected: expected, actual: raw)
        }
        return value
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }
}
