# Changelog

All notable changes to `swift-deep-links` are tracked here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.0.0] - 2026-10-14

Every change since `1.1.0`. Upgrading? Follow [MIGRATION-2.0.md](MIGRATION-2.0.md),
which covers each breaking item below with before/after code, the recommended
middleware order and a hardening checklist.

### Breaking

- **Middleware receives a `DeepLinkRequest` carrying a `DeepLinkContext` (S8/F2).**
  `DeepLinkContext` records the delivering channel (`source`:
  `.customScheme`, `.universalLink`, `.handoff`, `.notification`,
  `.spotlight`, `.shortcut`, `.intent`, `.unknown`), the `sourceApplication`
  and the `sceneID`. `DeepLinkMiddleware` gains the requirement
  `intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest?`.
  **Source-compatible shim:** 1.x middleware implementing only
  `intercept(_ url: URL)` still compiles and runs, bridged so the context is
  kept; that form is deprecated and will be removed in 3.0. Each form defaults
  to the other, so implement exactly one. New entry points:
  `coordinator.handle(url:context:)` (`handle(url:)` uses `.unknown`),
  `DeepLinkMiddlewareCoordinator.process(_: DeepLinkRequest)` and
  `process(_:startingAfter:)` for requests, and
  `DeepLinkContext.openedURL(_:sourceApplication:sceneID:)`. Handlers can read
  the context by implementing `DeepLinkHandler.handle(_:context:)`, which the
  coordinator now calls and which defaults to `handle(_:)`.
  `View.onDeepLink(_:)` tags `onOpenURL` links as `.customScheme` (or
  `.unknown` for unverified `http(s)`), and browsing-web activities as
  `.universalLink`. A type implementing neither `intercept` form (or neither
  `handle` form) throws `missingRequiredConfiguration` instead of recursing.
  Readiness drains and pending-link resumes replay each link with the context
  it arrived with (see below). `DeepLinksTesting.CollectingMiddleware`
  records `interceptedRequests`.
- **`DefaultDeepLinkRouting` stops at security errors.** A parser throwing
  `DeepLinkError.securityViolation` or `.blockedURL` (directly or nested in a
  delegating parser's `parsingFailed`) now ends routing with that error
  instead of letting the next parser try, so a laxer parser can no longer
  accept a link a stricter one (for example `PathPatternParser`'s traversal
  check) rejected. Migration: parsers that used these errors to mean "not
  mine" should throw `routeNotFound` instead.
- **Secure defaults (S3/S6/S7).**
  - `SecurityMiddleware` and `.security(...)` default to
    `SecurityStrategy.hardened` (was `.standard`). `.hardened` now requires a
    listed host only for `http(s)` links (an empty `allowedHosts` rejects every
    web link) and checks custom-scheme hosts only when `allowedHosts` is not
    empty, so `.security(allowedSchemes: ["myapp"])` keeps working. Migration:
    list your Universal Link domains in `allowedHosts`, or pass
    `strategy: .standard` for the 1.x behavior.
  - `DeepLinkReadinessQueue()` keeps at most
    `DeepLinkReadinessQueue.defaultMaxQueueSize` (50) links, dropping the
    oldest. Pass `maxQueueSize: nil` for the old unbounded queue, and
    `onEvict:` to observe drops (a flood of links can evict an earlier one).
  - Built-in `AnalyticsStrategy` values (`.standard`, `.detailed`,
    `.minimal`) and `LoggingFormat` values redact URLs by default;
    `.unredacted(_:)` restores full URLs. `DeepLinkNotificationDelegate` and
    `.notification(...)` default to `errorDetail: .redacted` (`.full` restores
    the old text). Plain path segments are still not redacted.
  - Every framework log site goes through the new `DeepLinkLogPrivacy`
    (`.redacted` by default, `.unredacted` for debugging):
    `DefaultDeepLinkRouting(logPrivacy:)`, `DeepLinkCoordinator(logPrivacy:)`
    and `DeepLinkCoordinatorBuilder.logPrivacy(_:)`,
    `ReadinessMiddleware(queue:privacy:)` / `.readiness(queue:privacy:)`,
    `DeepLinkLoggingDelegate(privacy:)` / `.logging(privacy:)`,
    `DeepLinkAnalyticsDelegate(privacy:)` / `.analytics(provider:privacy:)`
    (URL envelope and `error_description(s)`),
    `DefaultAnalyticsProvider(privacy:)` (sensitive parameter names and embedded
    URLs), and `LoggingProvider.console` / `.console(privacy:)`.
    `JSONQueryParameterParser` logs only the decoding error's type. Errors that
    are not `DeepLinkError` are logged by type name when redacted.
  - `DeepLinkCoordinator`'s public initializer is now a `convenience` init
    (the class is `final`, so only `self.init` delegation is affected).
- **`RateLimitPersistence.mutateRequests(_:)` is a new requirement (A3).**
  `func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) async -> Output`
  must read, change and store the timestamps without suspending in between.
  Every built-in strategy now records only through it, so separate
  `RateLimitMiddleware` instances sharing one persistence admit exactly their
  limit (before, only a single instance was atomic).
  `UserDefaultsRateLimitPersistence` (applying its `maxAge` pruning first) and
  `DeepLinksTesting.InMemoryRateLimitPersistence` implement it. Migration:
  custom persistences must implement it; in an actor, call
  `mutation(&timestamps)` synchronously and persist before returning. There
  is intentionally no default built on `loadRequests`/`saveRequests`, since it
  could not be atomic.
- **`handle(activity:)` checks the activity type.** It now takes
  `handoffActivityTypes:` (default empty) and `sceneID:`.
  `NSUserActivityTypeBrowsingWeb` runs as `.universalLink`, listed Handoff
  types as `.handoff`; any other activity type is rejected (returns `nil`,
  pipeline not run). Migration: pass your `Info.plist` `NSUserActivityTypes`
  as `handoffActivityTypes` if you route Handoff activities through it.
- **`SecurityMiddleware(allowedSources:)` / `.security(allowedSources:)`.**
  Rejects links whose source is not listed with
  `DeepLinkError.securityViolation("Source not allowed")`, before any other
  check; `nil` (default) accepts every source. Additive.

- **`PathPatternMatch.int(_:)` accepts only canonical non-negative
  integers.** `-5`, `+5`, `-0` and zero-padded values such as `007` now throw
  `DeepLinkError.invalidParameterValue`, so one resource cannot be reached
  through several spellings. Migration: call `value(name, as: Int.self)` to
  keep the 1.x `Int(_:)` conversion.
- **New `DeepLinkError.confirmationDenied(URL)` case.** Thrown by
  `ConfirmationMiddleware` when the user declines a link or does not answer in
  time, so a user's "no" is distinguishable from a security rejection (and need
  not be reported as one). `errorDescription` is
  `"Confirmation denied for URL: …"`, `redactedDescription` redacts the URL, and
  `==` compares the URL. Migration: exhaustive `switch` statements over
  `DeepLinkError` need a `confirmationDenied` branch (or `@unknown default`).

