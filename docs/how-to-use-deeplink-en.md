# How to Use DeepLink

A comprehensive guide to implementing deep links in your iOS app using the DeepLink library.

## Table of Contents

1. [Installation](#installation)
2. [Basic Setup](#basic-setup)
3. [Creating Routes](#creating-routes)
4. [Implementing Parsers](#implementing-parsers)
5. [Creating Handlers](#creating-handlers)
6. [Setting Up Routing](#setting-up-routing)
7. [Integrating with SwiftUI](#integrating-with-swiftui)
8. [Advanced Usage](#advanced-usage)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Installation

### Swift Package Manager

Add the DeepLink package to your project:

```swift
dependencies: [
    .package(url: "https://github.com/AlfredoHdz/swift-deep-link.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["DeepLink"]
)
```

## Basic Setup

### 1. Define Your Routes

First, create an enum that conforms to `DeepLinkRoute`:

```swift
import DeepLinks

enum AppRoute: DeepLinkRoute {
    case profile(userId: String)
    case product(productId: String, category: String)
    case settings(section: String)
    
    var id: String {
        switch self {
        case .profile(let userId):
            return "profile-\(userId)"
        case .product(let productId, let category):
            return "product-\(productId)-\(category)"
        case .settings(let section):
            return "settings-\(section)"
        }
    }
}
```

### 2. Create Parameter Models

Define models for your URL parameters:

```swift
struct ProfileParameters: Decodable {
    let userId: String
    let name: String?
}

struct ProductParameters: Decodable {
    let productId: String
    let category: String
}

struct SettingsParameters: Decodable {
    let section: String
}
```

## Implementing Parsers

### 1. Create Individual Parsers

```swift
import DeepLinks

final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser
    
    init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
        self.parameterParser = parameterParser
    }
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "profile":
            return try parseProfileData(from: deepLinkURL)
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
    
    private func parseProfileData(from url: DeepLinkURL) throws -> [AppRoute] {
        let data = try parameterParser.parse(ProfileParameters.self, from: url.queryParameters)
        return [.profile(userId: data.userId)]
    }
}
```

### 2. Create Additional Parsers

```swift
final class ProductParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser
    
    init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
        self.parameterParser = parameterParser
    }
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "product":
            return try parseProductData(from: deepLinkURL)
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
    
    private func parseProductData(from url: DeepLinkURL) throws -> [AppRoute] {
        let data = try parameterParser.parse(ProductParameters.self, from: url.queryParameters)
        return [.product(productId: data.productId, category: data.category)]
    }
}
```

## Creating Handlers

### 1. Implement Route Handlers

```swift
import DeepLinks

final class AppDeepLinkHandler: DeepLinkHandler {
    typealias Route = AppRoute
    private let navigationCoordinator: NavigationCoordinator
    
    init(navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
    }
    
    func handle(_ route: AppRoute) async throws {
        switch route {
        case .profile(let userId):
            await navigationCoordinator.navigateToProfile(userId: userId)
            
        case .product(let productId, let category):
            await navigationCoordinator.navigateToProduct(productId: productId, category: category)
            
        case .settings(let section):
            await navigationCoordinator.navigateToSettings(section: section)
        }
    }
}
```

### 2. Navigation Coordinator

```swift
@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var currentRoute: AppRoute?
    
    func navigateToProfile(userId: String) async {
        currentRoute = .profile(userId: userId)
    }
    
    func navigateToProduct(productId: String, category: String) async {
        currentRoute = .product(productId: productId, category: category)
    }
    
    func navigateToSettings(section: String) async {
        currentRoute = .settings(section: section)
    }
}
```

## Setting Up Routing

### 1. Configure Deep Link Routing

```swift
import DeepLinks

final class DeepLinkManager {
    private let routing: any DeepLinkRouting<AppRoute>
    private let handler: any DeepLinkHandler<AppRoute>
    private let coordinator: DeepLinkCoordinator<AppRoute>
    
    init(navigationCoordinator: NavigationCoordinator) {
        // Create parsers
        let parsers: [any DeepLinkParser<AppRoute>] = [
            ProfileParser(),
            ProductParser(),
            SettingsParser()
        ]
        
        // Create routing
        self.routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
        
        // Create handler
        self.handler = AppDeepLinkHandler(navigationCoordinator: navigationCoordinator)
        
        // Create coordinator
        self.coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
    }
    
    func handle(url: URL) async {
        await coordinator.handle(url: url)
    }
}
```

## Integrating with SwiftUI

### 1. App Integration

```swift
import SwiftUI
import DeepLinks

@main
struct MyApp: App {
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @State private var deepLinkManager: DeepLinkManager?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationCoordinator)
                .onAppear {
                    deepLinkManager = DeepLinkManager(navigationCoordinator: navigationCoordinator)
                }
                .onOpenURL { url in
                    Task {
                        await deepLinkManager?.handle(url: url)
                    }
                }
        }
    }
}
```

### 2. Content View with Navigation

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Welcome to My App")
                
                Button("Go to Profile") {
                    Task {
                        await navigationCoordinator.navigateToProfile(userId: "123")
                    }
                }
                
                Button("Go to Product") {
                    Task {
                        await navigationCoordinator.navigateToProduct(productId: "PROD-001", category: "Electronics")
                    }
                }
            }
            .navigationDestination(item: $navigationCoordinator.currentRoute) { route in
                switch route {
                case .profile(let userId):
                    ProfileView(userId: userId)
                case .product(let productId, let category):
                    ProductView(productId: productId, category: category)
                case .settings(let section):
                    SettingsView(section: section)
                }
            }
        }
    }
}
```

## Advanced Usage

### 1. Custom Query Parameter Parser

```swift
final class CustomParameterParser: QueryParameterParser {
    func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T {
        // Custom parsing logic
        let data = try JSONSerialization.data(withJSONObject: parameters)
        return try JSONDecoder().decode(type, from: data)
    }
}
```

### 2. Multiple Route Handling

```swift
final class MultiRouteParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "dashboard":
            // Return multiple routes for dashboard
            return [
                .profile(userId: "current-user"),
                .settings(section: "preferences")
            ]
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
}
```

### 3. Error Handling

```swift
final class ErrorHandlingParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        do {
            let deepLinkURL = try DeepLinkURL(url: url)
            // Parse logic
            return [.profile(userId: "default")]
        } catch {
            // Log error and return default route
            print("Error parsing URL: \(error)")
            return [.profile(userId: "default")]
        }
    }
}
```

## Best Practices

### 1. URL Structure

Use consistent URL structures:

```
myapp://profile?userId=123&name=John
myapp://product?productId=PROD-001&category=Electronics
myapp://settings?section=account
```

### 2. Error Handling

Always handle parsing errors gracefully:

```swift
func handle(url: URL) async {
    do {
        await coordinator.handle(url: url)
    } catch {
        // Handle error appropriately
        print("Deep link error: \(error)")
    }
}
```

### 3. Testing

Test your deep link implementation:

```swift
func testProfileDeepLink() async throws {
    let url = URL(string: "myapp://profile?userId=123")!
    let result = try await parser.parse(from: url)
    
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first, .profile(userId: "123"))
}
```

### 4. Performance

- Use lazy initialization for parsers
- Cache parsed results when appropriate
- Avoid blocking the main thread

## Troubleshooting

### Common Issues

1. **URL not being handled**
   - Check URL scheme registration in Info.plist
   - Verify parser host matching
   - Ensure proper error handling

2. **Parameters not parsed correctly**
   - Check parameter model structure
   - Verify URL encoding
   - Test with different parameter combinations

3. **Navigation not working**
   - Ensure handler is properly implemented
   - Check navigation coordinator setup
   - Verify SwiftUI navigation structure

### Debug Tips

1. Enable logging in your parsers
2. Test URLs in the simulator
3. Use the sample app as reference
4. Check the test suite for examples

## Example URLs

Test your implementation with these URLs:

```
myapp://profile?userId=123&name=John%20Doe
myapp://product?productId=PROD-001&category=Electronics
myapp://settings?section=account
myapp://dashboard
```

## Next Steps

1. Explore the [Sample App](../DeepLinkSample/) for a complete implementation
2. Check the [API Reference](./api-reference-en.md) for detailed documentation
3. Review the [Tests](../Tests/) for usage examples
4. Contribute to the project on [GitHub](https://github.com/AlfredoHdz/swift-deep-link)
