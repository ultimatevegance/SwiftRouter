import Testing
@testable import SwiftRouter

struct RoutePatternTests {
    @Test func parsesLiteralsAndScheme() throws {
        let pattern = try RoutePattern(parsing: "myapp://user/settings")
        #expect(pattern.scheme == "myapp")
        #expect(pattern.segments == [.literal("user"), .literal("settings")])
    }

    @Test func schemeIsLowercasedAndOptional() throws {
        #expect(try RoutePattern(parsing: "MyApp://a").scheme == "myapp")
        #expect(try RoutePattern(parsing: "user/<id>").scheme == nil)
        #expect(try RoutePattern(parsing: "/tabbar").scheme == nil)
    }

    @Test(arguments: [
        ("<int:id>", RoutePattern.Segment.placeholder(name: "id", type: .int)),
        ("<string:name>", .placeholder(name: "name", type: .string)),
        ("<double:lat>", .placeholder(name: "lat", type: .double)),
        ("<bool:flag>", .placeholder(name: "flag", type: .bool)),
        ("<uuid:token>", .placeholder(name: "token", type: .uuid)),
        ("<slug>", .placeholder(name: "slug", type: .string)),
        (":id", .placeholder(name: "id", type: .string)),
    ])
    func parsesPlaceholderSegments(raw: String, expected: RoutePattern.Segment) throws {
        let pattern = try RoutePattern(parsing: "x/\(raw)")
        #expect(pattern.segments == [.literal("x"), expected])
    }

    @Test func vueStylePathParses() throws {
        let pattern = try RoutePattern(parsing: "/novel/:id")
        #expect(pattern.scheme == nil)
        #expect(pattern.segments == [.literal("novel"), .placeholder(name: "id", type: .string)])
    }

    @Test func rejectsInvalidSyntax() {
        #expect(throws: RoutePattern.ParseError.emptyPattern) { try RoutePattern(parsing: "") }
        #expect(throws: RoutePattern.ParseError.unknownPlaceholderType("float", segment: "<float:x>")) {
            try RoutePattern(parsing: "a/<float:x>")
        }
        #expect(throws: RoutePattern.ParseError.emptyPlaceholder(segment: "<int:>")) {
            try RoutePattern(parsing: "a/<int:>")
        }
        #expect(throws: RoutePattern.ParseError.malformedSegment("<id")) { try RoutePattern(parsing: "a/<id") }
        #expect(throws: RoutePattern.ParseError.malformedSegment(":")) { try RoutePattern(parsing: "a/:") }
        #expect(throws: RoutePattern.ParseError.queryNotAllowed("a/b?x=1")) { try RoutePattern(parsing: "a/b?x=1") }
    }

    @Test func stringLiteralParsesValidPattern() {
        let pattern: RoutePattern = "myapp://user/<int:id>"
        #expect(pattern.scheme == "myapp")
        #expect(pattern.segments == [.literal("user"), .placeholder(name: "id", type: .int)])
    }

    @Test(arguments: [
        ("int", "42", true), ("int", "4.2", false),
        ("double", "4.2", true), ("double", "abc", false),
        ("bool", "TRUE", true), ("bool", "yes", false),
        ("uuid", "not-a-uuid", false),
        ("uuid", "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", true),
        ("string", "anything", true),
    ])
    func parameterTypeMatching(type: String, raw: String, expected: Bool) {
        #expect(RoutePattern.ParameterType(rawValue: type)?.matches(raw) == expected)
    }
}
