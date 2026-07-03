import Foundation

/// Merged view of path placeholder values and URL query items.
/// Path values win on key collision.
public struct RouteParameters: Sendable, Equatable {
    private let values: [String: String]

    public init(pathValues: [String: String] = [:], queryValues: [String: String] = [:]) {
        values = queryValues.merging(pathValues) { _, path in path }
    }

    public var isEmpty: Bool { values.isEmpty }

    public func string(_ name: String) throws -> String {
        guard let raw = values[name] else { throw RouterError.parameterMissing(name: name) }
        return raw
    }

    public func int(_ name: String) throws -> Int { try convert(name, expected: "Int", Int.init) }
    public func double(_ name: String) throws -> Double { try convert(name, expected: "Double", Double.init) }
    public func bool(_ name: String) throws -> Bool { try convert(name, expected: "Bool", Self.parseBool) }
    public func uuid(_ name: String) throws -> UUID { try convert(name, expected: "UUID") { UUID(uuidString: $0) } }

    /// `IfPresent` variants return nil on missing OR mismatched values.
    public func stringIfPresent(_ name: String) -> String? { values[name] }
    public func intIfPresent(_ name: String) -> Int? { values[name].flatMap(Int.init) }
    public func doubleIfPresent(_ name: String) -> Double? { values[name].flatMap(Double.init) }
    public func boolIfPresent(_ name: String) -> Bool? { values[name].flatMap(Self.parseBool) }
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
