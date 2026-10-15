# swift-deep-links — Architecture & DX Improvement Checklist

> **Purpose of this file.** A long-lived checklist for improving the `swift-deep-links` package, written so a contributor can pick it up without prior context. Each item has enough grounding (files, line numbers, rationale) to act on it independently. Internal planning notes; not part of the public documentation.

---

## 0. Orientation for a new session

If you are opening this file cold, read this section first.

- **Primary branch for this work:** `feature/modernization` (main branch is `main`)
- **Test baseline:** 282 tests in 27 suites (Swift Testing framework, no XCTest). All must stay green after every change.
- **Build / test commands:**
  ```bash
  swift build
  swift test
  ```
- **Swift version:** 6.2 (strict concurrency enabled by default via tools-version)
- **Commit convention:** short subject line, optional bullet body (`git log --oneline` for style). **Never add `Co-Authored-By` trailers.**
- **User preferences that constrain work:**
  - Do not push to remote until the user has tested locally.
  - Fix bugs by writing a failing test first, then the fix.
  - Prefer small, focused changes.
  - Threading in tests matters — use locks or actors, never fake `@unchecked Sendable`.
- **Key source map:**
  - `Sources/DeepLinks/Core/` — public protocols, coordinator, builder, error, result, URL wrapper
  - `Sources/DeepLinks/Extras/Middleware/` — concrete middleware (analytics, auth, logging, rate-limit, readiness, security, URL transformation)
  - `Sources/DeepLinks/Extras/Delegates/` — concrete delegates (analytics, logging, notifications)
  - `Sources/DeepLinksTesting/` — public test doubles consumers import in their own test targets
  - `Tests/DeepLinksTests/` — unit tests for the main library
  - `Tests/DeepLinksTestingTests/` — tests for the test-doubles library
  - `docs/` — public guides; `docs/internal/` — planning notes (Roadmap, this file)
- **Protocol-witness pattern is used extensively** for strategy objects (`AnalyticsStrategy`, `LoggingFormat`, `LoggingProvider`, `SecurityStrategy`, `AuthenticationStrategy`, `RateLimitStrategy`, `URLTransformationStrategy`). Prefer extending via `static let` properties on those types rather than adding more protocols.

---

## 1. Status snapshot

### ✅ Already completed on `feature/modernization`
- `9651dbe` — Expand Apple-style Quick Help documentation for public APIs
- `cbd1db3` — Improve concurrency safety and queue introspection (`MiddlewareResult: Sendable`, `ReadinessQueue.pendingURLs`, stray doc-comment fix in `RateLimitPersistence`)
- `d0cefe0` — Fix test-suite concurrency and correctness issues (removed flaky sleep, replaced duplicate empty-URL test, locked `LoggingProviderSpy`, `UserDefaultsSuiteCleanup` helper, removed unused `DummyMiddleware`)
- `33056c4` — Remove redundant comments throughout codebase
- `ac1055e` — **[BREAKING]** Make `DeepLinkCoordinatorDelegate` generic over `Route`; delete `DeepLinkResultProtocol`; `CompositeDeepLinkDelegate<Route>` and all concrete extras delegates now generic. Closes M1, M2, M3, M8.
- `8393f3c` — **[BREAKING]** Split six middleware files into per-type modules (23 new files, 6 deleted); remove misleading `URLTransformationStrategy.batch`, `AnalyticsStrategy.performance`; remove false-positive substring checks from `SecurityStrategy.strict`; readable `OSLogType` in `LoggingProvider.console`. Closes M4, M5, M7, Mi4, Mi10.
- `c0a754a` — Add this improvement checklist.
- `d46a2bf` + `70ee3cd` — Work around Swift 6.3 IRGen crash when `\.localizedDescription` keypath is used inside the new generic `DeepLinkAnalyticsDelegate<Route>`. Closure form + `swiftformat:disable:next preferKeyPath` directive.
- **Phase A — §4.1 + §4.2 + additive §4.3 (cross-platform + SwiftUI/UIKit integration + closure factories).**
  - `64ef066` — tvOS/watchOS/visionOS declared in `Package.swift`; `NotificationDelegate` + factory + tests gated behind `#if canImport(UserNotifications) && !os(tvOS)`.
  - `3cfc7c0` — Doc drift sync (generic delegate + removed strategies).
  - `2584c93` — `coordinator.handle(activity:)` + SwiftUI `View.onDeepLink(_:)` modifier + 3 tests.
  - `fc855a7` — Checklist convention: run a code review and a test review after every phase.
  - `f696ba2` — Phase-A review follow-up: drop `referrerURL` fallback; consolidate SwiftUI path to call `handle(activity:)`; mark `@MainActor`.
  - `9ce651e` — Extend NSUserActivity coverage (routing/handler/middleware-stop forwarding + `@discardableResult`) and add SwiftUI modifier smoke test; promote `StoppingMiddleware` to shared doubles.
  - `2ff3495` — Roadmap: development process notes (since removed).
  - `b9e9a13` — `DeepLinksTests` now depends on `DeepLinksTesting` so unit tests can reuse the public testing helpers.
  - `b6a0ade` — Closure-based `DeepLinkHandler.from(_:)` factory + `ClosureDeepLinkHandler<Route>` adopter + 3 tests.
  - `17a3bba` — Closure-based `DeepLinkParser.from(_:)` factories (multi-route + single-route) + adopter structs + 7 tests.
  - `fc5bcc4` — `DeepLinkCoordinatorBuilder.parser(_:)` / `.parsers([...])` / `.parsers(_:...)` fluent shortcuts + 6 tests.
  - Code and test reviews ran twice against Phase A (after §4.1+§4.2, and after §4.3 additive). Inline follow-ups applied in the commits above (last-one-wins doc on `routing(_:)`, empty-array parser test, outcome-oriented test names, `CollectingHandler` dedup, dropped unnecessary `@MainActor`). Overflow backlogged into §4.6 / §4.7. **Test baseline: 305 in 32 suites.**
