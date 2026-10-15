//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

enum PercentEncodingNormalizer {
	/// Decodes escapes of RFC 3986 unreserved characters and upper-cases the
	/// rest, so equivalent encodings of the same text compare equal.
	static func normalized(_ encoded: String) -> String {
		guard encoded.contains("%") else { return encoded }
		var result = ""
		var remainder = Substring(encoded)
		while let percent = remainder.firstIndex(of: "%") {
			result += remainder[..<percent]
			let escape = remainder[percent...].prefix(3)
			guard let byte = decodedByte(of: escape) else {
				result += "%"
				remainder = remainder[remainder.index(after: percent)...]
				continue
			}
			let scalar = Unicode.Scalar(byte)
			result += isUnreserved(scalar) ? String(Character(scalar)) : escape.uppercased()
			remainder = remainder[escape.endIndex...]
		}
		return result + remainder
	}

	private static func decodedByte(of escape: Substring) -> UInt8? {
		let digits = escape.dropFirst()
		guard digits.count == 2, digits.allSatisfy(\.isHexDigit) else { return nil }
		return UInt8(digits, radix: 16)
	}

	private static func isUnreserved(_ scalar: Unicode.Scalar) -> Bool {
		scalar.isASCII && (scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) || "-._~".unicodeScalars.contains(scalar))
	}
}
