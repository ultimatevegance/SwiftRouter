import Testing
@testable import SwiftRouter

private struct UserDetail: Route { let id: Int }
private struct Other: Route {}

@MainActor
struct RouteRegistryTests {
    @Test func typeKeyedRegistrationAndLookup() throws {
        final class Marker: PlatformViewController {}
        let registry = RouteRegistry()
        registry.register(UserDetail.self, guards: []) { route, _ in
            #expect(route.id == 42)
            return Marker()
        }
        let entry = try #require(registry.entry(for: UserDetail.self))
        let vc = try entry.factory(UserDetail(id: 42), RoutingContext())
        #expect(vc is Marker)
        #expect(registry.entry(for: Other.self) == nil)
    }

    @Test func reRegistrationIsLastWins() throws {
        final class First: PlatformViewController {}
        final class Second: PlatformViewController {}
        let registry = RouteRegistry()
        registry.register(UserDetail.self, guards: []) { _, _ in First() }
        registry.register(UserDetail.self, guards: []) { _, _ in Second() }
        let entry = try #require(registry.entry(for: UserDetail.self))
        #expect(try entry.factory(UserDetail(id: 1), RoutingContext()) is Second)
    }

    @Test func perRouteGuardsAreStored() {
        struct AllowGuard: NavigationGuard {
            func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision { .allow }
        }
        let registry = RouteRegistry()
        registry.register(UserDetail.self, guards: [AllowGuard(), AllowGuard()]) { _, _ in PlatformViewController() }
        #expect(registry.entry(for: UserDetail.self)?.guards.count == 2)
    }
}

@MainActor
struct RouteTableTests {
    @Test func addIndexesByNameAndRegistersPattern() {
        let table = RouteTable()
        let matcher = URLMatcher()
        table.add(RouteRecord(name: "novel_detail", path: "/novel/:id") { _ in PlatformViewController() }, matcher: matcher)
        #expect(table.record(named: "novel_detail") != nil)
        #expect(table.record(named: "missing") == nil)
        let match = matcher.match(pathOrURL: "/novel/123")
        #expect(match?.target == .record(0))
        #expect(table.record(at: 0).name == "novel_detail")
    }

    @Test func recordContentKinds() {
        let component = RouteRecord(name: "a", path: "/a") { _ in PlatformViewController() }
        let action = RouteRecord(name: "b", path: "/b", action: { _ in true })
        let redirect = RouteRecord(name: "c", path: "/c", redirect: .path("/a"))
        guard case .component = component.content else { Issue.record("expected component"); return }
        guard case .action = action.content else { Issue.record("expected action"); return }
        guard case .redirect(let target) = redirect.content, case .path("/a") = target else {
            Issue.record("expected redirect(.path)"); return
        }
    }

    @Test func pathBuildingSubstitutesAndValidates() throws {
        let table = RouteTable()
        let matcher = URLMatcher()
        table.add(RouteRecord(name: "user", path: "myapp://user/<int:id>") { _ in PlatformViewController() }, matcher: matcher)
        let record = try #require(table.record(named: "user"))
        #expect(try table.path(for: record, params: ["id": "42"]) == "/user/42")
        #expect(throws: RouterError.parameterMissing(name: "id")) {
            try table.path(for: record, params: [:])
        }
        #expect(throws: RouterError.parameterTypeMismatch(name: "id", expected: "int", actual: "abc")) {
            try table.path(for: record, params: ["id": "abc"])
        }
    }

    @Test func duplicateNameIsLastWins() {
        final class Second: PlatformViewController {}
        let table = RouteTable()
        let matcher = URLMatcher()
        table.add(RouteRecord(name: "dup", path: "/one") { _ in PlatformViewController() }, matcher: matcher)
        table.add(RouteRecord(name: "dup", path: "/two") { _ in Second() }, matcher: matcher)
        guard case .component(let make) = table.record(named: "dup")!.content else {
            Issue.record("expected component"); return
        }
        let location = RouteLocation(name: "dup", path: "/two", params: [:], query: [:], context: nil,
                                     meta: RouteMeta(), url: nil, route: nil, parameters: nil)
        #expect(make(location) is Second)
    }
}
