# API Reference

## Core Protocols

### DeepLinkRoute

```swift
public protocol DeepLinkRoute: Sendable {
    var id: String { get }
}
```

### DeepLinkParser

```swift
public protocol DeepLinkParser<Route>: Sendable {
    associatedtype Route: DeepLinkRoute
    func parse(from url: URL) async throws -> [Route]
}
```

### DeepLinkHandler

```swift
public protocol DeepLinkHandler<Route>: Sendable {
    associatedtype Route: DeepLinkRoute
    func handle(_ route: Route) async throws
}
```

### DeepLinkRouting

```swift
public protocol DeepLinkRouting<Route>: Sendable {
    associatedtype Route: DeepLinkRoute
    func route(from url: URL) async throws -> [Route]
}
```

### DeepLinkMiddleware

```swift
public protocol DeepLinkMiddleware: Sendable {
    func intercept(_ url: URL) async throws -> URL?
}
```

### AdvancedDeepLinkMiddleware

```swift
public protocol AdvancedDeepLinkMiddleware: Sendable {
    func intercept(_ url: URL) async -> MiddlewareResult
}

public enum MiddlewareResult {
    case `continue`(URL)
    case transform(URL)
    case error(Error)
    case handled
}
```

## Core Types

### DeepLinkCoordinator

The main orchestrator. Thread-safe `Sendable` final class with immutable properties.

```swift
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: Sendable {
    public init(
        routing: any DeepLinkRouting<Route>,
        handler: any DeepLinkHandler<Route>,
        middlewareCoordinator: DeepLinkMiddlewareCoordinator = .init(),
        routeExecutionDelay: Duration = .milliseconds(500),
        delegate: (any DeepLinkCoordinatorDelegate)? = nil
    )

    @discardableResult
    public func handle(url: URL) async -> DeepLinkResult<Route>

    public func add(_ middleware: any DeepLinkMiddleware) async
    public func add(_ middleware: any AdvancedDeepLinkMiddleware) async
    public func removeAllMiddleware() async
    public func removeMiddleware(_ type: (some DeepLinkMiddleware).Type) async
}
```

**Type aliases:**
- `CoordinatorOf<Route>` = `DeepLinkCoordinator<Route>`
- `ResultOf<Route>` = `DeepLinkResult<Route>`

### DeepLinkCoordinatorBuilder

Fluent, immutable builder for coordinator configuration.

```swift
public struct DeepLinkCoordinatorBuilder<Route: DeepLinkRoute>: Sendable {
    public init()
    public func routing(_ routing: any DeepLinkRouting<Route>) -> Self
    public func handler(_ handler: any DeepLinkHandler<Route>) -> Self
    public func middleware(_ middleware: any DeepLinkMiddleware...) -> Self
    public func advancedMiddleware(_ middleware: any AdvancedDeepLinkMiddleware...) -> Self
    public func delegate(_ delegate: DeepLinkCoordinatorDelegate...) -> Self
    public func build() async throws -> DeepLinkCoordinator<Route>
}
```

### DeepLinkResult

```swift
public struct DeepLinkResult<Route: DeepLinkRoute>: DeepLinkResultProtocol {
    public let originalURL: URL
    public let processedURL: URL?
    public let routes: [Route]
    public let executionTime: TimeInterval
    public let errors: [any Error]
    public let wasSuccessful: Bool
    public let successfulRoutes: Int
    public let failedRoutes: Int

    // Convenience
    public var wasStoppedByMiddleware: Bool
    public var hasRoutes: Bool
    public var hasErrors: Bool
    public var firstError: (any Error)?
    public var summary: String
}
```

### DeepLinkURL

```swift
public struct DeepLinkURL {
    public let url: URL
    public let scheme: String
    public let host: String
    public let path: String
    public let queryParameters: [String: String]
    public let allQueryParameters: [String: [String]]

    public static let defaultMaxLength: Int  // 8192

    public init(url: URL, maxLength: Int = defaultMaxLength) throws(DeepLinkError)
}
```

### DeepLinkError

```swift
public enum DeepLinkError: Error, Equatable, LocalizedError {
    case invalidURL(URL)
    case unsupportedScheme(String)
    case unsupportedHost(String)
    case missingRequiredParameter(String)
    case invalidParameterValue(String, String)
    case routeNotFound(String)
    case handlerError(String)
    case missingRequiredConfiguration(String)
    case rateLimitExceeded(Int, TimeInterval)
    case securityViolation(String)
    case unauthorizedAccess(String)
    case blockedURL(String)
}
```

### DefaultDeepLinkRouting

Tries parsers in sequence until one succeeds.

```swift
public struct DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
    public init(parsers: [any DeepLinkParser<Route>])
    public func route(from url: URL) async throws -> [Route]
}
```

### DeepLinkMiddlewareCoordinator

Actor for thread-safe middleware management.

```swift
public actor DeepLinkMiddlewareCoordinator {
    public init()
    public func add(_ middleware: any DeepLinkMiddleware)
    public func add(_ middleware: any AdvancedDeepLinkMiddleware)
    public func removeAll()
    public func remove<T: DeepLinkMiddleware>(_: T.Type)
    public func process(_ url: URL) async throws -> URL?
}
```

## Middleware Factory Methods

All middleware can be created using static factory methods on `DeepLinkMiddleware`:

```swift
.security(allowedSchemes:allowedHosts:blockedPatterns:strategy:)
.rateLimit(maxRequests:timeWindow:persistence:strategy:)
.authentication(provider:protectedHosts:strategy:)
.urlTransformation(transformer:strategy:)
.analytics(provider:strategy:)
.logging(provider:logLevel:format:)
.readiness(queue:)
```

