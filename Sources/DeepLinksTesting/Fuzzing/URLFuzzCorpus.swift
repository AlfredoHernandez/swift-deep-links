//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A fixed set of hostile deep-link URLs for regression-testing security
/// configuration.
///
/// Cases are built around the scheme and host you allow, so a rejection is
/// caused by the attack itself rather than by an unknown host. Run them as a
/// parameterized test:
///
///     @Test(arguments: URLFuzzCorpus.hostile(scheme: "https", host: "example.com"))
///     func rejectsHostileURL(_ fuzzCase: URLFuzzCase) async {
///         await #expect(throws: DeepLinkError.self) {
///             try await security.intercept(fuzzCase.url)
///         }
///     }
///
/// `SecurityStrategy.hardened` with input limits that reject duplicate
/// parameters rejects every case. The corpus is deterministic and not
/// exhaustive; it pins known bypasses, it does not prove their absence.
public enum URLFuzzCorpus {
	/// Every hostile case, grouped by category in ``URLFuzzCase/Category`` order.
	///
	/// - Parameters:
	///   - scheme: The scheme your configuration allows.
	///   - host: The host your configuration allows.
	/// - Returns: The cases whose strings form a valid `URL`.
	public static func hostile(scheme: String = "https", host: String = "example.com") -> [URLFuzzCase] {
		URLFuzzCase.Category.allCases.flatMap { hostile($0, scheme: scheme, host: host) }
	}

	/// The hostile cases of one category.
	///
	/// - Parameters:
	///   - category: The attack family.
	///   - scheme: The scheme your configuration allows.
	///   - host: The host your configuration allows.
	/// - Returns: The cases whose strings form a valid `URL`.
	public static func hostile(
		_ category: URLFuzzCase.Category,
		scheme: String = "https",
		host: String = "example.com",
	) -> [URLFuzzCase] {
		let base = "\(scheme)://\(host)"
		return templates(for: category, scheme: scheme, host: host, base: base).compactMap { name, string in
			URL(string: string).map { URLFuzzCase(category: category, name: name, url: $0) }
		}
	}
}

// MARK: - Templates

private extension URLFuzzCorpus {
	static func templates(
		for category: URLFuzzCase.Category,
		scheme: String,
		host: String,
		base: String,
	) -> KeyValuePairs<String, String> {
		switch category {
		case .traversal:
			[
				"dot-dot segment": "\(base)/a/../admin",
				"encoded dot-dot": "\(base)/a/%2e%2e/admin",
				"uppercase encoded dot-dot": "\(base)/a/%2E%2E/admin",
				"half encoded dot-dot": "\(base)/a/.%2e/admin",
				"double encoded dot-dot": "\(base)/a/%252e%252e/admin",
				"encoded slash after dot-dot": "\(base)/a/..%2Fadmin",
				"encoded backslash after dot-dot": "\(base)/a/..%5Cadmin",
			]

		case .encoding:
			[
				"overlong UTF-8 dots": "\(base)/a/%C0%AE%C0%AE/admin",
				"invalid UTF-8 byte": "\(base)/a/%FF",
				"encoding nested past the limit": "\(base)/a/%25252525252e",
			]

		case .controlCharacters:
			[
				"NUL byte": "\(base)/a%00b",
				"line feed in query": "\(base)/a?x=%0A",
				"CRLF header injection": "\(base)/a?x=1%0D%0ASet-Cookie:%20a",
				"double encoded line feed": "\(base)/a?x=%250A",
				"DEL character": "\(base)/a%7F",
				"right-to-left override": "\(base)/invoice%E2%80%AEfdp.exe",
				"line separator in query": "\(base)/a?x=1%E2%80%A82",
				"zero-width space": "\(base)/ad%E2%80%8Bmin",
				"byte order mark": "\(base)/a?x=%EF%BB%BF",
			]

		case .hostConfusion:
			[
				"userinfo credentials": "\(scheme)://user:pass@\(host)/a",
				"trusted host as userinfo": "\(scheme)://\(host)@evil.example/a",
				"empty authority host": "\(scheme):///\(host)/a",
			]

		case .internationalizedHost:
			[
				"Cyrillic homograph": "\(scheme)://\(homograph(of: host))/a",
				"punycode homograph": "\(scheme)://xn--80ak6aa92e.com/a",
			]

		case .duplicateParameters:
			[
				"repeated key": "\(base)/a?id=1&id=2",
				"repeated valueless key": "\(base)/a?admin&admin",
				"percent-encoded repeated key": "\(base)/a?id=1&%69d=2",
			]

		case .oversize:
			[
				"URL longer than 8192 characters": "\(base)/\(String(repeating: "a", count: 9000))",
				"100 query parameters": "\(base)/a?" + (0 ..< 100).map { "p\($0)=1" }.joined(separator: "&"),
				"2000-character parameter value": "\(base)/a?v=\(String(repeating: "x", count: 2000))",
			]

		case .scheme:
			[
				"javascript scheme": "javascript:alert(1)",
				"data scheme": "data:text/html,%3Cscript%3Ealert(1)%3C/script%3E",
				"file scheme": "file:///etc/passwd",
			]
		}
	}

	/// `host` with its first Latin `a`, `e`, `o` or `c` swapped for the
	/// identical-looking Cyrillic letter; prefixed with Cyrillic `а` when none is present.
	static func homograph(of host: String) -> String {
		let lookalikes: [Character: Character] = ["a": "а", "e": "е", "o": "о", "c": "с"]
		guard let index = host.firstIndex(where: { lookalikes[$0] != nil }) else {
			return "а" + host
		}
		var spoofed = host
		spoofed.replaceSubrange(index ... index, with: String(lookalikes[host[index]]!))
		return spoofed
	}
}
