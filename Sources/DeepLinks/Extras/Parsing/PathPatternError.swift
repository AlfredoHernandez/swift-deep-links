//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A path template that ``PathPatternParser`` cannot compile.
public enum PathPatternError: Error, Equatable, Sendable, LocalizedError {
	/// A `:name` segment whose name is empty or is not an identifier
	/// (a letter or `_` followed by letters, digits or `_`). Carries the segment.
	case invalidCaptureName(String)

	/// Two captures share the same name.
	case duplicateCaptureName(String)

	/// The `*` wildcard appears before the last segment.
	case wildcardNotLast

	/// A literal segment is `.` or `..`, or contains `%`, `?`, `#`, `:` or `*`.
	/// Carries the segment.
	case invalidLiteral(String)

	public var errorDescription: String? {
		switch self {
		case let .invalidCaptureName(segment):
			"Invalid capture '\(segment)' in path pattern"

		case let .duplicateCaptureName(name):
			"Duplicate capture name '\(name)' in path pattern"

		case .wildcardNotLast:
			"The '*' wildcard must be the last segment of a path pattern"

		case let .invalidLiteral(segment):
			"Invalid literal segment '\(segment)' in path pattern"
		}
	}
}