### Strategies

| Middleware | Strategies |
|-----------|-----------|
| `SecurityStrategy` | `.standard`, `.strict`, `.permissive`, `.schemeOnly`, `.hostOnly`, `.patternOnly`, `.whitelist` |
| `RateLimitStrategy` | `.slidingWindow`, `.fixedWindow`, `.permissive` |
| `AuthenticationStrategy` | `.standard`, `.strict`, `.permissive`, `.schemeBased` |
| `LoggingFormat` | `.singleLine`, `.json`, `.minimal`, `.detailed` |
| `AnalyticsStrategy` | `.standard`, `.detailed`, `.minimal`, `.performance` |
| `URLTransformationStrategy` | `.standard`, `.conditional`, `.safe`, `.aggressive`, `.selective`, `.passthrough`, `.validation`, `.batch` |

## Readiness

### ReadinessQueue Protocol

```swift
public protocol ReadinessQueue: ReadinessCondition {
    func enqueue(_ url: URL) -> URL?
    func markReady() -> [URL]
    var pendingCount: Int { get }
    func reset()
}
```

### DeepLinkReadinessQueue

Thread-safe queue backed by `OSAllocatedUnfairLock`. Compiler-verified `Sendable`.

```swift
public final class DeepLinkReadinessQueue: ReadinessQueue, Sendable {
    public init(maxQueueSize: Int? = nil)  // clamped to min 1
    public var isReady: Bool { get }
    public func enqueue(_ url: URL) -> URL?
    public func markReady() -> [URL]       // idempotent
    public var pendingCount: Int { get }
    public func reset()                    // re-gates, discards pending
}
```

## Delegates

### DeepLinkCoordinatorDelegate

`@MainActor`-isolated protocol. All methods have default empty implementations.

```swift
@MainActor
public protocol DeepLinkCoordinatorDelegate: AnyObject, Sendable {
    func coordinator(_ coordinator: AnyObject, willProcess url: URL)
    func coordinator(_ coordinator: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol)
    func coordinator(_ coordinator: AnyObject, didFailProcessing url: URL, error: Error)
}
```

### Delegate Factory Methods

```swift
.logging(enableDebugLogging:)
.analytics(provider:)
.notification(showSuccess:showErrors:showInfo:)
```

### Composition Functions

```swift
@MainActor public func compose(_ delegates: DeepLinkCoordinatorDelegate...) -> CompositeDeepLinkDelegate
public func compose(_ middleware: any DeepLinkMiddleware...) -> [any DeepLinkMiddleware]
```

## Parsing

### QueryParameterParser

```swift
public protocol QueryParameterParser: Sendable {
    func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
```

### JSONQueryParameterParser

```swift
public final class JSONQueryParameterParser: QueryParameterParser, Sendable {
    public init()
    public func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
    public func parse<T: Decodable>(_ type: T.Type, fromAll parameters: [String: [String]]) throws -> T
}
```

## Testing Utilities (`DeepLinksTesting` module)

Add to your test target: `dependencies: ["DeepLinks", "DeepLinksTesting"]`

### ImmediateRouting / ImmediateParser

Return preconfigured routes without URL inspection. Support error simulation.

```swift
public struct ImmediateRouting<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
    public init(routes: [Route])
    public init(error: some Error)
}

public struct ImmediateParser<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
    public init(routes: [Route])
    public init(error: some Error)
}
```

### CollectingHandler

Accumulates handled routes. Thread-safe via `OSAllocatedUnfairLock`.

```swift
public final class CollectingHandler<Route: DeepLinkRoute>: DeepLinkHandler, @unchecked Sendable {
    public var handledRoutes: [Route] { get }
}
```

### CollectingMiddleware / PassthroughMiddleware

```swift
public final class CollectingMiddleware: DeepLinkMiddleware, @unchecked Sendable {
    public var interceptedURLs: [URL] { get }  // passes through and records
}

public struct PassthroughMiddleware: DeepLinkMiddleware, Sendable { }  // no-op
```

### CollectingDelegate

`@MainActor`-isolated. Accumulates lifecycle events.

```swift
@MainActor
public final class CollectingDelegate: DeepLinkCoordinatorDelegate {
    public var willProcessURLs: [URL] { get }
    public var processedEvents: [ProcessedEvent] { get }  // .url, .result
    public var failedEvents: [FailedEvent] { get }        // .url, .error
}
```

### CollectingAnalyticsProvider

Thread-safe. Converts `[String: Any]` parameters to `[String: String]`.

```swift
public final class CollectingAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    public var trackedEvents: [TrackedEvent] { get }  // .name, .parameters
}
```

### FixedAuthenticationProvider

```swift
public struct FixedAuthenticationProvider: AuthenticationProvider, Sendable {
    public init(isAuthenticated: Bool)
}
```

### InMemoryRateLimitPersistence

Actor-based in-memory persistence. No disk I/O.

```swift
public actor InMemoryRateLimitPersistence: RateLimitPersistence {
    public func loadRequests() -> [TimeInterval]
    public func saveRequests(_ timestamps: [TimeInterval])
    public func clearRequests()
}
```

## Thread Safety

- `DeepLinkCoordinator` — `Sendable` final class, immutable `let` properties
- `DeepLinkMiddlewareCoordinator` — `actor`
- `DeepLinkReadinessQueue` — `OSAllocatedUnfairLock`, compiler-verified `Sendable`
- `UserDefaultsRateLimitPersistence` — `actor`
- All protocols — `Sendable`
- Delegates — `@MainActor`-isolated
