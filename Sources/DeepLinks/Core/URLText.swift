//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// The percent-decoding and normalization rules shared by every component
/// that compares, validates or redacts URL text, so a spelling one of them
/// accepts cannot slip past another.
enum URLText {
	/// The number of percent-decoding passes inspected before text is
	/// considered maliciously nested.
	static let maximumDecodingPasses = 4

	// MARK: - Decoding

	/// Every Foundation percent-decoding pass of `encoded`, starting with
	/// `encoded` itself, or `nil` when a pass hits an invalid escape or the
	/// text still decodes after ``maximumDecodingPasses``, so callers fail closed.
	static func strictDecodedForms(of encoded: String) -> [String]? {
		var current = encoded
		var forms = [current]
		for _ in 0 ..< maximumDecodingPasses {
			guard let decoded = current.removingPercentEncoding else { return nil }
			guard decoded != current else { return forms }
			forms.append(decoded)
			current = decoded
		}
		return current.removingPercentEncoding == current ? forms : nil
	}

	/// `text` decoded until it stops changing, an escape is invalid, or
	/// ``maximumDecodingPasses`` passes ran.
	static func fullyDecoded(_ text: String) -> String {
		var decoded = text
		for _ in 0 ..< maximumDecodingPasses {
			guard let next = decoded.removingPercentEncoding, next != decoded else { break }
			decoded = next
		}
		return decoded
	}

	/// `text` percent-decoded once, or `text` unchanged when an escape is invalid.
	static func decodedOnce(_ text: some StringProtocol) -> String {
		text.removingPercentEncoding ?? String(text)
	}

	// MARK: - Characters

	static func isControl(_ scalar: Unicode.Scalar) -> Bool {
		scalar.properties.generalCategory == .control
	}

	/// Unicode format characters (bidi overrides, zero-width space, BOM) and
	/// line or paragraph separators.
	static func isInvisibleFormatting(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar.properties.generalCategory {
		case .format, .lineSeparator, .paragraphSeparator: true
		default: false
		}
	}

	/// Control or invisible formatting characters, which never render but
	/// can split log lines or make two spellings of a URL look identical.
	static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
		isControl(scalar) || isInvisibleFormatting(scalar)
	}

	// MARK: - Hosts and Paths

	/// Lower-cased, without trailing dots, so `Home.` and `home` compare equal.
	static func normalizedHost(_ host: String) -> String {
		var normalized = host.lowercased()
		while normalized.hasSuffix(".") {
			normalized.removeLast()
		}
		return normalized
	}

	/// `/`, or `\`, which lenient URL parsers also treat as a path separator.
	static func isPathSeparator(_ character: Character) -> Bool {
		character == "/" || character == "\\"
	}

	static func isDotSegment(_ segment: some StringProtocol) -> Bool {
		segment == "." || segment == ".."
	}

	/// `.`, or a full stop that Unicode normalization (NFKC, IDNA) folds into
	/// `.`: fullwidth `．` (U+FF0E), ideographic `。` (U+3002) and halfwidth
	/// ideographic `｡` (U+FF61). A server or web view that normalizes the path
	/// would read `．．` as `..`.
	static func isDotLike(_ character: Character) -> Bool {
		character == "." || character == "\u{FF0E}" || character == "\u{3002}" || character == "\u{FF61}"
	}

	/// The segment before any `;` parameters (`..;x` is `..` to servers that
	/// strip matrix parameters).
	static func segmentName(_ segment: Substring) -> Substring {
		segment.prefix { $0 != ";" }
	}

	/// `segment` spelled with ASCII dots when it consists only of dot-like
	/// characters, so `．．` reads as `..`; any other segment unchanged.
	static func foldingDotLikeSegment(_ segment: Substring) -> Substring {
		guard !segment.isEmpty, segment.allSatisfy(isDotLike) else { return segment }
		return Substring(String(repeating: ".", count: segment.count))
	}

	/// `segments` with `.` removed and each `..` removing the segment before
	/// it (RFC 3986 §5.2.4); a `..` with nothing before it is dropped.
	static func resolvingDotSegments(_ segments: some Sequence<Substring>) -> [Substring] {
		var resolved: [Substring] = []
		for segment in segments {
			switch segment {
			case ".":
				continue

			case "..":
				_ = resolved.popLast()

			default:
				resolved.append(segment)
			}
		}
		return resolved
	}
}

// MARK: - Lenient Decoding Passes

extension URLText {
	/// Successive percent-decoding passes. Each pass decodes every valid `%HH`
	/// escape and keeps invalid ones literally, so an invalid escape such as a
	/// decoded literal `%zz` cannot stop decoding and hide what follows it.
	struct DecodingPasses {
		private(set) var forms: [String]
		private(set) var isValidUTF8 = true
		private(set) var decodesFurther = false

		init(of encoded: String, limit: Int = URLText.maximumDecodingPasses) {
			forms = [encoded]
			while let next = Self.decode(forms[forms.count - 1]), next.text != forms[forms.count - 1] {
				guard forms.count <= limit else {
					decodesFurther = true
					return
				}
				isValidUTF8 = isValidUTF8 && next.isValidUTF8
				forms.append(next.text)
			}
		}

		private static func decode(_ text: String) -> (text: String, isValidUTF8: Bool)? {
			let source = Array(text.utf8)
			var bytes: [UInt8] = []
			bytes.reserveCapacity(source.count)

			var index = 0
			while index < source.count {
				if source[index] == UInt8(ascii: "%"), index + 2 < source.count,
				   let high = hexValue(of: source[index + 1]), let low = hexValue(of: source[index + 2])
				{
					bytes.append(high << 4 | low)
					index += 3
				} else {
					bytes.append(source[index])
					index += 1
				}
			}

			if let valid = String(bytes: bytes, encoding: .utf8) {
				return (valid, true)
			}
			return (String(decoding: bytes, as: UTF8.self), false)
		}

		private static func hexValue(of byte: UInt8) -> UInt8? {
			switch byte {
			case UInt8(ascii: "0") ... UInt8(ascii: "9"):
				byte - UInt8(ascii: "0")

			case UInt8(ascii: "a") ... UInt8(ascii: "f"):
				byte - UInt8(ascii: "a") + 10

			case UInt8(ascii: "A") ... UInt8(ascii: "F"):
				byte - UInt8(ascii: "A") + 10

			default:
				nil
			}
		}
	}
}
