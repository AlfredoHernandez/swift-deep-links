# Securing your deep links

A deep link is untrusted input. Any app on the device can open your custom
scheme, any web page can trigger your Universal Links, and Handoff,
notifications and Spotlight deliver URLs you did not type. Assume every link
is hostile, and that app state (sign-in, readiness) can change between the
moment a link arrives and the moment it runs.

This guide shows how to combine the built-in middleware into a defensive
pipeline. For the full API, see the [API Reference](./api-reference-en.md);
when upgrading from 1.x, start with the [migration guide](../MIGRATION-2.0.md).

## 1. Know where a link came from

Every entry point tags the link with a `DeepLinkContext`:

| Entry point | Source |
|-------------|--------|
| `onOpenURL` / `handle(url:context: .openedURL(url))` | `.customScheme` (or `.unknown` for unverified `http(s)`) |
| `handle(activity:)` with `NSUserActivityTypeBrowsingWeb` | `.universalLink` |
| `handle(activity:handoffActivityTypes:)` | `.handoff` |
| `handle(notificationResponse:)` | `.notification` |
| `handle(searchableItemActivity:)` | `.spotlight` |
| `handle(shortcutItem:)` | `.shortcut` |
| `handle(url:)` | `.unknown` |
| readiness drains, pending-link resumes | the source the link arrived with |

The source is a claim your own entry point makes, not proof. Use it to
*restrict* flows, never to trust a link:

```swift
.security(
    allowedSchemes: ["https"],
    allowedHosts: ["pay.example.com"],
    allowedSources: [.universalLink]   // payment links only through verified Universal Links
)
```

## 2. Order the pipeline

```text
security → rate limit → replay → signed links → auth → readiness → confirmation → transforms → analytics
```

```swift
let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
    .parser(try PathPatternParser("/products/:id") { .product(id: try $0.int("id")) })
    .handler(handler)
    .middleware(
        .security(
            allowedSchemes: ["https", "myapp"],
            allowedHosts: ["example.com", "www.example.com"],
            limits: .recommended
        ),
        .rateLimit(maxRequests: 20, timeWindow: 60, strategy: .tokenBucket(capacity: 5, refillRate: 0.5)),
        .replayProtection(window: 2),
        .signedLinks(
            keys: SigningKeyring(keys: ["2026-10": currentKey, "2026-04": previousKey]),
            requiredFor: .paths(["/reset", "/invite"]),   // also covers myapp://reset and myapp://invite
            nonceStore: InMemoryNonceStore()
        ),
        .authentication(provider: auth, protectedHosts: ["account"], pendingLinks: pendingLinks),
        .readiness(queue: readinessQueue),
        .confirmation(provider: AlertConfirmation(), requiredFor: .paths(["/pay", "/account/delete"]), timeout: .seconds(60)),
        .analytics(provider: analytics)
    )
    .build()
```

Why this order:

1. **Security** rejects malformed, oversized and off-domain links before
   anything else reads them. `.hardened` (the default) canonicalizes the URL,
   rejects userinfo, control and invisible characters, `..` segments in any
   encoding and over-nested encodings, and requires an allowed host for web
   links. `limits: .recommended` caps length, parameter count and value size.
2. **Rate limiting** bounds the work an attacker can trigger, including HMAC
   checks and prompts later in the chain.
3. **Replay protection** drops the same link delivered twice (double taps,
   `onOpenURL` plus `NSUserActivity`) before the signature check, so a
   single-use link is not reported as reused. If you resume protected links
   after sign-in, place it after authentication instead, or the resumed link
   is a replay.
4. **Signed links** prove a link was minted by your server and is unmodified.
5. **Authentication** gates protected routes and can save the link to resume
   after sign-in. It runs again on resume, so the check happens at execution time.
6. **Readiness** holds links until the app can navigate; drained links resume
   the chain after it, so later stages evaluate them at drain time.
7. **Confirmation** asks the user only about links every earlier stage accepted.
8. **Transforms** run on canonical, verified links.
9. **Analytics and logging** record what will actually be routed. URLs are
   redacted by default.

## 3. Sign sensitive links

Password resets, invitations and payment confirmations should be signed by
your server. `SignedLinkMiddleware` verifies an HMAC-SHA256 signature over a
canonical form of the URL (scheme, host, port, path, sorted query without the
signature, fragment), plus an expiry and an optional single-use nonce.

```swift
// Server (Swift) or tests
let link = try SignedLinkBuilder(key: currentKey, keyID: "2026-10").sign(
    URL(string: "https://example.com/reset?user=42")!,
    expiresAt: .now.addingTimeInterval(15 * 60),
    nonce: UUID().uuidString
)

// App
.signedLinks(
    keys: SigningKeyring(keys: ["2026-10": currentKey]),
    requiredFor: .paths(["/reset"]),
    nonceStore: InMemoryNonceStore()
)
```

> **Cover every URL shape that reaches the same screen.** `myapp://reset?user=42`
> has host `reset` and an empty path, so a rule that only looked at the path
> would let it through unsigned. `.paths(_:)` therefore also matches a
> custom-scheme host as the first segment (`.paths(["/reset"])` covers
> `https://example.com/reset`, `myapp://reset` and `myapp://reset/42`), but web
> hosts are never treated as path segments. If your parsers route other shapes
> to the same screen (a different host, a query flag), add them with
> `.anyOf(.paths(...), .hosts(...), .custom { … })`, and test the unsigned forms
> are rejected.

- Keys: at least 256 random bits, stored in the Keychain or delivered by your
  configuration service, never in the binary in plain sight. Rotate by adding
  the new key id, signing with it, and removing the old key once its links
  have expired.
