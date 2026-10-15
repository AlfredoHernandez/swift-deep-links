//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

/// Pins the shared ``URLText`` helpers, and the callers rebuilt on them, to
/// the per-component helpers they replaced, frozen below as oracles.
struct URLTextDifferentialTests {
	@Test(arguments: DifferentialInput.all)
	func `lenient decoding passes match the canonicalizer's`(_ input: DifferentialInput) {
		let shared = URLText.DecodingPasses(of: input.text, limit: 4)
		let legacy = LegacyDecodingPasses(of: input.text, limit: 4)

		#expect(shared.forms == legacy.forms)
		#expect(shared.isValidUTF8 == legacy.isValidUTF8)
		#expect(shared.decodesFurther == legacy.decodesFurther)
	}

	@Test(arguments: DifferentialInput.all)
	func `strict decoded forms match the matcher's`(_ input: DifferentialInput) {
		#expect(URLText.strictDecodedForms(of: input.text) == Legacy.matcherDecodedForms(of: input.text))
	}

	@Test(arguments: DifferentialInput.all)
	func `full decoding matches the replay key's`(_ input: DifferentialInput) {
		#expect(URLText.fullyDecoded(input.text) == Legacy.replayFullyDecoded(input.text))
	}

	@Test(arguments: DifferentialInput.all)
	func `single decoding matches the redactor's`(_ input: DifferentialInput) {
		#expect(URLText.decodedOnce(input.text) == (input.text.removingPercentEncoding ?? input.text))
		#expect(URLText.decodedOnce(Substring(input.text)) == (Substring(input.text).removingPercentEncoding ?? input.text))
	}

	@Test(arguments: DifferentialInput.all)
	func `host normalization matches the matcher's`(_ input: DifferentialInput) {
		for form in LegacyDecodingPasses(of: input.text, limit: 4).forms {
			#expect(URLText.normalizedHost(form) == Legacy.normalizedHost(form))
		}
	}

	@Test(arguments: DifferentialInput.all)
	func `character classes match every former predicate`(_ input: DifferentialInput) {
		for form in LegacyDecodingPasses(of: input.text, limit: 4).forms {
			for scalar in form.unicodeScalars {
				#expect(URLText.isInvisible(scalar) == Legacy.matcherIsInvisible(scalar))
				#expect(URLText.isControl(scalar) == Legacy.canonicalizerIsControl(scalar))
				#expect(URLText.isInvisibleFormatting(scalar) == Legacy.canonicalizerIsInvisibleFormatting(scalar))
			}
		}
	}

	@Test(arguments: DifferentialInput.all)
	func `matcher path normalization is unchanged`(_ input: DifferentialInput) {
		for form in URLText.strictDecodedForms(of: input.text) ?? [input.text] {
			#expect(DeepLinkMatcher.normalizedPath(form) == Legacy.matcherNormalizedPath(form))
		}
	}

	@Test(arguments: DifferentialInput.all)
	func `transformer dot-segment resolution is unchanged`(_ input: DifferentialInput) {
		#expect(URLNormalizationTransformer.resolvingDotSegments(in: input.text) == Legacy.transformerResolvingDotSegments(in: input.text))
	}

	@Test(arguments: DifferentialInput.all)
	func `dot-segment detection matches the path-pattern parser's`(_ input: DifferentialInput) {
		let decoded = URLText.decodedOnce(input.text)
		#expect(URLText.isDotSegment(decoded) == (decoded == "." || decoded == ".."))
	}
}

// MARK: - Inputs

struct DifferentialInput: CustomTestStringConvertible, Sendable {
	let text: String

	var testDescription: String {
		text.debugDescription
	}

