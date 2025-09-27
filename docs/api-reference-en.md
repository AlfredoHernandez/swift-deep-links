# API Reference

Complete API documentation for the DeepLink library.

## Core Components

### DeepLinkRoute

The base protocol that all route types must conform to.

```swift
public protocol DeepLinkRoute {
    var id: String { get }
}
```

**Requirements:**
- `id: String` - A unique identifier for the route

### DeepLinkURL

A structured representation of a deep link URL with parsed components.

```swift
public struct DeepLinkURL {
    public let url: URL
    public let scheme: String
    public let host: String
    public let path: String
    public let queryParameters: [String: String]
    
    public init(url: URL) throws(DeepLinkError)
}
```

**Properties:**
- `url: URL` - The original URL
- `scheme: String` - The URL scheme (e.g., "myapp")
- `host: String` - The URL host (e.g., "profile")
- `path: String` - The URL path component
- `queryParameters: [String: String]` - Query parameters as a dictionary

**Methods:**
- `init(url: URL)` - Creates a new DeepLinkURL from a standard URL

### DeepLinkError

Error types for deep link operations.

```swift
public enum DeepLinkError: Error, Equatable {
    case invalidURL(URL)
    case unsupportedHost(String)
    case routeNotFound(String)
    case missingRequiredParameter(String)
}
```

**Cases:**
- `invalidURL(URL)` - The URL is malformed or missing required components
- `unsupportedHost(String)` - The URL host is not supported
- `routeNotFound(String)` - No parser could handle the URL
- `missingRequiredParameter(String)` - A required parameter is missing

## Parsing

### DeepLinkParser

Protocol for parsing URLs into route objects.

```swift
public protocol DeepLinkParser {
    associatedtype Route: DeepLinkRoute
    
    func parse(from url: URL) throws -> [Route]
}
```

**Requirements:**
- `parse(from url: URL) throws -> [Route]` - Parse a URL into route objects

### QueryParameterParser

Protocol for parsing query parameters into strongly-typed objects.

```swift
public protocol QueryParameterParser {
    func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
```

**Requirements:**
- `parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T` - Parse parameters into a Decodable type

### JSONQueryParameterParser

Default implementation of QueryParameterParser using JSON encoding/decoding.

```swift
public final class JSONQueryParameterParser: QueryParameterParser {
    public init(jsonDecoder: JSONDecoder = JSONDecoder())
    
    public func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
```

**Methods:**
- `init(jsonDecoder: JSONDecoder)` - Initialize with a custom JSON decoder
- `parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T` - Parse parameters using JSON decoding

## Routing

### DeepLinkRouting

Protocol for routing URLs to appropriate parsers.

```swift
public protocol DeepLinkRouting {
    associatedtype Route: DeepLinkRoute
    
    func route(from url: URL) async throws -> [Route]
}
```

**Requirements:**
- `route(from url: URL) async throws -> [Route]` - Route a URL to appropriate parsers

### DefaultDeepLinkRouting

Default implementation that tries multiple parsers until one succeeds.

```swift
public final class DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting {
    public init(parsers: [any DeepLinkParser<Route>])
    
    public func route(from url: URL) async throws -> [Route]
}
```

**Methods:**
- `init(parsers: [any DeepLinkParser<Route>])` - Initialize with an array of parsers
- `route(from url: URL) async throws -> [Route]` - Try parsers in sequence until one succeeds

## Handling

### DeepLinkHandler

Protocol for handling parsed route objects.

```swift
public protocol DeepLinkHandler {
    associatedtype Route: DeepLinkRoute
    
    func handle(_ route: Route) async throws
}
```

**Requirements:**
- `handle(_ route: Route) async throws` - Handle a parsed route

## Coordination

### DeepLinkCoordinator

Main orchestrator that coordinates the deep link handling flow.

```swift
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: @unchecked Sendable {
    public init(routing: any DeepLinkRouting<Route>, handler: any DeepLinkHandler<Route>)
    
    public func handle(url: URL) async
}
```

**Methods:**
- `init(routing: any DeepLinkRouting<Route>, handler: any DeepLinkHandler<Route>)` - Initialize with routing and handler
- `handle(url: URL) async` - Handle a deep link URL through the complete flow

## Usage Examples

### Basic Route Definition

```swift
enum AppRoute: DeepLinkRoute {
    case profile(userId: String)
    case product(productId: String)
    
    var id: String {
        switch self {
        case .profile(let userId): "profile-\(userId)"
        case .product(let productId): "product-\(productId)"
        }
    }
}
```

### Custom Parser Implementation

