# Swift Deep Link

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://developer.apple.com/macos/)
[![tvOS](https://img.shields.io/badge/tvOS-16.0+-blue.svg)](https://developer.apple.com/tvos/)
[![watchOS](https://img.shields.io/badge/watchOS-9.0+-blue.svg)](https://developer.apple.com/watchos/)
[![visionOS](https://img.shields.io/badge/visionOS-1.0+-blue.svg)](https://developer.apple.com/visionos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-supported-DE5C43.svg)](https://swift.org/package-manager/)

A modular deep link handling library for Swift with a composable middleware pipeline, type-safe routing, and full Swift 6 concurrency support.

- **Hardened when you opt in, redacted by default** — `SecurityMiddleware` defaults to the `.hardened` strategy and `.recommended` input limits, and one call (`.secureDefaults(allowedSchemes:)`) installs it with rate limiting and replay protection. Nothing validates links until you register it; debug builds log a warning when you don't. Logs, analytics and error descriptions redact URLs by default
- **Middleware pipeline** — security, rate limiting, signed links (HMAC-SHA256 with expiry, nonce and key rotation), replay protection, auth (with resume after sign-in), user confirmation, analytics, logging, URL transformation, readiness gating
- **Provenance** — every link carries a `DeepLinkContext` (Universal Link, custom scheme, Handoff, notification, Spotlight, quick action, scene)
- **Entry points** — `onOpenURL`, Universal Links, Handoff, notifications, Spotlight and Home Screen quick actions, routed per window in multi-scene apps
- **Declarative parsing** — `PathPatternParser` templates such as `/products/:id` with typed captures
- **Observability** — `os_signpost` intervals per middleware and an `AsyncStream` of results
- **Builder pattern** — fluent, immutable coordinator configuration
- **Strategy pattern** — swappable behaviors per middleware via protocol witnesses
- **Factory methods** — clean `.rateLimit()`, `.security()`, `.logging()` syntax
- **Array-literal composition** — middleware/delegate arrays flow straight through the builder; delegate-side `compose()` is still available when you need the `CompositeDeepLinkDelegate` wrapper
- **Thread safe** — actors, `OSAllocatedUnfairLock`, strict `Sendable`

> Upgrading from 1.x? Read the [migration guide](./MIGRATION-2.0.md).

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/AlfredoHernandez/swift-deep-links.git", from: "2.0.0")
]

// Targets
.target(name: "YourApp", dependencies: ["DeepLinks"])
.testTarget(name: "YourAppTests", dependencies: ["DeepLinks", "DeepLinksTesting"])
```

## Minimal Example

```swift
import DeepLinks

// 1. Route
enum AppRoute: DeepLinkRoute {
    case profile(userID: String)

    var id: String {
        switch self {
        case let .profile(userID): "profile_\(userID)"
        }
    }
}

// 2. Parser
final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    func parse(from url: URL) async throws -> [AppRoute] {
        let parsed = try DeepLinkURL(url: url)
        // Not this parser's link: routeNotFound lets the next parser try it.
        guard parsed.host == "profile" else { throw DeepLinkError.routeNotFound(url) }
        guard let id = parsed.queryParameters["userID"] else { throw DeepLinkError.missingRequiredParameter("userID") }
        return [.profile(userID: id)]
    }
}

// 3. Handler
final class AppHandler: DeepLinkHandler {
    typealias Route = AppRoute
    func handle(_ route: AppRoute) async throws { print("Navigating to \(route.id)") }
}

// 4. Wire it up
let coordinator = DeepLinkCoordinator(
    routing: DefaultDeepLinkRouting(parsers: [ProfileParser()]),
    handler: AppHandler()
)
let result = await coordinator.handle(url: URL(string: "myapp://profile?userID=42")!)
print(result.summary) // "Successfully processed 1 route(s) in 0.001s"
```

This coordinator accepts any scheme and host. Before shipping, add the security stages below.

## Secure Setup

`secureDefaults` puts the first three stages in front of the chain: `.security` (`.hardened` strategy, `.recommended` input limits), `.rateLimit` (30 links per minute) and `.replayProtection` (2 seconds). Add the stages your app needs after it, in the [recommended order](./docs/securing-deep-links-en.md#2-order-the-pipeline):

```swift
@MainActor // the delegate factories (.logging(), .analytics(provider:), .notification()) are main-actor isolated
func makeCoordinator() throws -> DeepLinkCoordinator<AppRoute> {
    try DeepLinkCoordinatorBuilder<AppRoute>()
        .parsers(ProfileParser(), ProductParser())
        .handler(AppHandler())
        // security (hardened + limits) → rate limit → replay
        .secureDefaults(
            allowedSchemes: ["myapp", "https"],
            allowedHostsByScheme: ["https": ["example.com"]]
        )
        .middleware(
            .signedLinks(keys: signingKeys, requiredFor: .paths(["/reset"]), nonceStore: UserDefaultsNonceStore()),
            .authentication(provider: authProvider, protectedHosts: ["account"], pendingLinks: pendingLinks),
            .readiness(queue: readinessQueue),
            .confirmation(provider: confirmationProvider, requiredFor: .paths(["/pay"])),
            .analytics(provider: analyticsProvider)
        )
        .delegate(.logging())
        .build()
}
```

After sign-in, call `await coordinator.resumePendingLinks(from: pendingLinks)`: each saved link runs the whole chain again, so a link resumed within the 2-second replay window is dropped. Once the app can navigate, call `await coordinator.markReadyAndDrain(queue: readinessQueue)`: queued links resume right after `.readiness`, so confirmation and analytics see them and the stages before it are not run twice.

What the preset does not do: sign, confirm, authenticate or gate links, reject duplicate query parameters, or apply `blockedPatterns`; register those stages yourself. Its rate limit is app-wide and, by default, kept in `UserDefaults`, which survives relaunches but which anyone with access to the app container can edit: treat it as an abuse brake, not a security boundary (pass `rateLimitPersistence:` to change where it is kept). The [security guide](./docs/securing-deep-links-en.md) explains each stage.

Integrate with SwiftUI using the built-in modifier — one line handles both custom schemes (`onOpenURL`) and Universal Links (`NSUserActivity`):

```swift
@main
struct MyApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel.navigationRouter)
                .onDeepLink(viewModel.coordinator) // also tags each link with its source
        }
    }
}
```

Or wire them yourself (for example from a UIKit scene delegate):

```swift
func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    for item in urlContexts {
        let context = DeepLinkContext.openedURL(
            item.url,
            sourceApplication: item.options.sourceApplication,
            sceneID: scene.session.persistentIdentifier
        )
        Task { await coordinator.handle(url: item.url, context: context) }
    }
}

