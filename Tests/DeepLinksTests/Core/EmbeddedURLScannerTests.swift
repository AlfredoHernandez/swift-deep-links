//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct EmbeddedURLScannerTests {
	private static let hugeLength = 100_000

	@Test(arguments: [
		("open https://example.com/a?b=c now", ["https://example.com/a?b=c"]),
		("'myapp://x' and \"web+app://y\"", ["myapp://x", "web+app://y"]),
		("1abc://host", ["abc://host"]),
		("+x.y-z://h", ["x.y-z://h"]),
		("a:// b://c", ["b://c"]),
		("no urls here: just text", []),
		("https://a.com/x://y <tail>", ["https://a.com/x://y"]),
	])
	func `finds every embedded scheme URL`(text: String, expected: [String]) {
		var sut = EmbeddedURLScanner()

		let found = sut.urlRanges(in: text).map { String(text.unicodeScalars[$0]) }

		#expect(found == expected)
	}

	@Test(arguments: [
		String(repeating: "a", count: hugeLength),
		String(repeating: "ab:", count: hugeLength / 3),
		String(repeating: "ab:/", count: hugeLength / 4),
		"Security violation: Unauthorized host: " + String(repeating: "x", count: hugeLength),
	])
	func `inspects each character a bounded number of times`(text: String) {
		var sut = EmbeddedURLScanner()

		_ = sut.urlRanges(in: text)

		#expect(sut.inspectedScalarCount <= 3 * text.unicodeScalars.count)
	}
}