- **Phase B — §4.3 breaking + §4.4 + §4.5 (API-surface cleanup, all bundled into one release).**
  - `3a9a8e0` — Add `DeepLinkResult.firstDeepLinkError` typed accessor (§4.4).
  - `22f372b` — **[BREAKING]** Drop `AnyObject` constraint from `DeepLinkCoordinatorDelegate` (§4.3).
  - `ec78d6c` — **[BREAKING]** Make `DeepLinkCoordinatorBuilder.build()` synchronous; add `DeepLinkMiddlewareCoordinator(middleware:)` + `nonisolated` `CompositeDeepLinkDelegate.init` (§4.3).
  - `4a50dcf` — **[BREAKING behavior]** Default `routeExecutionDelay` to `.zero`; guard skips `Task.sleep` when zero (§4.3).
  - `55557d6` — **[BREAKING]** Require `DeepLinkRoute: Sendable, Equatable, Hashable`; simplify every `& Equatable` constraint on generic routes across Sources and Tests (§4.3).
  - `d423942` — **[BREAKING]** Redesign `DeepLinkError`: URL-carrying cases, labeled `invalidParameterValue(name:value:)` / `rateLimitExceeded(maxRequests:timeWindow:)`, `handlerError(message:underlyingError:)`, new `parsingFailed(url:underlyingErrors:)`, manual `Equatable` (§4.4).
  - `5d35505` — Propagate parser errors through `DefaultDeepLinkRouting` via `parsingFailed` (§4.4).
  - `cab7dd0` — Update `SingleRouteClosureDeepLinkParser` sentinel to `routeNotFound(url)` (§4.4).
  - `e49cea2` — **[BREAKING]** Delete `AdvancedDeepLinkMiddleware` + `MiddlewareResult`; simpler `DeepLinkMiddleware` covers everything (§4.5).
  - `0984c67` — Drop tautological `any Error` cast + dead `BoxedParserError` wrapper in `DefaultDeepLinkRouting`.
  - `11cb860` — Add `coordinator.markReadyAndDrain(queue:)` helper that bypasses middleware on drain; `ReadinessDrainIntegrationTests` covers order, bypass, delegate hooks, empty queue (§4.5).
  - `571775f` — Phase-B review follow-up: flatten nested `parsingFailed` in `DefaultDeepLinkRouting`; add Quick Help note that `DeepLinkError.Equatable` compares underlying errors by locale-dependent `localizedDescription`; pin flatten behaviour with a new test.
  - `8db5a77` — Phase-B review follow-up: replace the four tautological `is` checks in `CompositionTests.swift` with spy-driven behavioural assertions; drop now-useless `async` on the local `makeTestCoordinator()`.
  - `f305958` — Phase-B review follow-up: extend `ReadinessDrainIntegrationTests` with routing-failure, handler-failure, and second-drain-idempotence scenarios.
  - `c94a942` — Phase-B review follow-up: add dedicated `DeepLinkErrorTests.swift` covering `errorDescription` per case + `Equatable` coverage per case + the `parsingFailed` / `handlerError` underlying-error comparison path.
  - `6e080af` — Phase-B review follow-up: sync public docs (README, `api-reference-en.md`, `faq.md`, `how-to-use-deeplink-en.md`) with the new surface.
  - Code and test reviews ran against Phase B. Findings triaged: pre-close follow-ups landed in `571775f`, `8db5a77`, `f305958`, `c94a942`, `6e080af`. Overflow backlogged into §4.7 (double consolidation, clock injection, parameterization, concurrency stress). **Test baseline: 331 in 35 suites.**
- **Phase C — §4.6 cleanup of minor noise (mostly internal; three small breaking deletions).**
  - `398ae0e` — Tighten `ClosureDeepLinkHandler` / `ClosureDeepLinkParser` / `SingleRouteClosureDeepLinkParser` inits to `fileprivate` so the `.from(_:)` factory is the only construction path.
  - `4d71d39` — Replace fragile DocC disambiguators (`from(_:)-([R])` / `-(R?)`) on parser adopter types with prose references that survive parameter-type rendering.
  - `c1369ba` — Document best-effort ordering of `onDeepLink` tasks: URLs arriving in quick succession may have their coordinator runs interleaved; consumers needing strict order should drive the coordinator from a serial owner above the view layer.
  - `bb557ab` — Make `RateLimitMiddleware.dateProvider` injectable (default `Date.init`) and mirror on the `.rateLimit(...)` factory so time-based tests can run deterministically.
  - `05e74ac` + `42d47a9` — `JSONQueryParameterParser.parse(_:fromAll:)` now falls back to array-preserving decode when scalar-unwrap fails; first-pass error is rethrown on both-fail so diagnostics stay useful.
  - `b5e4a00` — `NotificationDelegate` now tracks spawned Tasks in an `OSAllocatedUnfairLock<[UUID: Task]>` dictionary and cancels them in a nonisolated `deinit`; `print` → `Logger`.
  - `2729e27` + `6d4c26a` — **[BREAKING]** Introduce `DeepLinkNotificationPresenter` protocol + `DefaultDeepLinkNotificationPresenter`; delete the XCTest env-var bypass. Protocol carries a `DeepLinkNotificationKind` severity (`.success / .failure / .info`) so custom presenters route by severity without inspecting the title or identifier. `.notification(...)` factory grows a `presenter:` parameter.
  - `d795f23` — Extract internal `AnalyticsEventBuilder` to deduplicate the `scheme` / `host` / `url` / `path` / `timestamp` envelope that `DeepLinkAnalyticsDelegate` and the three `AnalyticsStrategy` values shared. Unifies on `url.host()` (method) across all call sites.
  - `93d54aa` — **[BREAKING]** Delete identity `compose(_:any DeepLinkMiddleware...)` / `compose(_:[any DeepLinkMiddleware])` overloads; middleware arrays now pass directly through `.middleware(_:)`.
  - `90065b9` — **[BREAKING]** Delete `CoordinatorOf` / `ResultOf` type aliases; canonical generic names only.
  - `3c2efd2` — **[BREAKING]** Variadic `parsers(_:any DeepLinkParser<Route>...)` now requires a leading `first` parser so `.parsers()` with zero arguments is a compile-time error rather than a silently-misbehaving coordinator.
  - `b4c4fbe` — Phase-C review follow-up: sync `Docs/api-reference-en.md` (delete removed `compose(middleware:...)` line, add Notification Presenter section, thread `presenter:` through `.notification(...)`, document middleware-array plumbing).
  - Code and test reviews ran against Phase C. Findings triaged: pre-close follow-ups landed in `42d47a9` (JSON first-pass error), `6d4c26a` (kind: on presenter + expanded tests + AsyncStream fence + drop `@unchecked`), `b4c4fbe` (doc drift). Overflow backlogged into §4.7 / §4.8 (AnalyticsStrategy/.full asymmetry, `host` → `host()` changelog, DeepLinkSample staleness, `CollectingPresenter` → DeepLinksTesting, factory `is` → behaviour tests, `deinit` cancels-in-flight regression test, RateLimit clock-injection port). **Test baseline: 336 in 36 suites.**
