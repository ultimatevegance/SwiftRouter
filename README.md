# SwiftRouter

SwiftRouter is a routing engine for UIKit apps. Declare destinations once, then
navigate by typed route, route name, path, or URL through one shared pipeline.

The core idea is simple: screens and actions are destinations; navigation is a
request to resolve one destination, check guards, follow redirects, choose a
transition, and perform it. This keeps authentication, deep links, tab switches,
modal presentation, and feature-module registration in one place instead of
spreading navigation decisions across view controllers.

- **Two API surfaces**: typed `Route` values and dynamic `RouteRecord` tables.
- **One pipeline** for typed routes, names, paths, and URLs.
- **Async guards** with allow, cancel, and redirect decisions.
- **UIKit-first transitions** with injectable performers for tests.
- **Zero dependencies**, Swift 6, iOS 15+.

## Installation

Add SwiftRouter to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ultimatevegance/SwiftRouter", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies...** and enter
`https://github.com/ultimatevegance/SwiftRouter`.

## Quick Start

Five steps from zero to your first navigation.

### 1. Declare a route

```swift
import SwiftRouter

struct UserDetail: Route {
    let id: Int
}
```

### 2. Register it at launch

```swift
@MainActor
enum AppBootstrap {
    static func configure() {
        let router = Router.shared

        router.register(UserDetail.self) { route, _ in
            UserViewController(userID: route.id)
        }

        router.beforeEach { _, _ in .allow }  // optional: auth, analytics, etc.
    }
}
```

### 3. Call `configure()` in `SceneDelegate`

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    AppBootstrap.configure()

    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)
    window?.rootViewController = UINavigationController(rootViewController: HomeViewController())
    window?.makeKeyAndVisible()
}
```

### 4. Navigate anywhere

```swift
Router.shared.push(UserDetail(id: 42))
```

### 5. Deep links (optional)

```swift
struct UserDetail: Route, DeepLinkable {
    let id: Int
    static let pattern: RoutePattern = "myapp://user/<int:id>"
    init(parameters: RouteParameters) throws { id = try parameters.int("id") }
    init(id: Int) { self.id = id }
}

// register with DeepLinkable — pattern is registered automatically
router.register(UserDetail.self) { route, _ in UserViewController(userID: route.id) }

// SceneDelegate
Router.shared.open(url)  // myapp://user/42
```

**Usage order:** register routes → configure guards → show window → `push` /
`navigate` / `open`. Never register routes from view controllers.

### Multiple feature modules

When the app grows, move registration into `RouteProvider` modules and install
them once:

```swift
struct UserFeature: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(UserDetail.self) { route, _ in UserViewController(userID: route.id) }
    }
}

@MainActor
enum AppModules {
    static func registerAll(in router: Router) {
        router.installAll([UserFeature(), NovelFeature()])
    }
}

// AppBootstrap.configure()
AppModules.registerAll(in: router)
```

See [Feature Modules](#feature-modules) for the full modular setup.

## Routing Setup

Register destinations during app startup or from feature modules.

```swift
import SwiftRouter

let router = Router.shared

router.addRoutes([
    RouteRecord(name: "tabbar", path: "/tabbar", meta: RouteMeta(transition: .replaceRoot())) { _ in
        TabBarViewController()
    },
    RouteRecord(name: "me", path: "/me", meta: RouteMeta(tabIndex: 2)) { _ in
        ProfileViewController()
    },
    RouteRecord(name: "login", path: "/login", meta: RouteMeta(transition: .present())) { location in
        let controller = LoginViewController()
        controller.callback = location.context as? CallBackBlock
        return controller
    },
    RouteRecord(name: "novel_detail", path: "/novel/:id") { location in
        NovelDetailViewController(id: location.params["id"] ?? "")
    },
    RouteRecord(name: "reading", path: "/reading", action: { location in
        let novelID = Int(location.query["novel_id"] ?? "") ?? 0
        ReaderManager.shared.load(novelID: novelID)
        return true
    }),
    RouteRecord(name: "old_page", path: "/old", redirect: .path("/novel/list")),
])
```

`RouteLocation` is the resolved request handed to guards, components, and
actions:

- `name`: the matched route name when available.
- `path`: the concrete matched path, without query items.
- `params`: path placeholder values such as `["id": "123"]`.
- `query`: URL query values plus explicit query values passed to navigation.
- `context`: an app-defined payload for callbacks or model objects.
- `meta`: route metadata used by guards, transitions, or tabs.
- `url`: the external URL when the request came from `open(_:)`.
- `route`: the typed route value for typed navigation.

## Navigation

Use the convenience methods when you want fire-and-forget app navigation:

```swift
router.push(name: "novel_detail", params: ["id": "123"], query: ["from": "home"])
router.push(path: "/reading?novel_id=1")
router.push(name: "tabbar")
router.replace(name: "novel_detail", params: ["id": "123"])
router.back()
router.switchTab(name: "me")
```

Use the async methods when the caller needs to handle failures or await the
whole pipeline:

```swift
try await router.navigate(name: "novel_detail", params: ["id": "123"])
try await router.navigate(path: "/reading?novel_id=1")
try await router.navigate(to: UserDetail(id: 123), via: .present())
```

The convenience methods swallow guard cancellations because a blocked
navigation is not a crash. Other failures are printed in DEBUG builds.

## Guards

Global guards run in registration order. Typed routes may also register
per-route guards.

```swift
router.beforeEach { to, from in
    guard to.meta.requiresAuth else { return .allow }
    return AccountService.shared.isLoggedIn ? .allow : .redirect(.name("login"))
}

