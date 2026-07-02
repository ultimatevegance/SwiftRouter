# SwiftRouter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A dependency-free Swift Package providing type-safe routing for iOS with a vue-router-flavored dynamic layer (RouteRecord table, beforeEach guards, push/replace/back/switchTab, declarative redirects) on a shared engine.

**Architecture:** One engine — pattern matcher, guard pipeline, transition performer — with two public surfaces: typed routes (`Route` structs, `DeepLinkable`, `ResultRoute`) and dynamic string routes (`RouteRecord`, `RouteLocation`, name/path navigation). `Router` is `@MainActor`; UIKit-touching code is gated behind `#if canImport(UIKit)` with a `PlatformViewController` typealias seam so the full pipeline is testable via `swift test` on macOS with a spy performer.

**Tech Stack:** Swift 6 (strict concurrency), swift-tools 6.0, Swift Testing (`import Testing`), UIKit (gated), zero dependencies.

## Global Constraints

- `swift-tools-version: 6.0`; Swift 6 language mode (the tools-6.0 default — do not add language-mode settings).
- Platforms: `.iOS(.v15)` plus `.macOS(.v13)` (macOS exists **solely** so `swift test` runs the pure-logic suite; no AppKit support is claimed).
- Zero package dependencies. Test framework is Swift Testing, which ships with the toolchain.
- All UIKit-touching code behind `#if canImport(UIKit)`; everything else must compile and test on macOS.
- `Router` is `@MainActor`; `Route` values are `Sendable`; guards are `Sendable`; no locks anywhere.
- Redirect depth cap is exactly 8 (record redirects and guard redirects share the cap).
- Philosophy: programmer errors (bad pattern syntax, pattern conflicts) trap in debug; runtime conditions (unmatched URL, cancelled guard, no nav context) are recoverable errors or quiet no-ops on convenience paths.
- Commit after every task. Match repo commit style: plain imperative ("Add X"), ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- All commands run from the repo root `/Users/xiongyongjie/SwiftRouter`.

## Design clarifications (spec ambiguities resolved — binding for all tasks)

1. Swift enums cannot have default associated values, so `RouteTransition` pairs cases with same-name static funcs: `.push()` (animated), `.present()` (default config), `.replace()` (animated), `.replaceRoot()` (not animated).
2. `Route.preferredTransition` is a `@MainActor static` protocol requirement with a default in a protocol extension (needed for dynamic dispatch through `any Route`).
3. `NavigationGuard.check(to:from:)` is `@MainActor` and `async` — `RouteLocation` is not `Sendable` (it carries `context: Any?`), so the guard call must stay on the main actor; guards may still suspend internally.
4. Cross-platform seam: `public typealias PlatformViewController = UIViewController` on UIKit; a minimal `open class` elsewhere. On iOS all public signatures are exactly `UIViewController` as spec'd.
5. `NavigationPerforming` has four requirements: `perform`, `dismiss`, `back`, `switchTab` — the last three with default implementations so custom performers only need `perform`.
6. Re-registration (same route type, or duplicate record name): last-wins with a DEBUG `print` warning — **not** an assertion (spec: setups "don't trap"). Pattern conflicts and invalid pattern syntax DO trap via `assertionFailure` in debug; in release, invalid patterns fall back to a single-literal pattern and conflicting registrations are ignored (first wins).
7. `RouteParameters` optional accessors use the `IfPresent` suffix (`intIfPresent`) — same-name throwing/optional overloads are ambiguous in Swift. `IfPresent` variants return `nil` on missing OR mismatched values, never throw.
8. Unmatched URL/path/name on the async throwing APIs throws `RouterError.notRegistered(routeType:)` with the URL/path/name string — no new error case beyond the spec's enum.
9. `finish(_:)` with a wrong result type: `assertionFailure` in debug, resolves `nil` in release.
10. Guard-issued redirects re-run the full pipeline (guards included) for the new target with `transition` reset to nil (target's own meta/preferred transition applies). Record redirects resolve before guards (vue semantics).
11. `bool` values accept case-insensitive `"true"`/`"false"` only. URL schemes compare case-insensitively (lowercased at parse). Path segments are case-sensitive. First query item wins on duplicate keys within a URL; an explicit `query:` dict wins over inline `?k=v` duplicates.
12. `RouteLocation.path` is the concrete matched path (`"/novel/123"`), never including query.

## File map

| File | Task | Responsibility |
|---|---|---|
| `Package.swift` | 1 | tools 6.0, iOS 15 + macOS 13, single library + test target |
| `Sources/SwiftRouter/SwiftRouter.swift` | 1 | module doc header |
| `Sources/SwiftRouter/Core/PlatformViewController.swift` | 2 (mod 11) | UIViewController typealias / macOS stand-in |
| `Sources/SwiftRouter/Core/RouterError.swift` | 2 | error enum |
| `Sources/SwiftRouter/Transitions/RouteTransition.swift` | 2 | ModalStyle, SheetDetent, PresentationConfig, RouteTransitioning, RouteTransition, ResolvedTransition |
| `Sources/SwiftRouter/Core/Route.swift` | 2 | Route protocol + preferredTransition default |
| `Sources/SwiftRouter/DeepLink/RoutePattern.swift` | 3 | pattern parsing (`<int:id>` and `:id`), ParameterType matching |
| `Sources/SwiftRouter/DeepLink/RouteParameters.swift` | 4 | merged typed accessors |
| `Sources/SwiftRouter/DeepLink/URLMatcher.swift` | 5 | matching, precedence, conflicts (internal) |
| `Sources/SwiftRouter/Guards/NavigationGuard.swift` | 6 | GuardDecision, RedirectTarget, NavigationGuard |
| `Sources/SwiftRouter/Core/RouteLocation.swift` | 6 | RouteLocation, RouteMeta |
| `Sources/SwiftRouter/Core/RoutingContext.swift` | 6 (mod 11) | context handed to typed factories |
| `Sources/SwiftRouter/Core/RouteRegistry.swift` | 7 | typed type-keyed factory storage (internal) |
| `Sources/SwiftRouter/Dynamic/RouteRecord.swift` | 7 | RouteRecord + Content |
| `Sources/SwiftRouter/Dynamic/RouteTable.swift` | 7 | record storage, name index, path building (internal) |
| `Sources/SwiftRouter/Core/NavigationPerforming.swift` | 8 | performer seam protocol |
| `Sources/SwiftRouter/Core/Router.swift` | 8 (mod 9, 10, 11, 13) | Router class |
| `Sources/SwiftRouter/DeepLink/DeepLinkable.swift` | 10 | DeepLinkable protocol |
| `Sources/SwiftRouter/Results/ResultRoute.swift` | 11 | ResultRoute protocol |
| `Sources/SwiftRouter/Results/ResultChannel.swift` | 11 | continuation plumbing + dealloc sentinel |
| `Sources/SwiftRouter/Modules/RouteProvider.swift` | 12 | multi-module registration |
| `Sources/SwiftRouter/Core/DefaultNavigationPerformer.swift` | 13 | UIKit performer, top-most discovery, pin |
| `Tests/SwiftRouterTests/…` | each | one test file per task (named in tasks) |

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`, `Sources/SwiftRouter/SwiftRouter.swift`, `Tests/SwiftRouterTests/PackageTests.swift`, `.gitignore`

**Interfaces:**
- Produces: buildable/testable empty package named `SwiftRouter`.

- [ ] **Step 1: Verify toolchain** — Run: `swift --version`. Expected: Swift 6.0 or newer. If older, STOP and report.

- [ ] **Step 2: Write files**

`Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftRouter",
    platforms: [
        .iOS(.v15),
        // macOS exists solely so the pure-logic suite runs via `swift test`.
        .macOS(.v13),
    ],
    products: [
        .library(name: "SwiftRouter", targets: ["SwiftRouter"])
    ],
    targets: [
        .target(name: "SwiftRouter"),
        .testTarget(name: "SwiftRouterTests", dependencies: ["SwiftRouter"]),
    ]
)
```

`Sources/SwiftRouter/SwiftRouter.swift`:
```swift
// SwiftRouter — type-safe routing for iOS with a web-router-flavored dynamic layer.
```

`Tests/SwiftRouterTests/PackageTests.swift`:
```swift
import Testing
@testable import SwiftRouter

@Test func packageBuilds() {
    #expect(Bool(true))
}
```

`.gitignore`:
```
.build/
.swiftpm/
.DS_Store
xcuserdata/
```

- [ ] **Step 3: Run** `swift test`. Expected: `Test run with 1 test passed`.

- [ ] **Step 4: Commit** — `git add -A && git commit` — message: `Add package scaffold (tools 6.0, iOS 15)`

---

### Task 2: Core value types and Route protocol

**Files:**
- Create: `Sources/SwiftRouter/Core/PlatformViewController.swift`, `Sources/SwiftRouter/Core/RouterError.swift`, `Sources/SwiftRouter/Transitions/RouteTransition.swift`, `Sources/SwiftRouter/Core/Route.swift`
- Test: `Tests/SwiftRouterTests/CoreTypesTests.swift`

**Interfaces:**
- Produces: `PlatformViewController`; `RouterError` (Equatable); `ModalStyle`, `SheetDetent`, `PresentationConfig(style:detents:animated:)`, `RouteTransitioning.perform(_:from:)`, `RouteTransition` (cases `push(animated:)`, `present(_)`, `replace(animated:)`, `replaceRoot(animated:)`, `custom(_)` + static sugar `push()`, `present()`, `replace()`, `replaceRoot()`), `ResolvedTransition` (same 5 shapes), internal `RouteTransition.resolved`; `Route: Sendable` with `@MainActor static var preferredTransition` defaulting to `.push()`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/CoreTypesTests.swift`:
```swift
import Testing
@testable import SwiftRouter

@MainActor
struct CoreTypesTests {
    @Test func pushSugarDefaultsToAnimated() {
        guard case .push(let animated) = RouteTransition.push() else {
            Issue.record("expected .push"); return
        }
        #expect(animated == true)
    }

    @Test func replaceRootSugarDefaultsToNotAnimated() {
        guard case .replaceRoot(let animated) = RouteTransition.replaceRoot() else {
            Issue.record("expected .replaceRoot"); return
        }
        #expect(animated == false)
    }

    @Test func presentationConfigDefaults() {
        let config = PresentationConfig()
        #expect(config.style == .automatic)
        #expect(config.detents == nil)
        #expect(config.animated == true)
    }

    @Test func resolvedMirrorsTransition() {
        guard case .present(let config) = RouteTransition.present(PresentationConfig(style: .formSheet)).resolved else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .formSheet)
    }

    @Test func routeDefaultsToPushTransition() {
        struct Dummy: Route {}
        guard case .push(let animated) = Dummy.preferredTransition else {
            Issue.record("expected .push"); return
        }
        #expect(animated == true)
    }

    @Test func routeCanOverridePreferredTransition() {
        struct Sheet: Route {
            @MainActor static var preferredTransition: RouteTransition { .present(PresentationConfig(style: .pageSheet)) }
        }
        guard case .present(let config) = Sheet.preferredTransition else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .pageSheet)
    }

    @Test func routerErrorEquality() {
        #expect(RouterError.guardCancelled == RouterError.guardCancelled)
        #expect(RouterError.notRegistered(routeType: "A") != RouterError.notRegistered(routeType: "B"))
    }
}
```

