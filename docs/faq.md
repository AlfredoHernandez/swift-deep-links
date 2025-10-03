# FAQ - Frequently Asked Questions

Common questions and answers about the DeepLink library.

## General Questions

### What is a deep link?

A deep link is a URL that opens a specific screen or section within your iOS app, rather than just launching the app. For example, `myapp://profile?userId=123` might open the user profile screen for user ID 123.

### Why should I use this library instead of handling deep links manually?

This library provides:
- **Type safety**: Compile-time guarantees for your deep link routes
- **Clean architecture**: Separation of concerns between parsing, routing, and handling
- **Testability**: Easy to unit test with protocol-oriented design
- **Extensibility**: Easy to add new deep link types without modifying existing code
- **Error handling**: Comprehensive error handling and logging

### What iOS versions are supported?

The library requires iOS 16.0+ and Swift 6.2+.

## Implementation Questions

### How do I register my app's URL scheme?
¬
Add your URL scheme to your app's `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourapp.deeplink</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
    </dict>
</array>
```

### Can I have multiple URL schemes?

Yes, you can register multiple URL schemes in your `Info.plist`. The library will handle URLs from any registered scheme.

### How do I handle deep links when the app is not running?

The `onOpenURL` modifier in SwiftUI handles deep links whether the app is running or not. The library works the same way in both scenarios.

### Can I use this library with UIKit?

Yes, the library is framework-agnostic. You can use it with UIKit by implementing the handler to update your UIKit navigation stack.

## Parsing Questions

### How do I handle optional parameters?

Use optional properties in your parameter models:

```swift
struct ProfileParameters: Decodable {
    let userId: String
    let name: String?  // Optional parameter
}
```

### Can I parse complex nested parameters?

Yes, you can create complex parameter models:

```swift
struct ProductParameters: Decodable {
    let productId: String
    let category: Category
    let filters: [String]
}

struct Category: Decodable {
    let id: String
    let name: String
}
```

### How do I handle URL encoding?

The library automatically handles URL encoding/decoding. Parameters like `name=John%20Doe` will be decoded to `name=John Doe`.

### What if my URL has a different structure?

You can implement custom parsers for any URL structure. The library is flexible and doesn't enforce a specific URL format.

## Error Handling Questions

### What happens if a deep link fails to parse?

The library will try all registered parsers. If none succeed, it will throw a `DeepLinkError.routeNotFound` error.

### How do I handle parsing errors gracefully?

Implement error handling in your app's deep link coordinator:

```swift
func handle(url: URL) async {
    do {
        await coordinator.handle(url: url)
    } catch {
        // Handle error appropriately
        print("Deep link error: \(error)")
        // Maybe show an error alert or navigate to a default screen
    }
}
```

### Can I provide fallback behavior for failed deep links?

Yes, you can implement fallback logic in your error handling:

```swift
do {
    await coordinator.handle(url: url)
} catch {
    // Fallback to home screen or show error
    await navigationService.navigateToHome()
}
```

## Testing Questions

### How do I test my deep link implementation?

The library provides comprehensive test helpers. See the test suite for examples:

```swift
func testProfileDeepLink() async throws {
    let url = URL(string: "myapp://profile?userId=123")!
    let result = try await parser.parse(from: url)
    
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first, .profile(userId: "123"))
}
```

### Can I mock the deep link components?

Yes, the protocol-oriented design makes mocking easy:

```swift
class MockDeepLinkHandler: DeepLinkHandler {
    var handledRoutes: [AppRoute] = []
    
    func handle(_ route: AppRoute) async throws {
        handledRoutes.append(route)
    }
}
```

## Performance Questions

### Is there any performance impact?

The library is designed for performance:
- Parsers are tried in sequence until one succeeds
- URL validation happens before parsing attempts
- No blocking operations on the main thread
- Minimal memory footprint

### Can I cache parsed results?

Yes, you can implement caching in your parsers or handlers for frequently accessed URLs.

### How many parsers can I have?

There's no hard limit, but consider performance implications. The library tries parsers in sequence, so order them by likelihood of success.

## Integration Questions

### How do I integrate with SwiftUI NavigationStack?

See the sample app for a complete SwiftUI integration example. The key is using `navigationDestination` with your route enum.

### Can I use this with other navigation libraries?

Yes, the library is navigation-agnostic. You can integrate it with any navigation system by implementing the handler appropriately.

### How do I handle deep links in a tab-based app?

You can implement different handlers for different tabs, or use a centralized navigation coordinator that manages tab state.

## Troubleshooting

### My deep links aren't working

1. Check that your URL scheme is registered in `Info.plist`
2. Verify your parser is handling the correct host
3. Check the console for error messages
4. Test with the sample app first

### Parameters aren't being parsed correctly

1. Check your parameter model structure
2. Verify URL encoding
3. Test with different parameter combinations
4. Use the test suite as a reference

### Navigation isn't working

1. Ensure your handler is properly implemented
2. Check your navigation coordinator setup
3. Verify SwiftUI navigation structure
4. Test with the sample app

### The app crashes when handling deep links

1. Check for force unwrapping in your parsers
2. Verify error handling
3. Test with malformed URLs
4. Use the debugger to identify the crash location

## Best Practices

### URL Design

- Use consistent URL structures
- Keep URLs simple and readable
- Use meaningful parameter names
- Consider URL length limits

### Error Handling

- Always handle parsing errors gracefully
- Provide meaningful error messages
- Implement fallback behavior
- Log errors for debugging

### Testing

- Test all your deep link scenarios
- Test with malformed URLs
- Test error conditions
- Use the provided test helpers

### Performance

- Order parsers by likelihood of success
- Consider caching for frequent URLs
- Avoid blocking operations
- Monitor performance in production

## Getting Help

If you have questions not covered in this FAQ:

1. Check the [Sample App](../DeepLinkSample/) for examples
2. Review the [API Reference](./api-reference-en.md)
3. Look at the [Tests](../Tests/) for usage patterns
4. Open an [Issue](https://github.com/AlfredoHdz/swift-deep-link/issues) on GitHub
