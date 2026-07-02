# SwiftRouter — Design

**Date:** 2026-07-02
**Status:** Approved

## Purpose

A Swift Package providing an elegant, type-safe routing solution for iOS — the role vue-router/react-router play on the web, in the spirit of URLNavigator but with compile-time-safe routes as the primary API. Routes are declared as plain value types; a URL deep-link layer maps external URLs onto those same typed routes.

## Decisions

| Question | Decision |
|---|---|
| UI framework | UIKit-first (SwiftUI screens adoptable via `UIHostingController`) |
| Type-safety model | Typed routes primary; URL pattern layer maps onto the same routes |
| Architecture | Protocol registry (type-keyed factories); no macros, no coordinator tree |
| Min deployment | iOS 15, swift-tools-version 6.0, Swift 6 strict concurrency |
| v1 features | Navigation guards, route results, custom transitions, multi-module registration |
| Dependencies | None |

## Package structure

```
SwiftRouter/
├── Package.swift                      # tools 6.0, .iOS(.v15), single library target
├── Sources/SwiftRouter/
│   ├── Core/
│   │   ├── Route.swift                # Route marker protocol
│   │   ├── Router.swift               # @MainActor final class Router
│   │   ├── RouteRegistry.swift        # type-keyed factory storage
│   │   ├── RoutingContext.swift       # context handed to factories
│   │   ├── NavigationPerforming.swift # injectable UIKit navigation seam
│   │   └── RouterError.swift
│   ├── DeepLink/
│   │   ├── DeepLinkable.swift         # Route refinement: pattern + init(parameters:)
│   │   ├── RoutePattern.swift         # "<int:id>" pattern parsing
│   │   ├── RouteParameters.swift      # typed accessors over path + query values
│   │   └── URLMatcher.swift           # matching engine with precedence rules
│   ├── Guards/
│   │   └── NavigationGuard.swift      # guard protocol + GuardDecision
│   ├── Results/
│   │   └── ResultRoute.swift          # associatedtype Result + continuation plumbing
│   ├── Transitions/
│   │   └── RouteTransition.swift      # push / present(config) / replaceRoot / custom
│   └── Modules/
│       └── RouteProvider.swift        # multi-module registration
└── Tests/SwiftRouterTests/
```

Pure-logic components (pattern parsing, matching, parameters, registry, guard chain) have no UIKit dependency; UIKit-touching code is gated behind `#if canImport(UIKit)` so `swift test` runs cross-platform.

## Core API

### Route protocol

```swift
public protocol Route: Sendable {}
```

Routes are plain structs. No inheritance, no registration strings at call sites.

### Router

`@MainActor public final class Router`. A `Router.shared` singleton for convenience; independent instances are fully supported (e.g. one per scene, or per test).

```swift
// Registration — type-keyed via ObjectIdentifier(R.self)
router.register(UserDetail.self) { route, context in
    UserViewController(userID: route.id)
}

// Navigation
router.push(UserDetail(id: 42))                    // fire-and-forget convenience
router.present(SettingsRoute(), style: .formSheet) // shorthand for .present(PresentationConfig(style: .formSheet))
try await router.navigate(to: UserDetail(id: 42),  // full pipeline:
                          via: .push())            // guards → factory → transition

// Resolution without navigation (for embedding, tabs, tests)
let vc = try router.viewController(for: UserDetail(id: 42))
```

Registering the same route type twice replaces the factory (last-wins) with a debug assertion, so hot-reload/test setups don't trap but accidental double-registration is surfaced during development.

### Navigation target discovery

By default the router discovers the top-most view controller from the key window (walking presented VCs, navigation/tab containers) and uses its `UINavigationController` for pushes, or the VC itself for presents. The seam is a protocol:

```swift
@MainActor public protocol NavigationPerforming {
    func perform(_ transition: ResolvedTransition, viewController: UIViewController) throws
}
```

Apps can pin the router to a specific navigation controller; tests inject a spy. `RouterError.noNavigationContext` is thrown when no usable navigation target exists.

## Deep links

### DeepLinkable

```swift
public protocol DeepLinkable: Route {
    static var pattern: RoutePattern { get }
    init(parameters: RouteParameters) throws
}
```

Registering a `DeepLinkable` route automatically registers its pattern with the URL matcher. `router.open(url)` matches the URL, constructs the typed route via `init(parameters:)`, and feeds it through the same navigate pipeline — guards and transitions apply identically.

```swift
struct UserDetail: Route, DeepLinkable {
    let id: Int
    static let pattern: RoutePattern = "myapp://user/<int:id>"
    init(parameters: RouteParameters) throws { id = try parameters.int("id") }
    init(id: Int) { self.id = id }
}

// AppDelegate / SceneDelegate
router.open(url)                       // Bool result, fire-and-forget navigation
try await router.open(url, via: .push())  // full control
```

### RoutePattern

`ExpressibleByStringLiteral`. Segments:

