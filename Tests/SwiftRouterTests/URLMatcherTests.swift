import Foundation
import Testing
@testable import SwiftRouter

private struct TypeA {}

struct URLMatcherTests {
    private func target(_ index: Int) -> MatchTarget { .record(index) }

    @Test func matchesLiteralAndExtractsPlaceholders() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "myapp://user/<int:id>"), target: .routeType(ObjectIdentifier(TypeA.self)))
        let result = matcher.match(URL(string: "myapp://user/42?ref=email")!)
        #expect(result?.target == .routeType(ObjectIdentifier(TypeA.self)))
        #expect(result?.pathValues == ["id": "42"])
        #expect(result?.queryValues == ["ref": "email"])
        #expect(result?.path == "/user/42")
    }

    @Test func schemeRules() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "myapp://a/b"), target: target(0))
        matcher.register(try RoutePattern(parsing: "c/d"), target: target(1))
        #expect(matcher.match(URL(string: "myapp://a/b")!)?.target == target(0))
        #expect(matcher.match(URL(string: "other://a/b")!) == nil)
        #expect(matcher.match(URL(string: "any://c/d")!)?.target == target(1))
    }

    @Test func typeConstrainedPlaceholdersRejectMismatches() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "user/<int:id>"), target: target(0))
        #expect(matcher.match(URL(string: "myapp://user/abc")!) == nil)
        #expect(matcher.match(URL(string: "myapp://user/42/extra")!) == nil)
        #expect(matcher.match(URL(string: "myapp://user/42")!) != nil)
    }

    @Test func literalBeatsPlaceholder() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "user/<string:name>"), target: target(0))
        matcher.register(try RoutePattern(parsing: "user/settings"), target: target(1))
        #expect(matcher.match(URL(string: "myapp://user/settings")!)?.target == target(1))
        #expect(matcher.match(URL(string: "myapp://user/bob")!)?.target == target(0))
    }

    @Test func matchesPlainPathStrings() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "/novel/:id"), target: target(0))
        let result = matcher.match(pathOrURL: "/novel/123?from=home")
        #expect(result?.target == target(0))
        #expect(result?.pathValues == ["id": "123"])
        #expect(result?.queryValues == ["from": "home"])
        #expect(result?.path == "/novel/123")
    }

    @Test func firstQueryItemWinsOnDuplicates() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "a/<id>"), target: target(0))
        let result = matcher.match(URL(string: "myapp://a/1?ref=email&ref=push")!)
        #expect(result?.queryValues == ["ref": "email"])
    }

    @Test func conflictDetection() throws {
        let matcher = URLMatcher()
        matcher.register(try RoutePattern(parsing: "user/<int:id>"), target: target(0))
        // Overlapping placeholder types conflict.
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/<string:slug>")) != nil)
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/<double:x>")) != nil)
        // Disjoint placeholder types don't.
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/<uuid:token>")) == nil)
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/<bool:flag>")) == nil)
        // Literal vs placeholder is resolved by precedence, not a conflict.
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/settings")) == nil)
        // Different length / different literals don't conflict.
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "user/<int:id>/x")) == nil)
        #expect(matcher.firstConflict(with: try RoutePattern(parsing: "post/<int:id>")) == nil)
        // Scheme-disjoint patterns don't conflict; scheme-less overlaps everything.
        let schemed = URLMatcher()
        schemed.register(try RoutePattern(parsing: "myapp://a/<id>"), target: target(0))
        #expect(schemed.firstConflict(with: try RoutePattern(parsing: "other://a/<id>")) == nil)
        #expect(schemed.firstConflict(with: try RoutePattern(parsing: "a/<id>")) != nil)
    }

    @Test func noEntriesMeansNoMatch() {
        #expect(URLMatcher().match(URL(string: "myapp://a")!) == nil)
        #expect(URLMatcher().match(pathOrURL: "/a") == nil)
    }
}
