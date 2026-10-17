# FAQ - Frequently Asked Questions

Common questions and answers about the DeepLink library.

## General Questions

### What is a deep link?

A deep link is a URL that opens a specific screen or section within your app, rather than just launching it. For example, `myapp://profile?userID=123` might open the profile screen for user 123.

### Why should I use this library instead of handling deep links manually?

This library provides:
- **Type safety**: Compile-time guarantees for your deep link routes
- **Clean architecture**: Separation of concerns between parsing, routing, and handling
- **Testability**: Easy to unit test with protocol-oriented design
- **Extensibility**: Easy to add new deep link types without modifying existing code
- **Error handling**: Comprehensive error handling and logging

### What platforms are supported?

iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, and visionOS 1+. The library requires Swift 6.2+.

Most APIs work on every supported platform. Two platform notes:

- **tvOS:** `DeepLinkNotificationDelegate` is unavailable because tvOS does not display banner notifications. Use `DeepLinkLoggingDelegate` or a custom delegate for user feedback.
- **watchOS:** `View.onDeepLink(_:)` attaches `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`, which is available on watchOS 9+ but Universal Link continuations only originate from paired-device Safari handoffs. If your app is watchOS-only, the SwiftUI modifier's `onOpenURL` branch is the one that matters in practice.

## Security Questions

### Is it secure by default?

Not on its own. The building blocks are hardened by default: `SecurityMiddleware` uses the `.hardened` strategy and `.recommended` input limits, and logs, analytics and error descriptions are redacted. But nothing validates a link until you register a `SecurityMiddleware`. The shortest secure setup is the builder's `secureDefaults(allowedSchemes:)`, which adds security, rate limiting and replay protection in front of the chain; debug builds log a warning from `build()` when no security middleware is registered. See [Securing your deep links](./securing-deep-links-en.md) for signed links, confirmation and the recommended order.

### What happens when a link fails a security check?

The middleware throws `DeepLinkError.securityViolation` (or `blockedURL`) and the link stops: no parser or handler sees it. `result.firstDeepLinkError?.securityViolationReason` tells you why (`.unauthorizedHost`, `.expiredLink`, ...). A parser that throws one of these errors also stops routing, so later parsers cannot accept the link; throw `routeNotFound(url)` for links a parser simply does not handle.

### Are URLs redacted in logs and analytics?

Yes, by default. The coordinator, routing, logging and analytics middleware, delegates and notification errors replace sensitive query and fragment values (tokens, codes, emails, JWTs) and userinfo with `REDACTED`. Plain path segments are kept unless you configure `URLRedactor(pathRedaction:)`. Use `.unredacted` (or `.full` for notifications) only while debugging, and `error.redactedDescription` when you log errors yourself. Since 2.0.1 `localizedDescription` is redacted too; `error.unredactedDescription` keeps the full text for debugging.

## Implementation Questions

### How do I register my app's URL scheme?

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

Yes, you can register multiple URL schemes in your `Info.plist`. The system delivers links for every registered scheme, but the coordinator only accepts the schemes your `SecurityMiddleware` allows (`allowedSchemes`, or `secureDefaults(allowedSchemes:)`). Without a security middleware nothing is checked. `DeepLinkDiagnostics.checkSecurityConfiguration(allowedSchemes:allowedHosts:)` reports schemes declared in `Info.plist` but not allowed, and the reverse.

### How do I handle deep links when the app is not running?

`.onDeepLink(coordinator)` (built on `onOpenURL` and `onContinueUserActivity`) receives the link whether the app was running or launched by it. If your app needs setup before it can navigate, add `.readiness(queue:)` and call `markReadyAndDrain(queue:)` once it is ready.

### Can I use this library with UIKit?

Yes, the library is framework-agnostic. You can use it with UIKit by implementing the handler to update your UIKit navigation stack.

## Parsing Questions

### How do I handle optional parameters?

Use optional properties in your parameter models:

```swift
struct ProfileParameters: Decodable {
    let userID: String
    let name: String?  // Optional parameter
}
```

### Can I parse complex nested parameters?

Yes, you can create complex parameter models:

```swift
struct ProductParameters: Decodable {
    let productID: String
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

The library tries every registered parser in order. The outcome depends on how the chain behaves:

- If **no parsers are configured**, `DefaultDeepLinkRouting` throws `DeepLinkError.routeNotFound(url)`.
- If a parser throws `DeepLinkError.securityViolation` or `.blockedURL` (directly or nested in `parsingFailed`), routing **stops** with that error and no later parser runs.
- If at least one parser is configured but **every parser throws**, `DefaultDeepLinkRouting` throws `DeepLinkError.parsingFailed(url:underlyingErrors:)` carrying the collected failures in order. Nested `parsingFailed` thrown by a delegating parser is flattened so callers never see `parsingFailed(parsingFailed(...))`.
- If any parser succeeds, its routes are returned and no error is raised.

### How do I handle parsing errors gracefully?

`coordinator.handle(url:)` is non-throwing — it always returns a `DeepLinkResult`. Inspect the result to decide how to react:

```swift
func handle(url: URL) async {
    let result = await coordinator.handle(url: url)

    if result.wasSuccessful {
        return
    }

    if let error = result.firstDeepLinkError {
        switch error {
        case .parsingFailed:
            await navigationService.navigateToHome()
        case .rateLimitExceeded:
            await showRateLimitAlert()
        default:
            await showErrorAlert(error)
        }
    }
}
```

### Can I provide fallback behavior for failed deep links?

Yes — the result surface makes fallback explicit. `firstDeepLinkError` returns the first framework-owned error in `result.errors`, or `nil` if the failure came from a non-`DeepLinkError` source:

```swift
let result = await coordinator.handle(url: url)

guard result.wasSuccessful else {
    await navigationService.navigateToHome()
    return
}
```

## Testing Questions

### How do I test my deep link implementation?

The library provides comprehensive test helpers. See the test suite for examples:

```swift
@Test("Profile deep link parses correctly")
func profileDeepLink() async throws {
    let url = URL(string: "myapp://profile?userID=123")!
    let result = try await parser.parse(from: url)

    #expect(result.count == 1)
    #expect(result.first == .profile(userID: "123"))
}
```

### Can I mock the deep link components?

Yes. `DeepLinksTesting` ships ready-made doubles (`CollectingHandler`, `ImmediateRouting`, `CollectingMiddleware`, `FixedAuthenticationProvider`, `ManualDateProvider`, ...):

```swift
import DeepLinksTesting

let handler = CollectingHandler<AppRoute>()
let coordinator = DeepLinkCoordinator(routing: ImmediateRouting(routes: [.profile(userID: "123")]), handler: handler)
await coordinator.handle(url: URL(string: "myapp://profile?userID=123")!)
#expect(handler.handledRoutes == [.profile(userID: "123")])
```

Your own doubles must be `Sendable`; keep mutable state behind a lock or in an actor.

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
4. Open an [Issue](https://github.com/AlfredoHernandez/swift-deep-links/issues) on GitHub
