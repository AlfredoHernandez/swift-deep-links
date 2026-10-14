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

For path-shaped links, a template is shorter and validates captures for you:

```swift
let productParser = try PathPatternParser<AppRoute>("/products/:id") { match in
    try .product(productID: match.string("id"), category: match.url.query() ?? "")
}
// Custom schemes: treat the host as the first segment (myapp://profile/42)
let profileParser = try PathPatternParser<AppRoute>("profile/:id", scope: .hostAndPath) { match in
    try .profile(userID: match.string("id"))
}
```

Captured segments are decoded once and restricted to RFC 3986 unreserved characters by default (pass `allowedCharacters:` to widen it); `.`/`..` segments are rejected with a `securityViolation` that stops routing, and a non-matching URL throws `routeNotFound` so the next parser runs.

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
let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
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
    .delegate(
        .logging(enableDebugLogging: true),
        .analytics(provider: analyticsProvider)
    )
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

The built-in `.onDeepLink(_:)` modifier handles both custom URL schemes (`onOpenURL`) and Universal Links (`NSUserActivityTypeBrowsingWeb`) in one line:

```swift
@Observable
final class AppViewModel {
    let navigationRouter = NavigationRouter()
    var coordinator: DeepLinkCoordinator<AppRoute>?

    func bootstrap() throws {
        self.coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
            .routing(DefaultDeepLinkRouting(parsers: [ProfileParser()]))
            .handler(AppHandler(router: navigationRouter))
            .build()
    }
}

@main
struct MyApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel.navigationRouter)
                .task { try? viewModel.bootstrap() }
                .modifier(DeepLinkModifier(coordinator: viewModel.coordinator))
        }
    }
}

private struct DeepLinkModifier: ViewModifier {
    let coordinator: DeepLinkCoordinator<AppRoute>?
    func body(content: Content) -> some View {
        if let coordinator { content.onDeepLink(coordinator) } else { content }
    }
}
```

### UIKit

If you prefer (or need) UIKit scene integration, forward URLs and `NSUserActivity` directly to the coordinator:

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    let coordinator: DeepLinkCoordinator<AppRoute> = …

    // Custom URL scheme (e.g. myapp://…)
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

    // Universal Link continuation
    func scene(_ scene: UIScene, continue activity: NSUserActivity) {
        Task { await coordinator.handle(activity: activity, sceneID: scene.session.persistentIdentifier) }
    }
}
```

### Multiple Windows

Pass each scene's identifier with the link and route through a `SceneRoutingHandler`, so a link opened in one window navigates that window:

```swift
let router = SceneRoutingHandler<AppRoute>(fallback: frontmostWindowHandler)
let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
    .parser(parser)
    .handler(router)
    .build()

// SwiftUI: one identifier per window
struct WindowRoot: View {
    @SceneStorage("deepLinkSceneID") private var sceneID = ""
    @State private var navigator = Navigator()   // a DeepLinkHandler for this window

    var body: some View {
        ContentView(navigator: navigator)
            .onDeepLink(coordinator, sceneID: sceneID)
            .onAppear {
                if sceneID.isEmpty { sceneID = UUID().uuidString }
                router.register(navigator, forScene: sceneID)
            }
            .onDisappear { router.unregister(scene: sceneID) }
    }
}
```

In UIKit, register in `scene(_:willConnectTo:options:)` under `session.persistentIdentifier` and unregister in `sceneDidDisconnect(_:)`. Links without a scene (`handle(url:)`, or a window closed before its queued link drained) go to the fallback; drained and resumed links keep their scene.

### Notifications, Spotlight and Quick Actions

Each entry point extracts one URL and runs it with its own source, so per-source policy (`.security(allowedSources:)`, `DeepLinkMatcher.sources`) applies:

```swift
// UNUserNotificationCenterDelegate — URL in userInfo["deepLink"]
func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    await coordinator.handle(notificationResponse: response)
}

// Spotlight — the item's uniqueIdentifier is the URL (or map it)
.onContinueUserActivity(CSSearchableItemActionType) { activity in
    Task { await coordinator.handle(searchableItemActivity: activity) }
}

