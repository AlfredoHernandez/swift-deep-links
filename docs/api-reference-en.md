# API Reference

## Core Protocols

### DeepLinkRoute

```swift
public protocol DeepLinkRoute: Sendable, Equatable, Hashable {
    var id: String { get }
}
```

Enum routes pick up `Equatable` and `Hashable` via synthesis; conformance is required so routes can be compared in tests and stored in `Set`/`Dictionary` without an explicit adopter.

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
    func handle(_ route: Route, context: DeepLinkContext) async throws  // 2.0, called by the coordinator
}
```

Implement exactly one method; each defaults to the other (`handle(_:)` receives `.unknown` when only the context form is implemented). 1.x handlers compile unchanged.

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
    func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest?  // 2.0
    func intercept(_ url: URL) async throws -> URL?                              // deprecated, removed in 3.0
    func didFinish(_ request: DeepLinkRequest, outcome: DeepLinkOutcome) async   // default: no-op
}

public enum DeepLinkOutcome: Sendable {
    case succeeded          // routing and every handler succeeded
    case stopped            // a middleware returned nil
    case deferred           // a ReadinessMiddleware queued the link
    case failed(any Error)  // a middleware, the router or a handler threw
}
```

`didFinish(_:outcome:)` lets middleware settle work once the link is done (`SignedLinkMiddleware` spends or releases its nonce there). `DeepLinkCoordinator` calls it, after the handler ran, for every middleware that ran in that pass (including one that threw), with the request that middleware received; middleware after a stop never ran and is not called. A drained link's pass only covers the middleware after the readiness gate. Calling `DeepLinkMiddlewareCoordinator.process` or `intercept` directly never triggers it.

Implement exactly one form; each has a default that calls the other, and a type implementing neither throws `DeepLinkError.missingRequiredConfiguration` instead of recursing (the same holds for `DeepLinkHandler`). A 1.x middleware implementing only the URL form still compiles: the coordinator calls it through the request form, which keeps the request's context and swaps in the returned URL. Calling the URL form on request-aware middleware passes `DeepLinkContext.unknown`.

### DeepLinkRequest and DeepLinkContext

```swift
public struct DeepLinkRequest: Sendable, Hashable {
    public var url: URL
    public var context: DeepLinkContext
    public init(url: URL, context: DeepLinkContext = .unknown)
    public func replacingURL(_ url: URL) -> DeepLinkRequest
}

public struct DeepLinkContext: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable, CaseIterable {
        case customScheme, universalLink, handoff, notification, spotlight, shortcut, intent, unknown
    }
    public static let unknown: DeepLinkContext
    public var source: Source
    public var sourceApplication: String?
    public var sceneID: String?
    public internal(set) var isSignatureVerified: Bool  // set only by SignedLinkMiddleware
    public init(source: Source = .unknown, sourceApplication: String? = nil, sceneID: String? = nil)
    public static func openedURL(_ url: URL, sourceApplication: String? = nil, sceneID: String? = nil) -> DeepLinkContext
}
```

The context is a claim made by your entry point, not proof: any app can open a custom scheme. Use it to restrict sensitive flows (`.security(..., allowedSources: [.universalLink])`), never to trust a link. `openedURL(_:)` maps custom schemes to `.customScheme` and `http(s)` to `.unknown`, because an open-URL callback does not prove associated-domain verification; only browsing-web activities (`handle(activity:)`, `onDeepLink`) are `.universalLink`. Links replayed by `markReadyAndDrain(queue:)` and `resumePendingLinks(from:)` keep the context they arrived with (custom queues and stores that implement only the URL requirements replay with `.unknown`).

## Core Types

### DeepLinkCoordinator

The main orchestrator. Thread-safe `Sendable` final class with immutable properties.

```swift
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: Sendable {
    public init(
        routing: any DeepLinkRouting<Route>,
        handler: any DeepLinkHandler<Route>,
        middlewareCoordinator: DeepLinkMiddlewareCoordinator = .init(),
        routeExecutionDelay: Duration = .zero,
        delegate: (any DeepLinkCoordinatorDelegate<Route>)? = nil,
        sleep: @Sendable @escaping (Duration) async -> Void = { … },
        logPrivacy: DeepLinkLogPrivacy = .redacted
    )

    @discardableResult
    public func handle(url: URL) async -> DeepLinkResult<Route>          // context: .unknown

    @discardableResult
    public func handle(url: URL, context: DeepLinkContext) async -> DeepLinkResult<Route>

    /// Browsing-web activities run as `.universalLink`, activity types listed in
    /// `handoffActivityTypes` as `.handoff`; every other activity type, and any
    /// activity without a `webpageURL`, is rejected and returns `nil`.
    /// Main-actor isolated so `NSUserActivity` (non-`Sendable`) can be passed directly.
    @MainActor
    @discardableResult
    public func handle(activity: NSUserActivity, handoffActivityTypes: Set<String> = [],
                       sceneID: String? = nil) async -> DeepLinkResult<Route>?

    // Notifications (canImport(UserNotifications) && !os(tvOS)): source .notification.
    // URL from userInfo[urlKey] (String or URL with a scheme); the dismiss action is ignored.
    // sceneID defaults to the response's targetScene on iOS/visionOS.
    @MainActor @discardableResult
    public func handle(notificationResponse: UNNotificationResponse, urlKey: String = "deepLink",
                       sceneID: String? = nil) async -> DeepLinkResult<Route>?
    @MainActor @discardableResult
    public func handle(notificationUserInfo: [AnyHashable: Any],
                       actionIdentifier: String = UNNotificationDefaultActionIdentifier,
                       urlKey: String = "deepLink", sceneID: String? = nil) async -> DeepLinkResult<Route>?

    // Spotlight (canImport(CoreSpotlight) && !os(tvOS)): source .spotlight.
    // Only CSSearchableItemActionType activities; the identifier maps to a URL (default: parsed as a URL).
    @MainActor @discardableResult
    public func handle(searchableItemActivity: NSUserActivity, sceneID: String? = nil,
                       urlForIdentifier: (String) -> URL? = { URL(string: $0) }) async -> DeepLinkResult<Route>?
    @MainActor @discardableResult
    public func handle(searchableItemIdentifier: String, sceneID: String? = nil,
                       urlForIdentifier: (String) -> URL? = { URL(string: $0) }) async -> DeepLinkResult<Route>?

    // Home Screen quick actions (iOS): source .shortcut.
    // URL from shortcutItem.userInfo[urlKey], else the item's type when it is an absolute URL.
    @MainActor @discardableResult
    public func handle(shortcutItem: UIApplicationShortcutItem, urlKey: String = "deepLink",
                       sceneID: String? = nil) async -> DeepLinkResult<Route>?

    /// Every result produced after the stream is created; see below.
    public var results: AsyncStream<DeepLinkResult<Route>> { get }

    public func add(_ middleware: any DeepLinkMiddleware) async
    public func removeAllMiddleware() async
    public func removeMiddleware(_ type: (some DeepLinkMiddleware).Type) async
}
```

