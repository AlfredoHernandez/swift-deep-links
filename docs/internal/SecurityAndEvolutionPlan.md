# Security Audit & Evolution Plan

Scope: `Sources/DeepLinks` and `Sources/DeepLinksTesting` at `feature/modernization` (last tag: `1.1.0`).
Goal: close security gaps, improve the architecture, and add features, staying source-compatible whenever possible and bumping to a major version only where a fix cannot be additive.

## 1. Threat model

A deep link is **untrusted input from any app or web page on the device** (custom schemes can be claimed by other apps; universal links can be triggered from any site; `NSUserActivity` can come from Handoff/Spotlight/notifications). The package must assume the URL is hostile, and that app state (auth, readiness) can change between receiving and executing a link.

## 2. Findings

Severity: **H** high, **M** medium, **L** low. "Compat" = whether the fix can ship without breaking the public API.

| ID | Sev | Finding | Where | Compat |
|----|-----|---------|-------|--------|
| S1 | H | **Readiness drain skips middleware.** `markReadyAndDrain` calls `handleBypassingMiddleware`, so any middleware placed *after* `ReadinessMiddleware` (auth, security, rate limit, transforms) never runs for queued links. Auth state is also checked at enqueue time, not execution time (TOCTOU). | `DeepLinkCoordinator+Readiness.swift`, `DeepLinkCoordinator.swift` | Additive: resume the chain after the readiness middleware |
| S2 | H | **Rate limiter is not atomic.** load → filter → save spans two `await`s on a non-isolated class; concurrent links all read the same count and all pass. `fixedWindow` with `timeWindow == 0` yields NaN windows and never limits. | `RateLimitStrategy.swift`, `RateLimitMiddleware.swift` | Additive (serialize in middleware, validate input) |
| S3 | H | **Security matching is bypassable / weak by default.** `blockedPatterns` run on the raw, still percent-encoded string and are case-sensitive (`%2e%2e`, `%6A%61vascript` slip through). Scheme/host compared case-sensitively (RFC 3986 says case-insensitive, and parsers may lower-case, creating a validator/parser differential). `.standard` accepts **any host** when `allowedHosts` is empty, so universal links from any domain pass. No userinfo (`https://allowed@evil`), control-character, IDN/homograph, or `..` checks. | `SecurityStrategy.swift` | Additive: new `.hardened` strategy + canonicalization; flip default in 2.0 |
| S4 | M | **Parser differential / parameter pollution.** `DeepLinkURL.queryParameters` keeps last duplicate, `allQueryParameters` keeps all; middleware and parsers can see different values. Valueless params (`?flag`) are silently dropped. | `DeepLinkURL.swift` | Additive (`rejectDuplicateParameters` option) |
| S5 | M | **Authentication is host-only, case-sensitive, sync and path-blind.** Protecting `/admin` under a public host is impossible; `schemeBased` compares the scheme against `protectedHosts` (misleading); no way to resume a protected link after login. | `AuthenticationStrategy.swift` | Additive (path rules, async provider, pending-link store) |
| S6 | M | **Sensitive data leakage.** `AnalyticsStrategy.standard` sends the full URL (tokens, emails, codes) to third-party providers; `LoggingMiddleware`/`readiness`/routing log full URLs; `DeepLinkError.errorDescription` embeds full URLs and the notification delegate shows it on the lock screen; `.console` provider uses `print`. | `AnalyticsStrategy.swift`, `LoggingFormat.swift`, `DeepLinkError.swift`, `NotificationDelegate.swift` | Additive redactor + opt-in; default change in 2.0 |
| S7 | M | **Resource exhaustion.** `DeepLinkURL` length cap (8192) only runs in routing, *after* all middleware (logging, analytics, JSON logging) already processed the URL. No cap on parameter count/value size. `DeepLinkReadinessQueue` is unbounded by default; drop-oldest eviction is silent. | `DefaultRouting.swift`, `DeepLinkReadinessQueue.swift` | Additive (limits in security middleware, bounded default in 2.0) |
| S8 | L-M | **No provenance.** Middleware only sees a `URL`; it cannot tell universal link from custom scheme (hijackable), Handoff, notification or Spotlight. `handle(activity:)` does not check `activityType`. | `DeepLinkMiddleware.swift`, `+NSUserActivity.swift` | Context type additive; middleware signature change is **breaking** |
| S9 | L | **No replay/idempotency protection** and no integrity for sensitive links (password reset, payment confirm). Rate-limit state in `UserDefaults` is user-tamperable. | n/a | Additive (new middleware) |
| S10 | L | Correctness: `DeepLinkError ==` compares `parsingFailed` by error *count* only; `URLNormalizationTransformer` does not resolve `..`/`.` segments and strips empty query values (semantic change). | `DeepLinkError.swift`, `URLNormalizationTransformer.swift` | Additive / bugfix |

