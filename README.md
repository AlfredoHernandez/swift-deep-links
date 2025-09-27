# Swift Deep Link

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift Package Manager](https://img.shields.io/badge/SPM-supported-DE5C43.svg)](https://swift.org/package-manager/)

A clean, modular, and extensible deep link handling library for iOS applications built with Swift.

## Why Swift Deep Link?

Deep links are essential for modern iOS apps to provide seamless navigation from external sources like web pages, notifications, or other apps. However, handling deep links can quickly become complex and hard to maintain as your app grows.

Swift Deep Link solves this by providing:

- **Clean Architecture**: Separation of concerns between URL parsing, routing, and action handling
- **Type Safety**: Generic-based design ensures compile-time safety
- **Extensibility**: Easy to add new deep link types without modifying existing code
- **Testability**: Protocol-oriented design enables easy unit testing and mocking
- **Modern Swift**: Built with Swift 6.2+ using async/await and Sendable compliance

## Features

- 🏗️ **Modular Architecture** - Clear separation between parsing, routing, and handling
- 🔒 **Type Safe** - Generic protocols ensure type safety across your deep link system
- 🧪 **Highly Testable** - Protocol-oriented design for easy testing and mocking
- ⚡ **Async/Await Ready** - Modern Swift concurrency support
- 📝 **Comprehensive Logging** - Built-in OSLog integration for debugging
- 🔄 **Extensible** - Easy to add new deep link types and parsers
- 📱 **iOS 16+** - Modern iOS support with latest Swift features

## 📚 Documentation

### English
- [**How to Use DeepLink**](./docs/how-to-use-deeplink-en.md) - Complete guide to implementing deep links in your iOS app
- [**API Reference**](./docs/api-reference-en.md) - Detailed API documentation for all components

### Español
- [**Cómo Usar DeepLink**](./docs/como-usar-deeplink-es.md) - Guía completa para implementar deep links en tu app iOS
- [**Referencia de API**](./docs/referencia-api-es.md) - Documentación detallada de la API para todos los componentes

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AlfredoHdz/swift-deep-link.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/AlfredoHdz/swift-deep-link.git`
3. Select your target

## 🚀 Quick Start

> **📖 For detailed documentation, see [How to Use DeepLink](./docs/how-to-use-deeplink-en.md) (English) or [Cómo Usar DeepLink](./docs/como-usar-deeplink-es.md) (Español)**

### 1. Define Your Route

```swift
enum AppRoute: Identifiable, DeepLinkRoute {
    case profile(userId: String)
    case product(productId: String)
    case settings(section: String)
    
    var id: String {
        switch self {
        case .profile(let userId): "profile_\(userId)"
        case .product(let productId): "product_\(productId)"
        case .settings(let section): "settings_\(section)"
        }
    }
}
```

### 2. Create a Parser

```swift
final class AppDeepLinkParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "profile":
            guard let userId = deepLinkURL.queryParameters["userId"] else {
                throw DeepLinkError.missingRequiredParameter("userId")
            }
            return [.profile(userId: userId)]
            
        case "product":
            guard let productId = deepLinkURL.queryParameters["productId"] else {
                throw DeepLinkError.missingRequiredParameter("productId")
            }
            return [.product(productId: productId)]
            
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
}
```

### 3. Implement a Handler

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
        case .settings(let section):
            await navigationService.navigateToSettings(section: section)
        }
    }
}
```

### 4. Set Up the Coordinator

```swift
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var navigationService = NavigationService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationService)
                .onOpenURL { url in
                    let parser = AppDeepLinkParser()
                    let routing = DefaultDeepLinkRouting<AppRoute>(parsers: [parser])
                    let handler = AppDeepLinkHandler(navigationService: navigationService)
                    let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
                    
                    Task {
                        await coordinator.handle(url: url)
                    }
                }
        }
    }
}
```

The `NavigationService` is a custom service class that manages your app's navigation state and provides methods to navigate to different screens or sections. It acts as a bridge between your deep link handlers and your app's navigation system. Here's a basic implementation:

```swift
class NavigationService: ObservableObject {
    @Published var currentRoute: AppRoute?
    
    func navigateToProfile(userId: String) async {
        await MainActor.run {
            currentRoute = .profile(userId: userId)
        }
    }
    
    func navigateToProduct(productId: String) async {
        await MainActor.run {
            currentRoute = .product(productId: productId)
        }
    }
    
    func navigateToSettings(section: String) async {
        await MainActor.run {
            currentRoute = .settings(section: section)
        }
    }
}
```

## 🏗️ Architecture

Swift Deep Link follows a clean architecture pattern with three main components:

### DeepLinkCoordinator
The main orchestrator that coordinates the deep link handling flow. It takes a URL, routes it through the routing system, and executes the appropriate handlers.

### DeepLinkRouting
Responsible for converting URLs into route objects. The `DefaultDeepLinkRouting` implementation tries multiple parsers until one succeeds.

### DeepLinkHandler
Handles the actual actions for each route. Implement this protocol to define what happens when a specific route is triggered.

## 📱 Sample App

Check out the [Sample App](./DeepLinkSample/) for a complete implementation example that demonstrates:
- Multiple deep link types (profile, product, settings, alerts)
- SwiftUI integration with NavigationStack
- Modal presentations and alerts
- Custom deep link testing interface

## 🔧 Advanced Usage

### Custom Parameter Parsing

For complex parameter structures, you can implement custom parameter parsers:

```swift
struct ProductParameters: Decodable {
    let id: String
    let category: String
}

final class ProductParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        if deepLinkURL.host == "products" {
            let params = try parameterParser.parse(ProductParameters.self, from: deepLinkURL.queryParameters)
            return [.product(productId: params.id)]
        }
        
        throw DeepLinkError.unsupportedHost(deepLinkURL.host)
    }
}
```

### Multiple Parsers

You can use multiple parsers for different deep link schemes:

```swift
let userParser = UserDeepLinkParser()
let productParser = ProductDeepLinkParser()
let settingsParser = SettingsDeepLinkParser()

let routing = DefaultDeepLinkRouting<AppRoute>(parsers: [
    userParser,
    productParser,
    settingsParser
])
```

## 📋 Requirements

- iOS 16.0+
- Swift 6.2+
- Xcode 15.0+

## 🧪 Testing

The library includes comprehensive test coverage:

```bash
swift test
```

Run the sample app to see the library in action:

```bash
open DeepLinkSample/DeepLinkSample.xcodeproj
```

## 📄 License

Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 👨‍💻 Author

**Jesús Alfredo Hernández Alarcón**
- GitHub: [@AlfredoHdz](https://github.com/AlfredoHdz)
- X: [@alfredohdzdev](https://x.com/alfredohdzdev)

## 📚 Additional Resources

- [Swift Package Manager Documentation](https://swift.org/package-manager/)
- [iOS Deep Links Guide](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [SwiftUI Navigation Documentation](https://developer.apple.com/documentation/swiftui/navigation)