The notification, Spotlight and quick-action entry points read exactly one absolute URL (it must have a scheme) from their payload and call `handle(url:context:)`; nothing else in the payload reaches middleware or handlers, and a payload without a URL returns `nil` without running the pipeline. Treat these links as untrusted like any other: a notification payload can come from your push provider, and a Spotlight identifier from an index another version of your app wrote.

`results` returns a new stream on each access. Every live stream receives every result (success, failure, or stopped by middleware) from `handle(url:)`, `markReadyAndDrain(queue:)` and `resumePendingLinks(from:)`. Earlier results are not replayed; each stream buffers at most 100 undelivered results (oldest dropped) and finishes when the coordinator is deallocated. Cancelling the consuming task unsubscribes.

### DeepLinkCoordinatorBuilder

Fluent, immutable builder for coordinator configuration.

```swift
public struct DeepLinkCoordinatorBuilder<Route: DeepLinkRoute>: Sendable {
    public init()
    public func routing(_ routing: any DeepLinkRouting<Route>) -> Self
    public func handler(_ handler: any DeepLinkHandler<Route>) -> Self
    public func middleware(_ middleware: any DeepLinkMiddleware...) -> Self
    public func delegate(_ delegate: any DeepLinkCoordinatorDelegate<Route>...) -> Self
    public func build() throws -> DeepLinkCoordinator<Route>
}
```

### DeepLinkResult

```swift
public struct DeepLinkResult<Route: DeepLinkRoute>: Sendable {
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
    public var firstDeepLinkError: DeepLinkError?
    public var summary: String
}
```

`firstDeepLinkError` is a typed shortcut that returns the first error in `errors` that is a `DeepLinkError`, or `nil` otherwise. Prefer it over casting `firstError` when branching on framework-owned cases.

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

    public init(url: URL, maxLength: Int = defaultMaxLength, rejectDuplicateParameters: Bool = false) throws(DeepLinkError)
}
```

`queryParameters` keeps the last value of a repeated key while `allQueryParameters` keeps all of them, so two readers can disagree about a value (parameter pollution). Pass `rejectDuplicateParameters: true` to throw `DeepLinkError.invalidURL` when any key repeats (compared case-sensitively after percent-decoding, valueless keys included).

### DeepLinkError

```swift
public enum DeepLinkError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL(URL)
    case unsupportedScheme(String)
    case unsupportedHost(String)
    case missingRequiredParameter(String)
    case invalidParameterValue(name: String, value: String)
    case routeNotFound(URL)
    case parsingFailed(url: URL, underlyingErrors: [any Error & Sendable])
    case handlerError(message: String, underlyingError: (any Error & Sendable)?)
    case missingRequiredConfiguration(String)
    case rateLimitExceeded(maxRequests: Int, timeWindow: TimeInterval)
    case securityViolation(String)
    case unauthorizedAccess(URL)
    case blockedURL(URL)
    case confirmationDenied(URL)      // 2.0: user declined or did not answer

    public var redactedDescription: String { get }
    public func redactedDescription(using redactor: URLRedactor) -> String
}
```

> **Framework log sites redact by default (2.0).** Every built-in site that logs, prints or tracks URLs or error text goes through `DeepLinkLogPrivacy`, `.redacted` by default: `DefaultDeepLinkRouting` and `DeepLinkCoordinator` logs, `ReadinessMiddleware`'s queued-link log, `DeepLinkLoggingDelegate`, `DeepLinkAnalyticsDelegate` (URL envelope and `error_description(s)`), `DefaultAnalyticsProvider` (sensitive parameter names and embedded URLs), `LoggingProvider.console`, the built-in `LoggingFormat`s and `AnalyticsStrategy`s, and `DeepLinkNotificationDelegate` (`errorDetail: .redacted`). Pass `.unredacted` only while debugging. Redaction covers query, fragment and matrix parameters, userinfo and token-shaped values; plain path segments (`/reset/<token>`) are not redacted, so keep secrets out of paths or log through your own redactor.

```swift
public struct DeepLinkLogPrivacy: Sendable {
    public static let redacted: DeepLinkLogPrivacy        // default URLRedactor
    public static let unredacted: DeepLinkLogPrivacy      // full URLs and localizedDescription
    public static func redacted(using redactor: URLRedactor) -> DeepLinkLogPrivacy
    public func redact(_ url: URL) -> URL
    public func describe(_ url: URL) -> String
    public func describe(_ error: any Error) -> String    // redactedDescription, or the type name of foreign errors
    public func redactingURLs(in text: String) -> String
}

// Opt-outs
DefaultDeepLinkRouting(parsers: parsers, logPrivacy: .unredacted)
DeepLinkCoordinator(routing:handler:..., logPrivacy: .unredacted)   // builder: .logPrivacy(.unredacted)
.readiness(queue: queue, privacy: .unredacted)
.logging(enableDebugLogging: true, privacy: .unredacted)            // delegate
.analytics(provider: provider, privacy: .unredacted)                // delegate
DefaultAnalyticsProvider(privacy: .unredacted)
LoggingProvider.console(privacy: .unredacted)
.logging(format: .unredacted(.detailed))                            // middleware
.analytics(provider: provider, strategy: .unredacted(.standard))    // middleware
.notification(errorDetail: .full)
```

`errorDescription` embeds full URLs. Use `redactedDescription` for logs, analytics and user-facing text: carried URLs and every `scheme://` URL embedded in a message, host or reason go through `URLRedactor`, the value in `invalidParameterValue` is always replaced, and underlying errors that are not `DeepLinkError` are described only by their type name.

### URLRedactor

```swift
public struct URLRedactor: Sendable {
    public static let defaultSensitiveKeys: Set<String>  // token, code, password, email, key, secret, otp, auth, session, ...
    public static let defaultPlaceholder: String         // "REDACTED"
    public init(sensitiveKeys: Set<String> = defaultSensitiveKeys, placeholder: String = defaultPlaceholder)
    public func isSensitive(parameterName: String) -> Bool
    public func redact(_ url: URL) -> URL
}
```

