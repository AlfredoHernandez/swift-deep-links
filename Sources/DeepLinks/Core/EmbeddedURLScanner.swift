//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Finds `scheme://…` URLs embedded in free-form text in a single pass.
///
/// A match is the leftmost letter of a run of scheme characters
/// (`A-Z a-z 0-9 + . -`) followed by `://` and at least one character that is
/// not whitespace, a quote, `<` or `>`; it ends before the next such
/// character. Each character is inspected a bounded number of times, so
/// attacker-controlled text (a 100 000-letter host in an error message)
/// costs linear time.
struct EmbeddedURLScanner {
	/// How many Unicode scalars the scanner has read; tests use it to pin the linear bound.
	private(set) var inspectedScalarCount = 0

	mutating func urlRanges(in text: String) -> [Range<String.Index>] {
		let scalars = text.unicodeScalars
		var ranges: [Range<String.Index>] = []
		var schemeStart: String.Index?
		var index = scalars.startIndex

		while index < scalars.endIndex {
			let scalar = read(scalars, at: index)
			if scalar == ":", let start = schemeStart, let end = urlEnd(in: scalars, afterColonAt: index) {
				ranges.append(start ..< end)
				schemeStart = nil
				index = end
				continue
			}
			if Self.isSchemeCharacter(scalar) {
				if schemeStart == nil, Self.isLetter(scalar) {
					schemeStart = index
				}
			} else {
				schemeStart = nil
			}
			index = scalars.index(after: index)
		}
		return ranges
	}

	private mutating func urlEnd(in scalars: String.UnicodeScalarView, afterColonAt colon: String.Index) -> String.Index? {
		var index = scalars.index(after: colon)
		for _ in 0 ..< 2 {
			guard index < scalars.endIndex, read(scalars, at: index) == "/" else { return nil }
			index = scalars.index(after: index)
		}
		let bodyStart = index
		while index < scalars.endIndex, Self.isURLBodyCharacter(read(scalars, at: index)) {
			index = scalars.index(after: index)
		}
		return index > bodyStart ? index : nil
	}

	private mutating func read(_ scalars: String.UnicodeScalarView, at index: String.Index) -> Unicode.Scalar {
		inspectedScalarCount += 1
		return scalars[index]
	}

	private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
		("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
	}

	private static func isSchemeCharacter(_ scalar: Unicode.Scalar) -> Bool {
		isLetter(scalar) || ("0" ... "9").contains(scalar) || scalar == "+" || scalar == "." || scalar == "-"
	}

	private static func isURLBodyCharacter(_ scalar: Unicode.Scalar) -> Bool {
		!scalar.properties.isWhitespace && !"'\"<>".unicodeScalars.contains(scalar)
	}
}