router.afterEach { to, from in
    Analytics.track(screen: to.path)
}
```

Guards return `GuardDecision`:

- `.allow`: continue to the next guard or perform the destination.
- `.cancel`: stop the navigation.
- `.redirect(...)`: resolve another destination through the full pipeline.

Redirects are capped at 8 hops. A cancelled async navigation throws
`RouterError.guardCancelled`.

## Typed Routes

Typed routes are plain Swift values. Register the factory once, then navigate
with the value.

```swift
struct UserDetail: Route {
    let id: Int
}

router.register(UserDetail.self) { route, context in
    UserViewController(userID: route.id)
}

router.push(UserDetail(id: 42))
try await router.navigate(to: UserDetail(id: 42), via: .present())

let controller = try router.viewController(for: UserDetail(id: 42))
```

A route can choose its default transition:

```swift
struct SettingsRoute: Route {
    @MainActor static var preferredTransition: RouteTransition {
        .present(PresentationConfig(style: .formSheet))
    }
}
```

Resolution order for transitions is:

1. Explicit `via:`.
2. Dynamic record `RouteMeta.transition`.
3. Typed route `preferredTransition`.
4. `.push()`.

## Deep Links

Conform a typed route to `DeepLinkable` to construct it from a URL or path.

```swift
struct UserDetail: Route, DeepLinkable {
    let id: Int

    static let pattern: RoutePattern = "myapp://user/<int:id>"

    init(parameters: RouteParameters) throws {
        id = try parameters.int("id")
    }

    init(id: Int) {
        self.id = id
    }
}

router.register(UserDetail.self) { route, context in
    UserViewController(userID: route.id)
}

router.open(URL(string: "myapp://user/42?ref=email")!)
try await router.open(URL(string: "myapp://user/42")!)
```

`open(_:)`, `navigate(path:)`, and typed `navigate(to:)` all use the same guard,
redirect, and transition pipeline.

### Pattern Syntax

| Segment | Meaning |
| --- | --- |
| `user` | Literal segment |
| `:id` | String placeholder |
| `<int:id>` | Integer placeholder |
| `<string:name>` / `<name>` | String placeholder |
| `<double:lat>` | Floating-point placeholder |
| `<bool:flag>` | `true` or `false`, case-insensitive |
| `<uuid:token>` | UUID placeholder |

Patterns with schemes match only that scheme. Patterns without schemes match
plain paths and URLs with any scheme. The URL host counts as the first segment,
so `myapp://user/42` matches `user`, `42`.

When multiple patterns match, literal segments beat placeholders from left to
right. Ambiguous pattern pairs assert at registration in DEBUG builds.

## Result Routes

`ResultRoute` lets a presented screen return a value to the caller.

```swift
struct ColorPickerRoute: ResultRoute {
    typealias Result = UIColor
}

let color = try await router.present(forResult: ColorPickerRoute())
```

Inside the presented screen's factory, call `context.finish(_:)` when the value
is ready:

```swift
router.register(ColorPickerRoute.self) { route, context in
    let controller = ColorPickerViewController()
    controller.onPick = { color in
        context.finish(color)
    }
    return controller
}
```

The continuation always completes. If the presented screen is dismissed or
deallocated without calling `finish(_:)`, the awaited result resolves to `nil`.

## Transitions

```swift
try await router.navigate(to: route, via: .push(animated: false))
try await router.navigate(to: route, via: .present(PresentationConfig(style: .pageSheet, detents: [.medium])))
try await router.navigate(to: route, via: .replace())
try await router.navigate(to: route, via: .replaceRoot())
try await router.navigate(to: route, via: .custom(MyTransition()))
```

The default performer discovers the top-most view controller from the key
window. To target a specific navigation stack:

```swift
router.pin(to: navigationController)
```

Custom containers can replace `navigationPerformer`.

## Feature Modules

Feature modules can register their own destinations without depending on each
other.

```swift
struct NovelFeature: RouteProvider {
    func registerRoutes(in router: Router) {
        router.register(NovelDetail.self) { route, _ in
            NovelDetailViewController(id: route.id)
        }

        router.addRoutes([
            RouteRecord(name: "novel_list", path: "/novel/list") { _ in
                NovelListViewController()
            }
        ])
    }
}

router.install(NovelFeature())
```

At app startup, register every module from one place:

```swift
@MainActor
enum AppModules {
    static func registerAll(in router: Router) {
        router.installAll([
            NovelFeature(),
            UserFeature(),
            ReaderFeature(),
        ])
    }
}

// SceneDelegate or AppDelegate
AppModules.registerAll(in: Router.shared)
```

Cross-feature navigation should go through shared route declarations, route
names, paths, or URLs.

## Testing

Inject `NavigationPerforming` to test routing logic without launching UIKit
navigation.

```swift
@MainActor final class SpyPerformer: NavigationPerforming {
    var performed: [(ResolvedTransition, PlatformViewController)] = []

    func perform(_ transition: ResolvedTransition, viewController: PlatformViewController) throws {
        performed.append((transition, viewController))
    }
}

let router = Router(navigationPerformer: SpyPerformer())
```

Independent `Router` instances are supported. `Router.shared` is only a
convenience.

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

Invalid route patterns and ambiguous pattern pairs are programmer errors and
assert in DEBUG builds. Runtime conditions such as missing registrations,
cancelled guards, and missing navigation context are reported through throwing
APIs.

## Requirements

| Requirement | Version |
| --- | --- |
| iOS | 15.0+ |
| Swift | 6.0+ |
| Dependencies | none |

The package also declares macOS 13 so the pure routing pipeline can be tested
with `swift test`. SwiftRouter does not provide AppKit navigation.