A parameter is sensitive when its decoded name, compared case-insensitively, equals a key, has a word (split at punctuation, camel case, acronyms and letter/digit boundaries) equal to a key or its plural, or contains a key of `minimumContainedKeyLength` (5) or more characters: `access_token`, `accesstoken`, `APIKey`, `SESSIONID`, `code1`, `keys` and `e-mail` match; `keyword`, `barcode` and `state` do not. `redact(_:)` replaces the values of sensitive query, fragment and path matrix (`;jsessionid=`) parameters, any JWT-shaped value whatever its name, sensitive values inside a parameter whose value is itself a URL (recursively), and userinfo. Plain path segments are not redacted. A URL that cannot be decomposed becomes `about:blank`.

> **Equality is structural, not recursive.** The manual `Equatable` conformance never reads `localizedDescription`, so it is locale-independent. `parsingFailed` compares the URL and the *number* of underlying errors; `handlerError` compares the message and whether an underlying error is present. The `any Error & Sendable` payloads themselves are not compared, so unwrap them when a test needs to assert on their contents.

> **`parsingFailed` is flattened.** If a delegating parser itself throws `DeepLinkError.parsingFailed`, `DefaultDeepLinkRouting` splices its `underlyingErrors` into the outer collection. Consumers never see `parsingFailed(parsingFailed(...))`.

### DefaultDeepLinkRouting

Tries parsers in sequence until one succeeds.

```swift
public struct DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
    public init(parsers: [any DeepLinkParser<Route>], rejectDuplicateParameters: Bool = false)
    public func route(from url: URL) async throws -> [Route]
}
```

With `rejectDuplicateParameters: true`, a URL that repeats a query key throws `DeepLinkError.securityViolation("Duplicate query parameter")` before any parser runs.

Any other parser error moves on to the next parser, except `securityViolation` and `blockedURL` (2.0): routing stops and rethrows them, also when a delegating parser nests them in `parsingFailed`, so a laxer later parser cannot accept a link a stricter one rejected.

### DeepLinkMiddlewareCoordinator

Actor for thread-safe middleware management.

```swift
public actor DeepLinkMiddlewareCoordinator {
    public init()
    public init(middleware: [any DeepLinkMiddleware])
    public func add(_ middleware: any DeepLinkMiddleware)
    public func removeAll()
    public func remove<T: DeepLinkMiddleware>(_: T.Type)
    public func process(_ url: URL) async throws -> URL?                     // context: .unknown
    public func process(_ request: DeepLinkRequest) async throws -> DeepLinkRequest?
    public func process(_ url: URL, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> URL?
    public func process(_ request: DeepLinkRequest, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> DeepLinkRequest?
}
```

Each middleware call is wrapped in an `os_signpost` interval named `Middleware` (subsystem `swift-deep-links`, category `Middleware`) labelled with the middleware type name; URLs are never included. Inspect them with the os_signpost instrument.

`process(_:startingAfter:)` runs only the middleware registered after `anchor` (matched by identity). If `anchor` is not registered, the whole chain runs, so a missing anchor never skips security checks.

## Middleware Factory Methods

All middleware can be created using static factory methods on `DeepLinkMiddleware`:

```swift
.security(allowedSchemes:allowedHosts:blockedPatterns:allowedSources:strategy:limits:)
.rateLimit(maxRequests:timeWindow:persistence:strategy:)
.authentication(provider:protectedHosts:strategy:pendingLinks:)
.urlTransformation(transformer:strategy:)
.analytics(provider:strategy:)
.logging(provider:logLevel:format:)
.readiness(queue:)
.replayProtection(window:maxEntries:key:ignoredQueryKeys:response:dateProvider:)
.signedLinks(keys:requiredFor:parameters:requiresExpiry:leeway:nonceStore:reusedNonce:stripsSignatureParameters:dateProvider:)
.confirmation(provider:requiredFor:redactor:timeout:sleep:)
```

### Strategies

| Middleware | Strategies |
|-----------|-----------|
| `SecurityStrategy` | `.hardened` (default), `.standard`, `.strict`, `.permissive`, `.schemeOnly`, `.hostOnly`, `.patternOnly`, `.whitelist` |
| `RateLimitStrategy` | `.slidingWindow`, `.fixedWindow`, `.tokenBucket(capacity:refillRate:)`, `.permissive` |
| `AuthenticationStrategy` | `.standard`, `.strict`, `.permissive`, `.schemeBased` |
| `LoggingFormat` | `.singleLine`, `.json`, `.minimal`, `.detailed`, `.redacted(_:using:)`, `.unredacted(_:)` |
| `AnalyticsStrategy` | `.standard`, `.detailed`, `.minimal`, `.redacted(_:using:)`, `.unredacted(_:)` |
| `URLTransformationStrategy` | `.standard`, `.conditional`, `.safe`, `.aggressive`, `.selective`, `.passthrough`, `.validation` |

`SecurityStrategy.hardened` is the default strategy of `SecurityMiddleware` and `.security(...)` since 2.0. It canonicalizes the URL with `URLCanonicalizer`, compares schemes and hosts case-insensitively, and matches `blockedPatterns` case-insensitively against the raw URL and every percent-decoded form. `http(s)` links require a host on `allowedHosts`, so an empty `allowedHosts` rejects every web link; custom-scheme links must have a listed host only when `allowedHosts` is not empty. It passes the canonical URL (lower-cased scheme and host) down the chain. Pass `strategy: .standard` for the 1.x behavior.

Built-in `LoggingFormat`s and `AnalyticsStrategy`s see a `URLRedactor`-redacted URL by default (2.0). `.redacted(_:using:)` swaps in a custom redactor; `.unredacted(_:)` logs and tracks full URLs.

`RateLimitMiddleware` serializes its check-and-record step per instance, so concurrent links never exceed `maxRequests`; a request cancelled before its turn throws `CancellationError` without consuming budget. Every strategy reads and records through the atomic `RateLimitPersistence.mutateRequests(_:)` (2.0 requirement), so separate instances sharing one persistence also never exceed the limit.

```swift
public protocol RateLimitPersistence: Sendable {
    func loadRequests() async -> [TimeInterval]
    func saveRequests(_ timestamps: [TimeInterval]) async
    func clearRequests() async
    /// Read-modify-write with no suspension in between (2.0).
    func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) async -> Output
}
```

