//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct ProtocolBridgeGuardTests {
	@Test
	func `a type implementing neither form throws from both entry points`() async {
		let expected = DeepLinkError.missingRequiredConfiguration("NeitherFormHandler implements neither handle(_:) form")

		await #expect(throws: expected) {
			try await NeitherFormHandler().handle(.route1, context: .unknown)
		}
		await #expect(throws: expected) {
			try await NeitherFormHandler().handle(.route1)
		}
	}

	@Test
	func `concurrent calls keep their marks apart`() async {
		let outcomes = await withTaskGroup(of: Bool.self) { group in
			for index in 0 ..< 200 {
				group.addTask {
					do {
						if index.isMultiple(of: 2) {
							try await NeitherFormHandler().handle(.route1)
						} else {
							try await LegacyFormHandler().handle(.route1, context: .unknown)
						}
						return !index.isMultiple(of: 2)
					} catch {
						return index.isMultiple(of: 2) && error as? DeepLinkError == .missingRequiredConfiguration("NeitherFormHandler implements neither handle(_:) form")
					}
				}
			}
			return await group.reduce(into: [Bool]()) { $0.append($1) }
		}

		let unexpected = outcomes.filter { !$0 }.count
		#expect(outcomes.count == 200)
		#expect(unexpected == 0)
	}

	@Test
	func `a one-form handler wrapping a neither-form handler surfaces the inner type's error`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("NeitherFormHandler implements neither handle(_:) form")) {
			try await WrappingLegacyHandler(inner: NeitherFormHandler()).handle(.route1, context: .unknown)
		}
	}

	@Test
	func `the same hop nested for one conformer is allowed`() async throws {
		let depth = try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .legacyToContext) {
			try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .legacyToContext) { 2 }
		}

		#expect(depth == 2)
	}

	@Test
	func `opposite hops for different conformers or requirements are allowed`() async throws {
		let byConformer = try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .legacyToContext) {
			try await ProtocolBridgeGuard.bridge(String.self, .handle, hop: .contextToLegacy) { true }
		}
		let byRequirement = try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .legacyToContext) {
			try await ProtocolBridgeGuard.bridge(Int.self, .intercept, hop: .contextToLegacy) { true }
		}

		#expect(byConformer)
		#expect(byRequirement)
	}

	@Test
	func `opposite hops for one conformer and requirement throw`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("Int implements neither handle(_:) form")) {
			try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .legacyToContext) {
				try await ProtocolBridgeGuard.bridge(Int.self, .handle, hop: .contextToLegacy) { true }
			}
		}
	}
}

// MARK: - Test Doubles

private struct NeitherFormHandler: DeepLinkHandler {
	typealias Route = TestRoute
}

private struct LegacyFormHandler: DeepLinkHandler {
	func handle(_: TestRoute) async throws {}
}

private struct WrappingLegacyHandler: DeepLinkHandler {
	let inner: NeitherFormHandler

	func handle(_ route: TestRoute) async throws {
		try await inner.handle(route, context: .unknown)
	}
}
