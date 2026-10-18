//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct URLRedactorTests {
	private let sut = URLRedactor()

	@Test
	func `redacts sensitive query values and keeps the rest of the URL`() throws {
		let url = try #require(URL(string: "https://example.com/reset?token=abc123&lang=en"))

		let redacted = sut.redact(url)

		#expect(redacted.absoluteString == "https://example.com/reset?token=REDACTED&lang=en")
	}

	@Test(arguments: [
		"token", "code", "password", "email", "key", "secret", "otp", "auth", "session",
		"access_token", "refreshToken", "api_key", "apiKey", "sessionId", "client-secret", "user.email",
		"TOKEN", "Password", "authorization", "signature", "pin",
	])
	func `treats a parameter as sensitive when it or one of its words is a sensitive key`(name: String) {
		#expect(sut.isSensitive(parameterName: name))
	}

	@Test(arguments: [
		"accesstoken", "apikey", "authtoken", "idtoken", "APIKEY", "SESSIONID", "APIKey", "xApiKey",
		"token2", "code1", "tokens", "codes", "keys", "e-mail", "mail", "ticket", "jsessionid", "user_password1",
	])
	func `treats concatenated, acronym, numbered and plural names as sensitive`(name: String) {
		#expect(sut.isSensitive(parameterName: name))
	}

	@Test(arguments: ["id", "lang", "keyword", "barcode", "authors", "page", "state", "monkey", "decode", "mailbox", ""])
	func `does not treat unrelated parameters as sensitive`(name: String) {
		#expect(!sut.isSensitive(parameterName: name))
	}

	@Test
	func `redacts every value of a repeated sensitive key`() throws {
		let url = try #require(URL(string: "myapp://login?code=1&code=2"))

		#expect(sut.redact(url).absoluteString == "myapp://login?code=REDACTED&code=REDACTED")
	}

	@Test
	func `keeps valueless sensitive keys valueless`() throws {
		let url = try #require(URL(string: "myapp://login?token&id=7"))

		#expect(sut.redact(url).absoluteString == "myapp://login?token&id=7")
	}

	@Test
	func `matches percent-encoded parameter names after decoding`() throws {
		let url = try #require(URL(string: "myapp://login?%74oken=abc"))

		#expect(sut.redact(url).query?.contains("abc") == false)
	}

	@Test
	func `redacts userinfo`() throws {
		let url = try #require(URL(string: "https://alice:hunter2@example.com/path"))

		let redacted = sut.redact(url)

		#expect(redacted.absoluteString == "https://REDACTED@example.com/path")
	}

	@Test
	func `redacts sensitive key-value pairs in the fragment`() throws {
		let url = try #require(URL(string: "https://example.com/cb#access_token=xyz&state=ok"))

		#expect(sut.redact(url).absoluteString == "https://example.com/cb#access_token=REDACTED&state=ok")
	}

	@Test
	func `leaves a plain fragment untouched`() throws {
		let url = try #require(URL(string: "https://example.com/docs#section-2"))

		#expect(sut.redact(url) == url)
	}

	@Test
	func `returns a URL without sensitive data unchanged`() throws {
		let url = try #require(URL(string: "myapp://product/42?color=red"))

		#expect(sut.redact(url) == url)
	}

	@Test
	func `custom sensitive keys replace the defaults`() throws {
		let redactor = URLRedactor(sensitiveKeys: ["promo"])
		let url = try #require(URL(string: "myapp://shop?promo=SUMMER&token=abc"))

		#expect(redactor.redact(url).absoluteString == "myapp://shop?promo=REDACTED&token=abc")
	}

	@Test
	func `custom sensitive keys are compared case-insensitively`() {
		let redactor = URLRedactor(sensitiveKeys: ["Promo"])

		#expect(redactor.isSensitive(parameterName: "PROMO_code"))
	}

	@Test
	func `custom placeholder is percent-encoded into the URL`() throws {
		let redactor = URLRedactor(placeholder: "<hidden & safe>")
		let url = try #require(URL(string: "myapp://login?token=abc&id=1"))

		let redacted = redactor.redact(url)

		let components = try #require(URLComponents(url: redacted, resolvingAgainstBaseURL: false))
		#expect(components.queryItems == [
			URLQueryItem(name: "token", value: "<hidden & safe>"),
			URLQueryItem(name: "id", value: "1"),
		])
	}

	@Test
	func `redacts sensitive values inside a nested URL parameter`() throws {
		let url = try #require(URL(string: "myapp://open?redirect=https%3A%2F%2Fx.com%2Fcb%3Ftoken%3Dabc%26lang%3Den&id=1"))

		let redacted = sut.redact(url)

		let components = try #require(URLComponents(url: redacted, resolvingAgainstBaseURL: false))
		#expect(components.queryItems == [
			URLQueryItem(name: "redirect", value: "https://x.com/cb?token=REDACTED&lang=en"),
			URLQueryItem(name: "id", value: "1"),
		])
	}

	@Test
	func `leaves a nested URL without sensitive values untouched`() throws {
		let url = try #require(URL(string: "myapp://open?redirect=https%3A%2F%2Fx.com%2Fcb%3Flang%3Den"))

		#expect(sut.redact(url) == url)
	}

	@Test
	func `redacts sensitive matrix parameters in the path`() throws {
		let url = try #require(URL(string: "https://example.com/app;jsessionid=ABC123/page;view=list?id=1"))

		#expect(sut.redact(url).absoluteString == "https://example.com/app;jsessionid=REDACTED/page;view=list?id=1")
	}

	@Test(arguments: [
		"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
		"eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMifQ.",
		"abcdefgh12.ijklmnop34.qrstuvwx56",
	])
	func `redacts JWT-like values regardless of the parameter name`(value: String) throws {
		let url = try #require(URL(string: "myapp://open?data=\(value)&id=1"))

		#expect(sut.redact(url).absoluteString == "myapp://open?data=REDACTED&id=1")
	}

	@Test(arguments: ["1.2.3", "com.example.app", "v2.10.4-beta"])
	func `keeps dotted values that are not JWT-like`(value: String) throws {
		let url = try #require(URL(string: "myapp://open?version=\(value)"))

		#expect(sut.redact(url) == url)
	}

	@Test
	func `bounds the text it redacts and marks it as truncated`() {
		let text = "Unauthorized host: " + String(repeating: "a", count: 100_000)

		let redacted = sut.redactingURLs(in: text)

		#expect(redacted.unicodeScalars.count <= URLRedactor.maximumRedactedTextLength + URLRedactor.truncationMarker.unicodeScalars.count)
		#expect(redacted.hasSuffix(URLRedactor.truncationMarker))
	}

	@Test
	func `replaces a URL cut by the length bound instead of keeping part of it`() {
		let padding = String(repeating: "p", count: URLRedactor.maximumRedactedTextLength - 30)
		let text = padding + " https://example.com/x?state=" + String(repeating: "s", count: 100)

		let redacted = sut.redactingURLs(in: text)

		#expect(redacted == padding + " REDACTED" + URLRedactor.truncationMarker)
	}

	@Test
	func `keeps text within the length bound intact`() {
		let text = "open https://example.com/x?token=abc now"

		#expect(sut.redactingURLs(in: text) == "open https://example.com/x?token=REDACTED now")
	}

	@Test
	func `default sensitive keys cover the documented set`() {
		let documented: Set = ["token", "code", "password", "email", "key", "secret", "otp", "auth", "session"]

		#expect(documented.isSubset(of: URLRedactor.defaultSensitiveKeys))
	}
}