Custom persistences must implement `mutateRequests(_:)`; in an actor, call `mutation(&state)` synchronously and persist before returning. There is no default built on `loadRequests`/`saveRequests`, because it could not be atomic.

`.tokenBucket(capacity:refillRate:)` admits a burst of up to `capacity` links and then `refillRate` links per second; it ignores the middleware's `maxRequests` and `timeWindow`. When the bucket is empty it throws `rateLimitExceeded(maxRequests: capacity, timeWindow: capacity / refillRate)`. A non-positive or NaN rate never refills, and its error reports the seconds since the first admitted request as `timeWindow`; an infinite rate never limits.

### ReplayProtectionMiddleware

```swift
public final class ReplayProtectionMiddleware: DeepLinkMiddleware {
    public enum Response: Sendable { case drop, reject }
    public init(window: TimeInterval = 2, maxEntries: Int = 100, key: ReplayKeyStrategy = .url,
                ignoredQueryKeys: Set<String> = [], response: Response = .drop,
                dateProvider: @Sendable @escaping () -> Date = Date.init)
}

public struct ReplayKeyStrategy: Sendable {
    public init(_ makeKey: @escaping @Sendable (URL) -> String?)
    public static let url: ReplayKeyStrategy   // scheme/host case and query order ignored
    public static let path: ReplayKeyStrategy  // scheme, host, port and path only
    public static func queryParameter(_ name: String) -> ReplayKeyStrategy
    public static func custom(_ makeKey: @escaping @Sendable (URL) -> String?) -> ReplayKeyStrategy
}
```

A link is a replay when its key was first seen less than `window` seconds earlier; replays do not extend the window. `.drop` stops the chain silently (`wasStoppedByMiddleware`), `.reject` throws `DeepLinkError.securityViolation("Replayed deep link")`. A `nil` key (for example `.queryParameter("nonce")` on a link without `nonce`) is never deduplicated. `ignoredQueryKeys` are removed before the key is computed. At most `maxEntries` keys are remembered, in memory only; when full, the oldest is evicted and may be admitted again inside its window. A non-positive or NaN `window` disables protection; entries seen "in the future" after a clock rollback count as expired. `.url` and `.path` normalize equivalent percent-encodings; `.queryParameter` keys on the value alone, so use unguessable values. A key is recorded even if later middleware rejects the link: place it after `.security(...)`, `.rateLimit(...)` and `.authentication(...)`, otherwise a protected link resumed inside the window is dropped as a replay.

### SignedLinkMiddleware

Available where `CryptoKit` can be imported.

```swift
public final class SignedLinkMiddleware: DeepLinkMiddleware {
    public init(keys: any SigningKeyProvider, requiredFor matcher: DeepLinkMatcher = .all,
                parameters: SignedLinkParameters = .default, requiresExpiry: Bool = true,
                leeway: TimeInterval = 0, nonceStore: (any NonceStore)? = nil,
                reusedNonce: ReusedNonceResponse = .reject,   // or .drop: stop silently
                stripsSignatureParameters: Bool = true,
                dateProvider: @Sendable @escaping () -> Date = Date.init)
    public static let missingSignatureReason, invalidSignatureReason, missingExpiryReason,
                      invalidExpiryReason, expiredReason, missingNonceReason, reusedNonceReason: String
}

public protocol SigningKeyProvider: Sendable {
    func verificationKey(forKeyID keyID: String?) async -> SymmetricKey?
}
public struct SigningKeyring: SigningKeyProvider {
    public init(keys: [String: SymmetricKey], defaultKeyID: String? = nil)
    public init(key: SymmetricKey)  // registered as "default", used for links without kid
}

public protocol NonceStore: Sendable {
    func consume(_ nonce: String, expiresAt: Date) async -> Bool  // atomic, true once
    // Two-phase (defaults consume at once and never release):
    func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation?
    func commit(_ reservation: NonceReservation) async
    func release(_ reservation: NonceReservation) async
}
public struct NonceReservation: Sendable, Hashable, Codable { public let nonce: String; public let expiresAt: Date; public let token: UUID }
public final class InMemoryNonceStore: NonceStore {
    public static let defaultReservationTTL: TimeInterval  // 300
    public init(maxEntries: Int = 1000, reservationTTL: TimeInterval = defaultReservationTTL,
                dateProvider: @Sendable @escaping () -> Date = Date.init)
}

public actor UserDefaultsNonceStore: NonceStore {
    public static let defaultKey: String  // "deeplink.signed-links.nonces"
    public init(userDefaults: UserDefaults = .standard, key: String = defaultKey, maxEntries: Int = 1000,
                reservationTTL: TimeInterval = InMemoryNonceStore.defaultReservationTTL,
                dateProvider: @Sendable @escaping () -> Date = Date.init)
}

public struct SignedLinkBuilder: Sendable {
    public init(key: SymmetricKey, keyID: String? = nil, parameters: SignedLinkParameters = .default)
    public func sign(_ url: URL, expiresAt: Date? = nil, nonce: String? = nil) throws(DeepLinkError) -> URL
}

public struct SignedLinkParameters: Sendable, Hashable {  // sig, exp, nonce, kid
    public init(signature: String = "sig", expiry: String = "exp", nonce: String = "nonce", keyID: String = "kid")
}
```

**Canonical form** (what the HMAC covers; implement it identically on your server): seven lines joined by `\n`, no trailing newline:

```
DLSIG1
<scheme, lower-cased>
<percent-encoded host, lower-cased>
<port, or empty>
<percent-encoded path>
<query items except sig, "name=value" or "name", sorted by UTF-8 bytes, joined by "&">
<percent-encoded fragment, or empty>
```

Path, query items and fragment first decode escapes of RFC 3986 unreserved characters (`A-Z a-z 0-9 - . _ ~`) and upper-case the remaining escapes. The signature is `base64url(HMAC-SHA256(key, canonical))` without padding, appended as the last `sig` parameter. `kid`, `exp` and `nonce` are ordinary query items and therefore signed. Userinfo (`user:pass@`) is not part of the canonical form: keep `.security(...)` with `.hardened` (which rejects userinfo) in front. Links from notifications, Spotlight and quick actions are checked like any other, so payloads pointing at a signed path must carry the signed URL.

