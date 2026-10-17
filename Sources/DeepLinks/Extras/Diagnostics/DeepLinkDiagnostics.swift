//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Debug-time checks that compare a deep-link configuration with the app's
/// declared URL schemes and, optionally, its associated domains.
///
/// Run it from a unit test or a `#if DEBUG` launch hook and print or assert
/// on the warnings; it never changes how links are handled.
///
/// ```swift
/// let diagnostics = DeepLinkDiagnostics(associatedDomains: ["applinks:example.com"])
/// let warnings = diagnostics.checkSecurityConfiguration(
///     allowedSchemes: ["myapp", "https"],
///     allowedHosts: ["example.com", "product"]
/// )
/// + (await diagnostics.checkParsers(parsers, probes: sampleLinks))
/// warnings.forEach { print("Deep link warning:", $0) }
/// ```
///
/// ## Limits
///
/// - Entitlements are not readable at runtime, so associated domains are
///   **not** discovered: pass the `com.apple.developer.associated-domains`
///   values yourself (for example, copied from your `.entitlements` file in a
///   test). Without them, associated-domain checks are skipped.
/// - Only allowed hosts that contain a `.` are treated as web domains; hosts
///   such as `product` are assumed to be custom-scheme hosts.
/// - Nothing verifies that the `apple-app-site-association` file is served
///   or matches your paths.
/// - Parser checks only cover the probe URLs you supply and call every
///   parser for each probe, so parsers must not have side effects.
public struct DeepLinkDiagnostics: Sendable {
	private static let webSchemes: Set<String> = ["http", "https"]

	/// The lower-cased schemes declared in `CFBundleURLTypes`.
	public let declaredURLSchemes: Set<String>

	/// The `applinks:` entries supplied at creation.
	public let associatedDomains: [String]

	/// Lower-cased declared schemes never reported as not allowed.
	public let ignoredDeclaredSchemes: Set<String>

	/// Lower-cased prefixes of declared schemes never reported as not allowed.
	public let ignoredDeclaredSchemePrefixes: Set<String>

	/// Creates diagnostics for `bundle`, reading its `CFBundleURLTypes`.
	///
	/// - Parameters:
	///   - bundle: The app bundle. Defaults to `.main`.
	///   - associatedDomains: Your `com.apple.developer.associated-domains`
	///     entitlement values (`applinks:example.com`); other services are ignored.
	///   - ignoredDeclaredSchemes: Declared schemes that are not deep links,
	///     such as third-party SDK callbacks; compared case-insensitively.
	///   - ignoredDeclaredSchemePrefixes: Prefixes of such schemes, such as
	///     `fb` for Facebook's `fb<app id>`; compared case-insensitively.
	public init(
		bundle: Bundle = .main,
		associatedDomains: [String] = [],
		ignoredDeclaredSchemes: Set<String> = [],
		ignoredDeclaredSchemePrefixes: Set<String> = [],
	) {
		self.init(
			declaredURLSchemes: Self.declaredURLSchemes(inInfoDictionary: bundle.infoDictionary),
			associatedDomains: associatedDomains,
			ignoredDeclaredSchemes: ignoredDeclaredSchemes,
			ignoredDeclaredSchemePrefixes: ignoredDeclaredSchemePrefixes,
		)
	}

	/// Creates diagnostics from explicit values.
	///
	/// - Parameters:
	///   - declaredURLSchemes: The schemes the app registers; compared case-insensitively.
	///   - associatedDomains: Your associated-domains entitlement values.
	///   - ignoredDeclaredSchemes: Declared schemes never reported as not allowed.
	///   - ignoredDeclaredSchemePrefixes: Prefixes of declared schemes never reported as not allowed.
	public init(
		declaredURLSchemes: Set<String>,
		associatedDomains: [String] = [],
		ignoredDeclaredSchemes: Set<String> = [],
		ignoredDeclaredSchemePrefixes: Set<String> = [],
	) {
		self.declaredURLSchemes = Set(declaredURLSchemes.map { $0.lowercased() })
		self.associatedDomains = associatedDomains
		self.ignoredDeclaredSchemes = Set(ignoredDeclaredSchemes.map { $0.lowercased() })
		self.ignoredDeclaredSchemePrefixes = Set(ignoredDeclaredSchemePrefixes.map { $0.lowercased() })
	}

	/// The lower-cased schemes listed under `CFBundleURLTypes` → `CFBundleURLSchemes`.
	///
	/// - Parameter info: An `Info.plist` dictionary, such as `Bundle.main.infoDictionary`.
	/// - Returns: The declared schemes; empty when the key is missing or malformed.
	public static func declaredURLSchemes(inInfoDictionary info: [String: Any]?) -> Set<String> {
		let urlTypes = info?["CFBundleURLTypes"] as? [[String: Any]] ?? []
		let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
		return Set(schemes.map { $0.lowercased() })
	}

	/// Compares the schemes and hosts given to ``SecurityMiddleware`` with the
	/// bundle's URL types and the supplied associated domains.
	///
	/// - Parameters:
	///   - allowedSchemes: The middleware's allowed schemes.
	///   - allowedHosts: The middleware's allowed hosts.
	/// - Returns: Warnings in a stable order; empty when nothing looks wrong.
	public func checkSecurityConfiguration(allowedSchemes: Set<String>, allowedHosts: Set<String>) -> [DeepLinkDiagnosticWarning] {
		let schemes = Set(allowedSchemes.map { $0.lowercased() })
		guard !schemes.isEmpty else { return [.emptyAllowedSchemes] }

		let hosts = Set(allowedHosts.map { $0.lowercased() })
		return schemeWarnings(allowed: schemes) + webWarnings(allowedSchemes: schemes, allowedHosts: hosts)
	}

