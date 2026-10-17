# Migrating from 1.x to 2.0

2.0 hardens the built-in middleware's defaults and lets every component see
where a link came from. Most apps need a handful of mechanical edits. This
guide covers the source and behavior breaks found by comparing the public API
of `1.1.0` with 2.0, with before/after snippets, then the recommended
middleware order and a hardening checklist. If you hit a break that is not
listed here, please open an issue.

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
11. [Custom nonce stores](#11-custom-nonce-stores)
12. [Smaller changes](#12-smaller-changes)
13. [Recommended middleware order](#recommended-middleware-order)
14. [Hardening checklist](#hardening-checklist)

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
1.x middleware implementing `intercept(_ url: URL)` keeps compiling (without a
warning; calling the URL form through `DeepLinkMiddleware` is what warns) and
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

`DeepLinkMiddlewareCoordinator.process(_:)` takes a `DeepLinkRequest`; the URL
forms `process(_: URL)` and `process(_: URL, startingAfter:)` are deprecated:

```swift
// 1.x
let processedURL = try await chain.process(url)

// 2.0
let processed = try await chain.process(DeepLinkRequest(url: url, context: context))
```

`CollectingMiddleware` adds `interceptedRequests`. `coordinator.handle(url:)`
is **not** deprecated: it is the convenience entry point for code with no
context to give (it uses `.unknown`); prefer `handle(url:context:)` wherever
you know the source. Links replayed from a
readiness queue or a pending-link store keep the context they arrived with.
Custom `ReadinessQueue` / `PendingLinkStore` types that implement only the URL
requirements still compile and replay with `.unknown`; implement
`enqueue(_: DeepLinkRequest)`, `markReadyReturningRequests()`,
`pendingRequests`, `save(_: DeepLinkRequest)` and `takeAllRequests()` to keep it.

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

**Descriptions.** In 2.0.0 `errorDescription` still embeds full URLs; since
2.0.1 it returns `redactedDescription`, and `unredactedDescription` keeps the
full text for debugging. Use `redactedDescription` for logs, analytics and UI:

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

**Legacy strategies match like `.hardened`.** `.standard`, `.strict`,
`.permissive`, `.schemeOnly`, `.hostOnly`, `.patternOnly` and `.whitelist`
keep their allow-list rules but compare schemes and hosts case-insensitively
(hosts percent-decoded, without a trailing dot) and match blocked patterns
case-insensitively against every decoded form. `strategy: .standard` is
therefore "1.x allow-lists", not byte-for-byte 1.x matching.

**Hosts are compared in every spelling.** `.hardened` decodes the host and
drops a trailing dot, and rejects `myapp:///path` (empty host). The default
authentication strategy protects `myapp://Account./x`, `myapp://account%2e/x`,
`myapp:///account/x`, `myapp:/account/x` and `myapp:account/x` when
`"account"` is protected. Protect sensitive screens at the route level too:

```swift
.handler(AppHandler().requiringAuthentication(for: .routes { $0.isPrivate }, provider: auth))
// or any URL rule, e.g. a path under a public host
.authentication(provider: auth, requiredFor: .paths(["/admin"]))
```

**Pending links come only from trusted sources** (pending links are new in
2.0). `AuthenticationMiddleware`
saves a rejected link only when its source is in `pendingSources` (by default
every source except `.customScheme` and `.unknown`). To resume custom-scheme
links, opt in and confirm them on resume:

```swift
.authentication(provider: auth, protectedHosts: ["account"], pendingLinks: pending,
                pendingSources: AuthenticationMiddleware.defaultPendingSources.union([.customScheme])),
.confirmation(provider: alerts, requiredFor: .resumedPendingLinks)
```

**Input limits are on.** `.security(...)` and `SecurityMiddleware` default to
`limits: .recommended` (8192-character URLs, 50 query parameters, 1024
characters per decoded value).

```swift
// 2.0: lift the limits (not recommended)
.security(allowedSchemes: ["myapp"], limits: .unlimited)
```

**Violations do not echo the rejected value.** Built-in strategies throw
`securityViolation("Unauthorized scheme")` and `securityViolation("Unauthorized host")`
without the attacker-supplied scheme or host; update tests that matched
`"Unauthorized host: evil.com"`.

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
are not redacted by default: keep secrets out of paths, or opt in with
`URLRedactor(pathRedaction: .templates(["/invite/:code"]))` (or
`.tokenLikeSegments()`) and pass that redactor to `.redacted(using:)`.

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

`persistence` defaults to `nil`: the limiter then uses
`UserDefaultsRateLimitPersistence.shared(key:)` with a key derived from its
strategy, `maxRequests` and `timeWindow`, so identical limiters share one
actor and differently configured ones keep separate records. The stored
data moves to the new keys, so 1.x counts are not carried over.

Persistences that prune old timestamps should also implement
`mutateRequests(retaining:_:)` and keep at least `window` seconds, as
`UserDefaultsRateLimitPersistence` does; otherwise a long `timeWindow` loses
requests. The built-in persistence keeps one budget per install for every
source; give each middleware its own `key` for separate budgets.

## 8. `handle(activity:)` checks the activity type

`handle(activity:)` is new in 2.0 (1.1.0 had no `NSUserActivity` entry point),
so this matters only if you adopted a 2.0 pre-release or forward
`webpageURL` yourself. Only `NSUserActivityTypeBrowsingWeb` (as
`.universalLink`) and the Handoff types you list (as `.handoff`) are
processed; anything else returns `nil`.

```swift
// 1.1.0: forward the URL yourself
if let url = activity.webpageURL { await coordinator.handle(url: url) }

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

`PathPatternParser` is new in 2.0; this matters only if you adopted a 2.0
pre-release. `int(_:)` rejects `-5`, `+5` and zero-padded values such as
`007`, so one resource has one spelling.

```swift
// 2.0: the lenient `Int(_:)` conversion
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

## 11. Custom nonce stores

Nonce stores are new in 2.0; this section matters if you write your own.
`SignedLinkMiddleware` uses nonces in two phases: it **reserves** the nonce
when the signature verifies and the coordinator **commits** it once a handler
runs, or **releases** it when authentication, confirmation or the parsers stop
the link first, so the user can retry and a link saved for sign-in resumes.

A custom `NonceStore` that implements only `consume(_:expiresAt:)` still
compiles, but the default `reserve` **consumes at once** and the default
`release` does nothing. With such a store a signed link is spent as soon as
its signature verifies: a link rejected by authentication cannot be resumed
after sign-in (it fails as `"Signed link already used"`), and a declined
confirmation or a parser error cannot be retried. Implement all three to get
retries:

```swift
actor RedisNonceStore: NonceStore {
    func consume(_ nonce: String, expiresAt: Date) async -> Bool {
        await redis.set(nonce, "spent", ifAbsent: true, expiresAt: expiresAt)
    }

    // Hold the nonce briefly; let it lapse if the app dies mid-link.
    func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
        let reservation = NonceReservation(nonce: nonce, expiresAt: expiresAt)
        let held = await redis.set(nonce, reservation.token.uuidString, ifAbsent: true, expiresIn: 300)
        return held ? reservation : nil
    }

    func commit(_ reservation: NonceReservation) async {
        await redis.set(reservation.nonce, "spent", expiresAt: reservation.expiresAt)
    }

    // Free it only if this reservation still owns it.
    func release(_ reservation: NonceReservation) async {
        await redis.delete(reservation.nonce, ifValue: reservation.token.uuidString)
    }
}
```

Declare the methods `async`: in an actor, a synchronous method with the same
name loses overload resolution to the protocol's `async` default, which
silently reintroduces consume-at-reserve. The built-in `InMemoryNonceStore` and
`UserDefaultsNonceStore` implement the full protocol.

## 12. Smaller changes

**`advancedMiddleware(_:)` is gone,** with the `add(_:)` overloads on
`DeepLinkCoordinator` and `DeepLinkMiddlewareCoordinator` that took an
`AdvancedDeepLinkMiddleware`. Rewrite the middleware as a
`DeepLinkMiddleware` (see [Removed APIs](#10-removed-apis)) and register it
with `.middleware(...)` or `add(_:)`.

**The built-in delegates are generic over `Route`.** `DeepLinkLoggingDelegate`,
`DeepLinkAnalyticsDelegate`, `DeepLinkNotificationDelegate` and
`CompositeDeepLinkDelegate` take the route type, `compose(_:)` returns a
`CompositeDeepLinkDelegate<Route>`, `.delegate(_:)` and `.delegates(_:)` take
`any DeepLinkCoordinatorDelegate<Route>`, and `coordinator.delegate` is
`(any DeepLinkCoordinatorDelegate<Route>)?`. The factories infer the route
inside the builder; spell it out when you create a delegate yourself:

```swift
// 1.x
let logging = DeepLinkLoggingDelegate(enableDebugLogging: true)
let observer: DeepLinkCoordinatorDelegate? = coordinator.delegate

// 2.0
let logging = DeepLinkLoggingDelegate<AppRoute>(enableDebugLogging: true)
let observer: (any DeepLinkCoordinatorDelegate<AppRoute>)? = coordinator.delegate
```

The built-in delegates and their factories (`.logging()`, `.analytics(provider:)`,
`.notification()`) are still `@MainActor`, as in 1.x: create them, and call
`build()` with them, on the main actor.

**Built-in middleware no longer declares `intercept(_ url: URL)`.** Calling
`securityMiddleware.intercept(url)` still compiles, but it now goes through
the protocol's bridge and runs with the `.unknown` source, so
`allowedSources` and source-based matchers treat the link as unknown. Call
`intercept(_: DeepLinkRequest)` with the link's context:

```swift
// 1.x
let checked = try await security.intercept(url)

// 2.0
let checked = try await security.intercept(DeepLinkRequest(url: url, context: context))?.url
```

**Draining a readiness queue by hand runs the whole chain.** 1.x drained with
`queue.markReady()` and `handle(url:)`. Do not keep that pattern: the returned
URLs were already rewritten by the stages before the readiness gate (a signed
link has lost its signature parameters, so it now fails as unsigned), every
link runs those stages a second time (rate limiting counts it twice, replay
protection can drop it) and it loses its source. 2.0 adds `markReadyAndDrain(queue:)`, which resumes each
link right after the `ReadinessMiddleware` that queued it, with the context
it arrived with:

```swift
// 1.x
for url in queue.markReady() { await coordinator.handle(url: url) }

// 2.0
await coordinator.markReadyAndDrain(queue: queue)
```

**`URLNormalizationTransformer` resolves dot segments.** Besides trimming
slashes and dropping empty query values, it decodes `%2F` into a separator and
resolves `.` and `..` segments (including `%2e`) without climbing above the
root: `myapp://files/a/../../etc` becomes `myapp://files/etc`. Parsers that
expected the raw segments see the resolved path.

**Analytics report the host as `url.host()`.** The `host` parameter is the
percent-encoded host, not the decoded or Punycode form: `https://bücher.de`
is reported as `b%C3%BCcher.de` (1.x: `xn--bcher-kva.de`) and
`myapp://caf%C3%A9` as `caf%C3%A9` (1.x: `café`). Dashboards keyed on
international hosts see new keys.

**`RateLimitMiddleware` can throw `CancellationError`.** Checks are
serialized; a task cancelled while it waits for its turn throws
`CancellationError` and spends no budget. Code that treated every error from
the chain as a rate-limit or security failure should let cancellation through.

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
  reserved there and spent once a handler runs (even one that throws, since it
  may have acted); if authentication, confirmation or the parsers stop it
  before any handler runs, the nonce is released and the link can be retried
  or resumed after sign-in. Keep handlers idempotent. Custom `NonceStore`s that
  only implement `consume` spend the nonce at once (see
  [Custom nonce stores](#11-custom-nonce-stores)).
- **Readiness** after the checks that do not need the app to be ready; queued
  links resume the chain after it, so later stages evaluate them at drain time.
- **Confirmation** after readiness (the UI must be able to present) and after
  every rejecting stage, so the user is never asked about a link that would
  be rejected anyway.
- **Transforms** after `.hardened` security (which rejects `..` outright). With
  `.standard`, run `URLNormalizationTransformer` before security instead.
- **Analytics and logging** last, so they record what will actually be routed.

## Hardening checklist

- [ ] `.security(...)` (or `.secureDefaults(allowedSchemes:)` on the builder) is first, uses `.hardened`, lists every Universal Link
      domain in `allowedHosts`, and keeps the default `limits: .recommended` (plus
      `rejectDuplicateParameters: true` if your parsers read single values).
- [ ] Sensitive flows are restricted by source:
      `.security(allowedSchemes: ["https"], allowedHosts: ["pay.example.com"], allowedSources: [.universalLink])`
      or a `DeepLinkMatcher.sources` rule.
      Custom schemes can be opened by any app.
- [ ] Password resets, invitations and payment links are signed
      (`.signedLinks`) with an expiry, a `maximumLifetime` and a nonce; prefer
      Ed25519 (`Ed25519PublicKeyring`, public keys only in the app); HMAC keys
      live in the Keychain or server config, rotate through `kid`, and are at
      least 256 bits (shorter keys are refused).
- [ ] Sensitive routes are protected at the route level
      (`handler.requiringSignature(for:)`, `handler.requiringAuthentication(for:provider:)`,
      `handler.confirming(_:)`), which holds
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
      entitlement values, and `checkMiddleware(_:)` over your chain (it warns
      about `.signedLinks` without a `nonceStore`).
- [ ] Your test suite runs your middleware chain over `URLFuzzCorpus.hostile(...)`.