Checks run in order: one `sig` and at most one `kid`/`exp`/`nonce`; constant-time HMAC verification with the key returned for `kid` (an unknown key id fails like a bad signature); `exp` (whole seconds since 1970, valid while `now < exp + leeway`; `leeway` only extends validity after expiry and counts as `0` when negative, infinite or NaN), required when `requiresExpiry` is `true` or a nonce store is set; finally the nonce is consumed (only after the signature is verified, so forged links cannot burn nonces). Failures throw `DeepLinkError.securityViolation` with one of the fixed reasons. Links the matcher does not select pass unchanged. `InMemoryNonceStore` keeps nonces until their link expires and rejects new nonces when `maxEntries` live ones are stored, rather than evicting one that could then be replayed; it does not survive relaunch. `UserDefaultsNonceStore` persists spent nonces (versioned JSON, pruned by expiry on load and when full) so links stay single-use across launches; open reservations live in memory and are dropped on relaunch, so a link interrupted by termination can be retried (a link whose handler finished just before the app was killed, before the commit was written, could run once more within its expiry). Unreadable stored data starts an empty store. Inside `DeepLinkCoordinator` the nonce is reserved when the link passes and settled through `didFinish(_:outcome:)`: committed when the link succeeds or readiness queues it, released when a later middleware, the router or a handler stops or fails it, so the link can be retried or resumed after sign-in. Called directly, the middleware consumes at once. Place `.replayProtection(...)` before `.signedLinks(...)` so a duplicate delivery is dropped quietly, or pass `reusedNonce: .drop`.

### ConfirmationMiddleware

```swift
public final class ConfirmationMiddleware: DeepLinkMiddleware {
    public init(provider: any DeepLinkConfirmationProvider, requiredFor matcher: DeepLinkMatcher = .all,
                redactor: URLRedactor = URLRedactor(), timeout: Duration? = nil,
                sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
}

public protocol DeepLinkConfirmationProvider: Sendable {
    func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool
}

public struct DeepLinkConfirmationRequest: Sendable, Hashable {
    public var url: URL                 // redacted, safe to display
    public var context: DeepLinkContext
}
```

Asks the user before a sensitive link continues. Approval passes the request on unchanged; denial or no answer within `timeout` throws `DeepLinkError.confirmationDenied(url)`. On timeout, or when the link's task is cancelled, the link is denied immediately, even if the provider ignores cancellation, and the task running `confirm` is cancelled: dismiss the prompt and resume with `false` in a cancellation handler. Prompts are serialized; a link cancelled while waiting for its turn throws `CancellationError` without being shown. Place it after `.readiness(...)` and every rejecting middleware, so the user is never asked about a link that would be rejected anyway.

### Route-Level Rules

```swift
public struct RouteMatcher<Route: DeepLinkRoute>: Sendable {
    public init(_ predicate: @escaping @Sendable (Route, DeepLinkContext) -> Bool)
    public func matches(_ route: Route, context: DeepLinkContext) -> Bool
    public static var all: RouteMatcher { get }
    public static func routes(where predicate: @escaping @Sendable (Route) -> Bool) -> RouteMatcher
    public static func custom(_ predicate: @escaping @Sendable (Route, DeepLinkContext) -> Bool) -> RouteMatcher
}

public struct SignedRouteGuard<Route: DeepLinkRoute>: DeepLinkHandler {
    public static var unsignedRouteReason: String { get }  // "Route requires a signed link"
    public init(_ handler: any DeepLinkHandler<Route>, requiredFor matcher: RouteMatcher<Route>)
}

public struct ConfirmingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
    public init(_ handler: any DeepLinkHandler<Route>, requiredFor matcher: RouteMatcher<Route>,
                timeout: Duration? = nil, sleep: … = { try await Task.sleep(for: $0) },
                confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool)
}

public extension DeepLinkHandler {
    func requiringSignature(for matcher: RouteMatcher<Route>) -> SignedRouteGuard<Route>
    func confirming(_ matcher: RouteMatcher<Route>, timeout: Duration? = nil,
                    confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool) -> ConfirmingHandler<Route>
}
```

Route rules decide on the route the parsers produced, so they hold however the URL was spelled; they are the strongest protection. `SignedRouteGuard` throws `securityViolation(unsignedRouteReason)` for a protected route unless `context.isSignatureVerified`, which only `SignedLinkMiddleware` sets (it verifies every link carrying a signature, whatever its URL rule); keep that middleware in the chain. `ConfirmingHandler` asks `confirm` with the route, so the prompt can describe the action; denial or timeout throws `confirmationDenied` with the arriving URL (`about:blank` outside a coordinator), and the timeout wins even if `confirm` ignores cancellation. Use URL rules (`DeepLinkMatcher`) in addition when you want to reject before parsing and other middleware run.

### DeepLinkMatcher


```swift
public struct DeepLinkMatcher: Sendable {
    public init(_ predicate: @escaping @Sendable (DeepLinkRequest) -> Bool)
    public func matches(_ request: DeepLinkRequest) -> Bool
    public static let all: DeepLinkMatcher
    public static func hosts(_ hosts: Set<String>) -> DeepLinkMatcher
    public static func paths(_ prefixes: Set<String>) -> DeepLinkMatcher
    public static func sources(_ sources: Set<DeepLinkContext.Source>) -> DeepLinkMatcher
    public static func custom(_ predicate: @escaping @Sendable (DeepLinkRequest) -> Bool) -> DeepLinkMatcher
    public static func anyOf(_ matchers: DeepLinkMatcher...) -> DeepLinkMatcher
    public static func allOf(_ matchers: DeepLinkMatcher...) -> DeepLinkMatcher
}
```

Selects the links a policy middleware applies to. Hosts compare case-insensitively ignoring a trailing dot. `paths` matches a prefix on segment boundaries (`/reset` matches `/reset/abc`, not `/resetting`), case-insensitively, after percent-decoding (up to `URLCanonicalizer.maximumDecodingPasses` times), collapsing empty segments, treating `\` as a separator, dropping `;` parameters and invisible or control characters, and resolving `.`/`..`, so encoded spellings of a protected path stay protected. A path that cannot be decoded, or is still encoded after the last pass, matches every prefix (fail closed). For schemes other than `http(s)` the host is also matched as the first segment, so `.paths(["/reset"])` covers `myapp://reset` and `https://example.com/reset`; web hosts never count as path segments.

### URLCanonicalizer

```swift
public struct URLCanonicalizer: Sendable {
    public static let maximumDecodingPasses: Int  // 4
    public let limits: DeepLinkInputLimits
    public init(limits: DeepLinkInputLimits = .unlimited)
    public func canonicalize(_ url: URL) throws(DeepLinkError) -> URL
    public func matchableForms(of url: URL) -> [String]
}
```