- **Phase D — §4.7 test-suite overhaul (tests only + one additive production seam).**
  - `f7987b5` — Add dedicated `DeepLinkResultTests` covering `wasSuccessful` truth table + `summary` branches + convenience accessors.
  - `64e1db6` — Regression test for `DeepLinkNotificationDelegate` deinit cancelling pending notification tasks before they reach the presenter.
  - `e2df6fb` — Concurrent-handle stress test for `DeepLinkHandler.from(_:)` + host-less URL coverage pair for single-route parser factory.
  - `cf5852f` — Inject `sleep: @Sendable (Duration) async -> Void` into `DeepLinkCoordinator.init` so time-dependent tests can run without wall-clock delays. Purely additive — defaults to `Task.sleep(for:)`.
  - `f011146` — Port `RateLimitMiddlewareTests` to a `ManualClock` via the Phase-C-injectable `dateProvider`, retiring ~2.7s of wall-clock per suite run.
  - `de6cfae` — Lock-protect `DeepLinkRoutingStub` / `DeepLinkHandlerSpy` via `OSAllocatedUnfairLock<State>` and drop `@unchecked Sendable`; consolidate duplicated `DeepLinkParserStub` / `ThrowingParserStub` into `Shared/TestDoubles.swift`.
  - `6f569eb` — Promote `CollectingNotificationPresenter` to `DeepLinksTesting` as a public `actor` with `recordedInvocations` + `waitFor(count:)`.
  - `1a7386b` — Consolidate readiness-drain test doubles: drop local `StubRouting` in favour of `ImmediateRouting` from `DeepLinksTesting`; clean up `FailingRouting` / `FailingHandler`.
  - `dbb543c` — New `ReadinessMiddlewareCoordinatorIntegrationTests` (middleware-stopped path end-to-end) + `DeepLinkReadinessQueueConcurrencyTests` (TaskGroup stress: 100 enqueues, enqueue-racing-markReady, reset-racing-enqueue, markReady-during-burst).
  - `281b1c7` — Convert middleware + delegate factory `is` assertions to behaviour tests (factory-produced types forward lifecycle events, gate URLs, throw on rate-limit, etc.); threads the notification presenter.
  - `edfca2f` — Parameterise `LoggingMiddlewareTests` 12-cell `LoggingFormat × URL shape` matrix into one `@Test(arguments:)` test.
  - `17e8c02` — Parameterise `DefaultDeepLinkRoutingTests` single-parser happy paths + `parsers([...])` / variadic precedence into `@Test(arguments:)` tests; add dedicated `AnalyticsEventBuilderTests` pinning the `.hostOnly` / `.withURL` / `.full` parameter shapes.
  - `2c12723` — Phase-D review follow-up: expose `routeExecutionDelay` and `sleep` on `DeepLinkCoordinatorBuilder` so the test seam is reachable from the recommended construction path.
  - `f2d2d4f` — Phase-D review follow-up: drop `CollectingNotificationPresenter.invocationCount` (redundant with `recordedInvocations`); trap on second concurrent awaiter in `waitFor(count:)`; rename `BlockingPresenter` → `RecordingPresenter`; replace the deinit-cancel test's `Task.sleep(50ms)` fence with a bounded `Task.yield` loop.
  - `51e9b8c` — Phase-D review follow-up: hoist parameterised scenario arrays from file scope into the owning suites; simplify `firstError` via `firstDeepLinkError`; add "processed with zero routes" summary case; bump handler concurrent-stress fan-in 8 → 64; tighten `urlTransformation` factory assertion to the exact normalised URL; add upper bound on `markReady-during-burst` drained count.
  - Code and test reviews ran against Phase D. Pre-close follow-ups landed in `2c12723`, `f2d2d4f`, `51e9b8c`. Overflow backlogged into §4.7 / §4.8. **Test baseline: 344 in 40 suites; full suite runtime collapsed from ~1.2s to 0.019s by retiring every wall-clock sleep.**
- **Phase E — §4.8 release prep + §4.7 residuals + §4.1 CI matrix.**
  - `73bfd2a` — Reconcile `AnalyticsStrategy.detailed` with `AnalyticsEventBuilder` via a new `.fullOmittingEmptyPath` `URLDetail` case; pin all four shapes in `AnalyticsEventBuilderTests`.
  - `ca463cc` — `DeepLinkHandlerSpy.handle(_:)` now uses a single `withLock` that returns an `Outcome` enum; introduce an `expectDeepLinkError` helper in `DefaultDeepLinkRoutingTests` replacing the older `do/catch+Issue.record` idiom at six call sites.
  - `093d164` — Migrate `DeepLinkSample` to the current API surface (`CoordinatorOf` / `ResultOf` / middleware `compose()` replaced with canonical generics + array literals); `createCoordinator()` is now `throws` (not `async throws`). Verified via `xcodebuild build`.
  - `b87fe94` — Add root `CHANGELOG.md` seeded with a complete `[Unreleased]` entry covering every phase's breaking changes, additions, removals, and fixes; calls out the locale-dependent `DeepLinkError` equality and the `url.host()` IDN shift.
  - `aa0cb81` + `586a50e` — Add `xcode-platforms` GitHub Actions matrix covering iOS / macOS / tvOS / watchOS / visionOS. Initial form used `Simulator` destinations; switched to device destinations per code-review finding that watchOS/visionOS simulator runtimes are opt-in on GitHub's `macos-15` runners. Also drop stray `set -o pipefail` + `-skipPackagePluginValidation` cleanup.
  - `32fcaa9` — Drop stale `compose(...)` samples from `README.md` + `Docs/how-to-use-deeplink-en.md`.
  - `fa856fb` — Phase-E review follow-up: fix `swift-deep-link` singular typo across public docs (CHANGELOG / ImprovementChecklist / faq).
  - `5ed0865` — Phase-E review follow-up: fix `DeepLinkSampleTests` compilation after 093d164 migrated sample sources but not the test target (`CollectingDelegate<AppRoute>()`, constrained `delegate:` parameter, `@MainActor` test annotation); add `keys.sorted()` assertions to the three new `AnalyticsEventBuilderTests` cases.
  - Code and test reviews ran against Phase E. Pre-close follow-ups landed in `fa856fb`, `586a50e`, `5ed0865`. `xcodebuild test -scheme DeepLinkSample` verified green on iPhone 17 Pro simulator. Overflow (expectDeepLinkError promote to Shared, Outcome enum collapse, README bullet split, xcodebuild test in CI matrix) backlogged into §4.7 / §4.8. **Test baseline: 347 in 40 suites; sample app tests green on iOS simulator.**

### ⏭️ Open — residual backlog items in §4.1 / §4.7 / §4.8 below

**Current test baseline: 347 tests in 40 suites, all passing. Sample app TEST SUCCEEDED on iPhone 17 Pro.**

---

## 2. How to resume work across sessions

1. From the repository root:
2. `git status` and `git log --oneline -10` to catch up on state.
3. `swift test` to verify 282 baseline (or whatever number is current — record in this file if you change it).
4. Read this file (`docs/internal/ImprovementChecklist.md`) and pick an unchecked item.
5. Each item lists: file(s), rationale, acceptance criteria, and whether it is breaking API.
6. After finishing an item: tick the checkbox (`[x]`), run `swift build` and `swift test`, then commit.
7. Group commits by concern (one logical change per commit). Do not bundle unrelated items.
8. If you introduce a breaking change, note migration guidance in the item's checkbox comment so the README / CHANGELOG update task (§6) stays in sync.