// Home Screen quick action (iOS) — URL in userInfo["deepLink"] or the item's type
func windowScene(_ scene: UIWindowScene, performActionFor item: UIApplicationShortcutItem) async -> Bool {
    await coordinator.handle(shortcutItem: item, sceneID: scene.session.persistentIdentifier)?.wasSuccessful ?? false
}
```

### AppKit

```swift
@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: DeepLinkCoordinator<AppRoute> = …

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await coordinator.handle(url: url) }
        }
    }

    func application(_ application: NSApplication, continue activity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        Task { await coordinator.handle(activity: activity) }
        return true
    }
}
```

## Middleware

Middleware processes URLs before routing. Each can pass through, transform, or stop the URL.

```text
URL → Security → RateLimit → Replay → SignedLinks → Auth → Readiness → Confirmation → Transform → Analytics → Router
```

[Securing your deep links](./securing-deep-links-en.md) explains the order.

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

Pass `limits: .recommended` (or your own `DeepLinkInputLimits`) to `.security(...)` to cap URL length, query-parameter count and parameter-value length. Limits run before any other check, so keep security first in the chain.

If you use `URLNormalizationTransformer`, run it **before** `.security(...)` or use `strategy: .hardened`. The transformer resolves `.`/`..` segments (including `%2e%2e` and `%2F`), so with `.standard` or `.strict` a link such as `/public/%2e%2e/admin` would pass validation and only turn into `/admin` afterwards. `.hardened` rejects `..` segments in any encoding.

Add `.replayProtection(window: 2)` after `.security(...)` to drop the same link arriving twice in quick succession (double taps, or a link delivered through both `onOpenURL` and `NSUserActivity`). Use `key: .queryParameter("nonce")` to deduplicate by an idempotency key, and `ignoredQueryKeys` to ignore tracking parameters.

Require a signature on sensitive links (password reset, invitations, payments) with `.signedLinks(...)`, placed after `.security(...)` and `.rateLimit(...)`. Sign links on your server with the documented canonical form, or with `SignedLinkBuilder` in Swift:

```swift
.signedLinks(
    keys: SigningKeyring(keys: ["2026-10": currentKey, "2026-04": previousKey]),
    requiredFor: .paths(["/reset", "/invite"]),
    nonceStore: InMemoryNonceStore()   // each link works once
)

let link = try SignedLinkBuilder(key: currentKey, keyID: "2026-10")
    .sign(resetURL, expiresAt: .now.addingTimeInterval(900), nonce: UUID().uuidString)
```

Ask the user before payments, deletions or account changes with `.confirmation(...)`. Implement `DeepLinkConfirmationProvider` to show an alert with the redacted URL; a denial (or no answer within `timeout`) fails the link with `DeepLinkError.confirmationDenied`. Put it after `.readiness(...)` so the UI can present the prompt:

```swift
.confirmation(provider: AlertConfirmation(), requiredFor: .hosts(["pay"]), timeout: .seconds(60))
```

Deep links often carry tokens, codes or emails. Since 2.0 every built-in log, analytics event, console line and notification replaces sensitive values with `REDACTED` (see `URLRedactor` and `DeepLinkLogPrivacy`). While debugging, opt out per site with `.unredacted`, for example `.logging(format: .unredacted(.singleLine))` or `.analytics(provider: provider, strategy: .unredacted(.standard))`.

`.security(...)` uses `strategy: .hardened` by default: `http(s)` links need their host in `allowedHosts`, and custom-scheme hosts are checked once you list any host. `DeepLinkReadinessQueue()` keeps at most 50 links (oldest dropped); pass `maxQueueSize: nil` for an unbounded queue.

### Custom Middleware

```swift
struct MyMiddleware: DeepLinkMiddleware {
    func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
        // Return the request to continue, request.replacingURL(_:) to rewrite, nil to stop
        request
    }
}
```

### Middleware Strategies

Each middleware supports swappable strategies:

| Middleware | Strategies |
|-----------|-----------|
| **Security** | `.standard`, `.strict`, `.permissive`, `.schemeOnly`, `.hostOnly`, `.patternOnly`, `.whitelist` |
| **Rate Limit** | `.slidingWindow`, `.fixedWindow`, `.tokenBucket(capacity:refillRate:)`, `.permissive` |
| **Authentication** | `.standard`, `.strict`, `.permissive`, `.schemeBased` |
| **Logging** | `.singleLine`, `.json`, `.minimal`, `.detailed` |
| **Analytics** | `.standard`, `.detailed`, `.minimal` |

## Delegates

Observe the coordinator lifecycle:

```swift
.delegate(
    .logging(enableDebugLogging: true),
    .analytics(provider: analyticsProvider),
    .notification(showSuccess: true, showErrors: true, showInfo: false)
)
```

### Custom Delegate

`DeepLinkCoordinatorDelegate` is generic over `Route`, so you get the concrete coordinator and result types directly — no casting:

```swift
final class MyDelegate: DeepLinkCoordinatorDelegate {
    typealias Route = AppRoute