`canonicalize(_:)` lower-cases the scheme and host and throws `DeepLinkError.securityViolation` for userinfo, control characters, invisible Unicode format and line/paragraph separator characters (bidi overrides, zero-width space, BOM, U+2028/U+2029; this also rejects the zero-width joiner in emoji sequences), `..` path segments (raw or percent-encoded, including `%252e%252e` and `..%5C`), and malformed or over-nested percent-encoding. The `..` check covers the path only, not the query or fragment. Each decoding pass decodes every valid `%HH` escape and keeps invalid ones literally, so a stray `%zz` cannot hide what follows. `matchableForms(of:)` returns the raw absolute string followed by each percent-decoding pass.

### DeepLinkInputLimits

```swift
public struct DeepLinkInputLimits: Sendable, Equatable {
    public static let unlimited: DeepLinkInputLimits
    public static let recommended: DeepLinkInputLimits  // 8192 chars, 50 params, 1024-char values
    public init(maxURLLength: Int? = nil, maxQueryParameterCount: Int? = nil, maxParameterValueLength: Int? = nil, rejectDuplicateParameters: Bool = false)
    public func validate(_ url: URL) throws(DeepLinkError)
}
```

Bounds the work an untrusted link can cause. `SecurityMiddleware` and `URLCanonicalizer` check the limits before anything else and throw `DeepLinkError.securityViolation`. The URL length is checked before the query is parsed; the parameter count includes duplicates and valueless parameters; value lengths are measured after percent-decoding. `rejectDuplicateParameters: true` throws `securityViolation("Duplicate query parameter")` for a repeated key, so the check runs in the middleware chain rather than only in `DeepLinkURL`. `nil` disables a limit and negative values are clamped to `0`. Error messages never include the attacker-controlled parameter name or value. Put `.security(..., limits: .recommended)` first in the chain so oversized links never reach logging, analytics or parsing.

## Pending Links

```swift
public protocol PendingLinkStore: Sendable {
    func save(_ url: URL) async       // newest last; re-saving moves the URL to the end
    func takeAll() async -> [URL]     // unexpired links, oldest first; empties the store
    func removeAll() async
    // Keep the context (defaults wrap the URL forms and resume with .unknown):
    func save(_ request: DeepLinkRequest) async
    func takeAllRequests() async -> [DeepLinkRequest]
}

public actor InMemoryPendingLinkStore: PendingLinkStore {
    public init(maxCount: Int = 1, expiry: TimeInterval = 300, dateProvider: @Sendable @escaping () -> Date = Date.init)
}

public actor UserDefaultsPendingLinkStore: PendingLinkStore {
    public init(userDefaults: UserDefaults = .standard, key: String = "deeplink.pending.links",
                maxCount: Int = 1, expiry: TimeInterval = 300, dateProvider: @Sendable @escaping () -> Date = Date.init)
}

public extension DeepLinkCoordinator {
    @discardableResult
    func resumePendingLinks(from store: any PendingLinkStore) async -> [DeepLinkResult<Route>]
}
```

`AuthenticationMiddleware` saves the link as it entered the chain, with its context, and `resumePendingLinks(from:)` replays it with that context through the whole chain. `UserDefaultsPendingLinkStore` persists the context as versioned JSON (`source`, `sourceApplication`, `sceneID`) but never the signature-verified flag, so a resumed link is verified again; links saved by 1.x or with an unknown source load as `.unknown`.

Pass a store to `AuthenticationMiddleware(authProvider:protectedHosts:strategy:pendingLinks:)` (or `.authentication(..., pendingLinks:)`) and a link rejected with `unauthorizedAccess` is saved before the error propagates. After sign-in, `resumePendingLinks(from:)` runs each saved link through the **whole** chain again, so authentication, security and rate limiting are evaluated at resume time; a link that is still unauthorized is saved again. Stores keep at most `maxCount` links (oldest dropped, clamped to at least 1) and discard links older than `expiry` seconds. Only the URL and its save time are stored; the `UserDefaults` store writes them unencrypted, so prefer the in-memory store when protected links carry secrets. Call `removeAll()` on sign-out so one account's pending link never runs for another. Any app or page can trigger a protected link, so only protect routes that are safe to run after sign-in without a fresh user action, or confirm before acting.

## Readiness

### ReadinessQueue Protocol

```swift
public protocol ReadinessQueue: ReadinessCondition {
    func enqueue(_ url: URL) -> URL?
    func markReady() -> [URL]
    var pendingCount: Int { get }
    var pendingURLs: [URL] { get }
    func reset()
    // Keep the context (defaults wrap the URL forms and replay with .unknown):
    func enqueue(_ request: DeepLinkRequest) -> DeepLinkRequest?
    func markReadyReturningRequests() -> [DeepLinkRequest]
    var pendingRequests: [DeepLinkRequest] { get }
}
```

`DeepLinkReadinessQueue` and `ReadinessMiddleware` keep the whole request, so `markReadyAndDrain(queue:)` replays each link with its source, source application, scene and signature-verified flag.

### DeepLinkReadinessQueue

Thread-safe queue backed by `OSAllocatedUnfairLock`. Compiler-verified `Sendable`.

```swift
public final class DeepLinkReadinessQueue: ReadinessQueue, Sendable {
    public init(maxQueueSize: Int? = nil, onEvict: (@Sendable (URL) -> Void)? = nil)  // size clamped to min 1
    public var isReady: Bool { get }
    public func enqueue(_ url: URL) -> URL?
    public func markReady() -> [URL]       // idempotent; drains the queue
    public var pendingCount: Int { get }
    public var pendingURLs: [URL] { get }  // snapshot without draining
    public func reset()                    // re-gates, discards pending
}
```

> Any app or web page can fire links before your app is ready, so an unbounded
> queue grows without limit. Prefer a `maxQueueSize` in production and pass
> `onEvict` to observe the oldest links dropped to make room; it runs after the
> queue lock is released, on the enqueuing thread.

> Prefer `pendingURLs` over `markReady()` when you only need to inspect the queue.
> Calling `markReady()` drains the queue — dropping the returned URLs loses them
> permanently.

### Coordinator helper

```swift
public extension DeepLinkCoordinator {
    @discardableResult
    func markReadyAndDrain(queue: any ReadinessQueue) async -> [DeepLinkResult<Route>]
}
```