- Expiry: keep lifetimes short (minutes for resets, days for invitations).
- Nonces are two-phase: `SignedLinkMiddleware` reserves the nonce once the
  signature verifies, and the coordinator spends it once a handler runs (even
  one that throws: it, or an earlier route, may already have acted; keep
  handlers idempotent). A link queued by readiness keeps the nonce reserved
  until it drains and is settled then; if the queue evicts or resets it, the
  nonce is released. If authentication, confirmation or the parsers stop the
  link before any handler runs, the nonce is released, so the user can retry,
  and a link saved for sign-in resumes once. A reservation never settled (the
  app was killed mid-link) lapses after `reservationTTL`; while the link is
  still in flight, `SignedLinkMiddleware` refuses the same nonce regardless,
  so a slow prompt cannot let it run twice. Give confirmation prompts a
  `timeout` shorter than `reservationTTL` when several processes share a store. Calling the
  middleware directly, outside a coordinator, consumes at once. Pass
  `reusedNonce: .drop` to stop reused links silently instead of with an error.
  `InMemoryNonceStore` is bounded and forgets on relaunch; use
  `UserDefaultsNonceStore` when a link must stay single-use across launches
  (it persists spent nonces and drops open reservations on relaunch, so an
  interrupted link can be retried).
- Userinfo (`user:pass@`) is not signed; `.hardened` security in front
  rejects it.
- Notification payloads, Spotlight identifiers and quick actions that open a
  signed path must carry the signed URL (mint it on the server, or sign it
  when you index the item); they are verified like any other link.
- Failures throw `securityViolation` with fixed reasons that never include the
  key, the signature or the link.
- Servers in other languages must reproduce the canonical form exactly; the
  [API Reference](./api-reference-en.md#signedlinkmiddleware) specifies it
  line by line, and `SignedLinkBuilder` is the reference implementation.

## 4. Confirm destructive actions

Even a valid, signed link should not delete an account or send money without
the user seeing it. `ConfirmationMiddleware` hands your
`DeepLinkConfirmationProvider` the redacted URL and the context, and stops the
link with `DeepLinkError.confirmationDenied` when the user declines or does not
answer within `timeout`. Treat that error as a user choice, not an attack. On
timeout the link is denied at once, even if your provider ignores
cancellation, but dismiss the prompt in the cancellation handler so it does
not linger.

```swift
@MainActor
final class AlertConfirmation: DeepLinkConfirmationProvider {
    private var pending: CheckedContinuation<Bool, Never>?

    func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = continuation
                presentAlert(
                    title: "Open this link?",
                    message: request.context.source == .customScheme ? "Opened by another app" : nil
                ) { approved in self.finish(approved) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(false) }   // timeout: dismiss and answer
        }
    }

    private func finish(_ approved: Bool) {
        dismissAlert()
        pending?.resume(returning: approved)
        pending = nil
    }
}
```

## 5. Prefer route-level rules

URL rules (`DeepLinkMatcher`) run before parsing and see a URL that may be
spelled in many ways. Route rules run on the route your parsers produced, so
they hold however the link was written. Use them for everything sensitive,
and keep URL rules as an early filter:

```swift
let isSensitive: @Sendable (AppRoute) -> Bool = {
    switch $0 { case .resetPassword, .payment: true; default: false }
}

.handler(
    AppHandler()
        .requiringSignature(for: .routes(where: isSensitive))      // only verified signed links
        .requiringAuthentication(for: .routes(where: isSensitive), provider: auth)
        .confirming(.routes { if case .payment = $0 { true } else { false } }) { route, _ in
            await alerts.confirm(route.summary)                      // describe the action, not the URL
        }
)
```

`SignedRouteGuard` relies on `DeepLinkContext.isSignatureVerified`, which only
`SignedLinkMiddleware` sets, so keep `.signedLinks(...)` in the chain (without
it, or without CryptoKit, the guard fails closed). It verifies every link
carrying a signature, even ones no URL rule selects. The
flag is bound to the URL that was verified: a middleware that rewrites the
URL afterwards clears it, so run URL transformations **before**
`.signedLinks(...)` (or not at all on signed links).

## 6. Parse strictly

- Prefer `PathPatternParser` (`PathPatternParser("/products/:id") { … }`): captures are
  decoded once, restricted to unreserved characters, and `.`/`..` segments are
  rejected.
- `PathPatternMatch.int` accepts only canonical non-negative integers.
- Reject duplicate parameters (`DeepLinkInputLimits(rejectDuplicateParameters: true)`
  or `DeepLinkURL(rejectDuplicateParameters:)`) so middleware and parsers never
  disagree about a value.
- Throw `routeNotFound` for links that are not yours; `securityViolation` and
  `blockedURL` stop routing so a laxer parser cannot accept what a stricter
  one rejected.

## 7. Keep secrets out of logs

Since 2.0, framework logs, analytics, error descriptions and notifications
redact tokens, codes, emails, JWTs and userinfo. Use
`error.redactedDescription` in your own logs, keep `.unredacted` / `.full` to
debug builds, and keep secrets out of path segments, which are never redacted.

## 8. Multi-window apps

Pass each scene's identifier with the link (`sceneID:` on every entry point,
`onDeepLink(_:sceneID:)` in SwiftUI) and route through a `SceneRoutingHandler`,
so a link opened in one window cannot drive navigation in another.

## 9. Verify

- Run `DeepLinkDiagnostics` in debug builds with your `applinks:` entitlement
  values to catch hosts that do not match your associated domains.
- Feed `URLFuzzCorpus.hostile(scheme:host:)` through your real middleware chain
  in tests and assert every case is rejected.
- Use `ManualDateProvider` and injected sleeps to test expiry, rate limits and
  timeouts deterministically.

See the [hardening checklist](../MIGRATION-2.0.md#hardening-checklist) before
shipping.
