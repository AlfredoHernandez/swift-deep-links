//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct LogInjectionTests {
	@Test(arguments: [
		("a\nb", "a\\nb"),
		("a\r\nb", "a\\r\\nb"),
		("tab\there", "tab\\there"),
		("nul\u{0}x", "nul\\u{0}x"),
		("esc\u{1B}[31m", "esc\\u{1B}[31m"),
		("line\u{2028}sep", "line\\u{2028}sep"),
		("plain text: ok", "plain text: ok"),
		("back\\slash", "back\\slash"),
	])
	func `control characters are escaped onto one line`(text: String, expected: String) {
		#expect(LogEscaping.singleLine(text) == expected)
	}

	@Test
	func `logged components escape decoded control characters`() throws {
		let components = try DeepLinkComponents(from: #require(URL(string: "myapp://host/a%0Ab?x=1%0D%0AINFO%20forged&y%0A=2")))

		#expect(components.path == "/a\\nb")
		#expect(components.queryParametersString == "x=1\\r\\nINFO forged&y\\n=2")
	}

	@Test
	func `redacted free text stays on one line`() {
		#expect(URLRedactor().redactingURLs(in: "first\nINFO forged https://e.com/?token=1") == "first\\nINFO forged https://e.com/?token=REDACTED")
	}

	@Test(arguments: [
		DeepLinkError.unsupportedHost("evil\nINFO forged"),
		.unsupportedScheme("x\r\ny"),
		.missingRequiredParameter("p\nq"),
		.invalidParameterValue(name: "n\nm", value: "v"),
		.handlerError(message: "failed\nINFO forged", underlyingError: nil),
		.securityViolation("reason\nINFO forged"),
	])
	func `redacted error descriptions stay on one line`(error: DeepLinkError) {
		let lineBreaks = error.redactedDescription.filter(\.isNewline)

		#expect(lineBreaks.isEmpty)
	}

	@Test
	func `single-line logging middleware writes one line for a link with encoded newlines`() async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, logLevel: .info, format: .singleLine)

		_ = try await sut.intercept(url: #require(URL(string: "myapp://host/p%0Aq?x=1%0AINFO%20forged")))

		let linesWithBreaks = messages.all.filter { $0.contains(where: \.isNewline) }

		#expect(!messages.all.isEmpty)
		#expect(linesWithBreaks.isEmpty)
	}
}
