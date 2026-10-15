//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

/// Pins which checks each pre-2.0 strategy runs, against a policy allowing
/// scheme `myapp`, host `home` and blocking the pattern `admin`.
struct LegacySecurityStrategyBehaviorTests {
	struct Case: CustomTestStringConvertible, Sendable {
		let strategyName: String
		let url: String
		let expected: Verdict

		var testDescription: String {
			"\(strategyName) \(url) → \(expected)"
		}
	}

	enum Verdict: Equatable, Sendable {
		case passes
		case rejected(SecurityViolationReason)
		case blocked
	}

	static let cases: [Case] = [
		Case(strategyName: "standard", url: "myapp://home/a", expected: .passes),
		Case(strategyName: "standard", url: "web://home/a", expected: .rejected(.unauthorizedScheme)),
		Case(strategyName: "standard", url: "myapp://other/a", expected: .rejected(.unauthorizedHost)),
		Case(strategyName: "standard", url: "myapp://home/admin", expected: .blocked),
		Case(strategyName: "strict", url: "myapp://home/a", expected: .passes),
		Case(strategyName: "strict", url: "myapp:a", expected: .rejected(.unauthorizedHost)),
		Case(strategyName: "strict", url: "myapp://home/admin", expected: .blocked),
		Case(strategyName: "permissive", url: "myapp://other/a", expected: .passes),
		Case(strategyName: "permissive", url: "web://home/a", expected: .rejected(.unauthorizedScheme)),
		Case(strategyName: "permissive", url: "myapp://other/admin", expected: .blocked),
		Case(strategyName: "schemeOnly", url: "myapp://other/admin", expected: .passes),
		Case(strategyName: "schemeOnly", url: "web://home/a", expected: .rejected(.unauthorizedScheme)),
		Case(strategyName: "hostOnly", url: "web://home/admin", expected: .passes),
		Case(strategyName: "hostOnly", url: "myapp://other/a", expected: .rejected(.unauthorizedHost)),
		Case(strategyName: "patternOnly", url: "web://other/a", expected: .passes),
		Case(strategyName: "patternOnly", url: "web://other/admin", expected: .blocked),
		Case(strategyName: "whitelist", url: "myapp://home/admin", expected: .passes),
		Case(strategyName: "whitelist", url: "web://home/a", expected: .rejected(.unauthorizedScheme)),
		Case(strategyName: "whitelist", url: "myapp://other/a", expected: .rejected(.unauthorizedHost)),
	]

	@Test(arguments: cases)
	func `each legacy strategy runs only its own checks`(_ testCase: Case) async throws {
		let url = try #require(URL(string: testCase.url))
		let policy = try SecurityPolicy(allowedSchemes: ["myapp"], allowedHosts: ["home"], blockedPatterns: [NSRegularExpression(pattern: "admin")])

		#expect(await verdict(of: Self.strategy(named: testCase.strategyName), on: url, policy: policy) == testCase.expected)
	}

	@Test
	func `whitelist rejects a path that does not start with a slash`() async throws {
		let url = try #require(URL(string: "myapp:relative"))
		let policy = SecurityPolicy(allowedSchemes: ["myapp"])

		#expect(await verdict(of: .whitelist, on: url, policy: policy) == .rejected(.invalidPath))
	}

	@Test(arguments: ["standard", "strict", "permissive", "schemeOnly", "hostOnly", "patternOnly", "whitelist"])
	func `legacy strategies pass the URL through unchanged`(strategyName: String) async throws {
		let url = try #require(URL(string: "myapp://home/a"))
		let policy = SecurityPolicy(allowedSchemes: ["myapp"], allowedHosts: ["home"])

		#expect(try await Self.strategy(named: strategyName).validate(url: url, policy: policy) == url)
	}

	private static func strategy(named name: String) -> SecurityStrategy {
		switch name {
		case "standard": .standard
		case "strict": .strict
		case "permissive": .permissive
		case "schemeOnly": .schemeOnly
		case "hostOnly": .hostOnly
		case "patternOnly": .patternOnly
		case "whitelist": .whitelist
		default: .hardened
		}
	}

	private func verdict(of strategy: SecurityStrategy, on url: URL, policy: SecurityPolicy) async -> Verdict? {
		do {
			return try await strategy.validate(url: url, policy: policy) == url ? .passes : nil
		} catch let error as DeepLinkError {
			if case .blockedURL = error {
				return .blocked
			}
			return error.securityViolationReason.map(Verdict.rejected)
		} catch {
			return nil
		}
	}
}