### Platform support

- Added `tvOS 16+`, `watchOS 9+`, and `visionOS 1+` alongside existing
  `iOS 16+` / `macOS 13+` targets. `DeepLinkNotificationDelegate` and its
  `.notification(...)` factory are gated behind
  `#if canImport(UserNotifications) && !os(tvOS)`.

### Added

- **SwiftUI one-liner** — `View.onDeepLink(_:)` wires the coordinator to
  both `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`
  in a single modifier. Ordering is best-effort (documented).
- **`View.onDeepLink(_:)` optional overload** — the modifier now also
  accepts `DeepLinkCoordinator<some DeepLinkRoute>?` and no-ops while
  the coordinator is `nil`. Lets callers whose coordinator is built
  asynchronously (for example inside `.task { … }` and stored in
  `@State` as an optional) drop the private `if let` wrapper.
- **`coordinator.handle(activity:)`** — routes an `NSUserActivity` directly
  by forwarding its `webpageURL` to `handle(url:)`.
- **Closure-based factories** — `DeepLinkHandler.from(_:)` and
  `DeepLinkParser.from(_:)` (multi-route and single-route overloads) let
  you wire a coordinator without declaring new types. Dot-shorthand is
  supported via `where Self == ClosureDeepLinkHandler<R>`.
- **Builder parser shortcuts** — `.parser(_:)` / `.parsers([...])` /
  `.parsers(_:...)` on `DeepLinkCoordinatorBuilder` wrap their arguments
  in `DefaultDeepLinkRouting`. The variadic form requires at least one
  leading parser so `.parsers()` with zero arguments is a compile error.
- **`DeepLinkResult.firstDeepLinkError`** — typed accessor returning the
  first `DeepLinkError` in the error chain, skipping non-framework errors.
- **`DefaultDeepLinkRouting` error propagation** — when every parser in
  the chain throws, the router now throws
  `DeepLinkError.parsingFailed(url:underlyingErrors:)` with the collected
  failures instead of swallowing them into a generic `routeNotFound`.
  Nested `parsingFailed` from a delegating parser is flattened.
- **`coordinator.markReadyAndDrain(queue:)`** — marks a readiness queue
  ready and drains every pending URL through routing + handler while
  bypassing middleware, so analytics / rate-limit / auth side effects
  don't re-fire.
