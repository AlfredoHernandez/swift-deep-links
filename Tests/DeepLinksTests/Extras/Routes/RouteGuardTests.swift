//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import os
import Testing

struct RouteGuardTests {
	// MARK: - Route Matcher

	@Test
	func `route matcher selects routes by predicate`() {
		let sut = RouteMatcher<TestRoute>.routes { $0 == .route1 }

		#expect(sut.matches(.route1, context: .unknown))
		#expect(!sut.matches(.route2, context: .unknown))
		#expect(RouteMatcher<TestRoute>.all.matches(.route3, context: .unknown))
	}

	@Test
	func `custom route matcher sees the context`() {
		let sut = RouteMatcher<TestRoute>.custom { _, context in context.source == .universalLink }

		#expect(sut.matches(.route1, context: DeepLinkContext(source: .universalLink)))
		#expect(!sut.matches(.route1, context: DeepLinkContext(source: .customScheme)))
	}

	// MARK: - Signature Guard

	@Test
	func `unsigned protected route is rejected before the handler runs`() async {
		let inner = CollectingHandler<TestRoute>()
		let sut = SignedRouteGuard(inner, requiredFor: .routes { $0 == .route1 })

		await #expect(throws: DeepLinkError.securityViolation(SignedRouteGuard<TestRoute>.unsignedRouteReason)) {
			try await sut.handle(.route1, context: DeepLinkContext(source: .universalLink))
		}
		#expect(inner.handledRoutes.isEmpty)
	}

	@Test
	func `verified protected route and unprotected routes reach the handler`() async throws {
		let inner = CollectingHandler<TestRoute>()
		let sut = inner.requiringSignature(for: .routes { $0 == .route1 })
		var verified = DeepLinkContext(source: .universalLink)
		verified.signatureVerifiedURL = payURL

		try await sut.handle(.route1, context: verified)
		try await sut.handle(.route2, context: .unknown)

		#expect(inner.handledRoutes == [.route1, .route2])
	}

	@Test(arguments: ["myapp://anything/else", "https://example.com/%72eset", "https://example.com/other"])
	func `any URL spelling that parses to a protected route needs a signature`(link: String) async throws {
		let sut = SignedPipeline()

		let result = try await sut.coordinator.handle(url: #require(URL(string: link)), context: DeepLinkContext(source: .customScheme))

		#expect(result.firstDeepLinkError == .securityViolation(SignedRouteGuard<TestRoute>.unsignedRouteReason))
		#expect(sut.handler.handledRoutes.isEmpty)
	}

	@Test
	func `a signed link reaches a protected route even when no URL rule selects it`() async throws {
		let sut = SignedPipeline()
		let link = try SignedLinkBuilder(key: key).sign(#require(URL(string: "myapp://anything/else")))

		let result = await sut.coordinator.handle(url: link, context: DeepLinkContext(source: .customScheme))

		#expect(result.wasSuccessful)
		#expect(sut.handler.handledContexts.map(\.isSignatureVerified) == [true])
	}

	@Test
	func `a link carrying an invalid signature is rejected even when no URL rule selects it`() async throws {
		let sut = SignedPipeline()
		let link = try SignedLinkBuilder(key: SymmetricKey(size: .bits256)).sign(#require(URL(string: "myapp://anything/else")))

		let result = await sut.coordinator.handle(url: link)

		#expect(result.firstDeepLinkError == .securityViolation(SignedLinkMiddleware.invalidSignatureReason))
	}

	@Test
	func `a signed link queued for readiness still passes the route guard when drained`() async throws {
		let handler = CollectingHandler<TestRoute>()
		let queue = DeepLinkReadinessQueue()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.requiringSignature(for: .all),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false),
				ReadinessMiddleware(queue: queue),
			]),
		)
		_ = try await coordinator.handle(url: SignedLinkBuilder(key: key).sign(#require(URL(string: "myapp://pay"))))

		let drained = await coordinator.markReadyAndDrain(queue: queue)

		#expect(drained.map(\.wasSuccessful) == [true])
		#expect(handler.handledRoutes == [.route1])
	}

	@Test(arguments: [RewriteKind.replacingURL, .assigningURL, .bridgedLegacy])
	func `a URL rewritten after verification no longer counts as signed`(kind: RewriteKind) async throws {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = try DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.requiringSignature(for: .all),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false),
				kind.middleware(to: #require(URL(string: "myapp://admin"))),
			]),
		)

		let result = try await coordinator.handle(url: SignedLinkBuilder(key: key).sign(#require(URL(string: "myapp://pay"))))

		#expect(result.firstDeepLinkError == .securityViolation(SignedRouteGuard<TestRoute>.unsignedRouteReason))
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `a middleware that keeps the verified URL keeps the signature`() async throws {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.requiringSignature(for: .all),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false),
				PassthroughMiddleware(),
			]),
		)

		let result = try await coordinator.handle(url: SignedLinkBuilder(key: key).sign(#require(URL(string: "myapp://pay"))))

		#expect(result.wasSuccessful)
	}

	@Test
	func `signed link middleware clears a verified flag it did not set`() async throws {
		let middleware = SignedLinkMiddleware(keys: SigningKeyring(key: key), requiredFor: .paths(["/nothing"]), requiresExpiry: false)
		var context = DeepLinkContext()
		context.signatureVerifiedURL = otherURL

		let result = try await middleware.intercept(DeepLinkRequest(url: #require(URL(string: "myapp://x")), context: context))

		#expect(result?.context.isSignatureVerified == false)
	}

	@Test
	func `without signed link middleware every protected route fails closed`() async throws {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.requiringSignature(for: .all),
		)

		let result = try await coordinator.handle(url: SignedLinkBuilder(key: key).sign(#require(URL(string: "myapp://pay"))))

		#expect(result.firstDeepLinkError == .securityViolation(SignedRouteGuard<TestRoute>.unsignedRouteReason))
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `entry point contexts are never verified`() throws {
		#expect(!DeepLinkContext(source: .universalLink).isSignatureVerified)
		#expect(try !DeepLinkContext.openedURL(#require(URL(string: "myapp://x"))).isSignatureVerified)
	}

	// MARK: - Confirmation Guard

	@Test
	func `confirmed route reaches the handler with its context`() async throws {
		let inner = CollectingHandler<TestRoute>()
		let asked = OSAllocatedUnfairLock<[TestRoute]>(initialState: [])
		let sut = inner.confirming(.routes { $0 == .route1 }) { route, _ in
			asked.withLock { $0.append(route) }
			return true
		}

		try await sut.handle(.route1, context: .unknown)
		try await sut.handle(.route2, context: .unknown)

		#expect(asked.withLock { $0 } == [.route1])
		#expect(inner.handledRoutes == [.route1, .route2])
	}

	@Test
	func `declined route fails with confirmationDenied for the arriving link`() async throws {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.confirming(.all) { _, _ in false },
		)

		let result = try await coordinator.handle(url: #require(URL(string: "myapp://pay?token=1")))

		#expect(try result.firstDeepLinkError == .confirmationDenied(#require(URL(string: "myapp://pay?token=1"))))
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `a declined signed link reports the routed URL without its signature parameters`() async throws {
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: CollectingHandler<TestRoute>().confirming(.all) { _, _ in false },
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(keys: ["k1": key]), requiresExpiry: false),
			]),
		)
		let link = try SignedLinkBuilder(key: key, keyID: "k1").sign(#require(URL(string: "myapp://pay?amount=5")), nonce: "n-1")

		let result = await coordinator.handle(url: link)

		#expect(try result.firstDeepLinkError == .confirmationDenied(#require(URL(string: "myapp://pay?amount=5"))))
	}

	@Test(.timeLimit(.minutes(1)))
	func `unanswered route confirmation times out as a denial`() async {
		let inner = CollectingHandler<TestRoute>()
		let sut = ConfirmingHandler(inner, requiredFor: .all, timeout: .seconds(10), sleep: { _ in }) { _, _ in
			await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in }
		}

		await #expect(throws: DeepLinkError.self) {
			try await sut.handle(.route1, context: .unknown)
		}
		#expect(inner.handledRoutes.isEmpty)
	}
}

