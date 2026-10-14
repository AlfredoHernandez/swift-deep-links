# Migrating from 1.x to 2.0

2.0 makes deep links secure by default and lets every component see where a
link came from. Most apps need a handful of mechanical edits. This guide lists
every source or behavior break since `1.1.0`, each with a before/after
snippet, then the recommended middleware order and a hardening checklist.

New, additive features (signed links, confirmation prompts, replay
protection, token-bucket limits, path patterns, pending links, notification /
Spotlight / quick-action entry points, multi-scene routing, diagnostics) are
described in the [CHANGELOG](CHANGELOG.md) and the
[Securing your deep links](docs/securing-deep-links-en.md) guide.

## Contents

1. [Coordinator and builder](#1-coordinator-and-builder)
2. [Routes, handlers and delegates](#2-routes-handlers-and-delegates)
3. [Middleware receives a request with context](#3-middleware-receives-a-request-with-context)
4. [Errors](#4-errors)
5. [Routing stops at security errors](#5-routing-stops-at-security-errors)
6. [Secure defaults](#6-secure-defaults)
7. [Rate-limit persistence](#7-rate-limit-persistence)
8. [`handle(activity:)` checks the activity type](#8-handleactivity-checks-the-activity-type)
9. [`PathPatternMatch.int` is canonical](#9-pathpatternmatchint-is-canonical)
10. [Removed APIs](#10-removed-apis)
11. [Recommended middleware order](#recommended-middleware-order)
12. [Hardening checklist](#hardening-checklist)

## 1. Coordinator and builder

**`build()` is synchronous.**

```swift
// 1.x
let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>().routing(routing).handler(handler).build()

// 2.0
let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>().routing(routing).handler(handler).build()
```

Drop `async` from your own factory protocols that wrap `build()`.

**No implicit delay between routes.** `routeExecutionDelay` defaults to
`.zero` (was 500 ms).

```swift
// 2.0: restore the 1.x pacing explicitly
DeepLinkCoordinator(routing: routing, handler: handler, routeExecutionDelay: .milliseconds(500))
// or: DeepLinkCoordinatorBuilder<AppRoute>()....routeExecutionDelay(.milliseconds(500))
```

**`DeepLinkCoordinator`'s public initializer is a `convenience` init.** The
class is `final`, so only code delegating to it with `self.init` from an
extension is affected.

**Prefer passing the context.** `handle(url:)` still works and uses the
`.unknown` source; entry points that know the channel should say so, so
per-source policy works:

```swift
// 1.x
Task { await coordinator.handle(url: context.url) }

// 2.0
let deepLinkContext = DeepLinkContext.openedURL(
    context.url,
    sourceApplication: context.options.sourceApplication,
    sceneID: scene.session.persistentIdentifier
)
Task { await coordinator.handle(url: context.url, context: deepLinkContext) }
```

## 2. Routes, handlers and delegates

**`DeepLinkRoute` requires `Equatable & Hashable & Sendable`.** Enums
synthesize both; structs must declare them.

```swift
// 1.x
struct ProductRoute: DeepLinkRoute { let id: String }

// 2.0
struct ProductRoute: DeepLinkRoute, Hashable { let id: String }
```

**Handlers can read the context** (optional). The coordinator now calls
`handle(_:context:)`, which defaults to your existing `handle(_:)`.
Implement exactly one of them.

```swift
// 2.0 (only when you need the source or scene)
func handle(_ route: AppRoute, context: DeepLinkContext) async throws {
    try await navigator(for: context.sceneID).show(route)
}
```

**`DeepLinkCoordinatorDelegate` no longer requires `AnyObject`** and is generic
over `Route` (`DeepLinkResultProtocol` was removed):

```swift
// 1.x
final class Observer: DeepLinkCoordinatorDelegate {
    func coordinator(_ c: AnyObject, didProcess url: URL, result: any DeepLinkResultProtocol) { … }
}

// 2.0 (a struct or actor works too)
@MainActor
struct Observer: DeepLinkCoordinatorDelegate {
    func coordinator(_ c: DeepLinkCoordinator<AppRoute>, didProcess url: URL, result: DeepLinkResult<AppRoute>) { … }
}
```

## 3. Middleware receives a request with context

`DeepLinkMiddleware` has a new requirement,
`intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest?`.
1.x middleware implementing `intercept(_ url: URL)` keeps compiling and
running (the context is preserved around it), but that form is deprecated and
will be removed in 3.0. Implement exactly one form.

```swift
// 1.x
struct StripTracking: DeepLinkMiddleware {
    func intercept(_ url: URL) async throws -> URL? { url.removingTracking() }
}

// 2.0
struct StripTracking: DeepLinkMiddleware {
    func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
        request.replacingURL(request.url.removingTracking())
    }
}
```

`DeepLinkMiddlewareCoordinator.process(_:)` takes a `DeepLinkRequest`;
`CollectingMiddleware` adds `interceptedRequests`. Links replayed from a
readiness queue or a pending-link store carry the `.unknown` source.

`AdvancedDeepLinkMiddleware` / `MiddlewareResult` were removed (see
[Removed APIs](#10-removed-apis)).

## 4. Errors

**Case reshape.**

```swift
// 1.x
throw DeepLinkError.routeNotFound(url.host ?? "")
throw DeepLinkError.invalidParameterValue("id", raw)
throw DeepLinkError.rateLimitExceeded(10, 60)
throw DeepLinkError.handlerError("Navigation failed")
throw DeepLinkError.unauthorizedAccess(url.absoluteString)
throw DeepLinkError.blockedURL(url.absoluteString)

// 2.0
throw DeepLinkError.routeNotFound(url)
throw DeepLinkError.invalidParameterValue(name: "id", value: raw)
throw DeepLinkError.rateLimitExceeded(maxRequests: 10, timeWindow: 60)
throw DeepLinkError.handlerError(message: "Navigation failed", underlyingError: error)
throw DeepLinkError.unauthorizedAccess(url)
throw DeepLinkError.blockedURL(url)
```

**New cases** `parsingFailed(url:underlyingErrors:)` (every parser threw) and
`confirmationDenied(URL)` (the user declined a `ConfirmationMiddleware`
prompt or did not answer in time). Exhaustive switches need branches for them:

```swift
switch error {
case .confirmationDenied:
    break                        // the user said no: not an error to report
case .securityViolation, .blockedURL:
    reportSuspiciousLink()
default:
    showGenericError()
}
```

**Equality** compares `parsingFailed` by URL and error count and
`handlerError` by message and whether an underlying error exists. Unwrap the
payloads to compare them in depth.

**Descriptions.** `errorDescription` still embeds full URLs. Use
`redactedDescription` for logs, analytics and UI:

```swift
// 1.x
logger.error("\(error.localizedDescription)")

// 2.0
logger.error("\(error.redactedDescription)")
```

## 5. Routing stops at security errors

`DefaultDeepLinkRouting` used to try the next parser after any error. A parser
throwing `securityViolation` or `blockedURL` (directly or nested in a
`parsingFailed`) now ends routing, so a laxer parser cannot accept a link a
stricter one rejected. When every parser throws, routing throws
`parsingFailed` instead of a bare `routeNotFound`.

```swift
// 1.x: "not mine" signalled with a security error
guard url.host() == "product" else { throw DeepLinkError.securityViolation("wrong host") }

// 2.0
guard url.host() == "product" else { throw DeepLinkError.routeNotFound(url) }
```

## 6. Secure defaults

**`SecurityMiddleware` uses `.hardened`.** `http(s)` links need their host in
`allowedHosts` (an empty set rejects every web link); custom-scheme hosts are
checked once you list any host.

```swift
// 1.x: any https host passed
.security(allowedSchemes: ["https", "myapp"])

// 2.0: list your Universal Link domains
.security(allowedSchemes: ["https", "myapp"], allowedHosts: ["example.com", "www.example.com"])

// 2.0: keep the 1.x behavior (not recommended)
.security(allowedSchemes: ["https", "myapp"], strategy: .standard)
```

`.hardened` also rejects userinfo, control and invisible Unicode characters
(including the emoji zero-width joiner), `..` segments in any encoding and
malformed encodings.

**Readiness queues are bounded.** `DeepLinkReadinessQueue()` keeps 50 links and
drops the oldest.

```swift
// 2.0: the old unbounded queue, or observe drops
DeepLinkReadinessQueue(maxQueueSize: nil)
DeepLinkReadinessQueue(onEvict: { url in logger.notice("Dropped queued link") })
```

**Everything the framework logs, tracks or shows is redacted** (tokens, codes,
emails, JWTs, userinfo). Opt out per site while debugging only:

```swift
// 2.0 debugging
.logging(format: .unredacted(.detailed))                       // middleware
.analytics(provider: provider, strategy: .unredacted(.standard))
DeepLinkCoordinatorBuilder<AppRoute>()....logPrivacy(.unredacted)
.notification(errorDetail: .full)
```

Dashboards keyed on full URLs will see `REDACTED` values. Plain path segments
are never redacted: keep secrets out of paths.

## 7. Rate-limit persistence

`RateLimitPersistence` requires an atomic read-modify-write. There is no
default implementation, because one built on `loadRequests`/`saveRequests`
could not be atomic.

```swift
// 2.0
actor KeychainRateLimitPersistence: RateLimitPersistence {
    private var timestamps: [TimeInterval] = []

    func mutateRequests<Output: Sendable>(
        _ mutation: @Sendable (inout [TimeInterval]) -> Output
    ) async -> Output {
        let output = mutation(&timestamps)   // no await in between
        persist(timestamps)
        return output
    }
    // loadRequests / saveRequests / clearRequests as before
}
```

## 8. `handle(activity:)` checks the activity type

Only `NSUserActivityTypeBrowsingWeb` (as `.universalLink`) and the Handoff
types you list (as `.handoff`) are processed; anything else returns `nil`.

```swift
// 1.x: any activity with a webpageURL
await coordinator.handle(activity: activity)

// 2.0: declare your Handoff types (Info.plist NSUserActivityTypes)
await coordinator.handle(
    activity: activity,
    handoffActivityTypes: ["com.example.viewing-product"],
    sceneID: scene.session.persistentIdentifier
)

// Spotlight results now have their own entry point
await coordinator.handle(searchableItemActivity: activity)
```

## 9. `PathPatternMatch.int` is canonical

`int(_:)` rejects `-5`, `+5` and zero-padded values such as `007`, so one
resource has one spelling.

```swift
// 2.0: the lenient 1.x conversion
let id = try match.value("id", as: Int.self)
```

## 10. Removed APIs

| Removed | Use instead |
|---------|-------------|
| `AdvancedDeepLinkMiddleware`, `MiddlewareResult` | `DeepLinkMiddleware.intercept(_:)`: return the request to continue, `nil` to stop, throw to fail |
| `CoordinatorOf<R>`, `ResultOf<R>` | `DeepLinkCoordinator<R>`, `DeepLinkResult<R>` |
| `compose(_:)` for middleware | Pass the middleware to `.middleware(...)` (delegate `compose` stays) |
| `AnalyticsStrategy.performance`, `URLTransformationStrategy.batch` | A custom strategy |
| `DeepLinkResultProtocol` | `DeepLinkResult<Route>` |
| Substring checks in `SecurityStrategy.strict` | `.hardened` with `blockedPatterns` |

`DeepLinksTesting` types are now checked `Sendable` (no source change).

## Recommended middleware order

Each stage only sees links the earlier stages accepted, so cheap rejections
come first and side effects (prompts, analytics) last:

```swift
.middleware(
    .security(allowedSchemes: ["https", "myapp"], allowedHosts: ["example.com"], limits: .recommended), // 1. security
    .rateLimit(maxRequests: 20, timeWindow: 60),                                                     // 2. rate limit
    .replayProtection(window: 2),                                                                    // 3. replay
    .signedLinks(keys: keyring, requiredFor: .paths(["/reset", "/invite"]), nonceStore: nonces),      //    signed links (optional)
    .authentication(provider: auth, protectedHosts: ["account"], pendingLinks: pendingLinks),         // 4. auth
    .readiness(queue: readinessQueue),                                                               // 5. readiness
    .confirmation(provider: alerts, requiredFor: .hosts(["pay"]), timeout: .seconds(60)),            //    confirmation (optional)
    .urlTransformation(transformer: URLNormalizationTransformer()),                                  // 6. transforms
    .analytics(provider: analytics),                                                                 // 7. analytics
    .logging()
)
```

- **Security** first: input limits and canonicalization run before anything
  else touches the URL.
- **Rate limit** before anything expensive (HMAC verification, prompts).
- **Replay** before signed links and authentication drops duplicates cheaply:
  a signed link delivered twice (`onOpenURL` and `NSUserActivity`) is dropped
  quietly instead of failing as a reused nonce. If you resume protected links
  with `resumePendingLinks(from:)`, move replay protection after
  authentication (or keep the window shorter than a sign-in), otherwise the
  resumed link is dropped as a replay.
- **Signed links** before authentication, so parsers and later stages see
  verified links with the signature parameters stripped. A nonce is only
  reserved there and spent when the whole link succeeds; if authentication,
  confirmation, a parser or a handler stops it, the nonce is released and the
  link can be retried or resumed after sign-in. Custom `NonceStore`s that only
  implement `consume` keep working but spend the nonce at once; implement
  `reserve`/`commit`/`release` to get retries.
- **Readiness** after the checks that do not need the app to be ready; queued
  links resume the chain after it, so later stages evaluate them at drain time.
- **Confirmation** after readiness (the UI must be able to present) and after
  every rejecting stage, so the user is never asked about a link that would
  be rejected anyway.
- **Transforms** after `.hardened` security (which rejects `..` outright). With
  `.standard`, run `URLNormalizationTransformer` before security instead.
- **Analytics and logging** last, so they record what will actually be routed.

## Hardening checklist

- [ ] `.security(...)` is first, uses `.hardened`, lists every Universal Link
      domain in `allowedHosts`, and passes `limits: .recommended` (plus
      `rejectDuplicateParameters: true` if your parsers read single values).
- [ ] Sensitive flows are restricted by source:
      `.security(allowedSources: [.universalLink])` or a `DeepLinkMatcher.sources` rule.
      Custom schemes can be opened by any app.
- [ ] Password resets, invitations and payment links are signed
      (`.signedLinks`) with an expiry and a nonce; keys live in the Keychain or
      server config, rotate through `kid`, and are at least 256 bits.
- [ ] Sensitive routes are protected at the route level
      (`handler.requiringSignature(for:)`, `handler.confirming(_:)`), which holds
      for every URL spelling; URL rules (`.signedLinks`, `.confirmation`) only filter early.
- [ ] Destructive or financial routes ask the user first (`.confirmation` or `.confirming`).
- [ ] A rate limiter runs before signature checks and prompts. The default
      `UserDefaultsRateLimitPersistence` is user-editable; implement your own
      `RateLimitPersistence` (in memory or in the Keychain) if a reset limit matters.
- [ ] Replay protection covers links with side effects.
- [ ] Protected routes use `AuthenticationMiddleware`; pending links are
      cleared with `removeAll()` on sign-out and never hold secrets in
      `UserDefaults`.
- [ ] No `.unredacted` / `.full` privacy options in release builds; no secrets
      in path segments.
- [ ] Readiness queues stay bounded and `onEvict` is observed.
- [ ] Parsers use `PathPatternParser` (or `DeepLinkURL(rejectDuplicateParameters:)`)
      and throw `routeNotFound`, not security errors, for links that are not theirs.
- [ ] `handle(activity:)` gets an explicit `handoffActivityTypes`; notification,
      Spotlight and quick-action payloads are trusted for their URL only.
- [ ] `DeepLinkDiagnostics` runs in debug builds, with your `applinks:`
      entitlement values.
- [ ] Your test suite runs your middleware chain over `URLFuzzCorpus.hostile(...)`.