- **`DeepLinkNotificationPresenter`** — swap the default
  `UNUserNotificationCenter` sink for a custom presenter (toast, in-app
  banner, test double) via `.notification(presenter:)`. The protocol
  carries a `DeepLinkNotificationKind` severity so custom presenters can
  route by `.success` / `.failure` / `.info` without parsing the title.
- **`RateLimitMiddleware.dateProvider`** — inject a deterministic time
  source for testing without wall-clock sleeps.
- **`DeepLinkCoordinator` clock injection** — `sleep:` init parameter
  (also exposed on the builder via `.sleep(_:)` + `.routeExecutionDelay(_:)`)
  replaces the hard-coded `Task.sleep(for:)` so tests can verify timing
  assertions without real delays.
- **`DeepLinksTesting` additions** —
  `CollectingNotificationPresenter` public actor for asserting on
  scheduled notifications; the test target now depends on
  `DeepLinksTesting` to eat its own dogfood.
- **`RateLimitStrategy.tokenBucket(capacity:refillRate:)` (F7).** Burst-tolerant
  limiting: admits up to `capacity` links at once and refills `refillRate`
  tokens per second. The state is a single timestamp in the existing
  `RateLimitPersistence`, so it persists and is serialized like the window
  strategies; the middleware's `maxRequests`/`timeWindow` are ignored. A
  non-positive or NaN rate never refills, an infinite rate never limits, and
  a clock moved backwards never blocks for longer than one full refill. A
  bucket that never refills reports `rateLimitExceeded` with the seconds
  since its first admitted request as `timeWindow` (never `inf`); a rate so
  small that one refill would take infinite time is treated as no refill.
- **`ReplayProtectionMiddleware` / `.replayProtection(...)` (F5).** Suppresses
  the same link arriving again within `window` seconds (double taps, a link
  delivered through both `onOpenURL` and `NSUserActivity`, pages firing a link
  repeatedly). `ReplayKeyStrategy` picks what identifies a link: `.url`
  (default; scheme/host case and query order ignored), `.path`,
  `.queryParameter(_:)` for idempotency keys or nonces, or `.custom`.
  `ignoredQueryKeys` drops tracking parameters before keying. Replays are
  dropped (`.drop`, default) or rejected with
  `securityViolation("Replayed deep link")` (`.reject`). Memory is bounded by
  `maxEntries` (oldest evicted), the check is atomic under concurrency, and
  the clock is injectable through `dateProvider`. Equivalent percent-encodings
  share a key. Place it after authentication so links resumed after sign-in
  are not dropped as replays.
- **`PathPatternParser` / `.pattern(...)` (F1).** Declarative templates such
  as `/products/:id` and `/u/:handle/posts/*` replace hand-written parsers.
  `PathPatternMatch` offers typed captures (`string`, `int`, `uuid`,
  `value(_:as:)`, `wildcard`, `url`), throwing `invalidParameterValue` on a
  failed conversion. Captured segments are percent-decoded once, after the
  path is split, and must use the allowed character set (RFC 3986 unreserved
  ASCII by default), so `%2F` cannot create a segment and `%252e%252e` cannot
  become `..`; decoded `.`/`..` segments throw `securityViolation`. Non-matching
  URLs throw `routeNotFound` so routing falls through to the next parser.
  `hosts:` restricts hosts (case-insensitive) and `scope: .hostAndPath` treats
  a custom-scheme host as the first segment. Invalid templates throw a
  descriptive `PathPatternError`.
- **Pending links and resume after sign-in (F3).** New `PendingLinkStore`
  protocol with `InMemoryPendingLinkStore` and `UserDefaultsPendingLinkStore`
  (bounded by `maxCount`, default 1; links expire after `expiry`, default
  5 minutes; only the URL and the save time are stored).
  `AuthenticationMiddleware(..., pendingLinks:)` and
  `.authentication(..., pendingLinks:)` save a link rejected with
  `unauthorizedAccess` (the link is still rejected).
  `coordinator.resumePendingLinks(from:)` empties the store and runs each link
  through the whole middleware chain again, so authentication is re-checked;
  a link that is still unauthorized is saved again. The `UserDefaults` store
  writes URLs in plain text; keep links carrying secrets in memory. Saved
  links can be hostile: only protect routes safe to run after sign-in and
  call `removeAll()` on sign-out.
- **Observability (A5).** `DeepLinkCoordinator.results` returns an
  `AsyncStream<DeepLinkResult<Route>>` of every result produced from then on
  (`handle(url:)`, readiness drains and pending-link resumes, including
  failures); each access is an independent subscriber, buffering at most 100
  undelivered results, and streams finish when the coordinator is
  deallocated. `DeepLinkMiddlewareCoordinator` wraps every middleware call in
  an `os_signpost` interval (`swift-deep-links` / `Middleware`) labelled with
  the middleware type name only, never the URL. No behavior change.
