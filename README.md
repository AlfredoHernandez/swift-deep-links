# Swift Deep Link

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-supported-DE5C43.svg)](https://swift.org/package-manager/)

A clean, modular, and extensible deep link handling library for iOS and macOS applications built with Swift.

## Why Swift Deep Link?

Deep links are essential for modern apps to provide seamless navigation from external sources like web pages, notifications, or other apps. However, handling deep links can quickly become complex and hard to maintain as your app grows.

Swift Deep Link solves this by providing:

- **Clean Architecture** - Separation of concerns between URL parsing, routing, middleware, and action handling
- **Type Safety** - Generic-based design ensures compile-time safety
- **Middleware Pipeline** - Composable middleware chain for security, rate limiting, authentication, analytics, and more
- **Extensibility** - Easy to add new deep link types without modifying existing code
- **Testability** - Protocol-oriented design enables easy unit testing and mocking
- **Modern Swift** - Built with Swift 6.2+ using async/await, actors, and strict Sendable compliance

## Features

| Feature | Description |
|---------|-------------|
| **Middleware Pipeline** | Composable chain: security, rate limiting, auth, analytics, logging, URL transformation, readiness gating |
| **Builder Pattern** | Fluent, immutable API for coordinator configuration |
| **Delegate System** | Observable lifecycle events with composite delegate support |
| **Strategy Pattern** | Swappable behaviors for each middleware via protocol witnesses |
| **Factory Methods** | Clean `.rateLimit()`, `.security()`, `.logging()` syntax |
| **Functional Composition** | `compose()` functions for middleware and delegates |
| **Readiness Queue** | Gate deep links until the app is ready, then drain and process |
| **Thread Safety** | Actors, `OSAllocatedUnfairLock`, and strict `Sendable` conformance |
| **Async/Await** | Full Swift Concurrency support throughout |

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AlfredoHernandez/swift-deep-links.git", from: "1.0.0")
]
```

Then add `"DeepLinks"` to your target's dependencies:

```swift
.target(name: "YourApp", dependencies: ["DeepLinks"])
```

Or add it through Xcode: **File > Add Package Dependencies** and enter the repository URL.

## Quick Start

### 1. Define Your Routes

```swift
import DeepLinks

enum AppRoute: DeepLinkRoute {
    case profile(userID: String)
    case product(productID: String, category: String)
    case settings(section: String)

    var id: String {
        switch self {
        case .profile(let userID): "profile_\(userID)"
        case .product(let productID, _): "product_\(productID)"
        case .settings(let section): "settings_\(section)"
        }
    }
}
```

### 2. Create Parsers

```swift
final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute

    func parse(from url: URL) async throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        guard deepLinkURL.host == "profile" else {
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
        guard let userID = deepLinkURL.queryParameters["userID"] else {
            throw DeepLinkError.missingRequiredParameter("userID")
        }
        return [.profile(userID: userID)]
    }
}
```

### 3. Implement a Handler

```swift
final class AppHandler: DeepLinkHandler {
    typealias Route = AppRoute
    private let router: NavigationRouter

    init(router: NavigationRouter) {
        self.router = router
    }

    func handle(_ route: AppRoute) async throws {
        await MainActor.run {
            switch route {
            case .profile(let userID):
                router.push(to: .profile(userID: userID))
            case .product(let productID, let category):
                router.push(to: .product(productID: productID, category: category))
            case .settings(let section):
                router.push(to: .settings(section: section))
            }
        }
    }
}
```

### 4. Set Up the Coordinator with the Builder

```swift
let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
    .routing(DefaultDeepLinkRouting(parsers: [ProfileParser(), ProductParser()]))
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

### 5. Handle Deep Links in SwiftUI

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

The middleware pipeline processes URLs in order before they reach the router. Each middleware can pass through, transform, or stop the URL.

```
URL -> Security -> RateLimit -> Auth -> Transform -> Analytics -> Logging -> Router
```