func scene(_ scene: UIScene, continue activity: NSUserActivity) {
    Task { await coordinator.handle(activity: activity, sceneID: scene.session.persistentIdentifier) }
}
```

Notifications, Spotlight and quick actions have their own entry points (`handle(notificationResponse:)`, `handle(searchableItemActivity:)`, `handle(shortcutItem:)`), and `SceneRoutingHandler` sends each link to the window it arrived in.

## Middleware

URLs flow through middleware in order before reaching the router. Each middleware can pass through, transform, or stop the URL.

```text
URL → Security → RateLimit → Replay → SignedLinks → Auth → Readiness → Confirmation → Transform → Analytics → Router
```

See [Securing your deep links](./docs/securing-deep-links-en.md) for why this order.

| Middleware | Purpose |
|-----------|---------|
| **Security** | Validate schemes, hosts, block patterns |
| **Rate Limit** | Prevent abuse (sliding window, fixed window, token bucket) |
| **Signed Links** | Require an HMAC-SHA256 signature, expiry and single-use nonce on sensitive links |
| **Replay Protection** | Drop the same link arriving again within a window |
| **Authentication** | Gate protected routes on auth state; optionally save them to resume after sign-in |
| **Confirmation** | Ask the user before destructive or financial links continue |
| **URL Transformation** | Normalize and transform URLs |
| **Analytics** | Track deep link events |
| **Logging** | Log processing (single-line, JSON, detailed) |
| **Readiness** | Queue URLs until app is ready |

Each middleware supports multiple **strategies** (e.g., `.standard`, `.strict`, `.permissive`). See the [API Reference](./docs/api-reference-en.md) for all options.

### Readiness Gating

Queue deep links until your app is ready, then drain and process:

```swift
let queue = DeepLinkReadinessQueue(maxQueueSize: 50)

