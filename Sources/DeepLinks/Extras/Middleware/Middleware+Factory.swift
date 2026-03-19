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
	///   - persistence: Persistence mechanism for storing request data
	///   - strategy: The rate limiting strategy (default: .slidingWindow)
	/// - Returns: A configured rate limit middleware instance
	static func rateLimit(
		maxRequests: Int = 100,
		timeWindow: TimeInterval = 60.0,
		persistence: RateLimitPersistence = UserDefaultsRateLimitPersistence(),
		strategy: RateLimitStrategy = .slidingWindow,
	) -> RateLimitMiddleware {
		RateLimitMiddleware(
			maxRequests: maxRequests,
			timeWindow: timeWindow,
			persistence: persistence,
			strategy: strategy,
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
	///   - allowedHosts: Set of allowed hosts (empty means all hosts allowed)
	///   - blockedPatterns: Array of regex patterns for blocked URLs
	///   - strategy: The security validation strategy (default: .standard)
	/// - Returns: A configured security middleware instance
	static func security(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		blockedPatterns: [NSRegularExpression] = [],
		strategy: SecurityStrategy = .standard,
	) -> SecurityMiddleware {
		SecurityMiddleware(
			allowedSchemes: allowedSchemes,
			allowedHosts: allowedHosts,
			blockedPatterns: blockedPatterns,
			strategy: strategy,
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
	/// - Returns: A configured authentication middleware instance
	static func authentication(
		provider: AuthenticationProvider,
		protectedHosts: Set<String>,
		strategy: AuthenticationStrategy = .standard,
	) -> AuthenticationMiddleware {
		AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: protectedHosts,
			strategy: strategy,
		)
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
	/// - Parameter queue: The readiness queue that stores URLs until ready
	/// - Returns: A configured readiness middleware instance
	static func readiness(
		queue: any ReadinessQueue,
	) -> ReadinessMiddleware {
		ReadinessMiddleware(queue: queue)
	}
}