    func coordinator(_ coordinator: DeepLinkCoordinator<AppRoute>, willProcess url: URL) { }
    func coordinator(_ coordinator: DeepLinkCoordinator<AppRoute>, didProcess url: URL, result: DeepLinkResult<AppRoute>) {
        // `result.routes` is `[AppRoute]` here — no casting required.
    }
    func coordinator(_ coordinator: DeepLinkCoordinator<AppRoute>, didFailProcessing url: URL, error: Error) { }
}
```

> On tvOS, the built-in `.notification()` factory is unavailable because tvOS does not display banner notifications. Use `.logging()` or your own delegate instead.

## Resume Protected Links After Sign-In

```swift
let pendingLinks = InMemoryPendingLinkStore()

let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
    .parser(parser)
    .handler(handler)
    .middleware(.authentication(provider: auth, protectedHosts: ["account"], pendingLinks: pendingLinks))
    .build()

// After a successful sign-in:
await coordinator.resumePendingLinks(from: pendingLinks)
```

The protected link still fails with `unauthorizedAccess` while signed out (show your login screen from the delegate or the result). Resumed links run through every middleware again, so authentication is re-checked.

## Readiness Gating

Queue deep links until your app is ready:

```swift
let queue = DeepLinkReadinessQueue(maxQueueSize: 50) { evicted in
    logger.warning("Dropped queued deep link for \(evicted.host() ?? "?")")
}

// Add to middleware stack
.middleware(.readiness(queue: queue))

// When the app is ready:
await coordinator.markReadyAndDrain(queue: queue)

// On logout — re-gate:
queue.reset()
```

Bound the queue in production: links can arrive from any app or web page before your app is ready, and an unbounded queue grows with each one. `onEvict` reports the oldest links dropped to make room.

`markReadyAndDrain` resumes the middleware chain for each previously-queued URL right after the readiness middleware: middleware placed before `.readiness(queue:)` does not re-fire, while middleware placed after it (auth, security, rate limiting) checks the link at drain time. Delegate notifications still fire for each drained URL.

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
| `CollectingConfirmation` | Answers confirmation prompts with a fixed decision and records them |
| `InMemoryRateLimitPersistence` | In-memory rate limit persistence (actor) |
| `ManualDateProvider` | Manually advanced clock for rate limits, replay protection and pending links |
| `URLFuzzCorpus` | Hostile URLs (traversal, encodings, IDN, duplicates, oversize, ...) for security tests |

Use `.permissive` strategies to bypass middleware in tests:

```swift
let middleware = RateLimitMiddleware(strategy: .permissive)
let auth = FixedAuthenticationProvider(isAuthenticated: true)
```

### Check Your Configuration

`DeepLinkDiagnostics` compares your security settings with the schemes in `Info.plist` and, if you pass them, your `applinks:` associated domains, and probes your parsers for unhandled or shadowed links:

```swift
@Test func deepLinkConfigurationIsConsistent() async {
    let diagnostics = DeepLinkDiagnostics(associatedDomains: ["applinks:example.com"])
    let warnings = diagnostics.checkSecurityConfiguration(allowedSchemes: ["myapp", "https"], allowedHosts: ["example.com"])
        + (await diagnostics.checkParsers(parsers, probes: [URL(string: "https://example.com/products/1")!]))
    #expect(warnings.isEmpty, "\(warnings)")
}
```

Entitlements are not readable at runtime, so associated domains must be passed in explicitly.

## Next Steps

- Explore the [Sample App](../DeepLinkSample/) for a complete implementation
- Check the [API Reference](./api-reference-en.md) for all types and methods
- Review the [Tests](../Tests/) for more examples
