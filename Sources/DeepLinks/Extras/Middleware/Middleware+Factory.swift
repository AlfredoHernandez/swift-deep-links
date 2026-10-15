//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os.log

// MARK: - Static Factory Methods

public extension DeepLinkMiddleware where Self == AnalyticsMiddleware {
	/// Creates analytics middleware with the specified provider and strategy.
	///
	/// This middleware tracks deep link events using the provided analytics provider.
	///
	/// ## Usage
	///
	/// ```swift
	/// coordinator.add(.analytics(
	///     provider: myProvider,
	///     strategy: .detailed
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - provider: The analytics provider to use for tracking events
	///   - strategy: The tracking strategy (default: .standard)
	/// - Returns: A configured analytics middleware instance
	static func analytics(
		provider: AnalyticsProvider,
		strategy: AnalyticsStrategy = .standard,
	) -> AnalyticsMiddleware {
		AnalyticsMiddleware(analyticsProvider: provider, strategy: strategy)
	}
}

public extension DeepLinkMiddleware where Self == LoggingMiddleware {
	/// Creates logging middleware with the specified configuration.
	///
	/// This middleware logs deep link processing events using the configured format.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage with default configuration
	/// coordinator.add(.logging())
	///
	/// // Custom configuration
	/// coordinator.add(.logging(
	///     provider: .systemLogger(myLogger),
	///     logLevel: .debug,
	///     format: .detailed
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - provider: The logging provider (default: system logger)
	///   - logLevel: The log level (default: .info)
	///   - format: The logging format (default: .singleLine)
	/// - Returns: A configured logging middleware instance
	static func logging(
		provider: LoggingProvider = .defaultSystemLogger(),
		logLevel: OSLogType = .info,
		format: LoggingFormat = .singleLine,
	) -> LoggingMiddleware {
		LoggingMiddleware(loggingProvider: provider, logLevel: logLevel, format: format)
	}
}

public extension DeepLinkMiddleware where Self == RateLimitMiddleware {
	/// Creates rate limit middleware with the specified configuration.
	///
	/// This middleware prevents abuse by limiting the number of deep link requests
	/// within a specified time window.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Allow 10 requests per minute
	/// coordinator.add(.rateLimit(maxRequests: 10, timeWindow: 60))
	///
	/// // With custom strategy
	/// coordinator.add(.rateLimit(
	///     maxRequests: 100,
	///     timeWindow: 3600,
	///     strategy: .fixedWindow
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - maxRequests: Maximum number of requests allowed (default: 100)
	///   - timeWindow: Time window in seconds (default: 60)
	///   - persistence: Persistence mechanism for storing request data; `nil` (default) shares
	///     a `UserDefaults` persistence among limiters with the same configuration
	///   - strategy: The rate limiting strategy (default: .slidingWindow)
	///   - dateProvider: Supplies the current time for rate-limit bookkeeping.
	///     Defaults to `Date.init`; inject a deterministic provider in tests.
	/// - Returns: A configured rate limit middleware instance
	static func rateLimit(
		maxRequests: Int = 100,
		timeWindow: TimeInterval = 60.0,
		persistence: RateLimitPersistence? = nil,
		strategy: RateLimitStrategy = .slidingWindow,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) -> RateLimitMiddleware {
		RateLimitMiddleware(
			maxRequests: maxRequests,
			timeWindow: timeWindow,
			persistence: persistence,
			strategy: strategy,
			dateProvider: dateProvider,
		)
	}
}

public extension DeepLinkMiddleware where Self == SecurityMiddleware {
	/// Creates security middleware with the specified configuration.
	///
	/// This middleware validates URLs against security policies to prevent
	/// malicious deep links.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic scheme validation
	/// coordinator.add(.security(
	///     allowedSchemes: ["https", "myapp"]
	/// ))
	///
	/// // With host validation
	/// coordinator.add(.security(
	///     allowedSchemes: ["https"],
	///     allowedHosts: ["myapp.com", "secure.myapp.com"]
	/// ))
	///
	/// // Strict security
	/// coordinator.add(.security(
	///     allowedSchemes: ["https"],
	///     allowedHosts: ["trusted-domain.com"],
	///     strategy: .strict
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - allowedSchemes: Set of allowed URL schemes
	///   - allowedHosts: Allowed hosts. With the default ``SecurityStrategy/hardened``,
	///     `http(s)` links require a listed host (empty rejects every web link)
	///     and custom-scheme hosts are checked only when the set is not empty
	///   - allowedHostsByScheme: Hosts allowed per scheme, checked by ``SecurityStrategy/hardened``;
	///     an entry replaces `allowedHosts` for its scheme and an empty entry rejects the scheme
	///   - blockedPatterns: Array of regex patterns for blocked URLs
	///   - allowedSources: Accepted link sources; `nil` (default) accepts every source
	///   - strategy: The security validation strategy (default: .hardened)
	///   - limits: Size limits checked before the strategy runs (default: ``DeepLinkInputLimits/recommended``)
	/// - Returns: A configured security middleware instance
	static func security(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		allowedHostsByScheme: [String: Set<String>] = [:],
		blockedPatterns: [NSRegularExpression] = [],
		allowedSources: Set<DeepLinkContext.Source>? = nil,
		strategy: SecurityStrategy = .hardened,
		limits: DeepLinkInputLimits = .recommended,
	) -> SecurityMiddleware {
		SecurityMiddleware(
			allowedSchemes: allowedSchemes,
			allowedHosts: allowedHosts,
			allowedHostsByScheme: allowedHostsByScheme,
			blockedPatterns: blockedPatterns,
			allowedSources: allowedSources,
			strategy: strategy,
			limits: limits,
		)
	}
}

