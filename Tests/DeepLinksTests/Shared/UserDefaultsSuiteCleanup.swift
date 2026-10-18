//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// Tracks `UserDefaults` suite names created during a test and removes their
/// persistent domains on `deinit`.
///
/// Swift Testing creates a fresh suite-type instance per `@Test`, so holding
/// one of these as a stored property gives you per-test teardown without a
/// traditional `tearDown()` hook: when the test finishes, the suite instance
/// is released, and this object's `deinit` runs and calls
/// `removePersistentDomain(forName:)` for every tracked suite name.
///
/// ## Usage
///
/// ```swift
/// struct MyTests {
///     private let cleanup = UserDefaultsSuiteCleanup()
///
///     @Test
///     func example() throws {
///         let suiteName = "test.\(UUID().uuidString)"
///         cleanup.track(suiteName)
///         let defaults = try #require(UserDefaults(suiteName: suiteName))
///         // ...
///     }
/// }
/// ```
final class UserDefaultsSuiteCleanup: @unchecked Sendable {
	private let lock = NSLock()
	private var suiteNames: Set<String> = []

	init() {}

	/// Registers a suite name so it will be cleared when this tracker
	/// is deinitialized. Safe to call multiple times with the same name.
	func track(_ suiteName: String) {
		lock.lock()
		defer { lock.unlock() }
		suiteNames.insert(suiteName)
	}

	deinit {
		// `deinit` runs on the thread that releases this object; `UserDefaults`
		// is documented as thread-safe for these operations.
		for name in suiteNames {
			UserDefaults.standard.removePersistentDomain(forName: name)
		}
	}
}
