//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// The values a ``PathPatternParser`` captured from a matching URL.
///
/// Capture values are percent-decoded path segments that already passed the
/// parser's character-set check. Typed accessors throw
/// ``DeepLinkError/invalidParameterValue(name:value:)`` when a value does not
/// convert, and ``DeepLinkError/missingRequiredParameter(_:)`` when the
/// template declares no capture with that name.
public struct PathPatternMatch: Sendable {
	/// The URL that matched, for reading its query or fragment.
	public let url: URL

	/// The decoded segments matched by a trailing `*`; empty when the
	/// template has no wildcard or it matched nothing.
	public let wildcard: [String]

	private let values: [String: String]

	init(url: URL, values: [String: String], wildcard: [String]) {
		self.url = url
		self.values = values
		self.wildcard = wildcard
	}

	/// The captured value for `name`, or `nil` when the template declares no such capture.
	public subscript(name: String) -> String? {
		values[name]
	}

	/// The captured value for `name`.
	///
	/// - Throws: ``DeepLinkError/missingRequiredParameter(_:)`` when the
	///   template declares no capture named `name`.
	public func string(_ name: String) throws -> String {
		guard let value = values[name] else {
			throw DeepLinkError.missingRequiredParameter(name)
		}
		return value
	}

	/// The captured value for `name` converted to a non-negative `Int`.
	///
	/// Only the canonical decimal form is accepted: `0` or digits without a
	/// leading zero. Signs (`-5`, `+5`) and zero padding (`007`) are rejected so
	/// several spellings cannot address the same resource. Use
	/// `value(name, as: Int.self)` for the lenient `Int(_:)` conversion.
	///
	/// - Throws: ``DeepLinkError/invalidParameterValue(name:value:)`` when the
	///   value is not a canonical non-negative integer or overflows `Int`.
	public func int(_ name: String) throws -> Int {
		try convert(name) { raw in
			guard raw.allSatisfy(\.isASCIIDigit), raw == "0" || raw.first != "0" else { return nil }
			return Int(raw)
		}
	}

	/// The captured value for `name` converted to `UUID`.
	///
	/// - Throws: ``DeepLinkError/invalidParameterValue(name:value:)`` when the
	///   value is not a UUID.
	public func uuid(_ name: String) throws -> UUID {
		try convert(name) { UUID(uuidString: $0) }
	}

	/// The captured value for `name` converted with `T(_:)`.
	///
	/// - Throws: ``DeepLinkError/invalidParameterValue(name:value:)`` when the
	///   conversion fails.
	public func value<T: LosslessStringConvertible>(_ name: String, as _: T.Type = T.self) throws -> T {
		try convert(name) { T($0) }
	}

	private func convert<T>(_ name: String, using conversion: (String) -> T?) throws -> T {
		let raw = try string(name)
		guard let converted = conversion(raw) else {
			throw DeepLinkError.invalidParameterValue(name: name, value: raw)
		}
		return converted
	}
}

private extension Character {
	var isASCIIDigit: Bool {
		("0" ... "9").contains(self)
	}
}
