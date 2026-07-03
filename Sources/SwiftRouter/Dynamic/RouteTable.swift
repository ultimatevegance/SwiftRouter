/// Storage and name index for dynamic route records.
@MainActor final class RouteTable {
    private(set) var records: [RouteRecord] = []
    private var nameIndex: [String: Int] = [:]

    func add(_ record: RouteRecord, matcher: URLMatcher) {
        let index = records.count
        records.append(record)
        if let name = record.name {
            if nameIndex[name] != nil {
                #if DEBUG
                print("SwiftRouter warning: route record named '\(name)' was already registered — replacing (last wins).")
                #endif
            }
            nameIndex[name] = index
        }
        matcher.register(record.pattern, target: .record(index))
    }

    func record(at index: Int) -> RouteRecord { records[index] }

    func record(named name: String) -> RouteRecord? {
        nameIndex[name].map { records[$0] }
    }

    /// Builds the concrete path for a record from `params`, validating
    /// placeholder types. E.g. "/novel/:id" + ["id": "123"] → "/novel/123".
    func path(for record: RouteRecord, params: [String: String]) throws -> String {
        var parts: [String] = []
        for segment in record.pattern.segments {
            switch segment {
            case .literal(let text):
                parts.append(text)
            case .placeholder(let name, let type):
                guard let value = params[name] else { throw RouterError.parameterMissing(name: name) }
                guard type.matches(value) else {
                    throw RouterError.parameterTypeMismatch(name: name, expected: type.rawValue, actual: value)
                }
                parts.append(value)
            }
        }
        return "/" + parts.joined(separator: "/")
    }
}
