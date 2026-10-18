//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct URLNormalizationDotSegmentTests {
	private let sut = URLNormalizationTransformer()

	@Test(arguments: [
		("myapp://host/a/./b", "/a/b"),
		("myapp://host/a/b/../c", "/a/c"),
		("myapp://host/a/b/c/../../d", "/a/d"),
		("myapp://host/./a", "/a"),
		("myapp://host/a/b/..", "/a"),
		("myapp://host/a/b/.", "/a/b"),
		("myapp://host/a/b/../", "/a"),
	])
	func `resolves dot segments within the path`(rawURL: String, expectedPath: String) throws {
		let url = try #require(URL(string: rawURL))

		let result = try sut.transform(url)

		#expect(result.path == expectedPath)
		#expect(result.host == "host")
	}

	@Test(arguments: [
		("myapp://host/../../etc/passwd", "/etc/passwd"),
		("myapp://host/a/../../../b", "/b"),
		("myapp://host/..", ""),
		("myapp://host/../..", ""),
	])
	func `never resolves above the root`(rawURL: String, expectedPath: String) throws {
		let url = try #require(URL(string: rawURL))

		let result = try sut.transform(url)

		#expect(result.path == expectedPath)
		#expect(result.host == "host")
	}

	@Test
	func `resolves percent-encoded dot segments`() throws {
		let url = try #require(URL(string: "myapp://host/a/%2e%2e/%2E/b"))

		let result = try sut.transform(url)

		#expect(result.path == "/b")
	}

	@Test(arguments: ["/a/..b/c", "/a/b../c", "/a/.../c", "/a/.hidden/c"])
	func `keeps segments that merely contain dots`(path: String) throws {
		let url = try #require(URL(string: "myapp://host\(path)"))

		let result = try sut.transform(url)

		#expect(result.path == path)
	}

	@Test
	func `leaves dot segments in the query and fragment untouched`() throws {
		let url = try #require(URL(string: "myapp://host/a?next=../b#../c"))

		let result = try sut.transform(url)

		#expect(result.path == "/a")
		#expect(result.query == "next=../b")
		#expect(result.fragment == "../c")
	}

	@Test
	func `preserves interior empty segments as before`() throws {
		let url = try #require(URL(string: "myapp://host/a//b"))

		let result = try sut.transform(url)

		#expect(result.path == "/a//b")
	}

	@Test
	func `still strips empty query values while resolving dot segments`() throws {
		let url = try #require(URL(string: "myapp://host/a/../b?keep=1&drop="))

		let result = try sut.transform(url)

		#expect(result.path == "/b")
		#expect(result.query == "keep=1")
	}
}

struct URLNormalizationEncodedSeparatorTests {
	private let sut = URLNormalizationTransformer()

	@Test
	func `percent-encoded slashes become separators before dot segments resolve`() throws {
		let url = try #require(URL(string: "myapp://host/a%2F..%2Fb"))

		let result = try sut.transform(url)

		#expect(result.path == "/b")
		#expect(result.absoluteString == "myapp://host/b")
	}

	@Test
	func `encoded traversal cannot climb above the root through encoded slashes`() throws {
		let url = try #require(URL(string: "myapp://host/public%2F..%2F..%2F..%2Fadmin"))

		let result = try sut.transform(url)

		#expect(result.absoluteString == "myapp://host/admin")
	}

	@Test
	func `backslashes are not separators and stay inside their segment`() throws {
		let url = try #require(URL(string: "myapp://host/a%5C..%5Cb/c"))

		let result = try sut.transform(url)

		#expect(result.path == "/a\\..\\b/c")
		#expect(result.absoluteString == "myapp://host/a%5C..%5Cb/c")
	}

	@Test
	func `a backslash dot-dot segment is not resolved`() throws {
		let url = try #require(URL(string: "myapp://host/a/..%5C/b"))

		let result = try sut.transform(url)

		#expect(result.path == "/a/..\\/b")
	}
}