Marks the queue ready and drains every pending URL, **resuming the middleware chain right after the `ReadinessMiddleware` that queued it**. Middleware placed before the readiness gate does not run a second time; middleware placed after it (authentication, security, rate limiting, transforms) evaluates each link at drain time, so state that changed while the link waited (for example a sign-out) is honored. If the queue is not registered through a `ReadinessMiddleware`, drained URLs run through the whole chain. Delegate notifications continue to fire for each drained URL.

## Delegates

### DeepLinkCoordinatorDelegate

Generic, `@MainActor`-isolated protocol. All methods have default empty implementations.

```swift
@MainActor
public protocol DeepLinkCoordinatorDelegate<Route>: Sendable {
    associatedtype Route: DeepLinkRoute
    func coordinator(_ coordinator: DeepLinkCoordinator<Route>, willProcess url: URL)
    func coordinator(_ coordinator: DeepLinkCoordinator<Route>, didProcess url: URL, result: DeepLinkResult<Route>)
    func coordinator(_ coordinator: DeepLinkCoordinator<Route>, didFailProcessing url: URL, error: Error)
}
```

Value types (structs) and actors can now adopt `DeepLinkCoordinatorDelegate`; the protocol no longer requires reference semantics.

### Delegate Factory Methods

```swift
.logging(enableDebugLogging:)
.analytics(provider:)
.notification(showSuccess:showErrors:showInfo:presenter:errorDetail:)   // iOS, macOS, watchOS, visionOS only
```

`errorDetail` (`DeepLinkNotificationErrorDetail`) controls failure text: `.full` (default, `localizedDescription`), `.redacted` / `.redacted(using:)` (`redactedDescription`, type name for foreign errors) or `.generic` (no error text). Notifications can appear on the lock screen, so prefer `.redacted` or `.generic`.

### Notification Presenter

Custom surfaces (toasts, in-app banners, test doubles) can replace the
default `UNUserNotificationCenter` sink:

```swift
public enum DeepLinkNotificationKind: Sendable { case success, failure, info }

public protocol DeepLinkNotificationPresenter: Sendable {
    func present(
        kind: DeepLinkNotificationKind,
        title: String,
        body: String,
        identifier: String,
    ) async throws
}

public struct DefaultDeepLinkNotificationPresenter: DeepLinkNotificationPresenter { }
```

### Composition Functions

```swift
@MainActor public func compose<Route>(_ delegates: any DeepLinkCoordinatorDelegate<Route>...) -> CompositeDeepLinkDelegate<Route>
@MainActor public func compose<Route>(_ delegates: [any DeepLinkCoordinatorDelegate<Route>]) -> CompositeDeepLinkDelegate<Route>
```

Middleware arrays are passed directly to ``DeepLinkCoordinatorBuilder.middleware(_:)`` — no `compose` helper is required.

## SwiftUI Integration

Gated behind `#if canImport(SwiftUI)`. Attaches both `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` handlers to a view, routing both to the given coordinator.

```swift
public extension View {
    func onDeepLink<Route: DeepLinkRoute>(_ coordinator: DeepLinkCoordinator<Route>) -> some View
    func onDeepLink<Route: DeepLinkRoute>(_ coordinator: DeepLinkCoordinator<Route>?) -> some View
    func onDeepLink<Route: DeepLinkRoute>(_ coordinator: DeepLinkCoordinator<Route>, sceneID: String?) -> some View
    func onDeepLink<Route: DeepLinkRoute>(_ coordinator: DeepLinkCoordinator<Route>?, sceneID: String?) -> some View
}
```

Usage:

```swift
ContentView()
    .onDeepLink(coordinator)
```

SwiftUI exposes no scene identifier, so the `sceneID:` overloads take one from the app (a UUID in `@SceneStorage` works) and put it in `DeepLinkContext.sceneID` for both `onOpenURL` and Universal Link activities. An empty string counts as no scene.

## Multiple Scenes

```swift
public final class SceneRoutingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
    public static var noSceneHandlerMessage: String { get }
    public init(fallback: (any DeepLinkHandler<Route>)? = nil)
    public var registeredSceneIDs: Set<String> { get }
    public func register(_ handler: any DeepLinkHandler<Route>, forScene sceneID: String)
    public func unregister(scene sceneID: String)
}
```

Use it as the coordinator's handler: each link goes to the handler registered for its `context.sceneID`, which receives the full context. Links without a scene or from an unregistered scene (closed window, `handle(url:)`, a custom queue or store that keeps only URLs) go to `fallback`; without one they fail with `handlerError(message: noSceneHandlerMessage, underlyingError: nil)`. The scene ID reaches the context through `handle(url:context:)`, `handle(activity:handoffActivityTypes:sceneID:)`, the notification, Spotlight and quick-action entry points (`sceneID:`; notifications default to the response's `targetScene` on iOS/visionOS) and `onDeepLink(_:sceneID:)`.

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

### PathPatternParser

```swift
public struct PathPatternParser<Route: DeepLinkRoute>: DeepLinkParser {
    public enum Scope: Sendable { case path, hostAndPath }
    public static var defaultAllowedCharacters: CharacterSet  // RFC 3986 unreserved ASCII
    public init(_ template: String, hosts: Set<String> = [], scope: Scope = .path,
                allowedCharacters: CharacterSet = Self.defaultAllowedCharacters,
                build: @escaping @Sendable (PathPatternMatch) throws -> Route) throws(PathPatternError)
}

// Factory (dot-shorthand wherever a parser is expected)
static func pattern<R>(_ template: String, hosts:scope:allowedCharacters:build:) throws(PathPatternError) -> PathPatternParser<R>

public struct PathPatternMatch: Sendable {
    public let url: URL
    public let wildcard: [String]
    public subscript(name: String) -> String?
    public func string(_ name: String) throws -> String
    public func int(_ name: String) throws -> Int     // canonical non-negative only (2.0)
    public func uuid(_ name: String) throws -> UUID
    public func value<T: LosslessStringConvertible>(_ name: String, as: T.Type = T.self) throws -> T
}

public enum PathPatternError: Error, Equatable, Sendable, LocalizedError {
    case invalidCaptureName(String), duplicateCaptureName(String), wildcardNotLast, invalidLiteral(String)
}
```