public extension DeepLinkMiddleware where Self == AuthenticationMiddleware {
	/// Creates authentication middleware with the specified configuration.
	///
	/// This middleware validates that the user is authenticated before processing
	/// certain deep links.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Protect specific hosts
	/// coordinator.add(.authentication(
	///     provider: authProvider,
	///     protectedHosts: ["secure.myapp.com", "admin.myapp.com"]
	/// ))
	///
	/// // Strict authentication for all URLs
	/// coordinator.add(.authentication(
	///     provider: authProvider,
	///     protectedHosts: [],
	///     strategy: .strict
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - provider: The authentication provider
	///   - protectedHosts: Set of hosts that require authentication
	///   - strategy: The authentication validation strategy (default: .standard)
	///   - pendingLinks: Where to save rejected links for ``DeepLinkCoordinator/resumePendingLinks(from:)`` (default: `nil`)
	///   - pendingSources: The sources whose rejected links are saved (default: ``AuthenticationMiddleware/defaultPendingSources``)
	/// - Returns: A configured authentication middleware instance
	static func authentication(
		provider: AuthenticationProvider,
		protectedHosts: Set<String>,
		strategy: AuthenticationStrategy = .standard,
		pendingLinks: (any PendingLinkStore)? = nil,
		pendingSources: Set<DeepLinkContext.Source> = AuthenticationMiddleware.defaultPendingSources,
	) -> AuthenticationMiddleware {
		AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: protectedHosts,
			strategy: strategy,
			pendingLinks: pendingLinks,
			pendingSources: pendingSources,
		)
	}
}

public extension DeepLinkMiddleware where Self == AuthenticationMiddleware {
	/// Creates authentication middleware for the links `matcher` selects.
	///
	/// See ``AuthenticationMiddleware/init(authProvider:requiredFor:pendingLinks:pendingSources:)``.
	static func authentication(
		provider: AuthenticationProvider,
		requiredFor matcher: DeepLinkMatcher,
		pendingLinks: (any PendingLinkStore)? = nil,
		pendingSources: Set<DeepLinkContext.Source> = AuthenticationMiddleware.defaultPendingSources,
	) -> AuthenticationMiddleware {
		AuthenticationMiddleware(authProvider: provider, requiredFor: matcher, pendingLinks: pendingLinks, pendingSources: pendingSources)
	}
}

public extension DeepLinkMiddleware where Self == URLTransformationMiddleware {
	/// Creates URL transformation middleware with the specified transformer.
	///
	/// This middleware transforms URLs using a provided transformer before processing.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage
	/// coordinator.add(.urlTransformation(
	///     transformer: myTransformer
	/// ))
	///
	/// // With safe strategy (returns original URL on transformation failure)
	/// coordinator.add(.urlTransformation(
	///     transformer: myTransformer,
	///     strategy: .safe
	/// ))
	/// ```
	///
	/// - Parameters:
	///   - transformer: The URL transformer to use
	///   - strategy: The transformation strategy (default: .standard)
	/// - Returns: A configured URL transformation middleware instance
	static func urlTransformation(
		transformer: URLTransformer,
		strategy: URLTransformationStrategy = .standard,
	) -> URLTransformationMiddleware {
		URLTransformationMiddleware(transformer: transformer, strategy: strategy)
	}
}

public extension DeepLinkMiddleware where Self == ReplayProtectionMiddleware {
	/// Creates a middleware that suppresses the same link arriving again within `window`.
	///
	/// See ``ReplayProtectionMiddleware/init(window:maxEntries:key:ignoredQueryKeys:response:dateProvider:)``
	/// for the parameters.
	static func replayProtection(
		window: TimeInterval = 2,
		maxEntries: Int = 100,
		key: ReplayKeyStrategy = .url,
		ignoredQueryKeys: Set<String> = [],
		response: ReplayProtectionMiddleware.Response = .drop,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) -> ReplayProtectionMiddleware {
		ReplayProtectionMiddleware(
			window: window,
			maxEntries: maxEntries,
			key: key,
			ignoredQueryKeys: ignoredQueryKeys,
			response: response,
			dateProvider: dateProvider,
		)
	}
}