---

## 3. Source of the findings

Three independent reviews informed this document:

1. **Senior-architect code review** — findings C1-C5 (critical), M1-M11 (major), Mi1-Mi14 (minor), N1-N7 (nit), plus design-pattern candidates.
2. **Swift Testing audit** — test-suite quality findings (naming, duplicated doubles, flakiness, missing coverage, parameterization opportunities).
3. **Architecture / DX / cross-platform review** — this is the newest pass; its findings drive §4 below. Full report lives in conversation history; summary embedded here.

---

## 4. Backlog — Architecture & DX improvements

Ordered roughly by impact × inverse effort (top = do first). `[BREAKING]` flags API-source-breaking changes.

### 4.1 Cross-platform — expand reach

- [x] ~~**Declare all deep-link-capable Apple platforms in `Package.swift`.**~~ Done in `64ef066`. Declared `.tvOS(.v16)`, `.watchOS(.v9)`, `.visionOS(.v1)` in addition to iOS 16 / macOS 13. Cross-compiled successfully for tvOS and watchOS simulators.

- [x] ~~**Fix package name inconsistency.**~~ **INVALID finding.** Reviewers confused the local directory name (`swift-deep-link`, singular) with the git remote, which is actually `github.com/AlfredoHernandez/swift-deep-links.git` (plural). The `Package.swift` `name: "swift-deep-links"` already matches the remote; nothing to change.

- [x] ~~**Guard `NotificationDelegate` with `#if canImport` + platform exclusions.**~~ Done in `64ef066`. Wrapped the file, the `.notification()` factory in `CoordinatorDelegate+Factory.swift`, and its tests in `#if canImport(UserNotifications) && !os(tvOS)`.

- [x] ~~**Audit every `import` in `Sources/DeepLinks/` for platform-locked frameworks.**~~ Done. Only platform-locked import found was `UserNotifications` (handled above). All other code uses only `Foundation`, `os.log` / `OSLog` / `os`, which are available on every supported platform.

### 4.2 SwiftUI / UIKit / AppKit integration

- [x] ~~**Ship a SwiftUI `View` modifier for one-liner URL handling.**~~ Done in `2584c93`. `View.onDeepLink(_:)` lives at `Sources/DeepLinks/Extras/SwiftUI/OnDeepLinkModifier.swift`, gated behind `#if canImport(SwiftUI)`. Attaches both `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` in one call.

- [x] ~~**Add `coordinator.handle(activity: NSUserActivity)` entry point.**~~ Done in `2584c93`. Added as an extension in `Sources/DeepLinks/Core/DeepLinkCoordinator+NSUserActivity.swift`. Extracts `webpageURL` (falling back to `referrerURL`) and forwards to `handle(url:)`. Three behavioural tests added at `Tests/DeepLinksTests/Core/DeepLinkCoordinator+NSUserActivityTests.swift`.

- [x] ~~**Consider scene-bridge helpers for UIKit and AppKit.**~~ **Declined.** The manual wiring is 2–3 lines in a scene/app delegate and is now shown in both `README.md` and `docs/how-to-use-deeplink-en.md` (§5). Adding library types around `UIScene.openURLContexts` / `NSAppleEventManager` would be thin wrappers with little value over the snippet. If demand surfaces later, revisit.

- [x] ~~**Set up CI that actually builds the package for every declared platform (tvOS, watchOS, visionOS).**~~ Done in Phase E (`aa0cb81` + `586a50e`). `.github/workflows/swift.yml` now has an `xcode-platforms` matrix that runs `xcodebuild build` against `generic/platform=<plat>` device destinations for iOS / macOS / tvOS / watchOS / visionOS, both for `DeepLinks` and `DeepLinksTesting`. Device destinations require only the platform SDK, not a simulator runtime — safe on stock `macos-15` runners.

### 4.3 Quickstart and ergonomics

- [x] ~~**Add closure-based factory initializers for `DeepLinkHandler` and `DeepLinkParser`.**~~ Done in `b6a0ade` + `17a3bba`. Landed as public `.from(_:)` factories on both protocols using the SwiftUI `where Self == ConcreteAdopter` pattern so dot-shorthand works. Parser ships two overloads: multi-route `(URL) async throws -> [Route]` and single-route `(URL) async throws -> Route?` (the latter translates `nil` into `DeepLinkError.routeNotFound(url.host ?? "")`).

- [x] ~~**Add `.parser(_:)` / `.parsers(_:)` shortcuts on `DeepLinkCoordinatorBuilder`.**~~ Done in `fc5bcc4`. Three overloads — single parser, array, variadic — wrap into `DefaultDeepLinkRouting`. Shares `_routing` with `.routing(_:)`; last-one-wins semantics documented on all four methods (no throw at `build()`).

- [x] ~~**Make `DeepLinkCoordinatorBuilder.build()` synchronous.** `[BREAKING]`~~ Done in `ec78d6c`. Added `DeepLinkMiddlewareCoordinator(middleware:)` init that bypasses the actor-add loop; made `CompositeDeepLinkDelegate.init` `nonisolated` (stored-property init only, method dispatch stays `@MainActor`); dropped `async` on `build()`.

- [x] ~~**Remove `routeExecutionDelay = 500ms` default.** `[BREAKING behavior]`~~ Done in `4a50dcf`. Default is now `.zero`; `DeepLinkCoordinator.executeRoutes` short-circuits the `Task.sleep` when the delay is zero. Consumers who relied on the implicit 500ms pacing must now pass it explicitly at `DeepLinkCoordinator.init`.

- [x] ~~**Require `Equatable & Hashable & Sendable` on `DeepLinkRoute`.** `[BREAKING]`~~ Done in `55557d6`. Every `<Route: DeepLinkRoute & Equatable>` constraint in Sources and Tests was simplified. `id` is preserved — still useful for logging and protocol-level identity — since enum-synthesized `Equatable` / `Hashable` doesn't obviate the need for a stable string ID.

- [x] ~~**Drop `AnyObject` constraint from `DeepLinkCoordinatorDelegate`.** `[BREAKING]`~~ Done in `22f372b`. Value types and actors can now conform. `@MainActor` isolation is preserved.

### 4.4 Error and result surface

- [x] ~~**Enrich `DeepLinkError` cases with URL and underlying error.** `[BREAKING]`~~ Done in `d423942`. Cases now carry URLs (`invalidURL`, `routeNotFound`, `parsingFailed`, `handlerError` underlying, `unauthorizedAccess`, `blockedURL`) and labeled payloads (`invalidParameterValue(name:value:)`, `rateLimitExceeded(maxRequests:timeWindow:)`, `handlerError(message:underlyingError:)`). Added `parsingFailed(url:underlyingErrors:)` for parser-chain failures. Manual `Equatable` compares underlying errors via `localizedDescription` (locale-dependent; Quick Help annotated in `571775f`).

