//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
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
	private let navigationRouter: NavigationRouter

	// MARK: - Service Providers

	private let authenticationProvider = SampleAuthenticationProvider()
	private let analyticsProvider = SampleAnalyticsProvider()

	// MARK: - Initialization

	/// Creates a new deep link service.
	///
	/// - Parameter navigationRouter: The navigation router for handling route actions
	init(navigationRouter: NavigationRouter) {
		self.navigationRouter = navigationRouter
	}

	// MARK: - Public Interface

	/// Creates a fully configured deep link coordinator.
	///
	/// This method demonstrates the modern functional API features:
	/// - **Factory Methods**: Using `.analytics()`, `.logging()`, etc. on the
	///   `DeepLinkMiddleware` / `DeepLinkCoordinatorDelegate` protocols.
	/// - **Array-literal composition**: Middleware and delegates pass as
	///   plain arrays through the builder; no dedicated `compose` helper is
	///   required.
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
	/// let coordinator: DeepLinkCoordinator<AppRoute> = ...
	/// .middleware(.analytics(provider: provider))
	/// .delegate(.logging(enableDebugLogging: true), .analytics(provider: provider))
	/// ```
	///
	/// - Returns: A fully configured deep link coordinator
	/// - Throws: `DeepLinkError` if coordinator creation fails
	func createCoordinator() throws -> DeepLinkCoordinator<AppRoute> {
		logger.info("Creating deep link coordinator")

		// Configure parsers
		let parsers = createParsers()

		// Configure middleware stack
		let middleware = createMiddlewareStack()

		// Configure delegates
		let delegates = createDelegates()

		// Create coordinator using builder pattern
		let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
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
	/// and an array literal for a cleaner, more declarative configuration
	/// than manually constructing each middleware type.
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
	/// [
	///     .rateLimit(maxRequests: 10, timeWindow: 60),
	///     .analytics(provider: provider),
	/// ]
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
		[
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
		]
	}

	/// Creates the delegate stack using static factory methods.
	///
	/// **Modern Functional API**: each element is produced by
	/// `.logging(...)`, `.analytics(...)`, `.notification(...)` etc.; the
	/// builder's `.delegates(_:)` takes the array and the coordinator
	/// composes them internally when it builds.
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
	/// [
	///     .logging(enableDebugLogging: true),
	///     .analytics(provider: provider),
	/// ]
	/// ```
	///
	/// The delegate provides:
	/// - Detailed logging of deep link processing
	/// - Analytics tracking for usage insights
	/// - User notifications for feedback
	///
	/// - Returns: An array with a single composite delegate
	func createDelegates() -> [any DeepLinkCoordinatorDelegate<AppRoute>] {
		[
			.logging(enableDebugLogging: true),
			.analytics(provider: analyticsProvider),
			.notification(
				showSuccess: true,
				showErrors: true,
				showInfo: false,
			),
		]
	}
}
