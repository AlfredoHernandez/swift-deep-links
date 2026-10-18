//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation

/// The byte string a signed link's HMAC covers.
///
/// Seven lines joined by `\n` (no trailing newline):
///
/// 1. `DLSIG1` (format version)
/// 2. the scheme, lower-cased
/// 3. the percent-encoded host, lower-cased
/// 4. the port, or empty
/// 5. the percent-encoded path
/// 6. every query item except the signature, rendered `name=value` (or `name`
///    when valueless), sorted by UTF-8 bytes and joined by `&`
/// 7. the percent-encoded fragment, or empty
///
/// Lines 5–7 normalize percent-encoding first: escapes of RFC 3986 unreserved
/// characters (`A-Z a-z 0-9 - . _ ~`) are decoded and remaining escapes are
/// upper-cased.
enum SignedLinkCanonicalForm {
	static let version = "DLSIG1"

	static func string(of url: URL, parameters: SignedLinkParameters) -> String {
		let components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
		let query = (components.percentEncodedQueryItems ?? [])
			.filter { decodedName(of: $0) != parameters.signature }
			.map(rendered)
			.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
			.joined(separator: "&")
		return [
			version,
			components.scheme?.lowercased() ?? "",
			components.percentEncodedHost?.lowercased() ?? "",
			components.port.map(String.init) ?? "",
			PercentEncodingNormalizer.normalized(components.percentEncodedPath),
			query,
			PercentEncodingNormalizer.normalized(components.percentEncodedFragment ?? ""),
		].joined(separator: "\n")
	}

	static func message(of url: URL, parameters: SignedLinkParameters) -> Data {
		Data(string(of: url, parameters: parameters).utf8)
	}

	static func decodedName(of item: URLQueryItem) -> String {
		URLText.decodedOnce(item.name)
	}

	/// Whether two query items share a decoded name. The canonical form sorts
	/// items while ``DeepLinkURL`` keeps the last value, so reordering a
	/// repeated name would keep the signature but change what the app reads.
	static func repeatsParameterName(in url: URL) -> Bool {
		var seen: Set<String> = []
		return (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? [])
			.filter { !$0.name.isEmpty || $0.value != nil }
			.contains { !seen.insert(decodedName(of: $0)).inserted }
	}

	private static func rendered(_ item: URLQueryItem) -> String {
		let name = PercentEncodingNormalizer.normalized(item.name)
		return item.value.map { "\(name)=\(PercentEncodingNormalizer.normalized($0))" } ?? name
	}
}

enum Base64URL {
	static func encoded(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	static func decoded(_ text: String) -> Data? {
		let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
		guard !text.isEmpty, text.allSatisfy(alphabet.contains) else { return nil }
		let base64 = text
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
	}
}

#endif
