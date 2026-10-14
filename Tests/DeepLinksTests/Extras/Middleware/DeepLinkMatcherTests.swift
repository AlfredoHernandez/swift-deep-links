//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct DeepLinkMatcherTests {
	@Test
	func `all matches every request`() {
		#expect(DeepLinkMatcher.all.matches(request("myapp://anything")))
	}

	@Test
	func `hosts match case-insensitively and ignore a trailing dot`() {
		let sut = DeepLinkMatcher.hosts(["Pay.Example.com"])

		#expect(sut.matches(request("https://PAY.example.COM/confirm")))
		#expect(sut.matches(request("https://pay.example.com./confirm")))
		#expect(!sut.matches(request("https://example.com/confirm")))
	}

	@Test(arguments: [
		"https://example.com/reset",
		"https://example.com/reset/",
		"https://example.com/reset/abc",
		"https://example.com/RESET/abc",
		"https://example.com/%72eset",
		"https://example.com/%2572eset",
		"https://example.com/a/../reset",
	])
	func `paths match the prefix through case, encoding and dot segments`(link: String) {
		#expect(DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test(arguments: [
		"https://example.com/resetting",
		"https://example.com/other/reset",
		"https://example.com",
	])
	func `paths match only on segment boundaries`(link: String) {
		#expect(!DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test(arguments: [
		"https://example.com/reset%FF",
		"https://example.com/%FF/other",
		"https://example.com/a/%C0%AE%C0%AE/reset",
		"https://example.com/%25252525252e",
	])
	func `paths match undecodable or over-nested paths so they fail closed`(link: String) {
		#expect(DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test(arguments: [
		"https://example.com//reset",
		"https://example.com/a//..//reset",
		"myapp:reset",
		"myapp:reset/abc",
		"https://example.com/reset;jsessionid=1",
		"https://example.com/reset;v=1/abc",
		"https://example.com/a/..%5Creset",
		"https://example.com/reset%5Cabc",
		"https://example.com/re%E2%80%8Bset",
		"https://example.com/%E2%80%AEreset",
	])
	func `paths see through empty segments, opaque paths, matrix parameters, backslashes and invisible characters`(link: String) {
		#expect(DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test(arguments: URLFuzzCorpus.hostile(.traversal) + URLFuzzCorpus.hostile(.encoding) + URLFuzzCorpus.hostile(.controlCharacters)
		.filter { $0.url.path(percentEncoded: true).contains("min") })
	func `paths protect the admin prefix against every hostile path spelling`(fuzzCase: URLFuzzCase) {
		#expect(DeepLinkMatcher.paths(["/admin"]).matches(DeepLinkRequest(url: fuzzCase.url)))
	}

	@Test
	func `paths evaluate the whole hostile corpus without crashing`() {
		let sut = DeepLinkMatcher.paths(["/reset"])

		for fuzzCase in URLFuzzCorpus.hostile() {
			_ = sut.matches(DeepLinkRequest(url: fuzzCase.url))
		}
	}

	@Test(arguments: ["myapp://reset", "myapp://reset?user=42", "myapp://RESET/abc", "myapp://reset./abc"])
	func `paths treat a custom-scheme host as the first path segment`(link: String) {
		#expect(DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test(arguments: ["https://reset/abc", "http://reset", "myapp://home/abc"])
	func `web hosts are never treated as path segments`(link: String) {
		#expect(!DeepLinkMatcher.paths(["/reset"]).matches(request(link)))
	}

	@Test
	func `paths accept prefixes without a leading slash`() {
		#expect(DeepLinkMatcher.paths(["reset/"]).matches(request("https://example.com/reset/abc")))
	}

	@Test
	func `root path prefix matches every path`() {
		#expect(DeepLinkMatcher.paths(["/"]).matches(request("myapp://host")))
	}

	@Test
	func `sources match the request context`() {
		let sut = DeepLinkMatcher.sources([.customScheme])

		#expect(sut.matches(request("myapp://x", source: .customScheme)))
		#expect(!sut.matches(request("myapp://x", source: .universalLink)))
	}

	@Test
	func `anyOf matches when one matcher matches`() {
		let sut = DeepLinkMatcher.anyOf(.hosts(["reset"]), .paths(["/pay"]))

		#expect(sut.matches(request("myapp://reset/1")))
		#expect(sut.matches(request("https://example.com/pay")))
		#expect(!sut.matches(request("https://example.com/home")))
	}

	@Test
	func `allOf matches only when every matcher matches`() {
		let sut = DeepLinkMatcher.allOf(.hosts(["example.com"]), .paths(["/pay"]))

		#expect(sut.matches(request("https://example.com/pay")))
		#expect(!sut.matches(request("https://other.com/pay")))
	}

	@Test
	func `custom matcher receives the request`() {
		let sut = DeepLinkMatcher.custom { $0.context.sceneID == "scene-1" }

		#expect(sut.matches(DeepLinkRequest(url: url("myapp://x"), context: DeepLinkContext(sceneID: "scene-1"))))
		#expect(!sut.matches(request("myapp://x")))
	}
}

private func request(_ string: String, source: DeepLinkContext.Source = .unknown) -> DeepLinkRequest {
	DeepLinkRequest(url: url(string), context: DeepLinkContext(source: source))
}

private func url(_ string: String) -> URL {
	URL(string: string)!
}
