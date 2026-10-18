//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct PendingLinkStoreTests {
	enum Kind: CaseIterable, CustomTestStringConvertible {
		case inMemory
		case userDefaults

		var testDescription: String {
			switch self {
			case .inMemory: "in-memory"

			case .userDefaults: "UserDefaults"
			}
		}
	}

	private let cleanup = UserDefaultsSuiteCleanup()

	// MARK: - Contract

	@Test(arguments: Kind.allCases)
	func `take all returns saved links once`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind)
		await sut.save(link("a"))

		#expect(await sut.takeAll() == [link("a")])
		#expect(await sut.takeAll() == [])
	}

	@Test(arguments: Kind.allCases)
	func `links come back oldest first`(kind: Kind) async throws {
		let (sut, clock) = try makeSUT(kind, maxCount: 3)
		await sut.save(link("a"))
		clock.advance(by: 1)
		await sut.save(link("b"))

		#expect(await sut.takeAll() == [link("a"), link("b")])
	}

	@Test(arguments: Kind.allCases)
	func `max count evicts the oldest link`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind, maxCount: 2)
		for name in ["a", "b", "c"] {
			await sut.save(link(name))
		}

		#expect(await sut.takeAll() == [link("b"), link("c")])
	}

	@Test(arguments: Kind.allCases)
	func `saving a link again keeps one copy as the newest`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind, maxCount: 3)
		await sut.save(link("a"))
		await sut.save(link("b"))
		await sut.save(link("a"))

		#expect(await sut.takeAll() == [link("b"), link("a")])
	}

	@Test(arguments: Kind.allCases)
	func `expired links are discarded`(kind: Kind) async throws {
		let (sut, clock) = try makeSUT(kind, maxCount: 3, expiry: 60)
		await sut.save(link("old"))
		clock.advance(by: 30)
		await sut.save(link("fresh"))

		clock.advance(by: 30)

		#expect(await sut.takeAll() == [link("fresh")])
	}

	@Test(arguments: Kind.allCases)
	func `links saved in the future after a clock rollback are discarded`(kind: Kind) async throws {
		let (sut, clock) = try makeSUT(kind, expiry: 60)
		await sut.save(link("a"))

		clock.advance(by: -3600)

		#expect(await sut.takeAll() == [])
	}

	@Test(arguments: Kind.allCases)
	func `negative expiry expires links immediately`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind, expiry: -1)
		await sut.save(link("a"))

		#expect(await sut.takeAll() == [])
	}

	@Test(arguments: Kind.allCases)
	func `remove all discards every link`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind, maxCount: 3)
		await sut.save(link("a"))
		await sut.save(link("b"))

		await sut.removeAll()

		#expect(await sut.takeAll() == [])
	}

	@Test(arguments: Kind.allCases)
	func `max count below one keeps a single link`(kind: Kind) async throws {
		let (sut, _) = try makeSUT(kind, maxCount: 0)
		await sut.save(link("a"))
		await sut.save(link("b"))

		#expect(await sut.takeAll() == [link("b")])
	}

	// MARK: - UserDefaults

	@Test
	func `user defaults links survive a new store instance`() async throws {
		let suiteName = makeSuiteName()
		let clock = ManualDateProvider()
		try await UserDefaultsPendingLinkStore(userDefaults: defaults(suiteName), key: "pending", dateProvider: clock.dateProvider).save(link("a"))

		let reopened = try UserDefaultsPendingLinkStore(userDefaults: defaults(suiteName), key: "pending", dateProvider: clock.dateProvider)

		#expect(await reopened.takeAll() == [link("a")])
	}

	@Test
	func `user defaults persists only the URL, the save time and the context`() async throws {
		let suiteName = makeSuiteName()
		var context = DeepLinkContext(source: .notification, sourceApplication: "com.example", sceneID: "scene")
		context.signatureVerifiedURL = link("a")
		try await UserDefaultsPendingLinkStore(userDefaults: defaults(suiteName), key: "pending")
			.save(DeepLinkRequest(url: link("a"), context: context))

		let data = try #require(defaults(suiteName).data(forKey: "pending"))
		let entries = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
		let storedContext = try #require(entries.first?["context"] as? [String: Any])

		#expect(entries.map { Set($0.keys) } == [["url", "savedAt", "context"]])
		#expect(Set(storedContext.keys) == ["version", "source", "sourceApplication", "sceneID"])
	}

	@Test
	func `user defaults treats corrupt data as empty`() async throws {
		let suiteName = makeSuiteName()
		try defaults(suiteName).set(Data("not json".utf8), forKey: "pending")

		let sut = try UserDefaultsPendingLinkStore(userDefaults: defaults(suiteName), key: "pending")

		#expect(await sut.takeAll() == [])
	}

	// MARK: - Helpers

	private func makeSUT(
		_ kind: Kind,
		maxCount: Int = 1,
		expiry: TimeInterval = 300,
	) throws -> (sut: any PendingLinkStore, clock: ManualDateProvider) {
		let clock = ManualDateProvider()
		switch kind {
		case .inMemory:
			return (InMemoryPendingLinkStore(maxCount: maxCount, expiry: expiry, dateProvider: clock.dateProvider), clock)

		case .userDefaults:
			let store = try UserDefaultsPendingLinkStore(
				userDefaults: defaults(makeSuiteName()),
				key: "pending",
				maxCount: maxCount,
				expiry: expiry,
				dateProvider: clock.dateProvider,
			)
			return (store, clock)
		}
	}

	private func makeSuiteName() -> String {
		let suiteName = "test.pending.\(UUID().uuidString)"
		cleanup.track(suiteName)
		return suiteName
	}

	private func defaults(_ suiteName: String) throws -> UserDefaults {
		try #require(UserDefaults(suiteName: suiteName))
	}

	private func link(_ name: String) -> URL {
		URL(string: "myapp://account/\(name)")!
	}
}