- [x] ~~**Propagate parser errors through `DefaultDeepLinkRouting`.**~~ Done in `5d35505` + `571775f`. All parser errors are collected into `parsingFailed(url:underlyingErrors:)` when every parser in the chain fails; empty parser list still throws `routeNotFound(url)`. Nested `parsingFailed` from a delegating parser is flattened so callers never see `parsingFailed(parsingFailed(...))`. Pinned by `DefaultDeepLinkRouting flattens nested parsingFailed from a delegating parser` test.

- [x] ~~**Add a typed accessor for the first `DeepLinkError` in `DeepLinkResult.errors`.**~~ Done in `3a9a8e0`. `firstDeepLinkError: DeepLinkError?` ships with `DeepLinkResultFirstErrorTests` covering empty/only-framework/non-framework-then-framework/mixed scenarios.

- [x] ~~**Revisit `SingleRouteClosureDeepLinkParser`'s `routeNotFound("")` sentinel.**~~ Done in `cab7dd0`. Sentinel now throws `routeNotFound(url)` with the full URL. Unambiguous under the new `routeNotFound(URL)` shape.

### 4.5 Middleware / strategy cleanup

- [x] ~~**Unify the middleware protocol (M1 + M8).**~~ Done in prior commits on this branch (verified clean in the Phase 2 review).
- [x] ~~**Generic delegate, delete `DeepLinkResultProtocol` (M2 + M3).**~~ Done in `ac1055e`.
- [x] ~~**Split multi-type files (M4).**~~ Done in `8393f3c`.
- [x] ~~**Remove misleading strategies (M5 / M7 / Mi4 / Mi10).**~~ Done in `8393f3c`.

- [x] ~~**Decide final shape of `MiddlewareResult`.**~~ Done in `e49cea2`. Deleted `AdvancedDeepLinkMiddleware` + `MiddlewareResult` entirely. The simpler `DeepLinkMiddleware.intercept(_:) async throws -> URL?` covers every semantics the advanced protocol expressed: return `URL` to continue, return modified URL to transform, return `nil` to halt without error, `throw` to halt with error. Existing middleware tests rewritten to target the unified protocol.

- [x] ~~**Improve readiness drain UX.**~~ Done in `11cb860`. Added `coordinator.markReadyAndDrain(queue:)` that marks the queue ready and routes every previously-queued URL directly through routing + handler, bypassing the middleware chain so analytics/rate-limit/auth side effects don't re-fire. Existing `queue.markReady()` stays available for consumers that want the re-feed behaviour. Behaviour pinned by `ReadinessDrainIntegrationTests`: order preservation, middleware-bypass, empty-queue, delegate hooks still firing, routing failure, handler failure, idempotence.

### 4.6 Cleanup of minor noise

- [x] ~~**Collapse or delete redundant `compose` functions.**~~ Done in `93d54aa`. Both middleware variadic and array overloads were pure-identity functions; deleted. Delegate overloads kept because they wrap in `CompositeDeepLinkDelegate`. Consumers pass arrays directly through `.middleware(_:)`.

- [x] ~~**Delete or rename `CoordinatorOf` / `ResultOf` type aliases.**~~ Done in `90065b9`. Type aliases deleted; `TypeAliases.swift` removed; DocC See-Also refs pruned from `DeepLinkCoordinator` / `DeepLinkResult`.

- [x] ~~**`DefaultDeepLinkRouting.route(from:)` logs lastError but discards it.**~~ Done in Phase B (`5d35505` + `571775f`) as part of the parser-error-propagation work.

- [x] ~~**`AnalyticsDelegate` duplicates parameter-building logic with `AnalyticsStrategy`.**~~ Done in `d795f23`. Extracted internal `AnalyticsEventBuilder.parameters(for:detail:)` with three `URLDetail` levels; all four surfaces (delegate + `.standard` / `.detailed` / `.minimal` strategies) route through it. Unifies on `url.host()`.

- [x] ~~**`NotificationDelegate` uses `print` in the catch block and spawns detached tasks.**~~ Done in `b5e4a00`. Tasks tracked in `OSAllocatedUnfairLock<[UUID: Task]>` dictionary, self-removed on completion, cancelled in a nonisolated `deinit`. `print` → `Logger`.

- [x] ~~**`NotificationDelegate` branches on `XCTestConfigurationFilePath` in production code.**~~ Done in `2729e27` + `6d4c26a`. Introduced `DeepLinkNotificationPresenter` protocol + `DefaultDeepLinkNotificationPresenter` default; removed the XCTest env-var branch; added `DeepLinkNotificationKind` severity to the protocol signature (locked before public release to avoid a source-breaking change later).

- [x] ~~**`onDeepLink` modifier spawns unordered Tasks; URLs arriving in quick succession may interleave.**~~ Done in `c1369ba`. Added an `## Ordering` section to the modifier's Quick Help calling out that order is best-effort and steering consumers who need strict ordering to a serial owner above the view layer.

- [x] ~~**`RateLimitMiddleware.dateProvider` is not injectable.**~~ Done in `bb557ab`. Added `dateProvider: @Sendable @escaping () -> Date = Date.init` to the init and mirrored on the `.rateLimit(...)` factory. Porting `RateLimitMiddlewareTests` to use it remains in §4.7 (biggest CI-time payoff).

- [x] ~~**`JSONQueryParameterParser.parse(_:fromAll:)` auto-unwraps single-element arrays.**~~ Done in `05e74ac` + `42d47a9`. Two-pass decoder: try scalar-unwrapping first, fall back to array-preserving on failure. First-pass error is rethrown on both-fail so diagnostics stay scalar-oriented (usually closer to the real fix). Limitation — mixed scalar+array models against single-value URLs still can't be resolved — is pinned by a dedicated test.

- [x] ~~**Audit DocC disambiguators on `DeepLinkParser.from(_:)` overloads.**~~ Done in `4d71d39`. Replaced `` `DeepLinkParser/from(_:)-([R])` `` / `` `-(R?)` `` disambiguator suffixes with prose references that survive rendered-parameter-type changes.

- [x] ~~**Guard variadic `parsers(_:...)` against empty-/zero-argument calls.**~~ Done in `3c2efd2`. Split variadic into `(first, rest...)`; `.parsers()` with zero args is now a compile error. Array overload still accepts `[]` for callers that deliberately want to clear the slot and override via `.routing(_:)`.

