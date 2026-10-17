//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

// MARK: - DeepLinkCoordinatorBuilder + Secure Defaults

public extension DeepLinkCoordinatorBuilder {
	/// Puts the recommended first stages of the chain in front of every other
	/// middleware: ``SecurityMiddleware`` (``SecurityStrategy/hardened`` with
	/// ``DeepLinkInputLimits/recommended`` and, by default,
	/// ``DeepLinkInputLimits/rejectDuplicateParameters``), then ``RateLimitMiddleware``, then
	/// ``ReplayProtectionMiddleware``.
	///
	/// The three stages always run first, whatever the order of the builder
	/// calls, so add the rest of the chain with `middleware(_:)` in the
	/// documented order: signed links, authentication, readiness,
	/// confirmation, transforms, analytics. Calling this again replaces the
	/// earlier preset. It cannot be combined with
	/// ``middlewareCoordinator(_:)``; ``build()`` throws.
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(parser)
	///     .handler(handler)
	///     .secureDefaults(
	///         allowedSchemes: ["myapp", "https"],
	///         allowedHostsByScheme: ["https": ["example.com"]]
	///     )
	///     .middleware(.authentication(provider: auth, protectedHosts: ["account"]))
	///     .build()
	/// ```
	///
	/// ## Not included
	///
	/// Signed links, confirmation prompts, authentication, readiness, URL
	/// transforms, logging and analytics depend on your app and are left out.
	/// So are `blockedPatterns`; register a ``SecurityMiddleware`` yourself
	/// when you need them. Rate limiting is
	/// app-wide, not per source or per link.
	///
	/// - Parameters:
	///   - allowedSchemes: The accepted schemes. Every other scheme is rejected.
	///   - allowedHosts: Allowed hosts. `http(s)` links require a listed host
	///     (empty rejects every web link); custom-scheme hosts are checked only
	///     when the set is not empty.
	///   - allowedHostsByScheme: Hosts allowed per scheme; an entry replaces
	///     `allowedHosts` for its scheme and an empty entry rejects the scheme.
	///   - allowedSources: Accepted link sources; `nil` (default) accepts every source.
	///   - rejectDuplicateParameters: Whether a link repeating a query parameter
	///     name is rejected, so middleware, signatures and parsers never disagree
	///     about its value. Defaults to `true`; pass `false` when your links
	///     carry lists as repeated parameters (`?tag=a&tag=b`).
	///   - maxRequests: Links accepted per `timeWindow` across the app. Defaults
	///     to `30`, well above what a person can open and low enough to stop a
	///     link flood; links rejected by the security check do not count.
	///   - timeWindow: The rate-limit window in seconds. Defaults to `60`.
	///   - rateLimitPersistence: Where accepted-link timestamps are kept. `nil`
	///     (default) uses `UserDefaults`, which survives relaunches but which a
	///     user with access to the app container can edit.
	///   - replayWindow: Seconds during which the same URL is dropped as a
	///     replay. Defaults to `2`, enough for a double tap or one link
	///     delivered by two entry points.
	///   - dateProvider: The clock for rate limiting and replay protection.
	/// - Returns: A new builder with the preset in front of the chain.
	func secureDefaults(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		allowedHostsByScheme: [String: Set<String>] = [:],
		allowedSources: Set<DeepLinkContext.Source>? = nil,
		rejectDuplicateParameters: Bool = true,
		maxRequests: Int = 30,
		timeWindow: TimeInterval = 60,
		rateLimitPersistence: (any RateLimitPersistence)? = nil,
		replayWindow: TimeInterval = 2,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) -> Self {
		var copy = self
		copy.presetMiddleware = [
			SecurityMiddleware(
				allowedSchemes: allowedSchemes,
				allowedHosts: allowedHosts,
				allowedHostsByScheme: allowedHostsByScheme,
				allowedSources: allowedSources,
				strategy: .hardened,
				limits: .recommended.rejectingDuplicateParameters(rejectDuplicateParameters),
			),
			RateLimitMiddleware(
				maxRequests: maxRequests,
				timeWindow: timeWindow,
				persistence: rateLimitPersistence,
				dateProvider: dateProvider,
			),
			ReplayProtectionMiddleware(window: replayWindow, dateProvider: dateProvider),
		]
		return copy
	}
}
