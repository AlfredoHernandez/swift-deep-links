//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import CryptoKit
import DeepLinks
import Foundation

/// Builds the sample's deep link coordinator with the recommended secure setup.
///
/// The chain runs in the order the security guide recommends:
///
/// 1. `secureDefaults`: security (`.hardened`, `limits: .recommended`), rate limiting, replay protection
/// 2. Signed links for `deeplink://reset`
/// 3. Authentication for the protected hosts, saving `deeplink://account` to resume after sign-in
/// 4. Confirmation for `deeplink://pay` and for every resumed link
/// 5. URL normalization, then analytics and logging (both redacted by default)
///
/// The signing key is random per launch: the app signs its own demo links. A
/// real app ships public keys (`Ed25519PublicKeyring`) or a Keychain key and
/// lets its server sign.
final class DeepLinkService {
	/// The schemes the coordinator accepts; each is declared in `Info.plist`.
	static let allowedSchemes: Set<String> = ["deeplink"]

	/// The hosts the coordinator accepts.
	static let allowedHosts = Set(["info", "profile", "product", "settings", "alert"]).union(SecureActionParser.hosts)

	static let protectedHosts: Set<String> = ["profile", "settings", SecureActionParser.accountHost]

	/// One representative link per parser, for ``diagnosticWarnings()``.
	static let probeLinks: [URL] = [
		"deeplink://info?title=News&brief=Hello",
		"deeplink://profile?userID=1",
		"deeplink://product?productID=1",
		"deeplink://settings?section=account",
		"deeplink://alert?title=Hi&message=There&type=info",
		"deeplink://reset?user=1",
		"deeplink://pay?amount=1",
		"deeplink://account",
	].compactMap(URL.init(string:))

	private static let signingKeyID = "demo"
	private static let signedLinkLifetime: TimeInterval = 15 * 60

	let authenticationProvider: SampleAuthenticationProvider
	let pendingLinks: any PendingLinkStore

	private let handler: any DeepLinkHandler<AppRoute>
	private let confirmationProvider: any DeepLinkConfirmationProvider
	private let analyticsProvider: SampleAnalyticsProvider
	private let nonceStore: any NonceStore
	private let signingKey: SymmetricKey
	private let rateLimitPersistence: (any RateLimitPersistence)?
	private let delegates: [any DeepLinkCoordinatorDelegate<AppRoute>]
	private let dateProvider: @Sendable () -> Date

	init(
		handler: any DeepLinkHandler<AppRoute>,
		confirmationProvider: any DeepLinkConfirmationProvider,
		authenticationProvider: SampleAuthenticationProvider = SampleAuthenticationProvider(),
		analyticsProvider: SampleAnalyticsProvider = SampleAnalyticsProvider(),
		pendingLinks: any PendingLinkStore = InMemoryPendingLinkStore(),
		nonceStore: any NonceStore = InMemoryNonceStore(),
		signingKey: SymmetricKey = SymmetricKey(size: .bits256),
		rateLimitPersistence: (any RateLimitPersistence)? = nil,
		delegates: [any DeepLinkCoordinatorDelegate<AppRoute>],
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.handler = handler
		self.confirmationProvider = confirmationProvider
		self.authenticationProvider = authenticationProvider
		self.analyticsProvider = analyticsProvider
		self.pendingLinks = pendingLinks
		self.nonceStore = nonceStore
		self.signingKey = signingKey
		self.rateLimitPersistence = rateLimitPersistence
		self.delegates = delegates
		self.dateProvider = dateProvider
	}

	/// The service the app runs: navigation through `navigationRouter`, prompts
	/// through `confirmationProvider`, and the logging, analytics and
	/// notification delegates.
	static func live(navigationRouter: NavigationRouter, confirmationProvider: any DeepLinkConfirmationProvider) -> DeepLinkService {
		let analyticsProvider = SampleAnalyticsProvider()
		return DeepLinkService(
			handler: AppDeepLinkHandler(navigationRouter: navigationRouter),
			confirmationProvider: confirmationProvider,
			analyticsProvider: analyticsProvider,
			delegates: [
				.logging(enableDebugLogging: true),
				.analytics(provider: analyticsProvider),
				.notification(showSuccess: true, showErrors: true, showInfo: false),
			],
		)
	}

	/// The parsers, in routing order.
	static var parsers: [any DeepLinkParser<AppRoute>] {
		[
			InformationParser(),
			ProfileParser(),
			ProductParser(),
			SettingsParser(),
			AlertParser(),
			SecureActionParser(),
		]
	}

	func makeCoordinator() throws -> DeepLinkCoordinator<AppRoute> {
		try DeepLinkCoordinatorBuilder<AppRoute>()
			.parsers(Self.parsers)
			.handler(handler)
			.secureDefaults(
				allowedSchemes: Self.allowedSchemes,
				allowedHosts: Self.allowedHosts,
				rateLimitPersistence: rateLimitPersistence,
				dateProvider: dateProvider,
			)
			.middleware(appMiddleware())
			.delegates(delegates)
			.build()
	}

	/// The middleware after the `secureDefaults` preset, in chain order.
	func appMiddleware() -> [any DeepLinkMiddleware] {
		[
			.signedLinks(
				keys: SigningKeyring(keys: [Self.signingKeyID: signingKey]),
				requiredFor: .hosts([SecureActionParser.resetHost]),
				maximumLifetime: Self.signedLinkLifetime,
				nonceStore: nonceStore,
				dateProvider: dateProvider,
			),
			.authentication(
				provider: authenticationProvider,
				protectedHosts: Self.protectedHosts,
				pendingLinks: pendingLinks,
				// The demo opens links as custom-scheme links; resumed ones are confirmed below.
				pendingSources: AuthenticationMiddleware.defaultPendingSources.union([.customScheme]),
			),
			.confirmation(
				provider: confirmationProvider,
				requiredFor: .anyOf(.hosts([SecureActionParser.paymentHost]), .resumedPendingLinks),
			),
			.urlTransformation(transformer: URLNormalizationTransformer()),
			.analytics(provider: analyticsProvider),
			.logging(),
		]
	}

	/// A single-use reset link for `userID`, valid for 15 minutes.
	func signedResetLink(userID: String) throws -> URL {
		var components = URLComponents()
		components.scheme = "deeplink"
		components.host = SecureActionParser.resetHost
		components.queryItems = [URLQueryItem(name: "user", value: userID)]
		guard let url = components.url else { throw DeepLinkError.invalidParameterValue(name: "user", value: userID) }
		return try SignedLinkBuilder(key: signingKey, keyID: Self.signingKeyID).sign(
			url,
			expiresAt: dateProvider().addingTimeInterval(Self.signedLinkLifetime),
			nonce: UUID().uuidString,
		)
	}

	/// Warnings about the configuration: undeclared or unused schemes, signed
	/// links without a nonce store, and probe links no parser (or more than
	/// one) handles. Meant for debug builds and tests.
	func diagnosticWarnings() async -> [DeepLinkDiagnosticWarning] {
		let diagnostics = DeepLinkDiagnostics()
		return await diagnostics.checkSecurityConfiguration(allowedSchemes: Self.allowedSchemes, allowedHosts: Self.allowedHosts)
			+ diagnostics.checkMiddleware(appMiddleware())
			+ (diagnostics.checkParsers(Self.parsers, probes: Self.probeLinks))
	}
}