- [x] ~~**Tighten adopter-struct initializers to `private`.**~~ Done in `398ae0e`. All three closure-adopter inits are now `fileprivate` — reachable from the same-file `.from(_:)` factory, blocked from other files in the module. `private` would prevent the factory from reaching them; `fileprivate` is the correct tightening.

### 4.7 Tests — missing coverage and hygiene

(A full test audit produced more items. Below is a subset that materially improves confidence. Full list lives in conversation history under the swift-testing audit.)

- [x] ~~**Inject clock into `RateLimitMiddleware`, then rewrite time-based tests to use it.**~~ Done in Phase C (`bb557ab`) + Phase D (`f011146`). `dateProvider` was made injectable in C; D ported the tests to a `ManualClock` double, retiring every `Task.sleep` in that file.

- [x] ~~**End-to-end Readiness integration test.**~~ Done in Phase D (`dbb543c`). New `ReadinessMiddlewareCoordinatorIntegrationTests` covers: `wasStoppedByMiddleware == true` while not ready; direct `queue.markReady()` → next `handle(url:)` routes normally; queued URLs drain via `markReadyAndDrain`.

- [x] ~~**Concurrency stress for `DeepLinkReadinessQueue`.**~~ Done in Phase D (`dbb543c`). `DeepLinkReadinessQueueConcurrencyTests` covers: 100 simultaneous enqueues preserve every URL; enqueue-racing-markReady converges consistently; reset-racing-enqueue never duplicates or loses URLs; markReady-during-burst captures at least the pre-race URLs.

- [x] ~~**Create `DeepLinkErrorTests.swift`.**~~ Done in Phase B (`c94a942`). Parameterized per-case `errorDescription` tests + per-case `Equatable` coverage + `parsingFailed` / `handlerError` underlying-error comparison path.

- [x] ~~**Create `DeepLinkResultTests.swift`.**~~ Done in Phase D (`f7987b5` + `51e9b8c` follow-up). Parameterised truth table for `wasSuccessful`, `summary` across middleware-stopped / successful / partial-failure / zero-routes, and the convenience accessors (`hasRoutes`, `hasErrors`, `firstDeepLinkError`).

- [x] ~~**Replace factory `is` tests with behavior tests.**~~ Done in Phase D (`281b1c7`). Middleware and delegate factory tests assert genuine side effects (provider receives events, rateLimit throws after cap, security halts disallowed schemes, URL transformer actually mutates, presenter threading proven). Composition's `is` tautologies were already cleaned up in Phase B (`8db5a77`).

- [x] ~~**Consolidate duplicated test doubles.**~~ Done in Phase D (`de6cfae` + `1a7386b`). `DeepLinkParserStub` / `ThrowingParserStub` moved to `Shared/TestDoubles.swift`; `StubRouting` in readiness tests replaced with `ImmediateRouting` from `DeepLinksTesting`.

- [ ] **Adopt uniform test naming `test_<subject>_<behavior>[_<condition>]`.**
  - Today three conventions coexist. Pick one and migrate. Use `@Test("display name")` paired with the method name in the convention. Phase D left this as-is — most new tests adopted the backtick-quoted sentence form.

- [x] ~~**Parameterize near-duplicate tests.**~~ Done in Phase D (`edfca2f` + `17e8c02`). `LoggingMiddleware` 12-cell format × URL shape matrix → one `@Test(arguments:)`. `DefaultDeepLinkRouting` single-parser happy paths → one parameterised test. `parsers([...])` / variadic → one `ParsersOverload`-driven test. Authentication and analytics strategy matrices not taken on — left in backlog below if ever useful.

- [x] ~~**Concurrent-`handle` regression test for closure-based `DeepLinkHandler`.**~~ Done in Phase D (`e2df6fb` + `51e9b8c` follow-up bumped N to 64).

- [ ] **Parameterize single-route parser factory tests when a 5th case lands.**
  - File: `Tests/DeepLinksTests/Core/DeepLinkParserFactoryTests.swift`
  - The single-route overload tests (non-nil, nil-with-host, nil-without-host, error, …) are structurally identical. Not worth parameterizing at 4 cases; revisit when a fifth scenario (host-less URL equivalence, distinct error types, etc.) surfaces.

- [x] ~~**Parameterize `parsers([...])` vs `parsers(_:...)` precedence tests.**~~ Done in Phase D (`17e8c02`). One `ParsersOverload`-driven `@Test(arguments:)` asserts both overloads agree.

- [x] ~~**Audit `@unchecked Sendable` on `DeepLinkRoutingStub` and other shared doubles.**~~ Done in Phase D (`de6cfae`). `DeepLinkRoutingStub` / `DeepLinkHandlerSpy` now use `OSAllocatedUnfairLock<State>` and drop `@unchecked Sendable`. `AnalyticsProviderSpy` kept `@unchecked` with a doc-annotated single-threaded contract — `[String: Any]` can't flow through `Sendable` storage cheaply. If stricter enforcement is needed, stringify parameters at ingress and migrate to checked `Sendable`.

- [x] ~~**Host-less URL coverage pair for single-route parser factory.**~~ Done in Phase D (`e2df6fb`).

- [x] ~~**Consolidate Phase-B-era duplicate test doubles.**~~ Done in Phase D (`de6cfae` moved `DeepLinkParserStub` / `ThrowingParserStub` / local `TestRoute` into `Shared/TestDoubles.swift`; `1a7386b` replaced `StubRouting` with `ImmediateRouting`).

- [x] ~~**Lock / actor-ify `DeepLinkParserStub.parseCalledWith`.**~~ Done in Phase D (`de6cfae`). `parseCalledWith` is now behind `OSAllocatedUnfairLock` and the class is plain `Sendable` (no `@unchecked`).

- [x] ~~**Retire the 500ms wall-clock sleep in `DeepLinkCoordinatorTests`.**~~ Done in Phase D (`cf5852f` + `2c12723` follow-up). `DeepLinkCoordinator.init` gained a `sleep:` closure parameter (also exposed on the builder via `.sleep(_:)`); tests use a `DurationRecorder` actor to assert N-1 sleep calls with the configured duration without wall-clock waits.

- [ ] **Parameterize `DefaultDeepLinkRoutingTests` happy paths + post-deletion middleware tests.**
  - File: `Tests/DeepLinksTests/Core/DeepLinkMiddlewareCoordinatorTests.swift`
  - The routing happy-paths portion was done in Phase D (`17e8c02`). The three post-`AdvancedDeepLinkMiddleware`-deletion middleware tests (transform / halt-with-nil / halt-with-error) remain — each uses a different stub type, so parameterisation would trade clarity for compactness. Keep unless the shape repeats elsewhere.

- [x] ~~**Elevate `DeepLinkReadinessQueue` concurrency-stress priority after drain path landed.**~~ Done in Phase D (`dbb543c`). See the stress tests added alongside the integration coverage.