	/// Runs every parser against each probe URL and reports probes no parser
	/// handles and parsers that a probe never reaches because an earlier
	/// parser handles it first, as ``DefaultDeepLinkRouting`` does.
	///
	/// - Parameters:
	///   - parsers: The parsers in routing order.
	///   - probes: Representative links your app must handle.
	/// - Returns: Warnings in probe order.
	public func checkParsers<Route: DeepLinkRoute>(
		_ parsers: [any DeepLinkParser<Route>],
		probes: [URL],
	) async -> [DeepLinkDiagnosticWarning] {
		var warnings: [DeepLinkDiagnosticWarning] = []
		for probe in probes {
			let handlers = await indicesOfParsers(parsers, handling: probe)
			if let first = handlers.first {
				if handlers.count > 1 {
					warnings.append(.shadowedParsers(probe: probe, handledBy: first, shadowed: Array(handlers.dropFirst())))
				}
			} else {
				warnings.append(.unhandledProbe(probe))
			}
		}
		return warnings
	}
}

// MARK: - Middleware

public extension DeepLinkDiagnostics {
	/// Checks a middleware chain for risky settings.
	///
	/// For every ``SignedLinkMiddleware``, warns with
	/// ``DeepLinkDiagnosticWarning/signedLinksWithSymmetricKey`` when it
	/// verifies with an HMAC key,
	/// ``DeepLinkDiagnosticWarning/signedLinksWithoutMaximumLifetime`` when
	/// `maximumLifetime` is `nil`, and
	/// ``DeepLinkDiagnosticWarning/signedLinksWithoutNonceStore`` when it has
	/// no ``NonceStore``, in that order. Pass the same middleware you give the
	/// coordinator builder.
	///
	/// - Parameter middleware: The middleware chain, in order.
	/// - Returns: The warnings found, in chain order.
	func checkMiddleware(_ middleware: [any DeepLinkMiddleware]) -> [DeepLinkDiagnosticWarning] {
		middleware.flatMap(Self.warnings(for:))
	}

	private static func warnings(for middleware: any DeepLinkMiddleware) -> [DeepLinkDiagnosticWarning] {
		#if canImport(CryptoKit)
		guard let signed = middleware as? SignedLinkMiddleware else { return [] }
		return [
			signed.usesSymmetricKey ? .signedLinksWithSymmetricKey : nil,
			signed.hasMaximumLifetime ? nil : .signedLinksWithoutMaximumLifetime,
			signed.hasNonceStore ? nil : .signedLinksWithoutNonceStore,
		].compactMap(\.self)
		#else
		return []
		#endif
	}
}

// MARK: - Checks

private extension DeepLinkDiagnostics {
	func schemeWarnings(allowed: Set<String>) -> [DeepLinkDiagnosticWarning] {
		let customSchemes = allowed.subtracting(Self.webSchemes)
		let undeclared = customSchemes.subtracting(declaredURLSchemes).sorted().map(DeepLinkDiagnosticWarning.schemeNotDeclared)
		let rejected = declaredURLSchemes.subtracting(allowed)
			.filter { !isIgnoredDeclaredScheme($0) }
			.sorted()
			.map(DeepLinkDiagnosticWarning.declaredSchemeNotAllowed)
		return undeclared + rejected
	}

	func isIgnoredDeclaredScheme(_ scheme: String) -> Bool {
		ignoredDeclaredSchemes.contains(scheme) || ignoredDeclaredSchemePrefixes.contains { scheme.hasPrefix($0) }
	}

	func webWarnings(allowedSchemes: Set<String>, allowedHosts: Set<String>) -> [DeepLinkDiagnosticWarning] {
		guard !allowedSchemes.isDisjoint(with: Self.webSchemes) else { return [] }
		guard !allowedHosts.isEmpty else { return [.webSchemeWithoutAllowedHosts] }

		let domains = associatedLinkDomains
		guard !domains.isEmpty else { return [] }

		let webHosts = allowedHosts.filter { $0.contains(".") }
		let uncovered = webHosts.filter { host in !domains.contains { $0.covers(host) } }
		let unused = domains.filter { domain in !webHosts.contains { domain.covers($0) } }
		return uncovered.sorted().map(DeepLinkDiagnosticWarning.hostNotInAssociatedDomains)
			+ unused.map(\.name).sorted().map(DeepLinkDiagnosticWarning.associatedDomainNotAllowed)
	}

	var associatedLinkDomains: [AssociatedDomain] {
		associatedDomains.compactMap(AssociatedDomain.init(entitlementValue:))
	}

	func indicesOfParsers<Route: DeepLinkRoute>(_ parsers: [any DeepLinkParser<Route>], handling probe: URL) async -> [Int] {
		var indices: [Int] = []
		for (index, parser) in parsers.enumerated() where await (try? parser.parse(from: probe)) != nil {
			indices.append(index)
		}
		return indices
	}
}

// MARK: - Associated Domain

/// An `applinks:` entitlement value such as `applinks:*.example.com?mode=developer`.
private struct AssociatedDomain {
	private static let servicePrefix = "applinks:"
	private static let wildcardPrefix = "*."

	let name: String
	let isWildcard: Bool

	init?(entitlementValue: String) {
		guard entitlementValue.lowercased().hasPrefix(Self.servicePrefix) else { return nil }
		let domain = entitlementValue.dropFirst(Self.servicePrefix.count)
			.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
			.lowercased()
		isWildcard = domain.hasPrefix(Self.wildcardPrefix)
		name = isWildcard ? String(domain.dropFirst(Self.wildcardPrefix.count)) : domain
	}

	func covers(_ host: String) -> Bool {
		isWildcard ? host.hasSuffix("." + name) : host == name
	}
}
