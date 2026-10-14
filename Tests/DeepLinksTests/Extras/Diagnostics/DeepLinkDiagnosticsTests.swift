//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct DeepLinkDiagnosticsTests {
	// MARK: - Info.plist Schemes

	@Test
	func `reads every scheme from the URL types of an info dictionary`() {
		let info: [String: Any] = [
			"CFBundleURLTypes": [
				["CFBundleURLSchemes": ["myapp", "MyApp-Beta"]],
				["CFBundleURLName": "other", "CFBundleURLSchemes": ["fb123"]],
				["CFBundleURLName": "no schemes"],
			],
		]

		#expect(DeepLinkDiagnostics.declaredURLSchemes(inInfoDictionary: info) == ["myapp", "myapp-beta", "fb123"])
	}

	@Test
	func `missing or malformed URL types declare no schemes`() {
		#expect(DeepLinkDiagnostics.declaredURLSchemes(inInfoDictionary: nil).isEmpty)
		#expect(DeepLinkDiagnostics.declaredURLSchemes(inInfoDictionary: ["CFBundleURLTypes": "oops"]).isEmpty)
	}

	@Test
	func `bundle initializer reads the bundle's info dictionary`() {
		let sut = DeepLinkDiagnostics(bundle: Bundle(for: BundleToken.self))

		#expect(sut.declaredURLSchemes == DeepLinkDiagnostics.declaredURLSchemes(inInfoDictionary: Bundle(for: BundleToken.self).infoDictionary))
	}

	// MARK: - Security Configuration

	@Test
	func `consistent configuration has no warnings`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: ["myapp"], associatedDomains: ["applinks:example.com"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["myapp", "https"], allowedHosts: ["example.com", "product"])

		#expect(warnings.isEmpty)
	}

	@Test
	func `empty allowed schemes is flagged alone`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: ["myapp"])

		#expect(sut.checkSecurityConfiguration(allowedSchemes: [], allowedHosts: []) == [.emptyAllowedSchemes])
	}

	@Test
	func `allowed custom scheme missing from the bundle is flagged`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: ["myapp"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["myapp", "MyOtherApp"], allowedHosts: ["home"])

		#expect(warnings == [.schemeNotDeclared("myotherapp")])
	}

	@Test
	func `declared scheme the security configuration rejects is flagged`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: ["myapp", "legacyapp"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["MYAPP"], allowedHosts: ["home"])

		#expect(warnings == [.declaredSchemeNotAllowed("legacyapp")])
	}

	@Test
	func `ignored declared schemes are not flagged`() {
		let sut = DeepLinkDiagnostics(
			declaredURLSchemes: ["myapp", "fb123456", "FB987", "com.googleusercontent.apps.42", "legacyapp"],
			ignoredDeclaredSchemes: ["com.googleusercontent.apps.42"],
			ignoredDeclaredSchemePrefixes: ["FB"],
		)

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["myapp"], allowedHosts: ["home"])

		#expect(warnings == [.declaredSchemeNotAllowed("legacyapp")])
	}

	@Test
	func `ignored schemes still count as declared for allowed schemes`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: ["fb123"], ignoredDeclaredSchemePrefixes: ["fb"])

		#expect(sut.checkSecurityConfiguration(allowedSchemes: ["fb123"], allowedHosts: ["home"]).isEmpty)
	}

	@Test
	func `web scheme without allowed hosts is flagged`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		#expect(sut.checkSecurityConfiguration(allowedSchemes: ["https"], allowedHosts: []) == [.webSchemeWithoutAllowedHosts])
	}

	@Test
	func `web host without an applinks entry is flagged`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [], associatedDomains: ["applinks:example.com", "webcredentials:shop.example.com"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["https"], allowedHosts: ["example.com", "Shop.Example.com"])

		#expect(warnings == [.hostNotInAssociatedDomains("shop.example.com")])
	}

	@Test
	func `applinks domain the security configuration rejects is flagged`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [], associatedDomains: ["applinks:example.com", "applinks:old.example.com?mode=developer"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["https"], allowedHosts: ["example.com"])

		#expect(warnings == [.associatedDomainNotAllowed("old.example.com")])
	}

	@Test
	func `wildcard applinks entry covers subdomains but not the apex`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [], associatedDomains: ["applinks:*.example.com"])

		let warnings = sut.checkSecurityConfiguration(allowedSchemes: ["https"], allowedHosts: ["www.example.com", "example.com"])

		#expect(warnings == [.hostNotInAssociatedDomains("example.com")])
	}

	@Test
	func `associated domains are not checked when none are supplied`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		#expect(sut.checkSecurityConfiguration(allowedSchemes: ["https"], allowedHosts: ["example.com"]).isEmpty)
	}

	// MARK: - Parser Probes

	@Test
	func `probe handled by exactly one parser has no warnings`() async throws {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])
		let parsers: [any DeepLinkParser<TestRoute>] = try [
			PathPatternParser("/a") { _ in .route1 },
			PathPatternParser("/b") { _ in .route2 },
		]

		let warnings = try await sut.checkParsers(parsers, probes: [#require(URL(string: "https://x.com/a")), #require(URL(string: "https://x.com/b"))])

		#expect(warnings.isEmpty)
	}

	@Test
	func `probe no parser handles is flagged`() async throws {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])
		let probe = try #require(URL(string: "https://x.com/missing"))
		let parsers: [any DeepLinkParser<TestRoute>] = try [PathPatternParser("/a") { _ in .route1 }]

		#expect(await sut.checkParsers(parsers, probes: [probe]) == [.unhandledProbe(probe)])
	}

	@Test
	func `later parsers that also handle a probe are flagged as shadowed`() async throws {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])
		let probe = try #require(URL(string: "https://x.com/products/1"))
		let parsers: [any DeepLinkParser<TestRoute>] = try [
			PathPatternParser("/orders/:id") { _ in .route1 },
			PathPatternParser("/products/*") { _ in .route2 },
			PathPatternParser("/products/:id") { _ in .route3 },
			ImmediateParser(routes: [.route1]),
		]

		let warnings = await sut.checkParsers(parsers, probes: [probe])

		#expect(warnings == [.shadowedParsers(probe: probe, handledBy: 1, shadowed: [2, 3])])
	}

	@Test
	func `probe descriptions redact sensitive values`() throws {
		let probe = try #require(URL(string: "myapp://reset?token=s3cret"))

		#expect(!DeepLinkDiagnosticWarning.unhandledProbe(probe).description.contains("s3cret"))
		#expect(!DeepLinkDiagnosticWarning.shadowedParsers(probe: probe, handledBy: 0, shadowed: [1]).description.contains("s3cret"))
	}

	@Test
	func `warnings describe the problem`() throws {
		#expect(DeepLinkDiagnosticWarning.schemeNotDeclared("myapp").description.contains("CFBundleURLTypes"))
		#expect(try DeepLinkDiagnosticWarning.shadowedParsers(probe: #require(URL(string: "myapp://a")), handledBy: 0, shadowed: [2]).description
			.contains("never reached"))
	}
}

private final class BundleToken {}
