//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
    /// This method sets up the complete deep link processing pipeline including:
    /// - Parser registration for all supported route types
    /// - Middleware stack configuration (rate limiting, security, authentication, etc.)
    /// - Delegate setup for logging, analytics, and notifications
    /// - Handler configuration with the provided navigation router
    ///
    /// - Parameter navigationRouter: The navigation router for handling route actions
    /// - Returns: A fully configured deep link coordinator
    /// - Throws: `DeepLinkError` if coordinator creation fails
    func createCoordinator(navigationRouter: NavigationRouter) async throws -> DeepLinkCoordinator<AppRoute> {
        logger.info("Creating deep link coordinator")

        // Configure parsers
        let parsers = createParsers()

        // Configure middleware stack
        let middleware = createMiddlewareStack()

        // Configure delegates
        let delegates = createDelegates()

        // Create coordinator using builder pattern
        let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
            .addingRouting(DefaultDeepLinkRouting<AppRoute>(parsers: parsers))
            .addingHandler(AppDeepLinkHandler(navigationRouter: navigationRouter))
            .addingMiddleware(middleware)
            .addingDelegates(delegates)
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

    /// Creates the middleware stack with all necessary components.
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
            RateLimitMiddleware(maxRequests: 10, timeWindow: 60.0),
            SecurityMiddleware(
                allowedSchemes: ["deeplink", "testapp"],
                allowedHosts: ["profile", "product", "settings", "info", "alert"],
                blockedPatterns: [],
            ),
            AuthenticationMiddleware(
                authProvider: authenticationProvider,
                protectedHosts: ["profile", "settings"],
            ),
            URLTransformationMiddleware(transformer: URLNormalizationTransformer()),
            AnalyticsMiddleware(analyticsProvider: analyticsProvider),
            LoggingMiddleware(),
        ]
    }

    /// Creates the delegate stack for comprehensive monitoring.
    ///
    /// The delegate stack provides:
    /// - Detailed logging of deep link processing
    /// - Analytics tracking for usage insights
    /// - User notifications for feedback
    ///
    /// - Returns: An array of configured delegates
    func createDelegates() -> [DeepLinkCoordinatorDelegate] {
        [
            DeepLinkLoggingDelegate(enableDebugLogging: true),
            DeepLinkAnalyticsDelegate(analyticsProvider: analyticsProvider),
            DeepLinkNotificationDelegate(
                showSuccessNotifications: true,
                showErrorNotifications: true,
                showInfoNotifications: false,
            ),
        ]
    }
}