- **Literal**: `user`
- **Placeholder**: `<int:id>`, `<string:name>`, `<double:lat>`, `<bool:flag>`, `<uuid:token>`; bare `<name>` defaults to string
- Scheme and host are part of the pattern when present (`myapp://user/...`); patterns without a scheme match any scheme.

Invalid pattern syntax traps at registration in debug builds (programmer error, fail fast). Two patterns that would both match the same URL shape also trap at registration in debug builds; in release, the first registration wins deterministically.

### Matching precedence

Per segment: literal beats placeholder. Comparison is segment-by-segment left to right (same rule vue-router and most web routers use), which makes `user/settings` win over `user/<id>` for `/user/settings`.

### RouteParameters

Merged view of path placeholders and URL query items (path wins on key collision). Typed accessors:

```swift
try parameters.int("id")        // throws .parameterMissing / .parameterTypeMismatch
parameters.string("ref")        // optional variants for query params
```

## Navigation guards

vue-router-style interception:

```swift
public protocol NavigationGuard: Sendable {
    func check(_ route: any Route, context: RoutingContext) async -> GuardDecision
}
public enum GuardDecision: Sendable {
    case allow
    case cancel
    case redirect(any Route)
}
```

- **Global guards**: `router.addGuard(_:)` — run in registration order for every navigation.
- **Per-route guards**: passed at registration — run after global guards.
- `.redirect` re-enters the full pipeline with the new route. Redirect depth is capped at 8; exceeding it throws `RouterError.redirectLoopDetected`.
- `.cancel` throws `RouterError.guardCancelled` from `navigate(to:)`; the fire-and-forget conveniences swallow it silently (a blocked navigation is not a crash).

## Route results

```swift
public protocol ResultRoute: Route {
    associatedtype Result: Sendable
}

let color = try await router.present(forResult: ColorPickerRoute())
// → ColorPickerRoute.Result? — nil when dismissed without finishing
```

The factory's `RoutingContext` carries a `finish(_:)` handle. The presented screen calls `context.finish(.red)`; the router resolves the continuation and dismisses. Dismissal without `finish` (swipe-down, programmatic dismiss) resolves to `nil` — user cancellation is not an error. Deallocation of the presented VC without either resolves to `nil` as well, guaranteeing the continuation always completes.

## Transitions

```swift
public enum RouteTransition {
    case push(animated: Bool = true)
    case present(PresentationConfig = .init())   // modal style, detents, animated
    case replaceRoot(animated: Bool = false)     // swap window root
    case custom(any RouteTransitioning)          // full transitioning-delegate control
}
```

A route type may declare `static var preferredTransition: RouteTransition` (defaults to `.push()`) so call sites can stay clean: `router.navigate(to: route)` uses the preferred transition.

## Multi-module registration

```swift
public protocol RouteProvider {
    @MainActor func registerRoutes(in router: Router)
}

router.install(FeatureAModule())
```

Feature modules depend only on SwiftRouter, never on each other. Cross-feature navigation goes through shared route declarations (a small shared routes target) or through URLs.

## Errors

```swift
public enum RouterError: Error {
    case notRegistered(routeType: String)
    case parameterMissing(name: String)
    case parameterTypeMismatch(name: String, expected: String, actual: String)
    case guardCancelled
    case redirectLoopDetected(depth: Int)
    case noNavigationContext
}
```

Philosophy: programmer errors (bad pattern syntax, double registration) fail fast in debug; runtime conditions (unmatched URL, cancelled guard, missing nav context) are recoverable errors or quiet no-ops on the convenience paths.

## Concurrency

Swift 6 strict concurrency throughout. `Router` is `@MainActor`; `Route` values are `Sendable`; guards are `Sendable` and may suspend (async auth checks). No locks — MainActor isolation is the synchronization story.

## Testing strategy

- **Pure logic via `swift test`** (runs on macOS, no simulator): pattern parsing (all placeholder types, invalid syntax), matching precedence (literal vs placeholder, conflict detection), `RouteParameters` typed accessors and collision rules, registry behavior (type keying, replace-on-reregister), guard chain ordering, redirect cap, `open(url)` → typed route construction.
- **UIKit layer via simulator run** (`xcodebuild test` with an iOS destination): `NavigationPerforming` default implementation, top-most VC discovery, transitions, result continuation resolution on dismiss.
- Router accepts an injected `NavigationPerforming`, so the full navigate pipeline (guards → factory → transition) is testable with a spy without UIKit.

## Out of scope for v1

- SwiftUI-native adapter (`NavigationStack` driving) — future direction, core is UI-agnostic enough to add one
- Macro-based route declaration (`@Routable`) — possible later sugar on the same registry
- Route state restoration / persistence
- watchOS/tvOS/macOS support

---

## Revision 2 (2026-07-02) — dynamic web-router layer

**Trigger:** user request — guards like `beforeEach`, `replace`/`redirect` APIs "just like web router", with a vue-router/uni-app-flavored usage sample as the target shape.