// Add to middleware stack
.middleware(.readiness(queue: queue))

// When the app is ready:
await coordinator.markReadyAndDrain(queue: queue)

// On logout — re-gate:
queue.reset()
```

## Delegates

Observe the coordinator lifecycle without modifying it:

```swift
.delegate(
    .logging(enableDebugLogging: true),
    .analytics(provider: myProvider),
    .notification(showSuccess: true, showErrors: true, showInfo: false)
)
```

## Testing

The `DeepLinksTesting` module provides purpose-named test utilities:

```swift
import DeepLinksTesting

let routing = ImmediateRouting<AppRoute>(routes: [.profile(userID: "42")])
let handler = CollectingHandler<AppRoute>()
let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

await coordinator.handle(url: URL(string: "myapp://profile?userID=42")!)
#expect(handler.handledRoutes == [.profile(userID: "42")])
```

| Type | Purpose |
|------|---------|
| `ImmediateRouting` / `ImmediateParser` | Return preconfigured routes |
| `CollectingHandler` | Accumulate handled routes and their contexts |
| `CollectingMiddleware` / `PassthroughMiddleware` | Collect or pass URLs |
| `CollectingDelegate` | Accumulate lifecycle events |
| `CollectingAnalyticsProvider` | Accumulate analytics events |
| `FixedAuthenticationProvider` | Fixed auth state |
| `CollectingConfirmation` | Fixed confirmation decision, records prompts |
| `InMemoryRateLimitPersistence` | In-memory persistence |
| `ManualDateProvider` | Manually advanced clock |
| `URLFuzzCorpus` | Hostile URLs for security tests |

## Documentation

- [How to Use DeepLink](./docs/how-to-use-deeplink-en.md) — step-by-step implementation guide
- [API Reference](./docs/api-reference-en.md) — complete type and method reference
- [Securing your deep links](./docs/securing-deep-links-en.md) — threat model, middleware order, signed links, confirmation
- [Migrating to 2.0](./MIGRATION-2.0.md) — every breaking change with before/after code and a hardening checklist
- [Architecture Diagram](./docs/architecture-diagram.md) — system flow with Mermaid
- [FAQ](./docs/faq.md) — common questions

## Sample App

The [Sample App](./DeepLinkSample/) (iOS 26+) shows the recommended setup: the `secureDefaults` preset, `.onDeepLink`, redacted logging, readiness gating drained with `markReadyAndDrain`, and a Secure screen with a signed link, a confirmation prompt, resume after sign-in and a debug-only `DeepLinkDiagnostics` check. It does not cover every API (for example Handoff, Spotlight, notifications and multi-scene routing). Built with MVVM and the Observation framework.

## Requirements

iOS 16+ · macOS 13+ · tvOS 16+ · watchOS 9+ · visionOS 1+ · Swift 6.2+ · Xcode 26+

Snippets that use `@Observable` (such as the SwiftUI one above) need iOS 17 / macOS 14 or later; the Sample App targets iOS 26.

The package targets Apple platforms only: it uses `os` (`Logger`, `OSAllocatedUnfairLock`, signposts) unconditionally and does not build on Linux or Windows.

> `DeepLinkNotificationDelegate` and `handle(notificationResponse:)` are unavailable on tvOS, Spotlight entry points require CoreSpotlight (not on tvOS), `handle(shortcutItem:)` requires UIKit on iOS or visionOS, and signed links require CryptoKit. All other APIs work on every supported platform.

## Contributing

1. Fork → 2. Branch → 3. Commit → 4. PR

## License

Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.

## Author

**Jesús Alfredo Hernández Alarcón** · [GitHub](https://github.com/AlfredoHernandez) · [X](https://x.com/alfredohdzdev)