- [x] ~~**Port `RateLimitMiddlewareTests` to the new injectable `dateProvider`.**~~ Done in Phase D (`f011146`). Retired ~2.7s of wall-clock per suite run via a `ManualClock` test double.

- [x] ~~**Promote `CollectingPresenter` to `DeepLinksTesting`.**~~ Done in Phase D (`6f569eb` + `f2d2d4f` follow-up). Public `CollectingNotificationPresenter` actor with `recordedInvocations` + `waitFor(count:)`; second-awaiter misuse trips a `precondition`.

- [x] ~~**Replace factory `is` tests with behaviour tests (revisit after Phase C).**~~ Done in Phase D (`281b1c7`). Notification factory's `presenter:` threading is now pinned by a dedicated behaviour test.

- [x] ~~**`deinit` cancels in-flight notification tasks regression test.**~~ Done in Phase D (`64e1db6` + `f2d2d4f` follow-up). A task queued before the delegate is released never reaches the presenter; assertion uses a bounded `Task.yield` fence instead of wall-clock sleep.

- [x] ~~**Parameterize `AnalyticsEventBuilder` shape assertions.**~~ Done in Phase D (`17e8c02`). Dedicated `AnalyticsEventBuilderTests` pins the `.hostOnly` / `.withURL` / `.full` shapes plus the `"unknown"` host fallback and the timestamp window.

- [x] ~~**Reconcile `AnalyticsStrategy.detailed` with `AnalyticsEventBuilder.full`.**~~ Done in Phase E (`73bfd2a`). Added a `.fullOmittingEmptyPath` `URLDetail` case that emits the `path` key only when non-empty; `.detailed` now composes on top of it instead of post-hoc patching. The delegate keeps using `.full` (always emits `path`, even empty) so its lifecycle events preserve their existing shape.

- [ ] **Extend factory behaviour tests with non-default strategy sweeps.**
  - Files: `Tests/DeepLinksTests/Extras/Middleware/DeepLinkMiddlewareFactoryTests.swift`, `Tests/DeepLinksTests/Extras/Delegates/DeepLinkCoordinatorDelegateFactoryTests.swift`
  - Phase D converted every factory `is` assertion to a behaviour assertion but exercises only the default strategy per factory. A single `@Test(arguments:)` sweep per factory would pin that non-default strategies (`.fixedWindow` rateLimit, `.detailed` analytics, `.strict` authentication, etc.) still plumb through. Low priority — strategy behaviour is already covered in the dedicated middleware suites. Surfaced in review.

- [ ] **Add runtime enforcement for `AnalyticsProviderSpy`'s single-threaded contract.**
  - File: `Tests/DeepLinksTests/Shared/TestDoubles.swift`
  - `AnalyticsProviderSpy` stays `@unchecked Sendable` because `[String: Any]` can't flow through `OSAllocatedUnfairLock`. The documented "single-threaded by convention" guarantee has no runtime check — a future test that writes from two tasks would race silently. Options: (a) `dispatchPrecondition` inside `track(_:parameters:)`, (b) migrate to `[String: String]` at ingress and flip to checked `Sendable`, mirroring `CollectingAnalyticsProvider`. Surfaced in review.

- [x] ~~**Refactor `DeepLinkHandlerSpy.handle(_:)` to hold the lock across the read-then-append.**~~ Done in Phase E (`ca463cc`). Folded the read-and-decide + append into a single `withLock` that returns a private `Outcome` enum; the throw happens outside the critical section.

- [x] ~~**Migrate `DefaultDeepLinkRoutingTests` error paths from `do { #expect(Bool(false)) } catch { Issue.record }` to `#expect(throws:)`.**~~ Done in Phase E (`ca463cc`). Introduced a file-private `expectDeepLinkError(_:)` helper that runs the throwing body, records an issue if it returns normally, and returns the typed `DeepLinkError?` so the caller can pattern-match. Six call sites migrated.

- [ ] **Unify deterministic-time primitives when a third clock-like seam lands.**
  - Files: `Tests/DeepLinksTests/Core/DeepLinkCoordinatorTests.swift` (`DurationRecorder`), `Tests/DeepLinksTests/Extras/Middleware/RateLimitMiddlewareTests.swift` (`ManualClock`).
  - Phase D shipped two patterns — `DurationRecorder` actor for `@Sendable (Duration) async -> Void` sleeps, `ManualClock` lock-wrapped Date for `@Sendable () -> Date` providers. Acceptable today; promote to `DeepLinksTesting` only when a third clock-like primitive in production needs the same harness. Surfaced in review.

### 4.8 Package hygiene

- [x] ~~**Remove duplicate mid-file copyright blocks.**~~ Resolved automatically when M4 split the mega-files in `8393f3c` (Phase 2). Grep in Phase E over `Sources/DeepLinks/Extras/Middleware/` confirms one copyright per file.

- [x] ~~**README and CHANGELOG pass after each breaking change.**~~ Done in Phase E. `CHANGELOG.md` added at the repo root in `b87fe94` with a complete `[Unreleased]` entry covering every Phase A–E change (platform expansion, additive DX wins, breaking API cleanup, middleware/strategy deep clean, test-suite overhaul, release prep). `README.md` + `Docs/how-to-use-deeplink-en.md` scrubbed of stale `compose(...)` usage in `32fcaa9`.

- [x] ~~**Add `@available` deprecation markers before removing public API.**~~ Declined early in Phase B per user direction — modernization ships as a single major-version bump with a clean break rather than a deprecation-then-removal cycle. Callers migrate via the `CHANGELOG.md` `[Unreleased]` entry, which enumerates every removed symbol + its replacement.

- [ ] **Promote `expectDeepLinkError` to a shared test helper.**
  - Files: `Tests/DeepLinksTests/Core/DefaultDeepLinkRoutingTests.swift`, potentially `Tests/DeepLinksTests/Shared/TestHelpers.swift` (new).
  - Phase E introduced the helper as a private method on the one suite whose six error paths needed it. `JSONQueryParameterParserTests` still uses the older `do { #expect(Bool(false)) } catch { Issue.record }` idiom for `DeepLinkError` pattern-matching and would benefit from the same helper. Move when a second call site materialises. Surfaced in review.

- [ ] **Collapse `DeepLinkHandlerSpy.Outcome` enum to an optional error return.**
  - File: `Tests/DeepLinksTests/Shared/TestDoubles.swift`
  - `Outcome` is a two-case enum whose only purpose is distinguishing "recorded" from "threw". `withLock` can return `(any Error & Sendable)?` directly and the caller can `if let errorToThrow { throw errorToThrow }`. Cosmetic cleanup — correctness is unchanged. Surfaced in review.