- [ ] **Step 2: Run** `swift test` — Expected: FAIL (compile errors: cannot find `RouteTransition`, `Route`, etc.)

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Core/PlatformViewController.swift`:
```swift
#if canImport(UIKit)
import UIKit
/// The platform's view controller type — `UIViewController` on iOS.
public typealias PlatformViewController = UIViewController
#else
/// Minimal stand-in so the routing pipeline compiles and its tests run
/// via `swift test` on platforms without UIKit.
open class PlatformViewController {
    public init() {}
}
#endif
```

`Sources/SwiftRouter/Core/RouterError.swift`:
```swift
public enum RouterError: Error, Equatable, Sendable {
    case notRegistered(routeType: String)
    case parameterMissing(name: String)
    case parameterTypeMismatch(name: String, expected: String, actual: String)
    case guardCancelled
    case redirectLoopDetected(depth: Int)
    case noNavigationContext
}
```

`Sources/SwiftRouter/Transitions/RouteTransition.swift`:
```swift
public enum ModalStyle: Sendable, Equatable {
    case automatic, fullScreen, pageSheet, formSheet, overFullScreen
}

public enum SheetDetent: Sendable, Equatable {
    case medium, large
}

public struct PresentationConfig: Sendable, Equatable {
    public var style: ModalStyle
    public var detents: [SheetDetent]?
    public var animated: Bool

    public init(style: ModalStyle = .automatic, detents: [SheetDetent]? = nil, animated: Bool = true) {
        self.style = style
        self.detents = detents
        self.animated = animated
    }
}

/// Full custom control over how a resolved view controller enters the screen.
@MainActor public protocol RouteTransitioning {
    func perform(_ viewController: PlatformViewController, from source: PlatformViewController?) throws
}

public enum RouteTransition {
    case push(animated: Bool)
    case present(PresentationConfig)
    /// Swap the top of the current navigation stack (`history.replaceState` analog).
    case replace(animated: Bool)
    case replaceRoot(animated: Bool)
    case custom(any RouteTransitioning)

    public static func push() -> RouteTransition { .push(animated: true) }
    public static func present() -> RouteTransition { .present(PresentationConfig()) }
    public static func replace() -> RouteTransition { .replace(animated: true) }
    public static func replaceRoot() -> RouteTransition { .replaceRoot(animated: false) }
}

/// The concrete transition handed to `NavigationPerforming` after the
/// route's preferred/meta transition has been resolved.
public enum ResolvedTransition {
    case push(animated: Bool)
    case present(PresentationConfig)
    case replace(animated: Bool)
    case replaceRoot(animated: Bool)
    case custom(any RouteTransitioning)
}

extension RouteTransition {
    var resolved: ResolvedTransition {
        switch self {
        case .push(let animated): .push(animated: animated)
        case .present(let config): .present(config)
        case .replace(let animated): .replace(animated: animated)
        case .replaceRoot(let animated): .replaceRoot(animated: animated)
        case .custom(let transitioning): .custom(transitioning)
        }
    }
}
```

`Sources/SwiftRouter/Core/Route.swift`:
```swift
/// Marker protocol for navigable destinations. Routes are plain value types.
public protocol Route: Sendable {
    /// The transition `navigate(to:)` uses when no explicit `via:` is given.
    @MainActor static var preferredTransition: RouteTransition { get }
}

extension Route {
    @MainActor public static var preferredTransition: RouteTransition { .push() }
}
```

- [ ] **Step 4: Run** `swift test` — Expected: PASS (8 tests).

- [ ] **Step 5: Commit** — `Add core value types, errors, transitions, Route protocol`

---

### Task 3: RoutePattern parsing

**Files:**
- Create: `Sources/SwiftRouter/DeepLink/RoutePattern.swift`
- Test: `Tests/SwiftRouterTests/RoutePatternTests.swift`

**Interfaces:**
- Produces: `RoutePattern` (`Sendable, Equatable, ExpressibleByStringLiteral`) with `scheme: String?`, `segments: [Segment]`, `init(parsing:) throws`, nested `ParameterType` (`int|string|double|bool|uuid`, `Hashable`, internal `matches(_ raw: String) -> Bool`), nested `Segment` (`literal(String)` / `placeholder(name:type:)`), nested `ParseError` (Equatable).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/RoutePatternTests.swift`:
```swift
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
```