```swift
final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "profile":
            guard let userId = deepLinkURL.queryParameters["userId"] else {
                throw DeepLinkError.missingRequiredParameter("userId")
            }
            return [.profile(userId: userId)]
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
}
```

### Custom Handler Implementation

```swift
final class AppDeepLinkHandler: DeepLinkHandler {
    typealias Route = AppRoute
    private let navigationService: NavigationService
    
    init(navigationService: NavigationService) {
        self.navigationService = navigationService
    }
    
    func handle(_ route: AppRoute) async throws {
        switch route {
        case .profile(let userId):
            await navigationService.navigateToProfile(userId: userId)
        case .product(let productId):
            await navigationService.navigateToProduct(productId: productId)
        }
    }
}
```

### Complete Setup

```swift
let parsers: [any DeepLinkParser<AppRoute>] = [
    ProfileParser(),
    ProductParser()
]

let routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
let handler = AppDeepLinkHandler(navigationService: navigationService)
let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

// Handle a deep link
await coordinator.handle(url: deepLinkURL)
```

## Middleware System

The library provides a powerful middleware system for intercepting and processing deep links before they reach the parsers.

### DeepLinkMiddleware

Basic middleware protocol for intercepting URLs:

```swift
public protocol DeepLinkMiddleware: Sendable {
    func intercept(_ url: URL) async throws -> URL?
}
```

### DeepLinkMiddlewareCoordinator

Coordinates the execution of middleware in sequence:

```swift
let coordinator = DeepLinkMiddlewareCoordinator()
coordinator.add(AnalyticsMiddleware())
coordinator.add(AuthenticationMiddleware())
coordinator.add(RateLimitMiddleware())

let processedURL = try await coordinator.process(url)
```

### Common Middleware

The library includes several built-in middleware implementations:

#### LoggingMiddleware
Logs all deep link attempts for debugging:

```swift
coordinator.add(LoggingMiddleware())
```

#### AnalyticsMiddleware
Tracks deep link usage for analytics:

```swift
let analyticsProvider = CustomAnalyticsProvider()
coordinator.add(AnalyticsMiddleware(analyticsProvider: analyticsProvider))
```

#### RateLimitMiddleware
Prevents abuse by limiting requests:

```swift
coordinator.add(RateLimitMiddleware(maxRequests: 100, timeWindow: 60.0))
```

#### AuthenticationMiddleware
Validates authentication for protected routes:

```swift
let authProvider = CustomAuthenticationProvider()
coordinator.add(AuthenticationMiddleware(
    authProvider: authProvider,
    protectedHosts: ["profile", "settings"]
))
```

#### SecurityMiddleware
Validates URLs against security policies:

```swift
let securityMiddleware = SecurityMiddleware(
    allowedSchemes: ["myapp"],
    allowedHosts: ["profile", "product"],
    blockedPatterns: [maliciousPattern]
)
coordinator.add(securityMiddleware)
```

#### URLTransformationMiddleware
Transforms URLs before processing:

```swift
coordinator.add(URLTransformationMiddleware(
    transformer: URLNormalizationTransformer()
))
```

### Advanced Middleware

For more control over the processing flow:

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

### Integration with DeepLinkCoordinator

The `DeepLinkCoordinator` automatically includes middleware support:

```swift
let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

// Add middleware
coordinator.add(AnalyticsMiddleware())
coordinator.add(AuthenticationMiddleware())

// Handle deep links (middleware runs automatically)
await coordinator.handle(url: deepLinkURL)
```

## Error Handling

The library provides comprehensive error handling through the `DeepLinkError` enum:

```swift
do {
    await coordinator.handle(url: url)
} catch let error as DeepLinkError {
    switch error {
    case .invalidURL(let url):
        print("Invalid URL: \(url)")
    case .unsupportedHost(let host):
        print("Unsupported host: \(host)")
    case .routeNotFound(let host):
        print("No parser found for host: \(host)")
    case .missingRequiredParameter(let parameter):
        print("Missing required parameter: \(parameter)")
    case .rateLimitExceeded(let count, let interval):
        print("Rate limit exceeded: \(count) requests in \(interval) seconds")
    case .securityViolation(let reason):
        print("Security violation: \(reason)")
    case .unauthorizedAccess(let resource):
        print("Unauthorized access to: \(resource)")
    case .blockedURL(let url):
        print("Blocked URL: \(url)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

## Thread Safety

All components are designed to be thread-safe:

- `DeepLinkCoordinator` is marked as `@unchecked Sendable`
- All operations are performed asynchronously
- No shared mutable state between components

## Performance Considerations

- Parsers are tried in sequence until one succeeds
- Failed parsers are logged but don't stop the process
- URL validation happens before parsing attempts
- Consider caching parsed results for frequently accessed URLs
