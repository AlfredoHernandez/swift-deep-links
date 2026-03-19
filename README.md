# Swift Deep Link

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-supported-DE5C43.svg)](https://swift.org/package-manager/)

A modular deep link handling library for Swift with a composable middleware pipeline, type-safe routing, and full Swift 6 concurrency support.

- **Middleware pipeline** — security, rate limiting, auth, analytics, logging, URL transformation, readiness gating
- **Builder pattern** — fluent, immutable coordinator configuration
- **Strategy pattern** — swappable behaviors per middleware via protocol witnesses
- **Factory methods** — clean `.rateLimit()`, `.security()`, `.logging()` syntax
- **Functional composition** — `compose()` for middleware and delegates
- **Thread safe** — actors, `OSAllocatedUnfairLock`, strict `Sendable`

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/AlfredoHernandez/swift-deep-links.git", from: "1.0.0")
]

// Target
.target(name: "YourApp", dependencies: ["DeepLinks"])
```

## Minimal Example

```swift
import DeepLinks

// 1. Route
enum AppRoute: DeepLinkRoute {
    case profile(userID: String)
    var id: String { "profile_\(userID)" }
    private var userID: String { if case .profile(let id) = self { id } else { "" } }
}

// 2. Parser
final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    func parse(from url: URL) async throws -> [AppRoute] {
        let parsed = try DeepLinkURL(url: url)
        guard parsed.host == "profile" else { throw DeepLinkError.unsupportedHost(parsed.host) }
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

## Full Setup with Builder

For production apps, use the builder with middleware and delegates:

```swift
let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
    .routing(DefaultDeepLinkRouting(parsers: [
        ProfileParser(), ProductParser(), SettingsParser()
    ]))
    .handler(AppHandler(router: navigationRouter))
    .middleware(
        .security(allowedSchemes: ["myapp"], allowedHosts: ["profile", "product"]),
        .rateLimit(maxRequests: 10, timeWindow: 60),
        .authentication(provider: authProvider, protectedHosts: ["profile"]),
        .logging()
    )
    .delegate(compose(
        .logging(enableDebugLogging: true),
        .analytics(provider: analyticsProvider)
    ))
    .build()
```

Integrate with SwiftUI:

```swift
@main
struct MyApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel.navigationRouter)
                .onOpenURL(perform: viewModel.processDeepLink)
        }
    }
}
```

## Middleware

URLs flow through middleware in order before reaching the router. Each middleware can pass through, transform, or stop the URL.

```
URL → Security → RateLimit → Auth → Transform → Analytics → Logging → Router
```

| Middleware | Purpose |
|-----------|---------|
| **Security** | Validate schemes, hosts, block patterns |
| **Rate Limit** | Prevent abuse (sliding window, fixed window) |
| **Authentication** | Gate protected routes on auth state |
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
let pending = queue.markReady()
for url in pending { await coordinator.handle(url: url) }

// On logout — re-gate:
queue.reset()
```

## Delegates

Observe the coordinator lifecycle without modifying it:

```swift
.delegate(compose(
    .logging(enableDebugLogging: true),
    .analytics(provider: myProvider),
    .notification(showSuccess: true, showErrors: true, showInfo: false)
))
```

## Documentation

- [How to Use DeepLink](./docs/how-to-use-deeplink-en.md) — step-by-step implementation guide
- [API Reference](./docs/api-reference-en.md) — complete type and method reference
- [Architecture Diagram](./docs/architecture-diagram.md) — system flow with Mermaid
- [FAQ](./docs/faq.md) — common questions

## Sample App

The [Sample App](./DeepLinkSample/) demonstrates all features: multiple route types, full middleware pipeline, readiness showcase with configurable drain delay, and a custom URL tester. Built with MVVM and the Observation framework.

## Requirements

iOS 16+ / macOS 13+ · Swift 6.2+ · Xcode 16+

## Contributing

1. Fork → 2. Branch → 3. Commit → 4. PR

## License

Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.

## Author

**Jesús Alfredo Hernández Alarcón** · [GitHub](https://github.com/AlfredoHernandez) · [X](https://x.com/alfredohdzdev)
