//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

public extension URLRedactor {
	/// Which path segments a ``URLRedactor`` replaces with its placeholder.
	///
	/// Paths are kept by default (``none``), so put secrets in parameters. When
	/// a link format carries one in the path (`/invite/<code>`), opt in with
	/// ``templates(_:)`` (precise) or ``tokenLikeSegments(minimumLength:)``
	/// (heuristic). Segments are compared after percent-decoding and without
	/// `;` matrix parameters; only the segment text before `;` is replaced.
	struct PathRedaction: Sendable {
		/// Returns the indices of `segments` to redact. For custom-scheme links
		/// with a host, `segments[0]` is the host, which is never redacted.
		private let select: @Sendable (_ segments: [String]) -> Set<Int>

		private init(_ select: @escaping @Sendable (_ segments: [String]) -> Set<Int>) {
			self.select = select
		}

		/// Keeps every path segment (the default).
		public static let none = PathRedaction { _ in [] }

		/// Redacts segments shaped like generated tokens: at least
		/// `minimumLength` characters from `A-Z a-z 0-9 - _ . ~ =`, switching
		/// between letters and digits at least twice (hex, base64url, UUIDs).
		/// Plain words, slugs and numbers are kept; a readable segment that
		/// mixes letters and digits may be redacted too.
		///
		/// - Parameter minimumLength: The shortest segment considered. Defaults to 16.
		public static func tokenLikeSegments(minimumLength: Int = 16) -> PathRedaction {
			segments { TokenShape.matches($0, minimumLength: minimumLength) }
		}

		/// Redacts the `:name` segments of every matching template, such as
		/// `/invite/:code/accept`.
		///
		/// A template matches a path with the same number of segments whose
		/// other segments are equal, case-insensitively. As in
		/// ``DeepLinkMatcher/paths(_:)``, a custom-scheme host counts as the
		/// first segment, so `/invite/:code` covers `https://example.com/invite/abc`
		/// and `myapp://invite/abc`. A missing leading `/` is ignored.
		///
		/// - Parameter templates: The path templates.
		public static func templates(_ templates: Set<String>) -> PathRedaction {
			let parsed = templates.map { $0.split(separator: "/").map { $0.lowercased() } }
			return PathRedaction { segments in
				let lowercased = segments.map { $0.lowercased() }
				var selected: Set<Int> = []
				for template in parsed where template.count == lowercased.count {
					let matches = zip(template, lowercased).allSatisfy { $0.hasPrefix(":") || $0 == $1 }
					if matches {
						selected.formUnion(template.indices.filter { template[$0].hasPrefix(":") })
					}
				}
				return selected
			}
		}

		/// Redacts every segment for which `predicate` returns `true`.
		///
		/// - Parameter predicate: Receives the percent-decoded segment without matrix parameters.
		public static func segments(where predicate: @escaping @Sendable (String) -> Bool) -> PathRedaction {
			PathRedaction { segments in Set(segments.indices.filter { predicate(segments[$0]) }) }
		}

		/// Redacts the segments any of `redactions` selects.
		public static func anyOf(_ redactions: PathRedaction...) -> PathRedaction {
			PathRedaction { segments in redactions.reduce(into: []) { $0.formUnion($1.select(segments)) } }
		}

		func selectedIndices(in segments: [String]) -> Set<Int> {
			select(segments)
		}
	}
}

// MARK: - Path Segment Redaction

extension URLRedactor {
	func redactingPathSegments(in encodedPath: String, hostSegment: String?) -> String {
		var rawSegments = encodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		let positions = rawSegments.indices.filter { !rawSegments[$0].isEmpty }
		let names = positions.map { Self.segmentName(of: rawSegments[$0]) }
		let leading = hostSegment.map { [$0] } ?? []
		let selected = pathRedaction.selectedIndices(in: leading + names)
		guard !selected.isEmpty else { return encodedPath }

		for (offset, position) in positions.enumerated() where selected.contains(offset + leading.count) {
			let segment = rawSegments[position]
			let parameters = segment.firstIndex(of: ";").map { segment[$0...] } ?? ""
			rawSegments[position] = encodedPlaceholder() + parameters
		}
		return rawSegments.joined(separator: "/")
	}

	private static func segmentName(of encodedSegment: String) -> String {
		let name = encodedSegment.prefix { $0 != ";" }
		return URLText.decodedOnce(name)
	}
}

private enum TokenShape {
	private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~=")
	private static let minimumLetterDigitSwitches = 2

	static func matches(_ segment: String, minimumLength: Int) -> Bool {
		guard segment.count >= minimumLength, segment.unicodeScalars.allSatisfy(allowed.contains) else { return false }
		var switches = 0
		var previousIsDigit: Bool?
		for character in segment where character.isLetter || character.isNumber {
			let isDigit = character.isNumber
			if let previousIsDigit, previousIsDigit != isDigit {
				switches += 1
			}
			previousIsDigit = isDigit
		}
		return switches >= minimumLetterDigitSwitches
	}
}
