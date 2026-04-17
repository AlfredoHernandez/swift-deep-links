# How to Use DeepLink

A step-by-step guide to implementing deep link handling in your app.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Define Routes](#1-define-routes)
3. [Create Parsers](#2-create-parsers)
4. [Implement a Handler](#3-implement-a-handler)
5. [Configure the Coordinator](#4-configure-the-coordinator)
6. [Integrate with SwiftUI](#5-integrate-with-swiftui)
7. [Middleware](#middleware)
8. [Delegates](#delegates)
9. [Readiness Gating](#readiness-gating)
10. [Testing](#testing)

## Core Concepts

The library has four core protocols:

| Protocol | Responsibility |
|----------|---------------|
| `DeepLinkRoute` | Defines navigation destinations |
| `DeepLinkParser` | Converts a `URL` into routes |
| `DeepLinkHandler` | Executes the action for a route |
| `DeepLinkMiddleware` | Intercepts URLs before routing |

The `DeepLinkCoordinator` orchestrates the flow:

```text
URL → Middleware → Routing (Parsers) → Handler → Navigation
```

## 1. Define Routes

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

## 2. Create Parsers

One parser per route type. `DefaultDeepLinkRouting` tries them in order until one succeeds.

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

For complex parameters, use `JSONQueryParameterParser`:

```swift
struct ProductParameters: Decodable {
    let productID: String
    let category: String
}

final class ProductParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parser = JSONQueryParameterParser()

    func parse(from url: URL) async throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        guard deepLinkURL.host == "product" else {
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
        let params = try parser.parse(ProductParameters.self, from: deepLinkURL.queryParameters)
        return [.product(productID: params.productID, category: params.category)]
    }
}
```

## 3. Implement a Handler

The handler receives parsed routes and triggers navigation:

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
            case let .profile(userID):
                router.sheet = .profile(userID: userID)
            case let .product(productID, category):
                router.push(to: .product(productID: productID, category: category))
            case let .settings(section):
                router.push(to: .settings(section: section))
            }
        }
    }
}
```

## 4. Configure the Coordinator

Use the builder for a fluent setup with middleware and delegates:

```swift
let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
    .routing(DefaultDeepLinkRouting(parsers: [
        ProfileParser(),
        ProductParser(),
        SettingsParser(),
    ]))
    .handler(AppHandler(router: navigationRouter))
    .middleware(
        .security(allowedSchemes: ["myapp"]),
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

Or create one directly without the builder:

```swift
let coordinator = DeepLinkCoordinator(
    routing: DefaultDeepLinkRouting(parsers: [ProfileParser()]),
    handler: AppHandler(router: navigationRouter)
)
```

## 5. Integrate with SwiftUI

```swift
@Observable
final class AppViewModel {
    let navigationRouter = NavigationRouter()
    private var coordinator: CoordinatorOf<AppRoute>?

    func processDeepLink(url: URL) {
        Task {
            let coordinator = try await getOrCreateCoordinator()
            await coordinator.handle(url: url)
        }
    }
}

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

Middleware processes URLs before routing. Each can pass through, transform, or stop the URL.

```text
URL → Security → RateLimit → Auth → Transform → Analytics → Logging → Router
```

### Built-in Middleware

```swift
.middleware(
    .security(allowedSchemes: ["myapp"], allowedHosts: ["profile", "product"]),
    .rateLimit(maxRequests: 10, timeWindow: 60, strategy: .slidingWindow),
    .authentication(provider: authProvider, protectedHosts: ["profile"]),
    .urlTransformation(transformer: URLNormalizationTransformer()),
    .analytics(provider: analyticsProvider),
    .logging(format: .detailed),
    .readiness(queue: readinessQueue)
)
```

### Custom Middleware

```swift
final class MyMiddleware: DeepLinkMiddleware {
    func intercept(_ url: URL) async throws -> URL? {
        // Return URL to continue, modified URL to transform, nil to stop
        return url
    }
}
```

### Middleware Strategies

Each middleware supports swappable strategies:

| Middleware | Strategies |
|-----------|-----------|
| **Security** | `.standard`, `.strict`, `.permissive`, `.schemeOnly`, `.hostOnly`, `.patternOnly`, `.whitelist` |
| **Rate Limit** | `.slidingWindow`, `.fixedWindow`, `.permissive` |
| **Authentication** | `.standard`, `.strict`, `.permissive`, `.schemeBased` |
| **Logging** | `.singleLine`, `.json`, `.minimal`, `.detailed` |
| **Analytics** | `.standard`, `.detailed`, `.minimal`, `.performance` |

## Delegates

Observe the coordinator lifecycle:

```swift
.delegate(compose(
    .logging(enableDebugLogging: true),
    .analytics(provider: analyticsProvider),
    .notification(showSuccess: true, showErrors: true, showInfo: false)
))
```

### Custom Delegate

```swift
final class MyDelegate: DeepLinkCoordinatorDelegate {
    func coordinator(_ coordinator: AnyObject, willProcess url: URL) { }
    func coordinator(_ coordinator: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol) { }
    func coordinator(_ coordinator: AnyObject, didFailProcessing url: URL, error: Error) { }
}
```

## Readiness Gating

Queue deep links until your app is ready:

```swift
let queue = DeepLinkReadinessQueue(maxQueueSize: 50)

// Add to middleware stack
.middleware(.readiness(queue: queue))

// When the app is ready:
let pending = queue.markReady()
for url in pending {
    await coordinator.handle(url: url)
}

// On logout — re-gate:
queue.reset()
```

## Testing

The `DeepLinksTesting` module provides ready-made test utilities. Add it to your test target:

```swift
// Package.swift
.testTarget(name: "MyAppTests", dependencies: ["DeepLinks", "DeepLinksTesting"])
```

### Test a Handler in Isolation

```swift
import DeepLinks
import DeepLinksTesting
import Testing

@Test("Coordinator routes product deep link to handler")
func coordinatorHandlesProduct() async throws {
    let routing = ImmediateRouting<AppRoute>(routes: [.product(productID: "123", category: "Books")])
    let handler = CollectingHandler<AppRoute>()
    let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

    let result = await coordinator.handle(url: URL(string: "myapp://product?productID=123")!)

    #expect(result.wasSuccessful)
    #expect(handler.handledRoutes == [.product(productID: "123", category: "Books")])
}
```

### Test Middleware Pipeline

```swift
@Test("Security middleware blocks unauthorized schemes")
func securityBlocksUnauthorized() async throws {
    let collecting = CollectingMiddleware()
    let coordinator = DeepLinkMiddlewareCoordinator()
    await coordinator.add(SecurityMiddleware(allowedSchemes: ["myapp"]))
    await coordinator.add(collecting)

    // https:// is not in allowed schemes — middleware stops the pipeline
    await #expect(throws: DeepLinkError.self) {
        try await coordinator.process(URL(string: "https://evil.com")!)
    }
    #expect(collecting.interceptedURLs.isEmpty)
}
```

### Test with Delegates

```swift
@MainActor
@Test("Delegate receives lifecycle events")
func delegateReceivesEvents() async throws {
    let delegate = CollectingDelegate()
    let routing = ImmediateRouting<AppRoute>(routes: [.settings(section: "account")])
    let handler = CollectingHandler<AppRoute>()
    let coordinator = DeepLinkCoordinator(routing: routing, handler: handler, delegate: delegate)

    await coordinator.handle(url: URL(string: "myapp://settings")!)

    #expect(delegate.willProcessURLs.count == 1)
    #expect(delegate.processedEvents.first?.result.wasSuccessful == true)
}
```

### Available Test Utilities

| Type | Purpose |
|------|---------|
| `ImmediateRouting<Route>` | Returns preconfigured routes without parsing |
| `ImmediateParser<Route>` | Returns preconfigured routes for a single parser |
| `CollectingHandler<Route>` | Accumulates handled routes for inspection |
| `CollectingMiddleware` | Passes through and accumulates intercepted URLs |
| `PassthroughMiddleware` | Always passes URLs through unchanged |
| `CollectingDelegate` | Accumulates coordinator lifecycle events |
| `CollectingAnalyticsProvider` | Accumulates tracked analytics events |
| `FixedAuthenticationProvider` | Returns a fixed auth state (`true`/`false`) |
| `InMemoryRateLimitPersistence` | In-memory rate limit persistence (actor) |

Use `.permissive` strategies to bypass middleware in tests:

```swift
let middleware = RateLimitMiddleware(strategy: .permissive)
let auth = FixedAuthenticationProvider(isAuthenticated: true)
```

## Next Steps

- Explore the [Sample App](../DeepLinkSample/) for a complete implementation
- Check the [API Reference](./api-reference-en.md) for all types and methods
- Review the [Tests](../Tests/) for more examples
