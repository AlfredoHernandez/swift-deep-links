//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// Detects a conforming type that implements neither of two requirements
/// whose default implementations call each other, so it fails with an error
/// instead of recursing forever.
///
/// Each default marks the hop it starts and checks only for the opposite
/// hop. A type implementing one requirement only ever runs the other one's
/// default, so the opposite mark exists only when both defaults ran, and
/// nested or re-entrant calls through the same default are never rejected.
enum ProtocolBridgeGuard {
	enum Requirement: Sendable {
		case intercept
		case handle

		var name: String {
			switch self {
			case .intercept: "intercept(_:)"
			case .handle: "handle(_:)"
			}
		}
	}

	/// Which of the two defaults started a hop.
	enum Hop: Sendable {
		case legacyToContext
		case contextToLegacy

		var opposite: Hop {
			switch self {
			case .legacyToContext: .contextToLegacy
			case .contextToLegacy: .legacyToContext
			}
		}
	}

	private struct Mark: Hashable, Sendable {
		let requirement: Requirement
		let hop: Hop
		let conformer: ObjectIdentifier
	}

	@TaskLocal private static var marks: Set<Mark> = []

	static func bridge<Output>(
		_ conformer: Any.Type,
		_ requirement: Requirement,
		hop: Hop,
		_ body: () async throws -> Output,
	) async throws -> Output {
		let conformerID = ObjectIdentifier(conformer)
		var updated = marks
		guard !updated.contains(Mark(requirement: requirement, hop: hop.opposite, conformer: conformerID)) else {
			throw DeepLinkError.missingRequiredConfiguration("\(conformer) implements neither \(requirement.name) form")
		}
		guard updated.insert(Mark(requirement: requirement, hop: hop, conformer: conformerID)).inserted else {
			return try await body()
		}
		return try await $marks.withValue(updated) {
			try await body()
		}
	}
}
