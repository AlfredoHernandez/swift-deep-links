//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A compiled path template such as `/products/:id` or `/u/:handle/posts/*`.
struct PathPattern: Sendable {
	enum Segment: Equatable {
		case literal(String)
		case capture(String)
		case wildcard
	}

	struct Captures: Equatable {
		var values: [String: String] = [:]
		var wildcard: [String] = []
	}

	static let wildcardName = "*"

	private static let forbiddenLiteralCharacters = CharacterSet(charactersIn: "%?#:*")

	let segments: [Segment]

	init(_ template: String) throws(PathPatternError) {
		let parts = template.split(separator: "/").map(String.init)
		var segments: [Segment] = []
		var names: Set<String> = []

		for (index, part) in parts.enumerated() {
			let segment = try Self.segment(from: part)
			if segment == .wildcard, index != parts.count - 1 {
				throw .wildcardNotLast
			}
			if case let .capture(name) = segment, !names.insert(name).inserted {
				throw .duplicateCaptureName(name)
			}
			segments.append(segment)
		}

		self.segments = segments
	}

	/// The captures when `pathSegments` match structurally, otherwise `nil`.
	/// Capture values are not validated here.
	func match(_ pathSegments: [String]) -> Captures? {
		var captures = Captures()

		for (index, segment) in segments.enumerated() {
			switch segment {
			case .wildcard:
				captures.wildcard = Array(pathSegments.dropFirst(index))
				return captures

			case let .literal(literal):
				guard index < pathSegments.count, pathSegments[index] == literal else { return nil }

			case let .capture(name):
				guard index < pathSegments.count else { return nil }
				captures.values[name] = pathSegments[index]
			}
		}

		return pathSegments.count == segments.count ? captures : nil
	}
}

// MARK: - Template Compilation

private extension PathPattern {
	static func segment(from part: String) throws(PathPatternError) -> Segment {
		if part == wildcardName {
			return .wildcard
		}

		if part.hasPrefix(":") {
			let name = String(part.dropFirst())
			guard isIdentifier(name) else { throw .invalidCaptureName(part) }
			return .capture(name)
		}

		guard part != ".", part != "..", part.rangeOfCharacter(from: forbiddenLiteralCharacters) == nil else {
			throw .invalidLiteral(part)
		}
		return .literal(part)
	}

	static func isIdentifier(_ name: String) -> Bool {
		guard let first = name.unicodeScalars.first, first == "_" || isASCIILetter(first) else {
			return false
		}
		return name.unicodeScalars.allSatisfy { $0 == "_" || isASCIILetter($0) || ("0" ... "9").contains($0) }
	}

	static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
		("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
	}
}
