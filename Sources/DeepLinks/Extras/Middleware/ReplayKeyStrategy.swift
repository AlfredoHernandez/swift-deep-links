//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// Decides which parts of a URL identify it for ``ReplayProtectionMiddleware``.
///
/// Two links with the same key inside the protection window are treated as
/// the same link. A `nil` key opts the URL out of replay protection.
///
/// The middleware removes its `ignoredQueryKeys` before asking for the key,
/// so every strategy sees the URL without them.
public struct ReplayKeyStrategy: Sendable {
	private let makeKey: @Sendable (URL) -> String?

	/// Creates a strategy from a closure that derives the key from a URL.
	///
	/// - Parameter makeKey: Returns the key identifying the URL, or `nil` to
	///   never deduplicate it.
	public init(_ makeKey: @escaping @Sendable (URL) -> String?) {
		self.makeKey = makeKey
	}

	func key(for url: URL) -> String? {
		makeKey(url)
	}
}

// MARK: - Built-in Strategies

public extension ReplayKeyStrategy {
	/// The whole URL. Scheme and host compare case-insensitively (the host
	/// percent-decoded and without a trailing dot, as ``URLCanonicalizer`` does), query
	/// parameter order is ignored, and equivalent percent-encodings
	/// (`%2f`/`%2F`, `%41`/`A`) compare equal, so none of them bypasses
	/// deduplication. Path, query values and fragment are otherwise compared
	/// exactly (`/a` and `/a/` differ).
	static let url = ReplayKeyStrategy { url in
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url.absoluteString
		}
		return [
			origin(of: components),
			PercentEncodingNormalizer.normalized(components.percentEncodedPath),
			"?" + sortedQuery(of: components),
			"#" + PercentEncodingNormalizer.normalized(components.percentEncodedFragment ?? ""),
		].joined()
	}

	/// Scheme, host, port and path (percent-encoding normalized as in
	/// ``url``); the query and fragment are ignored.
	static let path = ReplayKeyStrategy { url in
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url.absoluteString
		}
		return origin(of: components) + PercentEncodingNormalizer.normalized(components.percentEncodedPath)
	}

	/// The value of one query parameter, such as an idempotency key or nonce.
	/// Links without the parameter (or with an empty value) are never
	/// deduplicated. Names compare case-sensitively after percent-decoding and,
	/// when the parameter repeats, the last value is used, exactly as
	/// ``DeepLinkURL/queryParameters`` reads it, so the key is the value your
	/// parsers act on.
	///
	/// The key is the value alone, regardless of host or path, so a link
	/// anywhere that reuses a value suppresses the original for the window:
	/// use unguessable values.
	///
	/// - Parameter name: The query parameter carrying the idempotency key.
	/// - Returns: A strategy keyed by that parameter's value.
	static func queryParameter(_ name: String) -> ReplayKeyStrategy {
		ReplayKeyStrategy { url in
			let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?
				.last { $0.name == name && $0.value != nil }?
				.value
			guard let value, !value.isEmpty else { return nil }
			return value
		}
	}

	/// A strategy backed by a closure.
	///
	/// - Parameter makeKey: Returns the key identifying the URL, or `nil` to
	///   never deduplicate it.
	/// - Returns: A strategy that calls `makeKey`.
	static func custom(_ makeKey: @escaping @Sendable (URL) -> String?) -> ReplayKeyStrategy {
		ReplayKeyStrategy(makeKey)
	}
}

// MARK: - Key Components

private extension ReplayKeyStrategy {
	static func origin(of components: URLComponents) -> String {
		let scheme = components.scheme?.lowercased() ?? ""
		let host = components.percentEncodedHost.map { URLText.normalizedHost(URLText.fullyDecoded($0)) } ?? ""
		let port = components.port.map { ":\($0)" } ?? ""
		return "\(scheme)://\(host)\(port)"
	}

	static func sortedQuery(of components: URLComponents) -> String {
		(components.percentEncodedQueryItems ?? [])
			.map { item in
				let name = PercentEncodingNormalizer.normalized(item.name)
				return item.value.map { "\(name)=\(PercentEncodingNormalizer.normalized($0))" } ?? name
			}
			.sorted()
			.joined(separator: "&")
	}
}