	static let all: [DifferentialInput] = {
		let handwritten = [
			"", "%", "%%", "%2", "%zz", "%zz%41", "%%41", "%2541", "%252e%252e", "%25252525252e",
			"%2525252525252e", "%C0%AE", "%E0%A4%A", "%E2%80%AE", "%E2%80%8B", "%E2%80%A8", "a%00b", "a%0Ab",
			"%7F", "HOME.", "Home..", "...", "%68ome", "%48OME%2E", "/a/./b/../c", "/../a", "..", ".", "a\\..\\b",
			"/a;x/..;y/b", "//a//b/", "/x/%2e%2e/y", "/x/%2E%2E/y", "/public/%2e%2e/admin", "🙂", "a%E2%80%8Bb",
			"%2F%2f", "/a/b/c/../../..", "/a/./../../b", "a/b/", "/;p", "/a/;/b", "%F0%9F%99%82", "/%EF%BB%BFa",
		]
		let corpus = URLFuzzCorpus.hostile(scheme: "myapp", host: "home") + URLFuzzCorpus.hostile()
		let fromCorpus = corpus.flatMap { fuzzCase in
			[
				fuzzCase.url.absoluteString,
				fuzzCase.url.path(percentEncoded: true),
				fuzzCase.url.host(percentEncoded: true) ?? "",
				fuzzCase.url.query(percentEncoded: true) ?? "",
			]
		}
		var seen = Set<String>()
		return (handwritten + fromCorpus).filter { seen.insert($0).inserted }.map(DifferentialInput.init)
	}()
}

// MARK: - Frozen Former Helpers

private enum Legacy {
	static func matcherDecodedForms(of encodedPath: String) -> [String]? {
		var encoded = encodedPath
		var forms = [encoded]
		for _ in 0 ..< 4 {
			guard let decoded = encoded.removingPercentEncoding else { return nil }
			guard decoded != encoded else { return forms }
			forms.append(decoded)
			encoded = decoded
		}
		return encoded.removingPercentEncoding == encoded ? forms : nil
	}

	static func replayFullyDecoded(_ text: String) -> String {
		var decoded = text
		for _ in 0 ..< 4 {
			guard let next = decoded.removingPercentEncoding, next != decoded else { break }
			decoded = next
		}
		return decoded
	}

	static func normalizedHost(_ host: String) -> String {
		var normalized = host.lowercased()
		while normalized.hasSuffix(".") {
			normalized.removeLast()
		}
		return normalized
	}

	static func matcherIsInvisible(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar.properties.generalCategory {
		case .control, .format, .lineSeparator, .paragraphSeparator: true
		default: false
		}
	}

	static func canonicalizerIsControl(_ scalar: Unicode.Scalar) -> Bool {
		scalar.properties.generalCategory == .control
	}

	static func canonicalizerIsInvisibleFormatting(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar.properties.generalCategory {
		case .format, .lineSeparator, .paragraphSeparator: true
		default: false
		}
	}

	static func matcherNormalizedPath(_ path: String) -> String {
		let visible = String(String.UnicodeScalarView(path.unicodeScalars.filter { !matcherIsInvisible($0) }))
		var segments: [Substring] = []
		for rawSegment in visible.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
			let segment = rawSegment.prefix { $0 != ";" }
			switch segment {
			case "", ".":
				continue

			case "..":
				_ = segments.popLast()

			default:
				segments.append(segment)
			}
		}
		return ("/" + segments.joined(separator: "/")).lowercased()
	}

	static func transformerResolvingDotSegments(in path: String) -> String {
		let isAbsolute = path.hasPrefix("/")
		var resolved: [Substring] = []
		for segment in path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(isAbsolute ? 1 : 0) {
			switch segment {
			case ".":
				continue

			case "..":
				_ = resolved.popLast()

			default:
				resolved.append(segment)
			}
		}
		return (isAbsolute ? "/" : "") + resolved.joined(separator: "/")
	}
}

private struct LegacyDecodingPasses {
	private(set) var forms: [String]
	private(set) var isValidUTF8 = true
	private(set) var decodesFurther = false

	init(of encoded: String, limit: Int) {
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
		case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
		case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
		case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
		default: nil
		}
	}
}