- **`DeepLinksTesting`: fuzz corpus and manual clock (F10).**
  `URLFuzzCorpus.hostile(scheme:host:)` (and per-category
  `hostile(_:scheme:host:)`) returns `URLFuzzCase` values covering
  traversal, broken or over-nested encodings, control characters, host
  confusion (userinfo, `trusted@evil`, trailing dot), IDN homographs,
  duplicate parameters, oversize input and dangerous schemes, built around the
  host you allow; the package's own suite runs `SecurityStrategy.hardened`
  with strict input limits over it. `ManualDateProvider` is a lock-protected
  clock whose `dateProvider` plugs into rate limiting, replay protection and
  pending-link stores; tests advance it instead of sleeping.
- **`DeepLinkDiagnostics` (F11).** Debug-time checks returning
  `DeepLinkDiagnosticWarning`s: `checkSecurityConfiguration(allowedSchemes:allowedHosts:)`
  flags an empty scheme allow-list, allowed custom schemes missing from
  `CFBundleURLTypes`, declared schemes the configuration rejects, `http(s)`
  allowed without hosts and, when you pass your `applinks:` entitlement
  values, hosts and associated domains that do not match.
  `checkParsers(_:probes:)` flags probe URLs no parser handles and parsers
  shadowed by an earlier one. Entitlements are not readable at runtime, so
  associated domains must be supplied; the AASA file is not checked.
  `ignoredDeclaredSchemes` / `ignoredDeclaredSchemePrefixes` silence
  third-party SDK callback schemes (`fb<app id>`, Google client IDs).
- **`SignedLinkMiddleware` / `.signedLinks(...)` (F4).** Requires an
  HMAC-SHA256 signature (CryptoKit, unpadded base64url in `sig`) on the links a
  `DeepLinkMatcher` selects (`.all`, `.hosts`, `.paths`, `.sources`,
  `.custom`, `.anyOf`, `.allOf`). The signature covers a documented canonical
  form (`DLSIG1`, lower-cased scheme and host, port, path, sorted query minus
  `sig`, fragment, with percent-encoding normalized), so tampering with any
  part, adding a parameter or a fragment fails while query order and
  scheme/host case do not. `exp` (Unix seconds, required by default, with
  `leeway`) bounds the lifetime; a `NonceStore` (`InMemoryNonceStore`:
  bounded, injected clock, rejects rather than evicts when full) makes links
  single-use through `nonce`. `SigningKeyProvider` / `SigningKeyring` pick the
  key by `kid` for rotation; an unknown key fails like a bad signature.
  Signatures are compared in constant time, failures throw
  `securityViolation` with fixed reasons (`SignedLinkMiddleware.*Reason`) that
  never include the key, signature or link, the nonce is consumed only after
  verification, and verified links continue with the signature parameters
  stripped. Nonces are two-phase inside `DeepLinkCoordinator`: reserved when
  the signature verifies, spent once a handler ran (even if one threw, since
  it may have acted; outcome `.handlerFailed`) or readiness queued the link,
  and released when a later middleware or the router stopped or failed it
  before any handler ran, so the user can retry (including after sign-in
  through `resumePendingLinks(from:)`); concurrent deliveries still admit one.
  Make handlers idempotent where a repeat could double a side effect.
  While its link is in flight, `SignedLinkMiddleware` refuses the same nonce
  even if the store's reservation lapsed (a long confirmation prompt), so a
  link never runs twice in one process; keep prompt timeouts below the
  reservation time to live for stores shared across processes.
  `DeepLinkMiddlewareCoordinator.process(...)` called from a handler runs
  standalone (it consumes at once), so it cannot disturb the outer link's nonce.
  `NonceStore` gains `reserve(_:expiresAt:)`, `commit(_:)` and `release(_:)`
  with defaults that consume at once, so 1.x-style stores keep compiling;
  `InMemoryNonceStore(reservationTTL:)` lets abandoned reservations lapse
  (default 300 s). `DeepLinkMiddleware` gains
  `didFinish(_:outcome:)` (default no-op), which the coordinator calls for
  every middleware that ran with a `DeepLinkOutcome` (`.succeeded`,
  `.stopped`, `.deferred`, `.failed`, `.handlerFailed`). A link queued by
  readiness keeps its nonce reserved: the middleware before the gate hears
  `.deferred` and later the drained pass's outcome, or `.stopped` when
  `DeepLinkReadinessQueue` evicts or resets it (releasing the nonce). `AuthenticationMiddleware` now saves the
  link as it entered the chain (also when it was drained from a readiness
  queue), so a resumed signed link still carries its signature. `reusedNonce: .drop` stops a reused link silently, and replay
  protection belongs before signed links so double deliveries are dropped
  quietly. `SignedLinkBuilder` signs links for servers and tests. Matchers
  compare hosts and paths case-insensitively and match paths after
  percent-decoding and dot-segment resolution, erring towards protection; a
  path that cannot be decoded or stays encoded past the decoding limit matches
  every path rule (fail closed). Paths are also matched with empty segments
  collapsed, `\` treated as a separator, `;` parameters and invisible or
  control characters dropped, and a leading `/` forced (`myapp:reset`), both
  before and after RFC 3986 dot-segment removal. For schemes other than
  `http(s)` the host is also matched as the first segment, so `.paths(["/reset"])`
  covers `myapp://reset?user=42` as well as `https://example.com/reset`.