- [ ] **Run `xcodebuild test -scheme DeepLinkSample` in CI.**
  - File: `.github/workflows/swift.yml`
  - The Phase E xcode-platforms matrix builds both package libraries for every platform but never exercises the sample's test target. Commit `093d164` proved the risk — it migrated sample sources but not tests, masked by `build`-only verification. Adding a `xcodebuild test -scheme DeepLinkSample -destination '<iOS Simulator>'` step on the iOS cell (sample doesn't target other platforms) would have caught the regression on CI. Surfaced in review.

- [ ] **Split the README "Array-literal composition" bullet into two.**
  - File: `README.md`
  - The current single-line bullet bundles the feature ("middleware/delegate arrays flow through the builder") with its caveat ("delegate-side compose() is still available") and reads dense. Break into two bullets in a follow-up. Low priority. Surfaced in review.

- [ ] **Changelog entry: `AnalyticsStrategy` now reads `url.host()` instead of the deprecated `url.host`.**
  - File: `CHANGELOG.md` (to be created in Phase E).
  - Phase C unified all analytics parameter assembly on `url.host()` via `AnalyticsEventBuilder`. Observable for IDN hosts: the property returns percent-decoded Unicode, the method returns percent-encoded. Dashboards aggregating deep-link analytics by `host` for IDN URLs will see a key shift. Surfaced in review.

- [ ] **Resolve `DeepLinkSample/` staleness.**
  - Directory: `DeepLinkSample/`.
  - Sample app uses several symbols removed during Phase B + C (`CoordinatorOf`, `ResultOf`, middleware `compose(_:)`) and won't compile against the current Package. Either update the sample to the canonical names in Phase E, or mark it explicitly stale in the repo root README. Surfaced in review.

---

## 5. Phased execution plan

A suggested sequencing — do not treat as rigid. Each phase should be reviewed + committed + tested before the next begins.

1. **Phase A — Platform expansion & quickstart wins (mostly additive).** ✅ **Closed.**
   Items in §4.1 + §4.2 + closure-based factories in §4.3 + `.parser(_:)` builder shortcut. All shipped on `feature/modernization`; post-phase Code and test reviews both ran and their findings were triaged (follow-ups applied inline; overflow backlogged into §4.4 / §4.6 / §4.7).

2. **Phase B — API surface cleanup (breaking changes bundled).** ✅ **Closed.**
   All §4.3 breaking items (`build()` sync, `routeExecutionDelay = .zero`, `DeepLinkRoute: Equatable/Hashable/Sendable`, delegate drops `AnyObject`) + §4.4 (error enrichment + parser-error propagation + `firstDeepLinkError`) + §4.5 (`AdvancedDeepLinkMiddleware`/`MiddlewareResult` deletion, `markReadyAndDrain`). Shipped on `feature/modernization` as 16 commits. Post-phase Code and test reviews ran and their findings were triaged (follow-ups applied inline; overflow backlogged into §4.7).

3. **Phase C — Middleware / strategy deep clean.** ✅ **Closed.**
   All §4.6 items shipped on `feature/modernization` across 12 commits (includes three small-breaking deletions: `compose(middleware:)`, `CoordinatorOf` / `ResultOf`, empty-variadic `.parsers()`). Post-phase Code and test reviews ran and their findings were triaged (follow-ups applied inline; overflow backlogged into §4.7 / §4.8).

4. **Phase D — Test suite overhaul.** ✅ **Closed.**
   The bulk of §4.7 shipped on `feature/modernization` across 15 commits. Additive coverage (`DeepLinkResultTests`, deinit regression, concurrent handler, host-less URL), clock injection in `DeepLinkCoordinator` + builder surface, port of `RateLimitMiddlewareTests` to `ManualClock`, shared-double lock-protection + consolidation, `CollectingNotificationPresenter` promoted to `DeepLinksTesting`, end-to-end readiness integration + concurrency stress, factory `is` → behaviour tests, parameterisation of the logging matrix / routing happy paths / parsers overloads / AnalyticsEventBuilder shapes. Full suite runtime collapsed from ~1.2s to 0.019s. Residual items (uniform naming, non-default strategy factory sweep, AnalyticsProviderSpy enforcement, HandlerSpy single-lock, error-idiom migration, clock-primitive unification) remain in §4.7 as low-priority backlog.

5. **Phase E — Documentation & release prep.** ✅ **Closed.**
   §4.8 release hygiene + residual §4.7 cleanup + §4.1 CI matrix shipped across 9 commits. Highlights: root `CHANGELOG.md` with a complete `[Unreleased]` entry, `DeepLinkSample` migration to the current API (+ test-target fix), `.github/workflows/swift.yml` xcode-platforms matrix for all five declared platforms, `AnalyticsStrategy.detailed` reconciled with a new `.fullOmittingEmptyPath` `URLDetail` case, `DeepLinkHandlerSpy.handle(_:)` single-lock refactor, `expectDeepLinkError` helper replacing the `do/catch+Issue.record` idiom. Residual low-value items (uniform naming, non-default strategy factory sweep, `AnalyticsProviderSpy` enforcement, promote `expectDeepLinkError` to Shared, Outcome enum collapse, sample xcodebuild test in CI) remain explicit low-priority backlog in §4.7/§4.8. Version bump to `1.0.0` is intentionally deferred to the user — tagging the release is the next manual step after local verification.

---

## 6. Conventions for this checklist

- **Tick a box only after the change is merged and `swift test` shows green.** Do not tick based on local-only work.
- **Add new findings at the bottom of the relevant section**, not inline in §1. Keep §1 as a living status snapshot.
- **When an item is done, do not delete it** — keep it checked so history is visible.
- **If an item is obsolete (e.g., superseded by another finding), replace the description with `~~Superseded by: <link to new item>~~` and tick it.**
- **Flag anything that requires a user decision** with `⚠️ User decision needed:` and a short question — avoid guessing on API direction.
- **At the end of every phase in §5, run two reviews on the phase's diff before moving on:**
  1. Code review — architecture review of the source + any changed tests. Scope: the files touched during the phase.
  2. Test review — test-suite audit for coverage gaps, naming drift, flakiness risks, missing edge cases on the new APIs.
  Both are read-only passes. Triage their findings into either (a) small follow-up commits on the same branch before the next phase starts, or (b) new checklist items appended to §4 if they're larger than a commit. Do not proceed to the next phase with unreviewed phase work.

---

## 7. Related files / references

- [Roadmap](./Roadmap.md) — higher-level roadmap, may overlap; reconcile before closing items.
- `README.md` — consumer-facing quickstart; update alongside breaking changes.
- `Package.swift` — platform declarations, targets.

---

*Last updated: 2026-04-19 (Phase E closed: release prep + residual cleanup + CI matrix shipped, test baseline 347 in 40 suites, sample app TEST SUCCEEDED on iPhone 17 Pro simulator, CHANGELOG.md ready for release tagging). Bump this line whenever the file is materially edited.*
