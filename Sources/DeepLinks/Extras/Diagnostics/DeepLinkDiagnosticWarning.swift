//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A likely misconfiguration found by ``DeepLinkDiagnostics``.
public enum DeepLinkDiagnosticWarning: Sendable, Hashable, CustomStringConvertible {
	/// The security configuration allows no scheme, so every link is rejected.
	case emptyAllowedSchemes

	/// An allowed custom scheme (lower-cased) is not declared in the bundle's
	/// `CFBundleURLTypes`, so the system never delivers its links.
	case schemeNotDeclared(String)

	/// A scheme declared in `CFBundleURLTypes` (lower-cased) is not allowed,
	/// so its links are delivered and then rejected.
	case declaredSchemeNotAllowed(String)

	/// `http` or `https` is allowed but no host is: `.standard` then accepts
	/// universal links from any domain and `.hardened` rejects them all.
	case webSchemeWithoutAllowedHosts

	/// An allowed domain (lower-cased) has no matching `applinks:` entry in
	/// the associated domains you supplied, so universal links to it open Safari.
	case hostNotInAssociatedDomains(String)

	/// An `applinks:` domain (lower-cased, without `*.` or `?mode=`) has no
	/// allowed host, so its universal links reach the app and are rejected.
	case associatedDomainNotAllowed(String)

	/// No parser handled the probe URL.
	case unhandledProbe(URL)

	/// Several parsers handle the probe URL; routing stops at `handledBy`, so
	/// the `shadowed` parsers (indices into the parser list) never see it.
	case shadowedParsers(probe: URL, handledBy: Int, shadowed: [Int])

	/// A ``SignedLinkMiddleware`` has no ``NonceStore``, so a signed link can
	/// be opened any number of times until it expires.
	case signedLinksWithoutNonceStore

	/// A readable explanation; probe URLs are passed through ``URLRedactor``.
	public var description: String {
		switch self {
		case .emptyAllowedSchemes:
			"No scheme is allowed; every deep link will be rejected."

		case let .schemeNotDeclared(scheme):
			"Scheme '\(scheme)' is allowed but not declared in CFBundleURLTypes; the system will not deliver its links."

		case let .declaredSchemeNotAllowed(scheme):
			"Scheme '\(scheme)' is declared in CFBundleURLTypes but not allowed; its links will be rejected."

		case .webSchemeWithoutAllowedHosts:
			"http(s) is allowed without any allowed host; restrict allowedHosts to your domains."

		case let .hostNotInAssociatedDomains(host):
			"Host '\(host)' is allowed but has no applinks: associated domain; universal links to it will open Safari."

		case let .associatedDomainNotAllowed(domain):
			"Associated domain '\(domain)' has no allowed host; its universal links will be rejected."

		case let .unhandledProbe(url):
			"No parser handles \(URLRedactor().redact(url).absoluteString)."

		case let .shadowedParsers(probe, handledBy, shadowed):
			"Parser \(handledBy) handles \(URLRedactor().redact(probe).absoluteString) first; parsers \(shadowed.map(String.init).joined(separator: ", ")) are never reached for it."

		case .signedLinksWithoutNonceStore:
			"Signed links have no nonce store; each signed link can be reused until it expires. Pass a nonceStore (InMemoryNonceStore or UserDefaultsNonceStore)."
		}
	}
}