- [ ] **Step 2: Run** `swift test --filter RoutePatternTests` — Expected: FAIL (cannot find `RoutePattern`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/DeepLink/RoutePattern.swift`:
```swift
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
```

- [ ] **Step 4: Run** `swift test --filter RoutePatternTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add RoutePattern parsing with typed and vue-style placeholders`

---

### Task 4: RouteParameters

**Files:**
- Create: `Sources/SwiftRouter/DeepLink/RouteParameters.swift`
- Test: `Tests/SwiftRouterTests/RouteParametersTests.swift`

**Interfaces:**
- Consumes: `RouterError`.
- Produces: `RouteParameters(pathValues:queryValues:)` (`Sendable, Equatable`); throwing `string/int/double/bool/uuid(_ name:)`; non-throwing `stringIfPresent/intIfPresent/doubleIfPresent/boolIfPresent/uuidIfPresent(_ name:)`; `isEmpty`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/RouteParametersTests.swift`:
```swift
import Foundation
import Testing
@testable import SwiftRouter

struct RouteParametersTests {
    @Test func typedAccessorsConvert() throws {
        let uuid = UUID()
        let parameters = RouteParameters(pathValues: [
            "id": "42", "lat": "1.5", "flag": "TRUE", "token": uuid.uuidString, "slug": "hello",
        ])
        #expect(try parameters.int("id") == 42)
        #expect(try parameters.double("lat") == 1.5)
        #expect(try parameters.bool("flag") == true)
        #expect(try parameters.uuid("token") == uuid)
        #expect(try parameters.string("slug") == "hello")
    }

    @Test func missingParameterThrows() {
        let parameters = RouteParameters()
        #expect(throws: RouterError.parameterMissing(name: "id")) { try parameters.int("id") }
    }

    @Test func typeMismatchThrows() {
        let parameters = RouteParameters(pathValues: ["id": "abc"])
        #expect(throws: RouterError.parameterTypeMismatch(name: "id", expected: "Int", actual: "abc")) {
            try parameters.int("id")
        }
    }

    @Test func pathWinsOverQueryOnCollision() throws {
        let parameters = RouteParameters(pathValues: ["id": "7"], queryValues: ["id": "9", "ref": "email"])
        #expect(try parameters.int("id") == 7)
        #expect(parameters.stringIfPresent("ref") == "email")
    }

    @Test func ifPresentReturnsNilOnMissingOrMismatch() {
        let parameters = RouteParameters(pathValues: ["id": "abc"])
        #expect(parameters.intIfPresent("missing") == nil)
        #expect(parameters.intIfPresent("id") == nil)
        #expect(parameters.stringIfPresent("id") == "abc")
        #expect(parameters.boolIfPresent("id") == nil)
        #expect(parameters.doubleIfPresent("id") == nil)
        #expect(parameters.uuidIfPresent("id") == nil)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter RouteParametersTests` — Expected: FAIL (cannot find `RouteParameters`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/DeepLink/RouteParameters.swift`:
```swift
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
```

- [ ] **Step 4: Run** `swift test --filter RouteParametersTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add RouteParameters typed accessors`

---

### Task 5: URLMatcher

**Files:**
- Create: `Sources/SwiftRouter/DeepLink/URLMatcher.swift`
- Test: `Tests/SwiftRouterTests/URLMatcherTests.swift`

**Interfaces:**
- Consumes: `RoutePattern`, `ParameterType.matches`.
- Produces (all internal): `MatchTarget` enum (`routeType(ObjectIdentifier)` / `record(Int)`, Equatable); `URLMatchResult { pattern, target, path: String, pathValues: [String: String], queryValues: [String: String] }`; `URLMatcher` final class with `register(_ pattern:target:)`, `match(_ url: URL) -> URLMatchResult?`, `match(pathOrURL: String) -> URLMatchResult?`, `firstConflict(with:) -> RoutePattern?`.
- Matching: literal beats placeholder segment-by-segment left-to-right; ties impossible by construction (conflicts trapped at registration, first-wins in release). `URLMatchResult.path` is `"/" + matched segments joined` (host included), no query.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/URLMatcherTests.swift`:
```swift
import Foundation
import Testing
@testable import SwiftRouter

private struct TypeA {}
private struct TypeB {}

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
```

- [ ] **Step 2: Run** `swift test --filter URLMatcherTests` — Expected: FAIL (cannot find `URLMatcher`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/DeepLink/URLMatcher.swift`:
```swift
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
```

- [ ] **Step 4: Run** `swift test --filter URLMatcherTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add URLMatcher with precedence and conflict detection`

---

### Task 6: Locations, meta, guard types, routing context

**Files:**
- Create: `Sources/SwiftRouter/Core/RouteLocation.swift`, `Sources/SwiftRouter/Guards/NavigationGuard.swift`, `Sources/SwiftRouter/Core/RoutingContext.swift`
- Test: `Tests/SwiftRouterTests/GuardTypeTests.swift`

**Interfaces:**
- Consumes: `Route`, `RouteTransition`, `RouteParameters`.
- Produces:
  - `RouteMeta { transition: RouteTransition?, requiresAuth: Bool, tabIndex: Int?, userInfo: [String: Any] }` with memberwise-defaulted init.
  - `RouteLocation { name: String?, path: String, params: [String: String], query: [String: String], context: Any?, meta: RouteMeta, url: URL?, route: (any Route)? }` — public lets, internal init, plus internal `parameters: RouteParameters?`.
  - `RedirectTarget` enum: `.path(String)`, `.name(String, params: [String: String])`, `.route(any Route)` + static sugar `name(_:)` (empty params). `Sendable`.
  - `GuardDecision` enum: `.allow`, `.cancel`, `.redirect(RedirectTarget)`. `Sendable`.
  - `NavigationGuard: Sendable` protocol: `@MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision`.
  - `RoutingContext { url: URL?, parameters: RouteParameters? }` (`@MainActor` struct, internal init) — result plumbing added in Task 11.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/GuardTypeTests.swift`:
```swift
import Testing
@testable import SwiftRouter

@MainActor
struct GuardTypeTests {
    @Test func metaDefaults() {
        let meta = RouteMeta()
        #expect(meta.transition == nil)
        #expect(meta.requiresAuth == false)
        #expect(meta.tabIndex == nil)
        #expect(meta.userInfo.isEmpty)
    }

    @Test func redirectNameSugarUsesEmptyParams() {
        guard case .name(let name, let params) = RedirectTarget.name("login") else {
            Issue.record("expected .name"); return
        }
        #expect(name == "login")
        #expect(params.isEmpty)
    }

    @Test func closureGuardConformance() async {
        struct AllowAll: NavigationGuard {
            func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision { .allow }
        }
        let location = RouteLocation(name: "a", path: "/a", params: [:], query: [:], context: nil,
                                     meta: RouteMeta(), url: nil, route: nil, parameters: nil)
        let decision = await AllowAll().check(to: location, from: nil)
        guard case .allow = decision else { Issue.record("expected .allow"); return }
        #expect(location.context == nil)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter GuardTypeTests` — Expected: FAIL (cannot find `RouteMeta` etc.)

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Core/RouteLocation.swift`:
```swift
import Foundation

/// Route metadata. `requiresAuth` and `userInfo` are data for the app's own
/// guards; the router itself only interprets `transition` and `tabIndex`.
public struct RouteMeta {
    /// Transition used when the caller doesn't pass an explicit one. nil → `.push()`.
    public var transition: RouteTransition?
    public var requiresAuth: Bool
    /// Tab index selected by `switchTab(name:)` for this record.
    public var tabIndex: Int?
    public var userInfo: [String: Any]

    public init(transition: RouteTransition? = nil,
                requiresAuth: Bool = false,
                tabIndex: Int? = nil,
                userInfo: [String: Any] = [:]) {
        self.transition = transition
        self.requiresAuth = requiresAuth
        self.tabIndex = tabIndex
        self.userInfo = userInfo
    }
}

/// The resolved "where are we going" value handed to dynamic components,
/// actions, and navigation guards. Confined to the main actor via `Router`;
/// `context` may carry non-Sendable payloads (callbacks, model objects).
public struct RouteLocation {
    public let name: String?
    /// Concrete matched path, e.g. "/novel/123". Never includes query.
    public let path: String
    public let params: [String: String]
    public let query: [String: String]
    public let context: Any?
    public let meta: RouteMeta
    /// Non-nil when navigation came through `open(url:)`.
    public let url: URL?
    /// The typed route value when navigation began from the typed layer.
    public let route: (any Route)?
    let parameters: RouteParameters?

    init(name: String?, path: String, params: [String: String], query: [String: String],
         context: Any?, meta: RouteMeta, url: URL?, route: (any Route)?,
         parameters: RouteParameters?) {
        self.name = name
        self.path = path
        self.params = params
        self.query = query
        self.context = context
        self.meta = meta
        self.url = url
        self.route = route
        self.parameters = parameters
    }
}
```

`Sources/SwiftRouter/Guards/NavigationGuard.swift`:
```swift
/// Where a redirect decision or a redirect record sends the navigation.
public enum RedirectTarget: Sendable {
    case path(String)
    case name(String, params: [String: String])
    case route(any Route)

    public static func name(_ name: String) -> RedirectTarget { .name(name, params: [:]) }
}

public enum GuardDecision: Sendable {
    case allow
    case cancel
    case redirect(RedirectTarget)
}

/// Intercepts navigations, vue-router style. Global guards (`beforeEach` /
/// `addGuard`) run in registration order, then typed per-route guards.
public protocol NavigationGuard: Sendable {
    @MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision
}
```

`Sources/SwiftRouter/Core/RoutingContext.swift`:
```swift
import Foundation

/// Handed to typed route factories during resolution.
@MainActor public struct RoutingContext {
    /// The external URL that triggered this navigation, when it came through `open(url:)`.
    public let url: URL?
    /// Parameters extracted from a deep link or dynamic path navigation.
    public let parameters: RouteParameters?

    init(url: URL? = nil, parameters: RouteParameters? = nil) {
        self.url = url
        self.parameters = parameters
    }
}
```

- [ ] **Step 4: Run** `swift test --filter GuardTypeTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add route locations, meta, guard types, routing context`

---

### Task 7: Registries — typed RouteRegistry and dynamic RouteTable

**Files:**
- Create: `Sources/SwiftRouter/Core/RouteRegistry.swift`, `Sources/SwiftRouter/Dynamic/RouteRecord.swift`, `Sources/SwiftRouter/Dynamic/RouteTable.swift`
- Test: `Tests/SwiftRouterTests/RegistryTests.swift`

**Interfaces:**
- Consumes: `Route`, `RoutingContext`, `NavigationGuard`, `RouteLocation`, `RouteMeta`, `RedirectTarget`, `RoutePattern`, `URLMatcher`, `MatchTarget`, `RouterError`, `PlatformViewController`.
- Produces:
  - internal `RouteRegistry` (`@MainActor` final class): `register<R: Route>(_ type:guards:factory:)` (factory `@escaping @MainActor (R, RoutingContext) -> PlatformViewController`), `entry(for: any Route.Type) -> Entry?` where `Entry { factory: (any Route, RoutingContext) throws -> PlatformViewController, guards: [any NavigationGuard] }`. Re-registration: last-wins + DEBUG print.
  - public `RouteRecord`: `name: String?`, internal `pattern: RoutePattern`, `meta: RouteMeta`, internal `content: Content` enum (`component(@MainActor (RouteLocation) -> PlatformViewController)` / `action(@MainActor (RouteLocation) -> Bool)` / `redirect(RedirectTarget)`); three public inits `init(name:path:meta:component:)`, `init(name:path:meta:action:)`, `init(name:path:meta:redirect:)` (path is `String`, parsed with string-literal semantics: debug-trap on invalid, literal fallback in release).
  - internal `RouteTable` (`@MainActor` final class): `add(_ record:matcher:)` (appends, indexes name last-wins + DEBUG print on duplicate, registers pattern with `target: .record(index)`), `record(at: Int) -> RouteRecord`, `record(named: String) -> RouteRecord?`, `path(for record: RouteRecord, params: [String: String]) throws -> String` (substitutes placeholders; throws `parameterMissing` / `parameterTypeMismatch` when a placeholder is absent or fails its type's `matches`).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/RegistryTests.swift`:
```swift
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
```

- [ ] **Step 2: Run** `swift test --filter "RouteRegistryTests|RouteTableTests"` — Expected: FAIL (cannot find `RouteRegistry` / `RouteTable` / `RouteRecord`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Core/RouteRegistry.swift`:
```swift
/// Type-keyed factory storage for the typed layer.
@MainActor final class RouteRegistry {
    struct Entry {
        let factory: (any Route, RoutingContext) throws -> PlatformViewController
        let guards: [any NavigationGuard]
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func register<R: Route>(_ type: R.Type,
                            guards: [any NavigationGuard],
                            factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        let key = ObjectIdentifier(type)
        if entries[key] != nil {
            #if DEBUG
            print("SwiftRouter warning: factory for \(type) was already registered — replacing (last wins).")
            #endif
        }
        entries[key] = Entry(
            factory: { route, context in
                guard let typed = route as? R else {
                    throw RouterError.notRegistered(routeType: String(describing: Swift.type(of: route)))
                }
                return factory(typed, context)
            },
            guards: guards
        )
    }

    func entry(for routeType: any Route.Type) -> Entry? {
        entries[ObjectIdentifier(routeType)]
    }
}
```

`Sources/SwiftRouter/Dynamic/RouteRecord.swift`:
```swift
/// One row of the dynamic route table — vue-router's route record.
/// Exactly one of component / action / redirect, enforced by the initializers.
public struct RouteRecord {
    enum Content {
        case component(@MainActor (RouteLocation) -> PlatformViewController)
        case action(@MainActor (RouteLocation) -> Bool)
        case redirect(RedirectTarget)
    }

    public let name: String?
    public let meta: RouteMeta
    let pattern: RoutePattern
    let content: Content

    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                component: @escaping @MainActor (RouteLocation) -> PlatformViewController) {
        self.init(name: name, path: path, meta: meta, content: .component(component))
    }

    /// A handler route: runs after guards, performs no transition.
    /// Its Bool is the "handled" result.
    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                action: @escaping @MainActor (RouteLocation) -> Bool) {
        self.init(name: name, path: path, meta: meta, content: .action(action))
    }

    /// A declarative redirect, resolved before guards run (vue semantics).
    public init(name: String? = nil, path: String, meta: RouteMeta = RouteMeta(),
                redirect: RedirectTarget) {
        self.init(name: name, path: path, meta: meta, content: .redirect(redirect))
    }

    private init(name: String?, path: String, meta: RouteMeta, content: Content) {
        self.name = name
        self.meta = meta
        self.pattern = RoutePattern(stringLiteral: path)
        self.content = content
    }
}
```

`Sources/SwiftRouter/Dynamic/RouteTable.swift`:
```swift
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
```

- [ ] **Step 4: Run** `swift test --filter "RouteRegistryTests|RouteTableTests"` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add typed route registry and dynamic route table`

---

### Task 8: Router core — registration, resolution, performer seam

**Files:**
- Create: `Sources/SwiftRouter/Core/NavigationPerforming.swift`, `Sources/SwiftRouter/Core/Router.swift`
- Test: `Tests/SwiftRouterTests/TestSupport.swift`, `Tests/SwiftRouterTests/RouterResolutionTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `NavigationPerforming` (`@MainActor` protocol): `perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws`; `dismiss(_ viewController:animated:)`, `back(animated:) -> Bool`, `switchTab(index:) -> Bool` — the last three with protocol-extension defaults (UIKit dismiss / `false` / `false`).
  - `Router` (`@MainActor final class`): `static let shared`, `init(navigationPerformer: NavigationPerforming? = nil)` (defaults to internal `UnavailableNavigationPerformer` which throws `noNavigationContext` — Task 13 swaps in the UIKit default), `var navigationPerformer`, `register<R: Route>(_ type:guards:factory:)`, `viewController(for route:) throws -> PlatformViewController` (no guards, no transition — pure resolution), `addRoutes(_ records: [RouteRecord])`, internal `registry`, `routeTable`, `matcher`.
  - Test spy `SpyNavigationPerformer` (records `performed` / `dismissed` / `backCalls` / `switchTabCalls`, strongly retains VCs, `errorToThrow`, `removeAll()`).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/TestSupport.swift`:
```swift
@testable import SwiftRouter

@MainActor
final class SpyNavigationPerformer: NavigationPerforming {
    private(set) var performed: [(transition: ResolvedTransition, viewController: PlatformViewController)] = []
    private(set) var dismissed: [(viewController: PlatformViewController, animated: Bool)] = []
    private(set) var backCalls: [Bool] = []
    private(set) var switchTabCalls: [Int] = []
    var errorToThrow: Error?
    var backResult = true
    var switchTabResult = true

    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws {
        if let errorToThrow { throw errorToThrow }
        performed.append((transition, viewController))
    }

    func dismiss(_ viewController: PlatformViewController, animated: Bool) {
        dismissed.append((viewController, animated))
    }

    func back(animated: Bool) -> Bool {
        backCalls.append(animated)
        return backResult
    }

    func switchTab(index: Int) -> Bool {
        switchTabCalls.append(index)
        return switchTabResult
    }

    func removeAll() {
        performed.removeAll()
    }
}

/// Records the order guards ran in.
@MainActor
final class GuardLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

struct RecordingGuard: NavigationGuard {
    let name: String
    let log: GuardLog
    var decision: GuardDecision = .allow

    func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision {
        log.append(name)
        return decision
    }
}

/// Polls the main actor until `condition` is true (or ~1000 yields pass).
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1000 where !condition() {
        await Task.yield()
    }
}
```

`Tests/SwiftRouterTests/RouterResolutionTests.swift`:
```swift
import Testing
@testable import SwiftRouter

private struct UserDetail: Route { let id: Int }
private struct Unregistered: Route {}

@MainActor
struct RouterResolutionTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func resolvesRegisteredRoute() throws {
        final class UserVC: PlatformViewController { var id = 0 }
        router.register(UserDetail.self) { route, _ in
            let vc = UserVC(); vc.id = route.id; return vc
        }
        let vc = try router.viewController(for: UserDetail(id: 42))
        #expect((vc as? UserVC)?.id == 42)
    }

    @Test func unregisteredRouteThrows() {
        #expect(throws: RouterError.notRegistered(routeType: "Unregistered")) {
            try self.router.viewController(for: Unregistered())
        }
    }

    @Test func independentInstancesAreIsolated() {
        let other = Router(navigationPerformer: SpyNavigationPerformer())
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(throws: RouterError.self) { try other.viewController(for: UserDetail(id: 1)) }
    }

    @Test func sharedSingletonIsStable() {
        #expect(Router.shared === Router.shared)
    }

    @Test func defaultPerformerThrowsWithoutUIKitContext() {
        // On macOS (test host) the default performer has no navigation context.
        #if !canImport(UIKit)
        let bare = Router()
        bare.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(throws: RouterError.noNavigationContext) {
            try bare.navigationPerformer.perform(.push(animated: false), viewController: PlatformViewController())
        }
        #endif
    }

    @Test func addRoutesPopulatesTable() {
        router.addRoutes([
            RouteRecord(name: "tabbar", path: "/tabbar") { _ in PlatformViewController() },
            RouteRecord(name: "login", path: "/login") { _ in PlatformViewController() },
        ])
        #expect(router.routeTable.record(named: "tabbar") != nil)
        #expect(router.routeTable.record(named: "login") != nil)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter RouterResolutionTests` — Expected: FAIL (cannot find `Router` / `NavigationPerforming`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Core/NavigationPerforming.swift`:
```swift
/// Seam between the routing pipeline and actual UIKit navigation.
/// Apps can substitute custom containers; tests inject a spy. Only
/// `perform` is required — the rest have sensible defaults.
@MainActor public protocol NavigationPerforming {
    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws
    /// Dismiss a presented view controller (used when a result route finishes).
    func dismiss(_ viewController: PlatformViewController, animated: Bool)
    /// Pop or dismiss the current screen. Returns whether anything happened.
    @discardableResult func back(animated: Bool) -> Bool
    /// Select a tab by index. Returns whether a tab container was found.
    @discardableResult func switchTab(index: Int) -> Bool
}

extension NavigationPerforming {
    public func dismiss(_ viewController: PlatformViewController, animated: Bool) {
        #if canImport(UIKit)
        (viewController.presentingViewController ?? viewController).dismiss(animated: animated)
        #endif
    }

    @discardableResult public func back(animated: Bool) -> Bool { false }

    @discardableResult public func switchTab(index: Int) -> Bool { false }
}

/// Fallback performer for platforms (or setups) with no navigation container.
@MainActor struct UnavailableNavigationPerformer: NavigationPerforming {
    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws {
        throw RouterError.noNavigationContext
    }
}
```

`Sources/SwiftRouter/Core/Router.swift`:
```swift
import Foundation

@MainActor public final class Router {
    public static let shared = Router()

    let registry = RouteRegistry()
    let routeTable = RouteTable()
    let matcher = URLMatcher()

    /// Performs the actual UIKit transitions. Replaceable for testing or
    /// custom navigation containers.
    public var navigationPerformer: NavigationPerforming

    public init(navigationPerformer: NavigationPerforming? = nil) {
        self.navigationPerformer = navigationPerformer ?? Self.defaultPerformer()
    }

    private static func defaultPerformer() -> NavigationPerforming {
        // The UIKit task swaps this for DefaultNavigationPerformer on iOS.
        UnavailableNavigationPerformer()
    }

    // MARK: - Registration

    public func register<R: Route>(_ type: R.Type,
                                   guards: [any NavigationGuard] = [],
                                   factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        registry.register(type, guards: guards, factory: factory)
    }

    /// Register the dynamic route table — vue-router's `createRouter` routes array.
    public func addRoutes(_ records: [RouteRecord]) {
        for record in records {
            routeTable.add(record, matcher: matcher)
        }
    }

    // MARK: - Resolution

    /// Resolve a route to its view controller without navigating — no guards,
    /// no transition. For embedding, tabs, and tests.
    public func viewController(for route: some Route) throws -> PlatformViewController {
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        return try entry.factory(route, RoutingContext())
    }
}
```

- [ ] **Step 4: Run** `swift test --filter RouterResolutionTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add Router core with registration, resolution, performer seam`

---

### Task 9: Navigate pipeline — guards, redirects, verbs

**Files:**
- Modify: `Sources/SwiftRouter/Core/Router.swift` (add pipeline + verbs)
- Test: `Tests/SwiftRouterTests/NavigationPipelineTests.swift`

**Interfaces:**
- Produces on `Router`:
  - `addGuard(_ navigationGuard: any NavigationGuard)`; `beforeEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) async -> GuardDecision)` (wraps into internal `ClosureGuard`); `afterEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) -> Void)`.
  - `navigate(to route: some Route, via transition: RouteTransition? = nil) async throws` (typed, Void).
  - `@discardableResult navigate(name: String, params: [String: String] = [:], query: [String: String] = [:], context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool`.
  - `@discardableResult navigate(path: String, query: [String: String] = [:], context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool` (path may include inline `?k=v`; explicit `query` wins on duplicates; matches records AND typed deep-link patterns — the typed branch is completed in Task 10, so in this task the `.routeType` match arm throws `notRegistered`).
  - Fire-and-forget: `push(_ route: some Route, animated: Bool = true)`, `push(name:params:query:context:)`, `push(path:query:context:)`, `present(_ route: some Route, style: ModalStyle = .automatic, animated: Bool = true)`, `replace(name:params:query:context:)`, `replace(path:query:context:)` (both force `via: .replace()`), `@discardableResult back(animated: Bool = true) -> Bool`, `@discardableResult switchTab(name: String) -> Bool`.
  - `private(set) var currentLocation: RouteLocation?` — updated after each confirmed screen navigation; `from` for guards/hooks.
  - Internal: `ResolvedDestination { kind, location }` with `Kind` enum (`typed(RouteRegistry.Entry, any Route)` / `component(...)` / `action(...)` / `redirect(RedirectTarget)`); `navigateCore(_:transitionOverride:redirectDepth:) async throws -> Bool`; `resolve(_ target: RedirectTarget, context: Any?) throws -> ResolvedDestination`; `destination(path:query:context:) throws -> ResolvedDestination`; `maxRedirectDepth = 8`; `fireAndForget(_:)` helper (silent on `guardCancelled`, DEBUG-print other errors).
- Transition resolution order: explicit `via:` > `location.meta.transition` > typed `preferredTransition` > `.push()`. Guard redirects reset the override to nil.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/NavigationPipelineTests.swift`:
```swift
import Testing
@testable import SwiftRouter

private struct Basic: Route {}
private struct Target: Route {}
private struct SheetRoute: Route {
    @MainActor static var preferredTransition: RouteTransition { .present(PresentationConfig(style: .formSheet)) }
}

@MainActor
struct NavigationPipelineTests {
    let spy = SpyNavigationPerformer()
    let log = GuardLog()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func navigateUsesPreferredTransitionWhenViaIsNil() async throws {
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: SheetRoute())
        guard case .present(let config) = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
        #expect(config.style == .formSheet)
    }

    @Test func viaOverridesPreferredTransition() async throws {
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: SheetRoute(), via: .push(animated: false))
        guard case .push(false) = spy.performed.first?.transition else {
            Issue.record("expected .push(animated: false)"); return
        }
    }

    @Test func metaTransitionAppliesForRecords() async throws {
        router.addRoutes([
            RouteRecord(name: "login", path: "/login", meta: RouteMeta(transition: .present())) { _ in PlatformViewController() }
        ])
        let handled = try await router.navigate(name: "login")
        #expect(handled == true)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
    }

    @Test func globalThenPerRouteGuardOrder() async throws {
        router.addGuard(RecordingGuard(name: "global1", log: log))
        router.beforeEach { [log] _, _ in
            log.append("global2")
            return .allow
        }
        router.register(Basic.self, guards: [RecordingGuard(name: "perRoute", log: log)]) { _, _ in PlatformViewController() }
        try await router.navigate(to: Basic())
        #expect(log.entries == ["global1", "global2", "perRoute"])
        #expect(spy.performed.count == 1)
    }

    @Test func cancelThrowsAndBlocksNavigation() async {
        router.addGuard(RecordingGuard(name: "deny", log: log, decision: .cancel))
        router.register(Basic.self) { _, _ in PlatformViewController() }
        await #expect(throws: RouterError.guardCancelled) {
            try await self.router.navigate(to: Basic())
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func guardRedirectGoesToTargetWithItsPreferredTransition() async throws {
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.register(SheetRoute.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            to.route is Basic ? .redirect(.route(SheetRoute())) : .allow
        }
        try await router.navigate(to: Basic(), via: .push(animated: false))
        #expect(spy.performed.count == 1)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("redirect should use the target's preferred transition"); return
        }
    }

    @Test func redirectByNameAndPath() async throws {
        router.addRoutes([
            RouteRecord(name: "login", path: "/login") { _ in PlatformViewController() },
            RouteRecord(name: "detail", path: "/novel/:id") { _ in PlatformViewController() },
        ])
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.register(Target.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            if to.route is Basic { return .redirect(.name("login")) }
            if to.route is Target { return .redirect(.path("/novel/9")) }
            return .allow
        }
        try await router.navigate(to: Basic())
        try await router.navigate(to: Target())
        #expect(spy.performed.count == 2)
    }

    @Test func declarativeRecordRedirectResolvesBeforeGuards() async throws {
        router.addRoutes([
            RouteRecord(name: "old", path: "/old", redirect: .path("/new")),
            RouteRecord(name: "new", path: "/new") { _ in PlatformViewController() },
        ])
        router.beforeEach { [log] to, _ in
            log.append(to.path)
            return .allow
        }
        let handled = try await router.navigate(path: "/old")
        #expect(handled == true)
        #expect(log.entries == ["/new"]) // guards fired for the final destination only
        #expect(spy.performed.count == 1)
    }

    @Test func redirectLoopThrowsAtCap() async {
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.beforeEach { _, _ in .redirect(.route(Basic())) }
        await #expect(throws: RouterError.redirectLoopDetected(depth: 9)) {
            try await self.router.navigate(to: Basic())
        }
    }

    @Test func actionRecordRunsWithoutTransition() async throws {
        let actionLog = GuardLog()
        router.addRoutes([
            RouteRecord(name: "reading", path: "/reading", action: { [actionLog] location in
                actionLog.append(location.query["novel_id"] ?? "?")
                return true
            })
        ])
        let handled = try await router.navigate(path: "/reading?novel_id=1")
        #expect(handled == true)
        #expect(actionLog.entries == ["1"])
        #expect(spy.performed.isEmpty)
    }

    @Test func namedNavigationBuildsLocation() async throws {
        var captured: RouteLocation?
        router.addRoutes([
            RouteRecord(name: "novel_detail", path: "/novel/:id") { location in
                captured = location
                return PlatformViewController()
            }
        ])
        try await router.navigate(name: "novel_detail", params: ["id": "123"], query: ["from": "home"], context: "ctx")
        #expect(captured?.name == "novel_detail")
        #expect(captured?.path == "/novel/123")
        #expect(captured?.params["id"] == "123")
        #expect(captured?.query["from"] == "home")
        #expect(captured?.context as? String == "ctx")
    }

    @Test func unknownNameOrPathThrows() async {
        await #expect(throws: RouterError.notRegistered(routeType: "route named 'nope'")) {
            try await self.router.navigate(name: "nope")
        }
        await #expect(throws: RouterError.notRegistered(routeType: "/nope")) {
            try await self.router.navigate(path: "/nope")
        }
    }

    @Test func explicitQueryWinsOverInline() async throws {
        var captured: RouteLocation?
        router.addRoutes([
            RouteRecord(name: "a", path: "/a") { location in
                captured = location
                return PlatformViewController()
            }
        ])
        try await router.navigate(path: "/a?x=inline&y=keep", query: ["x": "explicit"])
        #expect(captured?.query == ["x": "explicit", "y": "keep"])
    }

    @Test func afterEachFiresWithFromLocation() async throws {
        let hookLog = GuardLog()
        router.addRoutes([
            RouteRecord(name: "a", path: "/a") { _ in PlatformViewController() },
            RouteRecord(name: "b", path: "/b") { _ in PlatformViewController() },
        ])
        router.afterEach { [hookLog] to, from in
            hookLog.append("\(from?.path ?? "nil")->\(to.path)")
        }
        try await router.navigate(path: "/a")
        try await router.navigate(path: "/b")
        #expect(hookLog.entries == ["nil->/a", "/a->/b"])
        #expect(router.currentLocation?.path == "/b")
    }

    @Test func pushConvenienceEventuallyPerforms() async {
        router.addRoutes([RouteRecord(name: "a", path: "/a") { _ in PlatformViewController() }])
        router.push(path: "/a")
        await waitUntil { !spy.performed.isEmpty }
        #expect(spy.performed.count == 1)
    }

    @Test func replaceConvenienceUsesReplaceTransition() async {
        router.addRoutes([RouteRecord(name: "tabbar", path: "/tabbar") { _ in PlatformViewController() }])
        router.replace(name: "tabbar")
        await waitUntil { !spy.performed.isEmpty }
        guard case .replace = spy.performed.first?.transition else {
            Issue.record("expected .replace"); return
        }
    }

    @Test func cancelledPushIsSilentlySwallowed() async {
        router.addGuard(RecordingGuard(name: "deny", log: log, decision: .cancel))
        router.register(Basic.self) { _, _ in PlatformViewController() }
        router.push(Basic())
        await waitUntil { !log.entries.isEmpty }
        for _ in 0..<50 { await Task.yield() }
        #expect(spy.performed.isEmpty)
    }

    @Test func backAndSwitchTabDelegateToPerformer() {
        router.addRoutes([
            RouteRecord(name: "me", path: "/me", meta: RouteMeta(tabIndex: 2)) { _ in PlatformViewController() },
            RouteRecord(name: "notab", path: "/notab") { _ in PlatformViewController() },
        ])
        #expect(router.back(animated: false) == true)
        #expect(spy.backCalls == [false])
        #expect(router.switchTab(name: "me") == true)
        #expect(spy.switchTabCalls == [2])
        #expect(router.switchTab(name: "notab") == false)   // no tabIndex in meta
        #expect(router.switchTab(name: "missing") == false) // unknown name
        #expect(spy.switchTabCalls == [2])
    }

    @Test func customTransitionReachesPerformer() async throws {
        @MainActor final class Recorder: RouteTransitioning {
            func perform(_ viewController: PlatformViewController, from source: PlatformViewController?) throws {}
        }
        let recorder = Recorder()
        router.register(Basic.self) { _, _ in PlatformViewController() }
        try await router.navigate(to: Basic(), via: .custom(recorder))
        guard case .custom(let transitioning) = spy.performed.first?.transition else {
            Issue.record("expected .custom"); return
        }
        #expect(transitioning as AnyObject === recorder)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter NavigationPipelineTests` — Expected: FAIL (no `navigate`, `addGuard`, etc.)

- [ ] **Step 3: Implement** — add to `Sources/SwiftRouter/Core/Router.swift`:

```swift
// MARK: - Guards

extension Router {
    public func addGuard(_ navigationGuard: any NavigationGuard) {
        beforeGuards.append(navigationGuard)
    }

    /// vue-router's `beforeEach`, Swift flavor: return a decision instead of
    /// calling `next(...)` — `.allow`, `.cancel`, or `.redirect(...)`.
    public func beforeEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) async -> GuardDecision) {
        addGuard(ClosureGuard(body: body))
    }

    /// Fires after every confirmed navigation (including handled actions).
    public func afterEach(_ body: @escaping @MainActor (RouteLocation, RouteLocation?) -> Void) {
        afterHooks.append(body)
    }
}

struct ClosureGuard: NavigationGuard {
    let body: @MainActor (RouteLocation, RouteLocation?) async -> GuardDecision

    @MainActor func check(to: RouteLocation, from: RouteLocation?) async -> GuardDecision {
        await body(to, from)
    }
}
```

Add stored properties to the `Router` class body:

```swift
    var beforeGuards: [any NavigationGuard] = []
    var afterHooks: [@MainActor (RouteLocation, RouteLocation?) -> Void] = []
    /// The last confirmed screen navigation — the `from` handed to guards.
    public private(set) var currentLocation: RouteLocation?
```

Add the pipeline (same file):

```swift
// MARK: - Navigation pipeline

extension Router {
    static let maxRedirectDepth = 8

    struct ResolvedDestination {
        enum Kind {
            case typed(RouteRegistry.Entry, any Route)
            case component(@MainActor (RouteLocation) -> PlatformViewController)
            case action(@MainActor (RouteLocation) -> Bool)
            case redirect(RedirectTarget)
        }

        let kind: Kind
        let location: RouteLocation
    }

    // MARK: Public verbs

    public func navigate(to route: some Route, via transition: RouteTransition? = nil) async throws {
        _ = try await navigateCore(try typedDestination(for: route), transitionOverride: transition, redirectDepth: 0)
    }

    @discardableResult
    public func navigate(name: String, params: [String: String] = [:], query: [String: String] = [:],
                         context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool {
        let destination = try namedDestination(name: name, params: params, query: query, context: context)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }

    @discardableResult
    public func navigate(path: String, query: [String: String] = [:],
                         context: Any? = nil, via transition: RouteTransition? = nil) async throws -> Bool {
        let destination = try pathDestination(path: path, query: query, context: context, url: nil)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }

    public func push(_ route: some Route, animated: Bool = true) {
        fireAndForget { try await self.navigate(to: route, via: .push(animated: animated)) }
    }

    public func present(_ route: some Route, style: ModalStyle = .automatic, animated: Bool = true) {
        fireAndForget {
            try await self.navigate(to: route, via: .present(PresentationConfig(style: style, animated: animated)))
        }
    }

    public func push(name: String, params: [String: String] = [:], query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(name: name, params: params, query: query, context: context) }
    }

    public func push(path: String, query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(path: path, query: query, context: context) }
    }

    public func replace(name: String, params: [String: String] = [:], query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(name: name, params: params, query: query, context: context, via: .replace()) }
    }

    public func replace(path: String, query: [String: String] = [:], context: Any? = nil) {
        fireAndForget { try await self.navigate(path: path, query: query, context: context, via: .replace()) }
    }

    /// Pop the navigation stack, else dismiss. Returns whether anything happened.
    @discardableResult
    public func back(animated: Bool = true) -> Bool {
        navigationPerformer.back(animated: animated)
    }

    /// Select the tab declared by the named record's `meta.tabIndex`.
    @discardableResult
    public func switchTab(name: String) -> Bool {
        guard let record = routeTable.record(named: name), let tabIndex = record.meta.tabIndex else { return false }
        return navigationPerformer.switchTab(index: tabIndex)
    }

    // MARK: Destination building

    func typedDestination(for route: any Route) throws -> ResolvedDestination {
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        let location = RouteLocation(name: String(describing: type(of: route)), path: "", params: [:], query: [:],
                                     context: nil, meta: RouteMeta(), url: nil, route: route, parameters: nil)
        return ResolvedDestination(kind: .typed(entry, route), location: location)
    }

    private func namedDestination(name: String, params: [String: String], query: [String: String],
                                  context: Any?) throws -> ResolvedDestination {
        guard let record = routeTable.record(named: name) else {
            throw RouterError.notRegistered(routeType: "route named '\(name)'")
        }
        let path = try routeTable.path(for: record, params: params)
        let location = RouteLocation(name: record.name, path: path, params: params, query: query,
                                     context: context, meta: record.meta, url: nil, route: nil,
                                     parameters: RouteParameters(pathValues: params, queryValues: query))
        return ResolvedDestination(kind: kind(of: record), location: location)
    }

    func pathDestination(path: String, query: [String: String], context: Any?, url: URL?) throws -> ResolvedDestination {
        guard let match = url.map({ matcher.match($0) }) ?? matcher.match(pathOrURL: path) else {
            throw RouterError.notRegistered(routeType: path)
        }
        let mergedQuery = match.queryValues.merging(query) { _, explicit in explicit }
        let parameters = RouteParameters(pathValues: match.pathValues, queryValues: mergedQuery)
        switch match.target {
        case .record(let index):
            let record = routeTable.record(at: index)
            let location = RouteLocation(name: record.name, path: match.path, params: match.pathValues,
                                         query: mergedQuery, context: context, meta: record.meta,
                                         url: url, route: nil, parameters: parameters)
            return ResolvedDestination(kind: kind(of: record), location: location)
        case .routeType(let id):
            return try deepLinkDestination(typeID: id, match: match, mergedQuery: mergedQuery,
                                           parameters: parameters, context: context, url: url)
        }
    }

    /// Typed deep-link construction — completed in the deep-link task.
    func deepLinkDestination(typeID: ObjectIdentifier, match: URLMatchResult, mergedQuery: [String: String],
                             parameters: RouteParameters, context: Any?, url: URL?) throws -> ResolvedDestination {
        throw RouterError.notRegistered(routeType: match.path)
    }

    private func kind(of record: RouteRecord) -> ResolvedDestination.Kind {
        switch record.content {
        case .component(let make): .component(make)
        case .action(let action): .action(action)
        case .redirect(let target): .redirect(target)
        }
    }

    private func resolve(_ target: RedirectTarget, context: Any?) throws -> ResolvedDestination {
        switch target {
        case .route(let route):
            return try typedDestination(for: route)
        case .name(let name, let params):
            return try namedDestination(name: name, params: params, query: [:], context: context)
        case .path(let path):
            return try pathDestination(path: path, query: [:], context: context, url: nil)
        }
    }

    // MARK: Core

    @discardableResult
    func navigateCore(_ destination: ResolvedDestination, transitionOverride: RouteTransition?,
                      redirectDepth: Int) async throws -> Bool {
        var destination = destination
        var depth = redirectDepth

        // Declarative record redirects resolve before guards (vue semantics).
        while case .redirect(let target) = destination.kind {
            depth += 1
            if depth > Self.maxRedirectDepth { throw RouterError.redirectLoopDetected(depth: depth) }
            destination = try resolve(target, context: destination.location.context)
        }

        let from = currentLocation
        let perRouteGuards: [any NavigationGuard] = if case .typed(let entry, _) = destination.kind { entry.guards } else { [] }
        for navigationGuard in beforeGuards + perRouteGuards {
            switch await navigationGuard.check(to: destination.location, from: from) {
            case .allow:
                continue
            case .cancel:
                throw RouterError.guardCancelled
            case .redirect(let target):
                if depth + 1 > Self.maxRedirectDepth { throw RouterError.redirectLoopDetected(depth: depth + 1) }
                let next = try resolve(target, context: destination.location.context)
                return try await navigateCore(next, transitionOverride: nil, redirectDepth: depth + 1)
            }
        }

        switch destination.kind {
        case .redirect:
            preconditionFailure("record redirects are resolved before guards")
        case .action(let action):
            let handled = action(destination.location)
            if handled { runAfterHooks(to: destination.location, from: from) }
            return handled
        case .component(let make):
            let viewController = make(destination.location)
            try performTransition(viewController, location: destination.location, from: from,
                                  transitionOverride: transitionOverride, preferred: nil)
            return true
        case .typed(let entry, let route):
            let context = RoutingContext(url: destination.location.url, parameters: destination.location.parameters)
            let viewController = try entry.factory(route, context)
            try performTransition(viewController, location: destination.location, from: from,
                                  transitionOverride: transitionOverride,
                                  preferred: type(of: route).preferredTransition)
            return true
        }
    }

    private func performTransition(_ viewController: PlatformViewController, location: RouteLocation,
                                   from: RouteLocation?, transitionOverride: RouteTransition?,
                                   preferred: RouteTransition?) throws {
        let transition = transitionOverride ?? location.meta.transition ?? preferred ?? .push()
        try navigationPerformer.perform(transition.resolved, viewController: viewController)
        currentLocation = location
        runAfterHooks(to: location, from: from)
    }

    private func runAfterHooks(to: RouteLocation, from: RouteLocation?) {
        for hook in afterHooks {
            hook(to, from)
        }
    }

    /// Convenience verbs swallow guard cancellations (a blocked navigation is
    /// not a crash) and surface real failures in DEBUG builds.
    private func fireAndForget(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch RouterError.guardCancelled {
                // Silent by design.
            } catch {
                #if DEBUG
                print("SwiftRouter: navigation failed — \(error)")
                #endif
            }
        }
    }
}
```

Note: `typed navigate` in this step uses `typedDestination`, so delete nothing from Task 8; `viewController(for:)` stays as is.

- [ ] **Step 4: Run** `swift test --filter NavigationPipelineTests` then full `swift test` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add navigate pipeline with beforeEach guards, redirects, web-router verbs`

---

### Task 10: Deep links — DeepLinkable and open(url:)

**Files:**
- Create: `Sources/SwiftRouter/DeepLink/DeepLinkable.swift`
- Modify: `Sources/SwiftRouter/Core/Router.swift`
- Test: `Tests/SwiftRouterTests/DeepLinkTests.swift`

**Interfaces:**
- Produces:
  - `public protocol DeepLinkable: Route { static var pattern: RoutePattern { get }; init(parameters: RouteParameters) throws }`.
  - `Router.register<R: DeepLinkable>(_ type:guards:factory:)` overload — also registers `R.pattern` with `matcher` (`target: .routeType(ObjectIdentifier(type))`) and stores `deepLinkFactories[id] = { try R(parameters: $0) }`.
  - `@discardableResult Router.open(_ url: URL) -> Bool` — synchronous match check, fire-and-forget navigation.
  - `@discardableResult Router.open(_ url: URL, via transition: RouteTransition? = nil) async throws -> Bool` — full pipeline; throws `notRegistered(routeType: url.absoluteString)` on no match.
  - Router stored property `var deepLinkFactories: [ObjectIdentifier: (RouteParameters) throws -> any Route] = [:]`; replace the Task 9 stub `deepLinkDestination` with a real implementation building a typed destination whose location carries url/params/query/route.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/DeepLinkTests.swift`:
```swift
import Foundation
import Testing
@testable import SwiftRouter

private struct UserDetail: Route, DeepLinkable {
    let id: Int
    static let pattern: RoutePattern = "myapp://user/<int:id>"
    init(parameters: RouteParameters) throws { id = try parameters.int("id") }
    init(id: Int) { self.id = id }
}

private struct StrictRoute: Route, DeepLinkable {
    let token: String
    static let pattern: RoutePattern = "myapp://strict/<int:id>"
    init(parameters: RouteParameters) throws { token = try parameters.string("token") }
}

@MainActor
struct DeepLinkTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func openConstructsTypedRouteThroughPipeline() async throws {
        var captured: (route: UserDetail, context: RoutingContext)?
        router.register(UserDetail.self) { route, context in
            captured = (route, context)
            return PlatformViewController()
        }
        let handled = try await router.open(URL(string: "myapp://user/42?ref=email")!)
        #expect(handled == true)
        #expect(captured?.route.id == 42)
        #expect(captured?.context.url?.absoluteString == "myapp://user/42?ref=email")
        #expect(captured?.context.parameters?.stringIfPresent("ref") == "email")
        #expect(spy.performed.count == 1)
    }

    @Test func syncOpenReturnsMatchAndNavigatesEventually() async {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        #expect(router.open(URL(string: "myapp://user/7")!) == true)
        #expect(router.open(URL(string: "myapp://user/abc")!) == false)
        #expect(router.open(URL(string: "myapp://nope")!) == false)
        await waitUntil { !spy.performed.isEmpty }
        #expect(spy.performed.count == 1)
    }

    @Test func guardsApplyToDeepLinks() async {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        router.beforeEach { to, _ in
            #expect(to.url != nil)
            #expect(to.route is UserDetail)
            #expect(to.params["id"] == "9")
            return .cancel
        }
        await #expect(throws: RouterError.guardCancelled) {
            try await self.router.open(URL(string: "myapp://user/9")!)
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func unmatchedURLThrowsOnAsyncOpen() async {
        await #expect(throws: RouterError.notRegistered(routeType: "myapp://nope")) {
            try await self.router.open(URL(string: "myapp://nope")!)
        }
    }

    @Test func initFailurePropagates() async {
        router.register(StrictRoute.self) { _, _ in PlatformViewController() }
        await #expect(throws: RouterError.parameterMissing(name: "token")) {
            try await self.router.open(URL(string: "myapp://strict/1")!)
        }
        let handled = try? await router.open(URL(string: "myapp://strict/1?token=abc")!)
        #expect(handled == true)
    }

    @Test func literalRecordBeatsTypedPlaceholderPattern() async throws {
        router.register(UserDetail.self) { _, _ in PlatformViewController() }
        var settingsHit = false
        router.addRoutes([
            RouteRecord(name: "user_settings", path: "myapp://user/settings") { _ in
                settingsHit = true
                return PlatformViewController()
            }
        ])
        _ = try await router.open(URL(string: "myapp://user/settings")!)
        #expect(settingsHit == true)
    }

    @Test func pathNavigationReachesTypedDeepLinkables() async throws {
        var captured: UserDetail?
        router.register(UserDetail.self) { route, _ in
            captured = route
            return PlatformViewController()
        }
        let handled = try await router.navigate(path: "myapp://user/5")
        #expect(handled == true)
        #expect(captured?.id == 5)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter DeepLinkTests` — Expected: FAIL (no `DeepLinkable`, no `open`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/DeepLink/DeepLinkable.swift`:
```swift
/// A route that external URLs can construct. Registering a `DeepLinkable`
/// automatically registers its pattern; `open(url:)` builds the typed route
/// via `init(parameters:)` and feeds it through the same pipeline — guards
/// and transitions apply identically.
public protocol DeepLinkable: Route {
    static var pattern: RoutePattern { get }
    init(parameters: RouteParameters) throws
}
```

In `Router.swift` — add stored property to the class body:
```swift
    var deepLinkFactories: [ObjectIdentifier: (RouteParameters) throws -> any Route] = [:]
```

Add the `DeepLinkable` registration overload next to `register`:
```swift
    public func register<R: DeepLinkable>(_ type: R.Type,
                                          guards: [any NavigationGuard] = [],
                                          factory: @escaping @MainActor (R, RoutingContext) -> PlatformViewController) {
        registry.register(type, guards: guards, factory: factory)
        matcher.register(R.pattern, target: .routeType(ObjectIdentifier(type)))
        deepLinkFactories[ObjectIdentifier(type)] = { parameters in try R(parameters: parameters) }
    }
```

Replace the Task 9 stub `deepLinkDestination` with:
```swift
    func deepLinkDestination(typeID: ObjectIdentifier, match: URLMatchResult, mergedQuery: [String: String],
                             parameters: RouteParameters, context: Any?, url: URL?) throws -> ResolvedDestination {
        guard let makeRoute = deepLinkFactories[typeID] else {
            throw RouterError.notRegistered(routeType: match.path)
        }
        let route = try makeRoute(parameters)
        guard let entry = registry.entry(for: type(of: route)) else {
            throw RouterError.notRegistered(routeType: String(describing: type(of: route)))
        }
        let location = RouteLocation(name: String(describing: type(of: route)), path: match.path,
                                     params: match.pathValues, query: mergedQuery, context: context,
                                     meta: RouteMeta(), url: url, route: route, parameters: parameters)
        return ResolvedDestination(kind: .typed(entry, route), location: location)
    }
```

Add the `open` APIs (new extension in `Router.swift`):
```swift
// MARK: - Deep links

extension Router {
    /// Synchronously reports whether `url` matches a registered pattern;
    /// the navigation itself runs fire-and-forget.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard matcher.match(url) != nil else { return false }
        // Type-construction or guard failures surface via fireAndForget's
        // DEBUG logging; the Bool only reports the match.
        fireAndForget { _ = try await self.open(url) }
        return true
    }

    /// Full-control variant: throws on no match, guard cancellation, or
    /// construction failure. Returns the action's Bool for action records.
    @discardableResult
    public func open(_ url: URL, via transition: RouteTransition? = nil) async throws -> Bool {
        guard matcher.match(url) != nil else {
            throw RouterError.notRegistered(routeType: url.absoluteString)
        }
        let destination = try pathDestination(path: url.absoluteString, query: [:], context: nil, url: url)
        return try await navigateCore(destination, transitionOverride: transition, redirectDepth: 0)
    }
}
```

Also make `fireAndForget` usable from the `open` extension: it is `private` in Task 9 — change its access to internal (`func fireAndForget`) when adding this task's code (same file, so `private` in an extension of the same type in the same file actually still works — leave it `private` if the compiler accepts; otherwise drop to internal).

One fix in `pathDestination` (Task 9 wrote a stub arm): it already routes `.routeType` matches through `deepLinkDestination`, and `URLMatchResult` matching for URL opens must use the URL (scheme host handling). Note the `url.map({ matcher.match($0) })` line returns `URLMatchResult??` — flatten it:
```swift
        let matched: URLMatchResult? = if let url { matcher.match(url) } else { matcher.match(pathOrURL: path) }
        guard let match = matched else { throw RouterError.notRegistered(routeType: path) }
```
Use this exact form in `pathDestination` (replace the Task 9 guard).

- [ ] **Step 4: Run** full `swift test` — Expected: PASS (all suites).

- [ ] **Step 5: Commit** — `Add deep-link layer with DeepLinkable and open(url:)`

---

### Task 11: Route results

**Files:**
- Create: `Sources/SwiftRouter/Results/ResultRoute.swift`, `Sources/SwiftRouter/Results/ResultChannel.swift`
- Modify: `Sources/SwiftRouter/Core/RoutingContext.swift` (add `resultChannel` + `finish`), `Sources/SwiftRouter/Core/Router.swift` (add `present(forResult:)`, thread channel through `navigateCore`/`performTransition`), `Sources/SwiftRouter/Core/PlatformViewController.swift` (non-UIKit: add internal `_swiftRouterResultSentinel: AnyObject?`)
- Test: `Tests/SwiftRouterTests/RouteResultTests.swift`

**Interfaces:**
- Produces:
  - `public protocol ResultRoute: Route { associatedtype Result: Sendable }`.
  - `Router.present<R: ResultRoute>(forResult route: R, config: PresentationConfig = PresentationConfig()) async throws -> R.Result?` — nil when dismissed/deallocated without finishing.
  - `RoutingContext.finish(_ result: any Sendable)` — resolves the channel; no-op when the navigation wasn't started with `present(forResult:)`.
  - internal `ResultChannel` (`@MainActor` final class): `attach(_ continuation:)`, `resolve(_ value: (any Sendable)?)` (idempotent; fires `onResolve` hook once), `onResolve: (@MainActor () -> Void)?`; handles resolve-before-attach via a pending value.
  - internal `DeallocSentinel` — associated with the presented VC (associated object on UIKit; stored property on the macOS stand-in); its `deinit` resolves the channel with nil via `MainActor.assumeIsolated` (VCs deallocate on the main thread).
  - `navigateCore(_:transitionOverride:redirectDepth:resultChannel: ResultChannel? = nil)` — channel flows into `RoutingContext` for typed factories and through redirects; after a successful perform with a channel: set `onResolve` to dismiss via the performer (weak VC), bind the sentinel.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/RouteResultTests.swift`:
```swift
import Testing
@testable import SwiftRouter

private struct ColorPicker: ResultRoute {
    typealias Result = String
}

@MainActor
struct RouteResultTests {
    let spy = SpyNavigationPerformer()
    let router: Router

    init() {
        router = Router(navigationPerformer: spy)
    }

    @Test func finishResolvesResultAndDismisses() async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        captured?.finish("red")
        let value = try await task.value
        #expect(value == "red")
        #expect(spy.dismissed.count == 1)
        guard case .present = spy.performed.first?.transition else {
            Issue.record("expected .present"); return
        }
    }

    @Test func secondFinishIsIgnored()  async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        captured?.finish("red")
        captured?.finish("blue")
        let value = try await task.value
        #expect(value == "red")
        #expect(spy.dismissed.count == 1)
    }

    @Test func deallocationWithoutFinishResolvesNil() async throws {
        var captured: RoutingContext?
        router.register(ColorPicker.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        let task = Task { try await router.present(forResult: ColorPicker()) }
        await waitUntil { captured != nil }
        spy.removeAll() // drop the only strong reference to the presented VC
        let value = try await task.value
        #expect(value == nil)
        #expect(spy.dismissed.isEmpty)
    }

    @Test func guardCancellationThrowsBeforePresenting() async {
        router.register(ColorPicker.self) { _, _ in PlatformViewController() }
        router.beforeEach { _, _ in .cancel }
        await #expect(throws: RouterError.guardCancelled) {
            _ = try await self.router.present(forResult: ColorPicker())
        }
        #expect(spy.performed.isEmpty)
    }

    @Test func finishIsNoOpForPlainNavigations() async throws {
        struct Plain: Route {}
        var captured: RoutingContext?
        router.register(Plain.self) { _, context in
            captured = context
            return PlatformViewController()
        }
        try await router.navigate(to: Plain())
        captured?.finish("ignored") // must not crash or dismiss
        #expect(spy.dismissed.isEmpty)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter RouteResultTests` — Expected: FAIL (no `ResultRoute` / `present(forResult:)`).

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Results/ResultRoute.swift`:
```swift
/// A route whose presented screen produces a value. `present(forResult:)`
/// suspends until the screen calls `context.finish(_:)` (→ the value) or is
/// dismissed/deallocated without finishing (→ nil — cancellation is not an error).
public protocol ResultRoute: Route {
    associatedtype Result: Sendable
}
```

`Sources/SwiftRouter/Results/ResultChannel.swift`:
```swift
#if canImport(UIKit)
import ObjectiveC
import UIKit
#endif

/// One-shot channel connecting a presented screen's `finish` back to the
/// `present(forResult:)` continuation. Always completes: `finish` resolves
/// the value; the dealloc sentinel resolves nil.
@MainActor final class ResultChannel {
    private var continuation: CheckedContinuation<(any Sendable)?, Never>?
    private var pendingValue: (any Sendable)??
    private var isResolved = false
    /// Dismissal hook installed by the router after presentation.
    var onResolve: (@MainActor () -> Void)?

    func attach(_ continuation: CheckedContinuation<(any Sendable)?, Never>) {
        if let pendingValue {
            continuation.resume(returning: pendingValue)
            return
        }
        self.continuation = continuation
    }

    func resolve(_ value: (any Sendable)?) {
        guard !isResolved else { return }
        isResolved = true
        if let continuation {
            continuation.resume(returning: value)
            self.continuation = nil
        } else {
            pendingValue = value
        }
        onResolve?()
        onResolve = nil
    }
}

/// Rides along on the presented view controller; when the screen deallocates
/// without finishing, resolves the channel with nil. View controllers
/// deallocate on the main thread, so `assumeIsolated` is sound.
final class DeallocSentinel {
    private let channel: @Sendable () -> ResultChannel?

    @MainActor init(channel: ResultChannel) {
        self.channel = { [weak channel] in channel }
    }

    deinit {
        let channel = channel
        MainActor.assumeIsolated {
            channel()?.resolve(nil)
        }
    }
}

#if canImport(UIKit)
private nonisolated(unsafe) var sentinelKey: UInt8 = 0

@MainActor func bindDeallocSignal(from viewController: PlatformViewController, to channel: ResultChannel) {
    objc_setAssociatedObject(viewController, &sentinelKey, DeallocSentinel(channel: channel), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
#else
@MainActor func bindDeallocSignal(from viewController: PlatformViewController, to channel: ResultChannel) {
    viewController._swiftRouterResultSentinel = DeallocSentinel(channel: channel)
}
#endif
```

Note for the implementer: if the compiler rejects `MainActor.assumeIsolated` from `deinit` capture wiring, the fallback is to make `DeallocSentinel`'s stored closure `let onDeinit: @Sendable () -> Void` built at init time on the main actor; the shape above should compile as written.

Modify `Sources/SwiftRouter/Core/PlatformViewController.swift` — non-UIKit branch only:
```swift
#else
/// Minimal stand-in so the routing pipeline compiles and its tests run
/// via `swift test` on platforms without UIKit.
open class PlatformViewController {
    /// Retains the result-route dealloc sentinel (associated object on UIKit).
    var _swiftRouterResultSentinel: AnyObject?

    public init() {}
}
#endif
```

Modify `Sources/SwiftRouter/Core/RoutingContext.swift`:
```swift
@MainActor public struct RoutingContext {
    public let url: URL?
    public let parameters: RouteParameters?
    let resultChannel: ResultChannel?

    init(url: URL? = nil, parameters: RouteParameters? = nil, resultChannel: ResultChannel? = nil) {
        self.url = url
        self.parameters = parameters
        self.resultChannel = resultChannel
    }

    /// Complete a result-producing navigation: the awaited `present(forResult:)`
    /// resolves with `result` and the screen is dismissed. No-op when this
    /// navigation wasn't started with `present(forResult:)`.
    public func finish(_ result: any Sendable) {
        resultChannel?.resolve(result)
    }
}
```

Modify `Router.swift`:
1. `navigateCore` gains `resultChannel: ResultChannel? = nil`; pass it through guard-redirect recursion; in the `.typed` arm build `RoutingContext(url:parameters:resultChannel:)`; pass the channel to `performTransition`.
2. `performTransition` gains `resultChannel: ResultChannel?`; after a successful `perform` and before `currentLocation` update:
```swift
        if let resultChannel {
            let performer = navigationPerformer
            let animated: Bool = if case .present(let config) = transition.resolved { config.animated } else { true }
            resultChannel.onResolve = { [weak viewController] in
                guard let viewController else { return }
                performer.dismiss(viewController, animated: animated)
            }
            bindDeallocSignal(from: viewController, to: resultChannel)
        }
```
(Compute `transition` once into a local before this block: `let resolved = transition.resolved` used for both `perform` and the animated check.)
3. Add the public API:
```swift
// MARK: - Route results

extension Router {
    /// Present a screen and suspend until it finishes with a value or is
    /// dismissed (→ nil). The factory's `RoutingContext` carries the
    /// `finish(_:)` handle.
    public func present<R: ResultRoute>(forResult route: R,
                                        config: PresentationConfig = PresentationConfig()) async throws -> R.Result? {
        let channel = ResultChannel()
        // Deliberately not holding the returned view controller here: its
        // only strong owners must be the presentation hierarchy, so the
        // dealloc sentinel can fire when the screen goes away.
        _ = try await navigateCore(try typedDestination(for: route), transitionOverride: .present(config),
                                   redirectDepth: 0, resultChannel: channel)
        let raw = await withCheckedContinuation { channel.attach($0) }
        guard let raw else { return nil }
        guard let typed = raw as? R.Result else {
            assertionFailure("SwiftRouter: finish(_:) called with \(type(of: raw)), expected \(R.Result.self)")
            return nil
        }
        return typed
    }
}
```

- [ ] **Step 4: Run** full `swift test` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add route results with continuation-backed present(forResult:)`

---

### Task 12: Multi-module route providers

**Files:**
- Create: `Sources/SwiftRouter/Modules/RouteProvider.swift`
- Test: `Tests/SwiftRouterTests/RouteProviderTests.swift`

**Interfaces:**
- Produces: `public protocol RouteProvider { @MainActor func registerRoutes(in router: Router) }`; `Router.install(_ provider: some RouteProvider)`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftRouterTests/RouteProviderTests.swift`:
```swift
import Testing
@testable import SwiftRouter

private struct FeatureRoute: Route {}

private struct FeatureModule: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(FeatureRoute.self) { _, _ in PlatformViewController() }
        router.addRoutes([RouteRecord(name: "feature_home", path: "/feature") { _ in PlatformViewController() }])
    }
}

@MainActor
struct RouteProviderTests {
    @Test func installRegistersModuleRoutes() async throws {
        let spy = SpyNavigationPerformer()
        let router = Router(navigationPerformer: spy)
        router.install(FeatureModule())
        try await router.navigate(to: FeatureRoute())
        _ = try await router.navigate(path: "/feature")
        #expect(spy.performed.count == 2)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter RouteProviderTests` — Expected: FAIL.

- [ ] **Step 3: Implement**

`Sources/SwiftRouter/Modules/RouteProvider.swift`:
```swift
/// Feature modules implement this to register their routes. Modules depend
/// only on SwiftRouter, never on each other — cross-feature navigation goes
/// through shared route declarations or URLs/paths.
public protocol RouteProvider {
    @MainActor func registerRoutes(in router: Router)
}

extension Router {
    /// Install a feature module's routes.
    public func install(_ provider: some RouteProvider) {
        provider.registerRoutes(in: self)
    }
}
```

- [ ] **Step 4: Run** `swift test --filter RouteProviderTests` — Expected: PASS.

- [ ] **Step 5: Commit** — `Add multi-module route providers`

---

### Task 13: UIKit default navigation performer

**Files:**
- Create: `Sources/SwiftRouter/Core/DefaultNavigationPerformer.swift`
- Modify: `Sources/SwiftRouter/Core/Router.swift` (`defaultPerformer()` returns `DefaultNavigationPerformer()` under UIKit)

**Interfaces:**
- Produces (all `#if canImport(UIKit)`):
  - `DefaultNavigationPerformer` (`@MainActor public final class`, `NavigationPerforming`): `init(pinnedNavigationController: UINavigationController? = nil)` (held weakly); `perform` handling all 5 transitions; `dismiss`; `back(animated:)` (pop if stack > 1, else dismiss presented, else false); `switchTab(index:)` (find first `UITabBarController` walking down from key-window root through presented/nav containers; guard index bounds); static `keyWindow()` (connected scenes → key window), `topMostViewController()` (root → presented chain → nav visible → tab selected), `apply(_ config:to:)` (modal style + iOS 15 detents mapping).
  - `ModalStyle.uiKit: UIModalPresentationStyle` mapping.
  - `Router.pin(to navigationController: UINavigationController)` — swaps performer for a pinned one.

- [ ] **Step 1: Implement** (UIKit-gated code can't run under `swift test`; simulator tests are Task 14 — build verification is this task's test)

`Sources/SwiftRouter/Core/DefaultNavigationPerformer.swift`:
```swift
#if canImport(UIKit)
import UIKit

/// Default UIKit performer: discovers the top-most view controller from the
/// key window (walking presented VCs and nav/tab containers), or uses a
/// pinned navigation controller.
@MainActor public final class DefaultNavigationPerformer: NavigationPerforming {
    private weak var pinnedNavigationController: UINavigationController?

    public init(pinnedNavigationController: UINavigationController? = nil) {
        self.pinnedNavigationController = pinnedNavigationController
    }

    public func perform(_ transition: ResolvedTransition, viewController: UIViewController) throws {
        switch transition {
        case .push(let animated):
            guard let navigationController = pushTarget() else { throw RouterError.noNavigationContext }
            navigationController.pushViewController(viewController, animated: animated)
        case .present(let config):
            guard let presenter = presentTarget() else { throw RouterError.noNavigationContext }
            Self.apply(config, to: viewController)
            presenter.present(viewController, animated: config.animated)
        case .replace(let animated):
            guard let navigationController = pushTarget() else { throw RouterError.noNavigationContext }
            var stack = navigationController.viewControllers
            if stack.isEmpty {
                stack = [viewController]
            } else {
                stack[stack.count - 1] = viewController
            }
            navigationController.setViewControllers(stack, animated: animated)
        case .replaceRoot(let animated):
            guard let window = Self.keyWindow() else { throw RouterError.noNavigationContext }
            window.rootViewController = viewController
            if animated {
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
            }
        case .custom(let transitioning):
            try transitioning.perform(viewController, from: presentTarget())
        }
    }

    public func dismiss(_ viewController: UIViewController, animated: Bool) {
        (viewController.presentingViewController ?? viewController).dismiss(animated: animated)
    }

    @discardableResult
    public func back(animated: Bool) -> Bool {
        guard let top = Self.topMostViewController() else { return false }
        if let navigationController = (top as? UINavigationController) ?? top.navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: animated)
            return true
        }
        if top.presentingViewController != nil {
            top.dismiss(animated: animated)
            return true
        }
        return false
    }

    @discardableResult
    public func switchTab(index: Int) -> Bool {
        var current = Self.keyWindow()?.rootViewController ?? pinnedNavigationController
        while let candidate = current {
            if let tabs = candidate as? UITabBarController {
                guard index >= 0, index < (tabs.viewControllers?.count ?? 0) else { return false }
                tabs.selectedIndex = index
                return true
            }
            if let presented = candidate.presentedViewController {
                current = presented
            } else if let navigation = candidate as? UINavigationController {
                current = navigation.visibleViewController
            } else {
                return false
            }
        }
        return false
    }

    private func pushTarget() -> UINavigationController? {
        if let pinnedNavigationController { return pinnedNavigationController }
        guard let top = Self.topMostViewController() else { return nil }
        return (top as? UINavigationController) ?? top.navigationController
    }

    private func presentTarget() -> UIViewController? {
        pinnedNavigationController ?? Self.topMostViewController()
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    static func topMostViewController() -> UIViewController? {
        guard var current = keyWindow()?.rootViewController else { return nil }
        while true {
            if let presented = current.presentedViewController {
                current = presented
            } else if let navigation = current as? UINavigationController, let visible = navigation.visibleViewController {
                current = visible
            } else if let tabs = current as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
            } else {
                return current
            }
        }
    }

    static func apply(_ config: PresentationConfig, to viewController: UIViewController) {
        viewController.modalPresentationStyle = config.style.uiKit
        if let detents = config.detents, let sheet = viewController.sheetPresentationController {
            sheet.detents = detents.map { detent in
                switch detent {
                case .medium: .medium()
                case .large: .large()
                }
            }
        }
    }
}

extension ModalStyle {
    var uiKit: UIModalPresentationStyle {
        switch self {
        case .automatic: .automatic
        case .fullScreen: .fullScreen
        case .pageSheet: .pageSheet
        case .formSheet: .formSheet
        case .overFullScreen: .overFullScreen
        }
    }
}

extension Router {
    /// Pin all future navigations to a specific navigation controller.
    public func pin(to navigationController: UINavigationController) {
        navigationPerformer = DefaultNavigationPerformer(pinnedNavigationController: navigationController)
    }
}
#endif
```

In `Router.swift`, change `defaultPerformer()`:
```swift
    private static func defaultPerformer() -> NavigationPerforming {
        #if canImport(UIKit)
        DefaultNavigationPerformer()
        #else
        UnavailableNavigationPerformer()
        #endif
    }
```

- [ ] **Step 2: Verify macOS suite still green** — Run: `swift test` — Expected: PASS.

- [ ] **Step 3: Verify iOS compilation** — Run:
`xcodebuild -scheme SwiftRouter -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit** — `Add UIKit default navigation performer with top-most discovery`

---

### Task 14: Simulator tests and final verification

**Files:**
- Create: `Tests/SwiftRouterTests/UIKitPerformerTests.swift` (entirely `#if canImport(UIKit)`-gated — invisible to `swift test` on macOS)

- [ ] **Step 1: Write the simulator tests**

`Tests/SwiftRouterTests/UIKitPerformerTests.swift`:
```swift
#if canImport(UIKit)
import Testing
import UIKit
@testable import SwiftRouter

private struct SimRoute: Route {}

@MainActor
struct UIKitPerformerTests {
    @Test func pinnedPushUsesNavigationController() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let performer = DefaultNavigationPerformer(pinnedNavigationController: navigation)
        let destination = UIViewController()
        try performer.perform(.push(animated: false), viewController: destination)
        #expect(navigation.viewControllers.last === destination)
    }

    @Test func replaceSwapsTopOfStack() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(UIViewController(), animated: false)
        let performer = DefaultNavigationPerformer(pinnedNavigationController: navigation)
        let replacement = UIViewController()
        try performer.perform(.replace(animated: false), viewController: replacement)
        #expect(navigation.viewControllers == [root, replacement])
    }

    @Test func applyConfigSetsModalStyle() {
        let viewController = UIViewController()
        DefaultNavigationPerformer.apply(PresentationConfig(style: .formSheet), to: viewController)
        #expect(viewController.modalPresentationStyle == .formSheet)
    }

    @Test func routerEndToEndPushViaPin() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let router = Router()
        router.pin(to: navigation)
        router.register(SimRoute.self) { _, _ in UIViewController() }
        try await router.navigate(to: SimRoute(), via: .push(animated: false))
        #expect(navigation.viewControllers.count == 2)
    }

    @Test func dynamicRecordEndToEndViaPin() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let router = Router()
        router.pin(to: navigation)
        router.addRoutes([RouteRecord(name: "novel", path: "/novel/:id") { _ in UIViewController() }])
        _ = try await router.navigate(name: "novel", params: ["id": "1"])
        #expect(navigation.viewControllers.count == 2)
    }
}
#endif
```

- [ ] **Step 2: Pick a simulator** — Run: `xcrun simctl list devices available | grep -m1 iPhone` and use that device name below.

- [ ] **Step 3: Run simulator tests** — Run:
`xcodebuild test -scheme SwiftRouter -destination 'platform=iOS Simulator,name=<device from step 2>' 2>&1 | tail -20`
Expected: `TEST SUCCEEDED` (all suites, including the pure-logic ones, run on the simulator).
If no simulator runtime is installed, report it and fall back to the Task 13 build verification — do not silently skip.

- [ ] **Step 4: Full local suite once more** — Run: `swift test` — Expected: PASS, ~60 tests.

- [ ] **Step 5: Commit** — `Add UIKit simulator test coverage`

---

## Self-review checklist (executed at plan-writing time)

- **Spec coverage:** Route protocol → T2; Router registration/resolution/shared → T8; navigate pipeline + guards + redirect cap + fire-and-forget swallow → T9; beforeEach/afterEach/replace/back/switchTab/RouteRecord/action/meta/context/declarative redirect (Revision 2) → T7 + T9; DeepLinkable/pattern/precedence/conflicts/parameters → T3–T5, T10; results → T11; multi-module → T12; transitions + custom + preferred → T2, T9, T13; top-most discovery + pin + noNavigationContext → T13; errors → T2; Swift 6 concurrency → global constraints; testing strategy (pure logic via swift test, UIKit via simulator) → structure + T14.
- **Known deviations from spec text** are enumerated in "Design clarifications" — all deliberate.
- **Type consistency spot-checks:** `ResolvedDestination.Kind` arms match between T9 creation sites and T10/T11 modifications; `URLMatchResult` fields consistent across T5/T9/T10; `NavigationPerforming` requirements match the T8 spy and T13 implementation; `RouteLocation` init signature identical at every call site (9 args incl. `parameters:`).