// MARK: - Helpers

private let key = SymmetricKey(data: Data(repeating: 9, count: 32))
private let payURL = URL(string: "myapp://pay")!
private let otherURL = URL(string: "myapp://x")!

/// A URL rule that never matches plus a route rule protecting `.route1`, so
/// only the route guard can catch an unsigned link.
private struct SignedPipeline {
	let handler = CollectingHandler<TestRoute>()
	let coordinator: DeepLinkCoordinator<TestRoute>

	init() {
		coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler.requiringSignature(for: .routes { $0 == .route1 }),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), requiredFor: .paths(["/nothing"]), requiresExpiry: false),
			]),
		)
	}
}

enum RewriteKind: Sendable, CaseIterable {
	case replacingURL, assigningURL, bridgedLegacy

	func middleware(to target: URL) -> any DeepLinkMiddleware {
		switch self {
		case .replacingURL: ReplacingMiddleware(target: target)
		case .assigningURL: AssigningMiddleware(target: target)
		case .bridgedLegacy: LegacyRewritingMiddleware(target: target)
		}
	}
}

private struct ReplacingMiddleware: DeepLinkMiddleware {
	let target: URL

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		request.replacingURL(target)
	}
}

private struct AssigningMiddleware: DeepLinkMiddleware {
	let target: URL

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		var rewritten = request
		rewritten.url = target
		return rewritten
	}
}

/// A 1.x middleware rewriting through the deprecated URL form.
private struct LegacyRewritingMiddleware: DeepLinkMiddleware {
	let target: URL

	func intercept(_: URL) async throws -> URL? {
		target
	}
}

#endif