- **`ConfirmationMiddleware` / `.confirmation(...)` (F6).** For the links a
  `DeepLinkMatcher` selects, asks an app-implemented
  `DeepLinkConfirmationProvider` (`confirm(_:) async -> Bool`) with a
  `DeepLinkConfirmationRequest` carrying the `URLRedactor`-redacted URL and the
  `DeepLinkContext`. Approval continues unchanged; denial throws
  `DeepLinkError.confirmationDenied`. An optional `timeout` (with an injectable
  `sleep`) denies an unanswered prompt and cancels the provider's task so it
  can dismiss its UI; the timeout (and cancelling the link) denies at once even
  when the provider ignores cancellation, releasing the next prompt. Prompts are serialized in arrival order; a link
  cancelled while waiting is never shown. `DeepLinksTesting.CollectingConfirmation`
  answers with a configurable decision and records every prompt.
- **Notification, Spotlight and quick-action entry points (F8).**
  `handle(notificationResponse:urlKey:sceneID:)` and
  `handle(notificationUserInfo:actionIdentifier:urlKey:sceneID:)`
  (`canImport(UserNotifications) && !os(tvOS)`, source `.notification`, URL
  from `userInfo["deepLink"]` by default, dismiss action ignored, scene taken
  from the response's `targetScene` on iOS/visionOS);
  `handle(searchableItemActivity:sceneID:urlForIdentifier:)` and
  `handle(searchableItemIdentifier:sceneID:urlForIdentifier:)`
  (`canImport(CoreSpotlight) && !os(tvOS)`, source `.spotlight`, only
  `CSSearchableItemActionType` activities); `handle(shortcutItem:urlKey:sceneID:)`
  (iOS, source `.shortcut`, URL from `userInfo["deepLink"]` or the item's
  `type`). Each reads a single absolute URL from its payload and delegates to
  `handle(url:context:)`; no other payload value reaches the pipeline, and a
  payload without a URL returns `nil` without running it. All are main-actor
  isolated so the non-`Sendable` system objects can be passed directly.
- **Deprecated the superseded URL forms.** `DeepLinkMiddleware.intercept(_: URL)`
  and `DeepLinkMiddlewareCoordinator.process(_: URL)` /
  `process(_: URL, startingAfter:)` are `@available(*, deprecated)` (removed in
  3.0): they drop the link's context. 1.x middleware that implements the URL
  form keeps compiling without a warning; calling the URL form through
  `DeepLinkMiddleware` warns. Every built-in middleware and
  `DeepLinksTesting.PassthroughMiddleware` now implement the request form.
  Deliberately **not** deprecated: `DeepLinkCoordinator.handle(url:)` (a
  convenience entry point equal to `handle(url:context: .unknown)`, for code
  that has no context to give), `DeepLinkHandler.handle(_:)` (handlers that do
  not need the context), and the URL requirements of `ReadinessQueue` and
  `PendingLinkStore` (custom conformers must still implement them, and the new
  request requirements default to them; deprecating them would warn every
  conformer until 3.0 flips the defaults). The public `_DeepLinkURLIntercepting`
  base protocol is an implementation detail of the bridge; do not use it.
- **Queued and pending links keep their context.** `ReadinessQueue` gains
  `enqueue(_: DeepLinkRequest)`, `markReadyReturningRequests()` and
  `pendingRequests`, and `PendingLinkStore` gains `save(_: DeepLinkRequest)`
  and `takeAllRequests()`, each with a default over the URL requirements so
  1.x conformers still compile (and replay with `.unknown`).
  `DeepLinkReadinessQueue`, both pending stores, `ReadinessMiddleware` and
  `AuthenticationMiddleware` keep the whole request, so `markReadyAndDrain` and
  `resumePendingLinks` hand the handler the original source, source
  application and scene (a drained signed link stays verified for
  `SignedRouteGuard`). `UserDefaultsPendingLinkStore` persists the context as
  versioned JSON without the signature-verified flag; links stored by 1.x, or
  with a source this version does not know, load as `.unknown`.
- **`UserDefaultsNonceStore`.** A bounded, persistent `NonceStore` (injectable
  `UserDefaults`, key and clock): spent nonces survive relaunch as versioned
  JSON and are pruned by expiry; open reservations stay in memory and are
  dropped on relaunch so an interrupted link can be retried. It writes only
  when the spent set changes; unreadable data is logged and starts an empty
  store, data from a newer format version is kept and the store refuses every
  nonce, and a nonce whose spending cannot be written is refused. Not atomic
  across processes sharing an app group.
- **Route-level rules.** `RouteMatcher<Route>` (`.routes(where:)`, `.all`,
  `.custom`) selects **parsed** routes, and two handler decorators enforce
  rules on them regardless of URL spelling: `SignedRouteGuard` /
  `handler.requiringSignature(for:)` rejects protected routes whose link was
  not verified (`securityViolation(SignedRouteGuard.unsignedRouteReason)`),
  and `ConfirmingHandler` / `handler.confirming(_:timeout:confirm:)` asks a
  route-aware closure first (`confirmationDenied` on denial or timeout).
  `DeepLinkContext.isSignatureVerified` records the result and only
  `SignedLinkMiddleware` can set it, bound to the URL it verified: rewriting
  the URL afterwards (`replacingURL`, assigning `url`, a bridged 1.x
  middleware, `URLTransformationMiddleware`) clears it, so place rewriting
  middleware before `.signedLinks(...)`; the middleware now also verifies any link
  that carries a signature, not only those its URL rule selects (an invalid
  signature is rejected either way).
- **Multi-scene routing (F9).** `SceneRoutingHandler<Route>` is a handler that
  forwards each route to the handler registered for its
  `DeepLinkContext.sceneID` (`register(_:forScene:)`, `unregister(scene:)`),
  with a `fallback` for links without a known scene (or
  `handlerError(message: SceneRoutingHandler.noSceneHandlerMessage, …)` when
  there is none). `View.onDeepLink(_:sceneID:)` (plain and optional
  coordinator) tags `onOpenURL` links and Universal Link activities with an
  app-supplied scene identifier (empty means none), since SwiftUI exposes
  none. `DeepLinksTesting.CollectingHandler.handledContexts` records the
  context of each handled route.

### Changed

- **`DeepLinkCoordinatorBuilder.build()` is now synchronous.** Consumers
  must drop `await` from the call site. `DeepLinkMiddlewareCoordinator`
  gained an `init(middleware:)` that bypasses the actor-add loop;
  `CompositeDeepLinkDelegate.init` is `nonisolated`. Consumer-owned
  protocols that wrap `build()` — for example, a
  `DeepLinkCoordinatorProviding` factory type that returns a prebuilt
  coordinator — will also need to drop `async` from their call
  signatures (and any conforming type's `func` declaration).
- **`DeepLinkRoute` now requires `Equatable & Hashable & Sendable`.**
  Enum synthesis handles both for free; consumers whose `Route` was a
  struct need to add conformances explicitly.
- **`DeepLinkCoordinatorDelegate` no longer requires `AnyObject`.**
  Value types and actors can now conform directly. `@MainActor`
  isolation is preserved.
- **`DeepLinksTesting` types tightened to checked `Sendable`.**
  `CollectingHandler`, `CollectingMiddleware`, and
  `CollectingAnalyticsProvider` previously declared `@unchecked Sendable`.
  Their conformance is now synthesised from the `OSAllocatedUnfairLock<T>`
  stored state, so consumers that ban `@unchecked Sendable` can adopt
  the test utilities directly. Public surface and behaviour are
  unchanged.
- **`routeExecutionDelay` default is now `.zero`.** The coordinator
  previously inserted a hard-coded 500ms delay between consecutive route
  handlers; the new default fires handlers back-to-back. Callers who
  relied on the implicit pacing must pass an explicit `Duration`.
- **`DeepLinkError` case reshape.**
  - `routeNotFound`, `unauthorizedAccess`, `blockedURL` now carry a
    `URL` instead of a `String`.
  - `invalidParameterValue` gains labels: `(name:value:)`.
  - `rateLimitExceeded` gains labels: `(maxRequests:timeWindow:)`.
  - `handlerError` gains labels and an underlying error:
    `(message:underlyingError:)`.
  - New case `parsingFailed(url:underlyingErrors:)` for the parser-chain
    propagation described above.
  - Manual `Equatable` implementation for the two cases that carry
    `any Error` payloads — `parsingFailed` and `handlerError` — now
    compares the structurally-stable fields only: URL + underlying
    error *count* for `parsingFailed`, message + *nil-ness* of the
    underlying error for `handlerError`. Underlying payloads are no
    longer compared by `localizedDescription`, which removes the
    previous locale-dependence. Two `parsingFailed` values with the
    same URL and same number of underlying errors are now equal even
    when the underlying errors themselves differ; callers who need
    deeper comparison must unwrap the payloads explicitly.
- **`AnalyticsStrategy` now reads `url.host()` (method) instead of
  `url.host` (property).** Observable for percent-encoded IDN hosts: the
  method returns percent-encoded, the property returned percent-decoded
  Unicode. Dashboards aggregating deep-link analytics by `host` for IDN
  URLs will see a key shift.
- **`DeepLinkNotificationDelegate` internals.** In-flight notification
  tasks are tracked in an `OSAllocatedUnfairLock<[UUID: Task]>`
  dictionary and cancelled from a nonisolated `deinit`; `print` fallback
  replaced with `Logger`.
- **`SingleRouteClosureDeepLinkParser` `nil` sentinel** now throws
  `DeepLinkError.routeNotFound(url)` with the full URL instead of the
  earlier `routeNotFound(url.host ?? "")` empty-string fallback.
- **`AnalyticsEventBuilder` (internal)** is now the single source of
  truth for the scheme / host / url / path / timestamp envelope shared
  by `DeepLinkAnalyticsDelegate` and the three `AnalyticsStrategy`
  values.

### Removed

- **`AdvancedDeepLinkMiddleware` and `MiddlewareResult`.** The simpler
  `DeepLinkMiddleware.intercept(_:) async throws -> URL?` covers every
  semantics the advanced protocol expressed (return URL to continue or
  transform; return `nil` to halt without error; `throw` to halt with
  error).
- **`CoordinatorOf` and `ResultOf` type aliases.** Use the canonical
  generic names `DeepLinkCoordinator<Route>` and `DeepLinkResult<Route>`.
- **Identity `compose(_:any DeepLinkMiddleware...)` / `compose(_:[any DeepLinkMiddleware])`
  overloads.** Pass middleware arrays directly through
  `.middleware(_:)` on the builder. The delegate-side `compose` overloads
  stay — they wrap their input in `CompositeDeepLinkDelegate`.
- **`AnalyticsStrategy.performance` and `URLTransformationStrategy.batch`.**
  Both were misleading placeholders; removed.
- **`DeepLinkResultProtocol`.** `DeepLinkCoordinatorDelegate` is now
  directly generic over `Route`; the protocol layer was unnecessary.
- **Substring-based security checks** in `SecurityStrategy.strict`
  produced false positives; removed.

### Fixed

- `NotificationDelegate` no longer branches on `XCTestConfigurationFilePath`
  in production code. The XCTest bypass is now handled via an injectable
  `DeepLinkNotificationPresenter`.
- `JSONQueryParameterParser.parse(_:fromAll:)` now falls back to an
  array-preserving decode when the scalar-unwrap pass fails, so models
  declaring `let tags: [String]` against a single-value URL decode
  correctly. On both-pass failure, the first-pass error is rethrown to
  preserve the clearer diagnostic.
- `DeepLinkAnalyticsDelegate`'s Swift 6.3 IRGen crash when
  `\.localizedDescription` was used as a key path in the generic context
  was worked around with a closure form and a local SwiftFormat
  directive.

### Security

- **Readiness drain resumes the middleware chain (S1).**
  `markReadyAndDrain(queue:)` used to route drained links while bypassing
  every middleware, so authentication, security or rate limiting placed
  after `.readiness(queue:)` never ran for queued links. Each drained link
  now resumes the chain right after the `ReadinessMiddleware` gating that
  queue: middleware before the gate does not re-fire, middleware after it
  evaluates the link at drain time. A queue that is not registered through
  `ReadinessMiddleware` runs the whole chain. New
  `DeepLinkMiddlewareCoordinator.process(_:startingAfter:)` exposes the
  same resumption for manual drains.
  **Behavior change:** middleware placed after `.readiness(queue:)` now
  runs for drained links (once each); before, it never did.
- **`RateLimitMiddleware` is atomic under concurrency (S2).** Each
  instance serializes the check-and-record step, so N simultaneous links
  against a limit of K admit exactly K. A request cancelled before its turn
  throws `CancellationError` and consumes no budget. `.fixedWindow` no longer computes a
  NaN window for a zero or infinite `timeWindow` (zero counts same-instant
  requests, infinite never resets), and a NaN `timeWindow` is treated as `0`.
- **`SecurityStrategy.hardened` and `URLCanonicalizer` (S3).** The new
  opt-in strategy canonicalizes the URL (lower-cased scheme and host),
  rejects userinfo, control characters, `..` path segments (path only, not
  query or fragment) and malformed or over-nested percent-encoding, requires an allow-listed host (compared
  case-insensitively), and matches `blockedPatterns` case-insensitively
  against the raw URL and every percent-decoded form. Existing strategies
  are unchanged; prefer `.hardened` for new integrations.
- **Input limits (S7).** New `DeepLinkInputLimits` (maximum URL length,
  query-parameter count and decoded parameter-value length; `.unlimited`
  and `.recommended` presets) is accepted by `SecurityMiddleware(limits:)`,
  `.security(limits:)` and `URLCanonicalizer(limits:)`. Limits are checked
  before the security strategy or any decoding runs and throw
  `DeepLinkError.securityViolation`; place the security middleware first so
  oversized links never reach logging, analytics or parsing. Error messages
  never echo the offending parameter name or value. Defaults are
  `.unlimited`, so existing configurations are unchanged.
- **Observable readiness eviction (S7).**
  `DeepLinkReadinessQueue(maxQueueSize:onEvict:)` reports each URL dropped
  to make room, outside the queue lock. Prefer a bounded queue in production.
- **Duplicate query parameters can be rejected (S4).**
  `DeepLinkURL(url:maxLength:rejectDuplicateParameters:)` throws
  `DeepLinkError.invalidURL` when a query key repeats (compared
  case-sensitively after percent-decoding, valueless keys included), so
  `queryParameters` and `allQueryParameters` can never disagree. Defaults to
  `false`; existing last-value-wins behavior is unchanged. The same check is
  available before any parser or middleware work as
  `DeepLinkInputLimits(rejectDuplicateParameters:)` (in `SecurityMiddleware`
  and `URLCanonicalizer`) and as
  `DefaultDeepLinkRouting(parsers:rejectDuplicateParameters:)`; both throw
  `DeepLinkError.securityViolation("Duplicate query parameter")`, so it can
  be told apart from a malformed URL.
- **`URLNormalizationTransformer` resolves dot segments (S10).** `.` and
  `..` path segments (including percent-encoded `%2e`) are resolved and
  clamped at the root, so `myapp://files/a/../../etc` normalizes to
  `myapp://files/etc` instead of reaching parsers with `..` intact. Segments
  that only contain dots (`..b`, `...`), the query and the fragment are
  untouched; slash trimming and empty-value stripping are unchanged.
  **Behavior change:** paths with `.`/`..` segments now come out resolved.
  Percent-encoded slashes (`%2F`) are decoded into separators before
  resolution (`a%2F..%2Fb` becomes `/b`); backslashes (`%5C`) are not
  separators. **Ordering:** run the transformer *before* `SecurityMiddleware`,
  or use `.hardened` (which rejects `..` outright): with `.standard` or
  `.strict`, `/public/%2e%2e/admin` passes validation and only becomes
  `/admin` if normalization runs afterwards.
- **Opt-in redaction (S6).** New `URLRedactor` replaces the values of
  sensitive query and fragment parameters (`token`, `code`, `password`,
  `email`, `key`, `secret`, `otp`, `auth`, `session`, … matched per word,
  plural or, for keys of five or more characters, by containment,
  case-insensitively; configurable), path matrix parameters, JWT-shaped
  values, sensitive values inside nested URL parameters, and userinfo. Use it through
  `LoggingFormat.redacted(_:using:)`, `AnalyticsStrategy.redacted(_:using:)`,
  `DeepLinkError.redactedDescription` / `redactedDescription(using:)` (also
  redacts URLs embedded in free-form messages and every
  `invalidParameterValue` value), and
  `DeepLinkNotificationDelegate(errorDetail:)` / `.notification(errorDetail:)`
  with `.redacted` or `.generic`. Defaults are unchanged and still expose
  full URLs; prefer the redacted variants in production.
  **Still unredacted in 1.x** (redacted by default since 2.0, see Breaking):
  `DefaultDeepLinkRouting` logger messages, `DeepLinkCoordinator` error
  logs, `ReadinessMiddleware`'s queued-link log, `DeepLinkLoggingDelegate`,
  `DeepLinkAnalyticsDelegate` error descriptions, `DefaultAnalyticsProvider`
  event logging and `LoggingProvider.console`.
- **Invisible Unicode characters rejected (`.hardened`).** `URLCanonicalizer`
  (and so `SecurityStrategy.hardened`) also rejects Unicode format (Cf) and
  line/paragraph separator (Zl, Zp) characters in any decoded form, such as
  the right-to-left override `U+202E`, zero-width space `U+200B`, BOM and
  `U+2028`, with `securityViolation("Invisible formatting characters are not allowed")`.
  **Behavior change:** links carrying emoji sequences joined by `U+200D` are
  now rejected by `.hardened`. `URLFuzzCorpus` gained matching cases.