Templates are `/`-separated: literals match exactly (case-sensitive), `:name` captures one segment, and a trailing `*` captures the remaining segments. Empty segments are ignored. The path is split before decoding, each segment is percent-decoded once, a decoded `.` or `..` throws `securityViolation("Path traversal is not allowed")`, and captured or wildcard values with characters outside `allowedCharacters` throw `invalidParameterValue`. `int(_:)` accepts only `0` or digits without a leading zero: `-5`, `+5` and `007` throw `invalidParameterValue`, so one resource has one spelling. Use `value(name, as: Int.self)` for the lenient `Int(_:)` conversion (1.x behavior). A host or structure mismatch throws `routeNotFound`, so `DefaultDeepLinkRouting` moves on to the next parser; a traversal `securityViolation` stops routing (2.0). Still reject traversal before routing with `.security(..., strategy: .hardened)`, so logging and analytics never see it.

```swift
.parsers([
    try .pattern("/products/:id") { try .product(id: $0.int("id")) },
    try .pattern("products/:id", scope: .hostAndPath) { try .product(id: $0.int("id")) },  // myapp://products/42
])
```

## Diagnostics

```swift
public struct DeepLinkDiagnostics: Sendable {
    public let declaredURLSchemes: Set<String>   // lower-cased CFBundleURLTypes schemes
    public let associatedDomains: [String]
    public init(bundle: Bundle = .main, associatedDomains: [String] = [],
                ignoredDeclaredSchemes: Set<String> = [], ignoredDeclaredSchemePrefixes: Set<String> = [])
    public init(declaredURLSchemes: Set<String>, associatedDomains: [String] = [],
                ignoredDeclaredSchemes: Set<String> = [], ignoredDeclaredSchemePrefixes: Set<String> = [])
    public static func declaredURLSchemes(inInfoDictionary info: [String: Any]?) -> Set<String>
    public func checkSecurityConfiguration(allowedSchemes: Set<String>, allowedHosts: Set<String>) -> [DeepLinkDiagnosticWarning]
    public func checkParsers<Route>(_ parsers: [any DeepLinkParser<Route>], probes: [URL]) async -> [DeepLinkDiagnosticWarning]
}

public enum DeepLinkDiagnosticWarning: Sendable, Hashable, CustomStringConvertible {
    case emptyAllowedSchemes
    case schemeNotDeclared(String)
    case declaredSchemeNotAllowed(String)
    case webSchemeWithoutAllowedHosts
    case hostNotInAssociatedDomains(String)
    case associatedDomainNotAllowed(String)
    case unhandledProbe(URL)
    case shadowedParsers(probe: URL, handledBy: Int, shadowed: [Int])
}
```

Run it from a unit test or a `#if DEBUG` hook; it never changes link handling. **Limits:** entitlements cannot be read at runtime, so pass your `applinks:` values in `associatedDomains` (without them the associated-domain checks are skipped); only allowed hosts containing a `.` are treated as web domains; the `apple-app-site-association` file is not fetched or validated; parser checks cover only the probes you supply and call every parser for each probe, so parsers must be side-effect free. A wildcard `applinks:*.example.com` covers subdomains, not `example.com` itself. Pass third-party SDK callback schemes in `ignoredDeclaredSchemes` or `ignoredDeclaredSchemePrefixes` (for example `fb` for `fb<app id>`) so they are not reported as `declaredSchemeNotAllowed`.

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
public final class CollectingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
    public var handledRoutes: [Route] { get }
    public var handledContexts: [DeepLinkContext] { get }  // same order; .unknown for handle(_:) calls
}
```

### CollectingMiddleware / PassthroughMiddleware

```swift
public final class CollectingMiddleware: DeepLinkMiddleware {
    public var interceptedURLs: [URL] { get }  // passes through and records
}

public struct PassthroughMiddleware: DeepLinkMiddleware, Sendable { }  // no-op
```

### CollectingDelegate

`@MainActor`-isolated. Accumulates lifecycle events.

```swift
@MainActor
public final class CollectingDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
    public var willProcessURLs: [URL] { get }
    public var processedEvents: [ProcessedEvent] { get }  // .url, .result
    public var failedEvents: [FailedEvent] { get }        // .url, .error
}
```

### CollectingAnalyticsProvider

Thread-safe. Converts `[String: Any]` parameters to `[String: String]`.

```swift
public final class CollectingAnalyticsProvider: AnalyticsProvider {
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
    public func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) -> Output
}
```

### CollectingConfirmation

```swift
public final class CollectingConfirmation: DeepLinkConfirmationProvider {
    public init(approves: Bool)
    public var approves: Bool { get set }
    public var requests: [DeepLinkConfirmationRequest] { get }
}
```

Answers every prompt with `approves` and records the requests (redacted URL and context).

### ManualDateProvider

```swift
public final class ManualDateProvider: Sendable {
    public static let defaultStart: Date  // 2023-11-14T22:13:20Z
    public init(now: Date = ManualDateProvider.defaultStart)
    public var now: Date { get set }
    public var dateProvider: @Sendable () -> Date { get }  // reads the clock on every call
    public func advance(by seconds: TimeInterval)
}
```

Pass `dateProvider` to `RateLimitMiddleware`, `ReplayProtectionMiddleware` or the pending-link stores and call `advance(by:)` instead of sleeping.

### URLFuzzCorpus

```swift
public enum URLFuzzCorpus {
    public static func hostile(scheme: String = "https", host: String = "example.com") -> [URLFuzzCase]
    public static func hostile(_ category: URLFuzzCase.Category, scheme: String = "https", host: String = "example.com") -> [URLFuzzCase]
}

public struct URLFuzzCase: Sendable, Hashable, CustomStringConvertible {
    public enum Category: String, Sendable, CaseIterable {
        case traversal, encoding, controlCharacters, hostConfusion, internationalizedHost, duplicateParameters, oversize, scheme
    }
    public let category: Category
    public let name: String
    public let url: URL
}
```

Hostile URLs built around the scheme and host you allow, for parameterized security tests. `.security(..., strategy: .hardened, limits:)` with `rejectDuplicateParameters: true` rejects every case. The corpus pins known bypasses; it is not exhaustive.

```swift
@Test(arguments: URLFuzzCorpus.hostile(scheme: "https", host: "example.com"))
func rejectsHostileURL(_ fuzzCase: URLFuzzCase) async {
    await #expect(throws: DeepLinkError.self) { try await security.intercept(fuzzCase.url) }
}
```

## Thread Safety

- `DeepLinkCoordinator` — `Sendable` final class, immutable `let` properties
- `DeepLinkMiddlewareCoordinator` — `actor`
- `DeepLinkReadinessQueue` — `OSAllocatedUnfairLock`, compiler-verified `Sendable`
- `UserDefaultsRateLimitPersistence` — `actor`
- All protocols — `Sendable`
- Delegates — `@MainActor`-isolated