public extension DeepLinkMiddleware where Self == ReadinessMiddleware {
	/// Creates readiness middleware that queues deep links until
	/// the app signals readiness.
	///
	/// ## Usage
	///
	/// ```swift
	/// let queue = DeepLinkReadinessQueue()
	///
	/// // In the middleware stack
	/// .readiness(queue: queue)
	///
	/// // When ready, drain and reprocess
	/// let pending = queue.markReady()
	/// for url in pending {
	///     await coordinator.handle(url: url)
	/// }
	/// ```
	///
	/// - Parameters:
	///   - queue: The readiness queue that stores URLs until ready
	///   - privacy: How the queued-link log describes the URL. Defaults to ``DeepLinkLogPrivacy/redacted``.
	/// - Returns: A configured readiness middleware instance
	static func readiness(
		queue: any ReadinessQueue,
		privacy: DeepLinkLogPrivacy = .redacted,
	) -> ReadinessMiddleware {
		ReadinessMiddleware(queue: queue, privacy: privacy)
	}
}

#if canImport(CryptoKit)

public extension DeepLinkMiddleware where Self == SignedLinkMiddleware {
	/// Creates a middleware requiring an HMAC-SHA256 signature on the links `matcher` selects.
	///
	/// See ``SignedLinkMiddleware/init(keys:requiredFor:parameters:requiresExpiry:leeway:maximumLifetime:nonceStore:reusedNonce:stripsSignatureParameters:dateProvider:)``
	/// for the parameters.
	static func signedLinks(
		keys: any SigningKeyProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		parameters: SignedLinkParameters = .default,
		requiresExpiry: Bool = true,
		leeway: TimeInterval = 0,
		maximumLifetime: TimeInterval? = nil,
		nonceStore: (any NonceStore)? = nil,
		reusedNonce: SignedLinkMiddleware.ReusedNonceResponse = .reject,
		stripsSignatureParameters: Bool = true,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) -> SignedLinkMiddleware {
		SignedLinkMiddleware(
			keys: keys,
			requiredFor: matcher,
			parameters: parameters,
			requiresExpiry: requiresExpiry,
			leeway: leeway,
			maximumLifetime: maximumLifetime,
			nonceStore: nonceStore,
			reusedNonce: reusedNonce,
			stripsSignatureParameters: stripsSignatureParameters,
			dateProvider: dateProvider,
		)
	}

	/// Creates a middleware requiring a signature checked by `verifier`, such as
	/// an ``Ed25519PublicKeyring``, on the links `matcher` selects.
	///
	/// See ``SignedLinkMiddleware/init(verifier:requiredFor:parameters:requiresExpiry:leeway:maximumLifetime:nonceStore:reusedNonce:stripsSignatureParameters:dateProvider:)``
	/// for the parameters.
	static func signedLinks(
		verifier: any SignedLinkVerifier,
		requiredFor matcher: DeepLinkMatcher = .all,
		parameters: SignedLinkParameters = .default,
		requiresExpiry: Bool = true,
		leeway: TimeInterval = 0,
		maximumLifetime: TimeInterval? = nil,
		nonceStore: (any NonceStore)? = nil,
		reusedNonce: SignedLinkMiddleware.ReusedNonceResponse = .reject,
		stripsSignatureParameters: Bool = true,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) -> SignedLinkMiddleware {
		SignedLinkMiddleware(
			verifier: verifier,
			requiredFor: matcher,
			parameters: parameters,
			requiresExpiry: requiresExpiry,
			leeway: leeway,
			maximumLifetime: maximumLifetime,
			nonceStore: nonceStore,
			reusedNonce: reusedNonce,
			stripsSignatureParameters: stripsSignatureParameters,
			dateProvider: dateProvider,
		)
	}
}

#endif

public extension DeepLinkMiddleware where Self == ConfirmationMiddleware {
	/// Creates a middleware asking the user to confirm the links `matcher` selects.
	///
	/// See ``ConfirmationMiddleware/init(provider:requiredFor:redactor:timeout:maxPendingPrompts:sleep:)``
	/// for the parameters.
	static func confirmation(
		provider: any DeepLinkConfirmationProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		redactor: URLRedactor = URLRedactor(),
		timeout: Duration? = ConfirmationMiddleware.defaultTimeout,
		maxPendingPrompts: Int = ConfirmationMiddleware.defaultMaxPendingPrompts,
		sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
	) -> ConfirmationMiddleware {
		ConfirmationMiddleware(
			provider: provider,
			requiredFor: matcher,
			redactor: redactor,
			timeout: timeout,
			maxPendingPrompts: maxPendingPrompts,
			sleep: sleep,
		)
	}
}
