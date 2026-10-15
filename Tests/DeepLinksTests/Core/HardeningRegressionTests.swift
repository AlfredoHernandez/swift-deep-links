//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct HardeningRegressionTests {
	// MARK: - Default Rate-Limit Persistence

	@Test
	func `default rate limiters share a persistence only when their configuration matches`() throws {
		let short = try #require(RateLimitMiddleware(maxRequests: 5, timeWindow: 10).persistence as? UserDefaultsRateLimitPersistence)
		let sameAsShort = try #require((RateLimitMiddleware.rateLimit(maxRequests: 5, timeWindow: 10) as RateLimitMiddleware)
			.persistence as? UserDefaultsRateLimitPersistence)
		let long = try #require(RateLimitMiddleware(maxRequests: 5, timeWindow: 3600).persistence as? UserDefaultsRateLimitPersistence)
		let fixed = try #require(RateLimitMiddleware(maxRequests: 5, timeWindow: 10, strategy: .fixedWindow).persistence as? UserDefaultsRateLimitPersistence)
		let bucket = try #require(RateLimitMiddleware(strategy: .tokenBucket(capacity: 5, refillRate: 1)).persistence as? UserDefaultsRateLimitPersistence)

		#expect(short === sameAsShort)
		#expect(short !== long)
		#expect(short !== fixed)
		#expect(short !== bucket)
	}

	// MARK: - Redaction

	@Test
	func `an embedded URL Foundation cannot parse is replaced, not kept`() {
		let redacted = URLRedactor().redactingURLs(in: "see https://[::1/?token=s3cret now")

		#expect(!redacted.contains("s3cret"))
		#expect(redacted == "see REDACTED now")
	}

	// MARK: - Host Canonicalization

	@Test(arguments: ["myapp://h%C3%A9%2F..", "myapp://h%C3%A9%40evil"])
	func `a non-ASCII host that also decodes to a delimiter is rejected`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Malformed host")) {
			try URLCanonicalizer().canonicalize(url)
		}
	}

	@Test
	func `every trailing dot is dropped from a host`() throws {
		let url = try #require(URL(string: "myapp://account../x"))

		#expect(try URLCanonicalizer().canonicalize(url).absoluteString == "myapp://account/x")
		#expect(DeepLinkMatcher.hosts(["account"]).matches(DeepLinkRequest(url: url)))
	}

	@Test
	func `replay keys decode the host as many times as the canonicalizer`() throws {
		let key = ReplayKeyStrategy.path
		let plain = try #require(URL(string: "myapp://home/x"))
		let doubleEncoded = try #require(URL(string: "myapp://%2568ome/x"))

		#expect(key.key(for: plain) == key.key(for: doubleEncoded))
	}

	// MARK: - Route Declines

	@Test
	func `a wrapper that catches a decline and then fails on its own counts as a handler failure`() async throws {
		let declineThenFail = FallbackAfterDecline(guarded: CollectingHandler<TestRoute>().confirming(.all) { _, _ in false })
		let routeDecline = RouteDecline()

		let thrown = try await #require(DeepLinkRun.$routeDecline.withValue(routeDecline) {
			await #expect(throws: FallbackAfterDecline<TestRoute>.FallbackError.self) {
				try await declineThenFail.handle(.route1, context: .unknown)
			}
		})

		#expect(!routeDecline.declined(thrown))
	}
}

private struct FallbackAfterDecline<Route: DeepLinkRoute>: DeepLinkHandler {
	struct FallbackError: Error {}

	let guarded: any DeepLinkHandler<Route>

	func handle(_ route: Route, context: DeepLinkContext) async throws {
		do {
			try await guarded.handle(route, context: context)
		} catch {
			throw FallbackError()
		}
	}
}