## 3. Improvements (architecture)

- **A1 Canonical URL stage.** One `URLCanonicalizer` (lower-case scheme/host, decode unreserved, resolve dot-segments, reject controls/userinfo) used by security, auth and parsing, so every component sees identical data (fixes S3/S4 root cause).
- **A2 Middleware chain resumption.** `DeepLinkMiddlewareCoordinator` exposes `process(_:startingAfter:)`; the readiness middleware records its position so drain continues through the remaining chain (S1).
- **A3 Atomic persistence contract.** Add `RateLimitPersistence.recordIfAllowed(...)`-style atomic operation with a default implementation built on the current methods; implement natively in the `UserDefaults` actor and in-memory test double (S2).
- **A4 Redaction layer.** `URLRedactor` (sensitive keys: `token`, `code`, `password`, `email`, `key`, `secret`, `otp`...) injected into logging, analytics, error descriptions and notifications (S6).
- **A5 Observability.** `os_signpost` intervals per middleware, and an `AsyncStream<DeepLinkResult>` on the coordinator for SwiftUI/Combine consumers.
- **A6 Error model.** Keep full URL out of `LocalizedError` text; provide `redactedDescription` and `debugDescription` (S6, S10).

## 4. New features

| ID | Feature | Use cases |
|----|---------|-----------|
| F1 | `PathPatternParser`: declarative templates (`/products/:id`, `/u/:handle/posts/*`) with typed captures | Remove hand-written parsers, consistent validation |
| F2 | `DeepLinkContext` (`source`: universalLink / customScheme / handoff / notification / spotlight / intent, `sourceApplication`, scene id) | Per-source policy: sensitive flows only via universal links |
| F3 | `PendingLinkStore` + `AuthenticationMiddleware` resume | Open protected link → login → land on original destination |
| F4 | `SignedLinkMiddleware` (HMAC-SHA256 via CryptoKit, expiry, nonce) | Password reset, invitations, payment confirmation |
| F5 | `ReplayProtectionMiddleware` (dedupe window, idempotency key) | Double taps, malicious repeated triggers |
| F6 | `ConfirmationMiddleware` / `SensitiveRoute` | User confirmation before destructive/financial actions |
| F7 | `TokenBucket` rate strategy (already on the [Roadmap](./Roadmap.md)) | Burst-tolerant limits |
| F8 | Additional entry points: `UNNotificationResponse`, App Intents / `CSSearchableItem`, `UIApplicationShortcutItem` | Push, Spotlight, Siri, quick actions |
| F9 | Multi-scene routing (route to originating scene) | iPadOS / visionOS multi-window |
| F10 | `DeepLinksTesting`: URL fuzz corpus (traversal, encoding, IDN, duplicates, oversize) + `TestClock` for rate limits | Regression-proof security tests |
| F11 | Debug diagnostics: validate configured hosts against the app's associated-domains entitlement, warn on shadowed parsers | Catches misconfiguration early |

## 5. Phases and versioning

### Phase 1 — security hardening (shipped in 2.0.0) — **Done**
1. S1 chain resumption on drain (A2) — test: auth after readiness blocks drained link.
2. S2 atomic rate limiting + `timeWindow`/`maxRequests` validation (A3) — test: 50 concurrent calls with limit 5 allow exactly 5.
3. S3 `SecurityStrategy.hardened` + `URLCanonicalizer` (A1): case-insensitive, decoded matching, userinfo/control/traversal rejection, host required.
4. S7 length / parameter-count limits as middleware option; `maxQueueSize` guidance.
5. S4 `DeepLinkURL(rejectDuplicateParameters:)`.
6. S10 fix `DeepLinkError ==`, dot-segment resolution in normalizer.
7. S6 `URLRedactor` + opt-in redacted logging/analytics strategies.

