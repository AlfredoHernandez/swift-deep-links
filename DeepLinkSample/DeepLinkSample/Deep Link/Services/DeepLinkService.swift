//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation
import OSLog

/// Service responsible for creating and configuring deep link coordinators.
///
/// This service encapsulates all the configuration logic for deep link processing,
/// including middleware setup, delegate configuration, and coordinator creation.
/// It provides a clean interface for the ViewModel and follows the Single Responsibility Principle.
///
/// ## Responsibilities:
/// - Deep link coordinator configuration
/// - Middleware stack setup
/// - Delegate configuration
/// - Parser registration
/// - Service provider management
final class DeepLinkService {
	// MARK: - Private Properties

	private let logger = Logger(subsystem: "swift-deep-link-sample-app", category: "DeepLinkService")

	// MARK: - Service Providers

	private lazy var authenticationProvider = SampleAuthenticationProvider()
	private lazy var analyticsProvider = SampleAnalyticsProvider()

	// MARK: - Public Interface

	/// Creates a fully configured deep link coordinator.
	///
	/// This method demonstrates the modern functional API features:
	/// - **Type Aliases**: Using `CoordinatorOf<AppRoute>` for cleaner signatures
	/// - **Factory Methods**: Using `.analytics()`, `.logging()`, etc.
	/// - **Functional Composition**: Using `compose()` for middleware and delegates
	///
	/// ## Traditional vs Modern Style
	///
	/// Before (verbose):
	/// ```swift
	/// let coordinator: DeepLinkCoordinator<AppRoute> = ...
	/// .middleware(AnalyticsMiddleware(analyticsProvider: provider))
	/// .delegates([
	///     DeepLinkLoggingDelegate(enableDebugLogging: true),
	///     DeepLinkAnalyticsDelegate(analyticsProvider: provider)
	/// ])
	/// ```
	///
	/// After (functional style):
	/// ```swift
	/// let coordinator: CoordinatorOf<AppRoute> = ...
	/// .middleware(.analytics(provider: provider))
	/// .delegate(compose(.logging(enableDebugLogging: true), .analytics(provider: provider)))
	/// ```
	///
	/// - Parameter navigationRouter: The navigation router for handling route actions
	/// - Returns: A fully configured deep link coordinator
	/// - Throws: `DeepLinkError` if coordinator creation fails
	func createCoordinator(navigationRouter: NavigationRouter) async throws -> CoordinatorOf<AppRoute> {
		logger.info("Creating deep link coordinator")

		// Configure parsers
		let parsers = createParsers()

		// Configure middleware stack
		let middleware = createMiddlewareStack()

		// Configure delegates
		let delegates = createDelegates()

		// Create coordinator using builder pattern
		let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
			.routing(DefaultDeepLinkRouting<AppRoute>(parsers: parsers))
			.handler(AppDeepLinkHandler(navigationRouter: navigationRouter))
			.middleware(middleware)
			.delegates(delegates)
			.build()

		logger.info("Deep link coordinator created successfully")
		return coordinator
	}

	/// Gets the current authentication provider for testing/debugging.
	func getAuthenticationProvider() -> SampleAuthenticationProvider {
		authenticationProvider
	}

	/// Gets the current analytics provider for testing/debugging.
	func getAnalyticsProvider() -> SampleAnalyticsProvider {
		analyticsProvider
	}
}

// MARK: - Private Configuration Methods

private extension DeepLinkService {
	/// Creates the parser stack for all supported route types.
	///
	/// - Returns: An array of configured parsers
	func createParsers() -> [any DeepLinkParser<AppRoute>] {
		[
			InformationParser(),
			ProfileParser(),
			ProductParser(),
			SettingsParser(),
			AlertParser(),
		]
	}

	/// Creates the middleware stack using functional factory methods.
	///
	/// **Modern Functional API**: This method uses static factory methods
	/// and the `compose()` function for cleaner, more declarative configuration.
	///
	/// ## Before (Traditional Style):
	/// ```swift
	/// [
	///     RateLimitMiddleware(maxRequests: 10, timeWindow: 60.0),
	///     AnalyticsMiddleware(analyticsProvider: provider)
	/// ]
	/// ```
	///
	/// ## After (Functional Style):
	/// ```swift
	/// compose(
	///     .rateLimit(maxRequests: 10, timeWindow: 60),
	///     .analytics(provider: provider)
	/// )
	/// ```
	///
	/// The middleware stack is configured in the following order:
	/// 1. Rate limiting (prevents abuse)
	/// 2. Security validation (validates URLs against security policies)
	/// 3. Authentication checks (validates user authentication for protected routes)
	/// 4. URL transformation (normalizes URLs)
	/// 5. Analytics tracking (tracks deep link usage)
	/// 6. Logging (comprehensive logging of deep link attempts)
	///
	/// - Returns: An array of configured middleware
	func createMiddlewareStack() -> [any DeepLinkMiddleware] {
		compose(
			.rateLimit(maxRequests: 10, timeWindow: 60.0),
			.security(
				allowedSchemes: ["deeplink", "testapp"],
				allowedHosts: ["profile", "product", "settings", "info", "alert"],
			),
			.authentication(
				provider: authenticationProvider,
				protectedHosts: ["profile", "settings"],
			),
			.urlTransformation(transformer: URLNormalizationTransformer()),
			.analytics(provider: analyticsProvider),
			.logging(),
		)
	}

	/// Creates a composite delegate using functional composition.
	///
	/// **Modern Functional API**: This method uses static factory methods
	/// and the `compose()` function to create a composite delegate.
	///
	/// ## Before (Traditional Style):
	/// ```swift
	/// [
	///     DeepLinkLoggingDelegate(enableDebugLogging: true),
	///     DeepLinkAnalyticsDelegate(analyticsProvider: provider)
	/// ]
	/// ```
	///
	/// ## After (Functional Style):
	/// ```swift
	/// [compose(
	///     .logging(enableDebugLogging: true),
	///     .analytics(provider: provider)
	/// )]
	/// ```
	///
	/// The delegate provides:
	/// - Detailed logging of deep link processing
	/// - Analytics tracking for usage insights
	/// - User notifications for feedback
	///
	/// - Returns: An array with a single composite delegate
	func createDelegates() -> [DeepLinkCoordinatorDelegate] {
		[compose(
			.logging(enableDebugLogging: true),
			.analytics(provider: analyticsProvider),
			.notification(
				showSuccess: true,
				showErrors: true,
				showInfo: false,
			),
		)]
	}
}