| Middleware | Purpose | Factory Method |
|-----------|---------|----------------|
| **Security** | Validate schemes, hosts, block patterns | `.security(allowedSchemes:allowedHosts:blockedPatterns:strategy:)` |
| **Rate Limit** | Prevent abuse with sliding/fixed windows | `.rateLimit(maxRequests:timeWindow:persistence:strategy:)` |
| **Authentication** | Gate protected routes on auth state | `.authentication(provider:protectedHosts:strategy:)` |
| **URL Transformation** | Normalize and transform URLs | `.urlTransformation(transformer:strategy:)` |
| **Analytics** | Track deep link events | `.analytics(provider:strategy:)` |
| **Logging** | Log deep link processing | `.logging(provider:logLevel:format:)` |
| **Readiness** | Queue URLs until app is ready | `.readiness(queue:)` |

Each middleware supports multiple **strategies** (e.g., `.slidingWindow`, `.fixedWindow`, `.permissive` for rate limiting). See the [API Reference](./docs/api-reference-en.md) for details.

## Readiness Middleware

Gate deep link processing until your app is ready (e.g., after onboarding, auth, or initial setup):

```swift
let queue = DeepLinkReadinessQueue(maxQueueSize: 50)

let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
    .routing(routing)
    .handler(handler)
    .middleware(.readiness(queue: queue))
    .build()

// Deep links arriving now are queued...

// When the app is ready, drain and process:
let pending = queue.markReady()
for url in pending {
    await coordinator.handle(url: url)
}

// To re-gate (e.g., on logout):
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

| Delegate | Events Tracked |
|----------|---------------|
| **Logging** | Logs all processing events via OSLog |
| **Analytics** | Tracks `deep_link_attempted`, `deep_link_processed`, `deep_link_failed` |
| **Notification** | Shows `UserNotifications` for success/error/info |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   DeepLinkCoordinator                   │
│                                                         │
│  URL ──► MiddlewareCoordinator ──► Routing ──► Handler  │
│              │                        │                 │
│              ▼                        ▼                 │
│    ┌──────────────────┐    ┌──────────────────┐         │
│    │ Security         │    │ Parser 1         │         │
│    │ RateLimit        │    │ Parser 2         │         │
│    │ Authentication   │    │ Parser N         │         │
│    │ URLTransformation│    └──────────────────┘         │
│    │ Analytics        │                                 │
│    │ Logging          │    Delegate ──► willProcess     │
│    │ Readiness        │              ──► didProcess     │
│    └──────────────────┘              ──► didFail        │
└─────────────────────────────────────────────────────────┘
```

For detailed architecture diagrams, see:
- [Architecture Diagram](./docs/architecture-diagram.md) - Complete flow from URL to navigation
- [Core Package Architecture](./docs/core-architecture-diagram.md) - Internal component interactions

## Documentation

- [How to Use DeepLink](./docs/how-to-use-deeplink-en.md) - Complete implementation guide
- [API Reference](./docs/api-reference-en.md) - Detailed API documentation
- [FAQ](./docs/faq.md) - Frequently asked questions

## Sample App

The [Sample App](./DeepLinkSample/) demonstrates:
- Multiple deep link types (profile, product, settings, info, alerts)
- SwiftUI integration with NavigationStack, sheets, and alerts
- Full middleware pipeline (security, rate limit, auth, analytics, logging)
- **Readiness Middleware showcase** with configurable drain delay and random deep links
- Custom deep link tester for manual URL testing
- MVVM architecture with the Observation framework

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 6.2+
- Xcode 16.0+

## Testing

```bash
swift test
```

Run the sample app:

```bash
open DeepLinkSample/DeepLinkSample.xcodeproj
```

## License

Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Author

**Jesús Alfredo Hernández Alarcón**
- GitHub: [@AlfredoHernandez](https://github.com/AlfredoHernandez)
- X: [@alfredohdzdev](https://x.com/alfredohdzdev)