Compatibility rule: every change adds API or fixes behavior that was a bug; existing initializers and defaults keep working. Defaults that remain insecure are documented and flagged `@available(*, deprecated)` only where a safe replacement exists.

### Phase 2 — additive features (shipped in 2.0.0) — **Done**
F1, F3, F5, F7, F10, F11, A5. Also: `.hardened` rejects invisible Unicode format and separator characters (Cf, Zl, Zp).

### Phase 3 — `2.0.0` (breaking, only what cannot be additive) — **Done**
- ~~`DeepLinkMiddleware.intercept(_ request: DeepLinkRequest)` carrying `DeepLinkContext` (S8/F2); a source-compat shim keeps `intercept(_ url:)` default-implemented for one release.~~ Done, plus `allowedSources` and activity-type checks.
- ~~Secure defaults: `SecurityMiddleware` defaults to `.hardened` and requires `allowedHosts` for http(s); analytics/logging/errors redacted by default (S6), including the built-in sites listed in `api-reference-en.md` (routing/coordinator/readiness logs, logging and analytics delegates, `DefaultAnalyticsProvider`, `.console`); `ReadinessQueue` bounded by default (S7).~~ Done (`DeepLinkLogPrivacy`, `.unredacted` opt-outs).
- ~~`RateLimitPersistence` atomic method becomes a requirement (A3).~~ Done as `mutateRequests(_:)`, no default implementation.
- ~~F4 signed links, F6 confirmation, F8/F9 entry points that depend on the request type.~~ Done: `SignedLinkMiddleware` (+ `SignedLinkBuilder`, `SigningKeyring`, `InMemoryNonceStore`, `DeepLinkMatcher`), `ConfirmationMiddleware` (+ new `DeepLinkError.confirmationDenied`), notification / Spotlight / quick-action entry points, `SceneRoutingHandler` and `onDeepLink(_:sceneID:)`.
- ~~Migration guide + `CHANGELOG` "Breaking" section.~~ Done: `MIGRATION-2.0.md`, `docs/securing-deep-links-en.md`, `CHANGELOG` `[2.0.0]`. Phase 1 added no `@available(*, deprecated)` markers (every Phase 1 change was additive or a bug fix), so there are none to repoint; the 1.x `intercept(_ url:)` form and `DeepLinkMiddlewareCoordinator.process(_: URL)` are now `@available(*, deprecated)` (see CHANGELOG for what stays undeprecated and why).

### Backlog (deferred from Phase 2 review)
- ~~**Router swallows `securityViolation`.**~~ Done in 2.0 (also `blockedURL`). `DefaultDeepLinkRouting` treats every parser error as "try the next parser", so a traversal rejected by `PathPatternParser` can still be accepted by a laxer later parser. Rethrow `securityViolation` immediately (behavior change → 2.0, or opt-in flag in 1.x). Today the parser check is documented as defence in depth.
- ~~**`PathPatternMatch.int` accepts `-5` and `007`.**~~ Done in 2.0: `int(_:)` is canonical non-negative; `value(_:as:)` stays lenient.
- ~~**`rateLimitExceeded` with an infinite window.**~~ Done: a non-refilling `.tokenBucket` reports the seconds since its first admitted request.
- **`AuthenticationMiddleware.init` gained a defaulted `pendingLinks:` parameter.** Source-compatible for calls, but breaks references to the old initializer as a function value; keep an explicit overload if strict compatibility matters.
- **Replay protection and attacker floods.** `maxEntries` eviction can be forced by many distinct links inside one window; documented, mitigated by placing the rate limiter first.

### Backlog (deferred from Phase 3)
- **SwiftUI scene identifier.** SwiftUI exposes none, so `onDeepLink(_:sceneID:)` takes an app-supplied identifier (documented `@SceneStorage` pattern) rather than deriving one.
- **Replay vs. pending-link resume ordering.** The recommended order puts replay protection before authentication; apps resuming protected links must move it after authentication (documented).

## 6. Quality gates (per phase)
- TDD: failing test first for each finding (user rule), deterministic clocks (no real sleeps).
- `swift test` green on all targets; CI matrix unchanged.
- A code review at the end of each phase; findings triaged before the next phase.
- Docs: update `api-reference-en.md`, `how-to-use-deeplink-en.md`, and add a "Securing your deep links" guide (middleware ordering: security → rate limit → auth → readiness → transforms → analytics).