The typed core above stays. A dynamic, string-based layer is added on the **same engine** — one pattern matcher, one guard pipeline, one transition performer. Vue idioms are adapted to Swift: guards return a decision from an async closure (vue-router 4's return-value style) rather than calling `next(...)`.

### Route table — `RouteRecord` / `addRoutes`

```swift
router.addRoutes([
    RouteRecord(name: "tabbar", path: "/tabbar") { _ in TabBarViewController() },
    RouteRecord(name: "login", path: "/login", meta: RouteMeta(transition: .present())) { location in
        let vc = LoginViewController()
        vc.callback = location.context as? CallBackBlock
        return vc
    },
    RouteRecord(name: "novel_detail", path: "/novel/:id") { location in
        NovelDetailViewController(id: location.params["id"] ?? "")
    },
    RouteRecord(name: "reading", path: "/reading", action: { location in
        let novelID = Int(location.query["novel_id"] ?? "") ?? 0
        ReaderManager.shared.loadData(novelID: novelID) { novel in
            Router.shared.push(path: "/reader", context: novel)
        }
        return true
    }),
    RouteRecord(name: "old_page", path: "/old", redirect: .path("/novel/list")),
])
```

Rules:

- `path` accepts vue-style `:param` placeholders (string-typed); the typed `<int:id>` syntax from the deep-link layer is also accepted in the same pattern.
- Exactly one of `component:` / `action:` / `redirect:` per record (enforced by the three initializers).
- `name` is optional but must be unique — duplicate names are last-wins with a DEBUG warning, same policy as factory re-registration.
- Record patterns participate in `open(url:)` matching alongside `DeepLinkable` patterns (scheme-less patterns match any scheme).
- Action records run their closure after guards; they perform no transition. Their `Bool` is the "handled" result.
- Redirect records re-enter matching **before** guards run (vue semantics: guards fire for the final destination). Every hop — record redirects and guard redirects alike — counts against the shared redirect cap of 8.

### RouteLocation

The dynamic layer's currency, passed to component closures, actions, and guards:

```swift
public struct RouteLocation {
    public let name: String?               // record name, or the type name for typed routes
    public let path: String                // concrete path, e.g. "/novel/123"
    public let params: [String: String]    // path placeholder values
    public let query: [String: String]     // query values (explicit dict wins over inline "?k=v")
    public let context: Any?               // arbitrary payload (callbacks, models) — never crosses actors
    public let meta: RouteMeta
    public let url: URL?                   // non-nil when navigation came through open(url:)
    public let route: (any Route)?         // typed payload when navigation began from a typed route
}
```

`RouteMeta(transition:requiresAuth:tabIndex:userInfo:)` — `requiresAuth` and `userInfo: [String: Any]` are data for the app's own guards; the router itself only interprets `transition` and `tabIndex`.

### Guards — beforeEach / afterEach

```swift
router.beforeEach { to, from in
    if to.name == "profile", !AccountService.shared.isLogin {
        return .redirect(.name("login"))
    }
    return .allow
}
router.afterEach { to, from in Analytics.track(to.path) }
```

- Vue mapping: `next(true)` → `.allow`, `next(false)` → `.cancel`, "push elsewhere then `next(false)`" → `.redirect(.name("login"))`.
- `NavigationGuard.check(to:from:)` (locations) **supersedes** the earlier `check(_:context:)` signature; typed navigations surface their route value as `to.route`.
- `GuardDecision.redirect` takes a `RedirectTarget`: `.path(String)`, `.name(String, params:)`, or `.route(any Route)`.
- `beforeEach(_:)` is sugar for `addGuard(_:)` with a closure guard; global guards run in registration order, then typed per-route guards.
- `afterEach` hooks fire after a confirmed navigation (including handled actions); `from` is the router's last confirmed location.

### Navigation verbs

```swift
router.push(name: "novel_detail", params: ["id": "123"], query: ["from": "home"])
router.push(path: "/reading", query: ["novel_id": "1"])
router.push(path: "/reading?novel_id=1")            // inline query also accepted
router.replace(name: "tabbar")
router.back()
router.switchTab(name: "me")
try await router.navigate(name: "novel_detail", params: ["id": "123"])   // full control
try await router.navigate(path: "/reading?novel_id=1")
```

- `push` → `.push` transition unless the record's `meta.transition` says otherwise.
- `replace` → new `.replace(animated:)` transition case: swaps the top of the current navigation stack (`history.replaceState` analog).
- `back()` → pops the navigation stack, else dismisses the presented screen; returns whether anything happened.
- `switchTab(name:)` → selects `meta.tabIndex` on the nearest `UITabBarController` from the window root; returns `Bool`.
- Fire-and-forget verbs stay silent on guard cancellation and log other failures in DEBUG; the async `navigate` variants throw, and return the action's `Bool` for action records (`true` otherwise).
- `open(url:via:)` (async) now returns `@discardableResult Bool` for the same reason.
- Sample's `AppRouter.shared` maps to `Router.shared` (apps can `typealias AppRouter = Router`).
