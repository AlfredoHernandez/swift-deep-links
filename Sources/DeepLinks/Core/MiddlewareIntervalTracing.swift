//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import OSLog

/// Opens one timing interval per middleware invocation.
protocol MiddlewareIntervalTracing: Sendable {
	func beginInterval(named name: String) -> any MiddlewareInterval
}

/// An open interval, closed exactly once when its middleware returns or throws.
protocol MiddlewareInterval {
	func end()
}

/// Emits an `os_signpost` interval named `Middleware` per middleware, labelled
/// with the middleware's type name only, so URLs never reach Instruments.
struct SignpostMiddlewareTracing: MiddlewareIntervalTracing {
	static let intervalName: StaticString = "Middleware"

	private let signposter = OSSignposter(subsystem: "swift-deep-links", category: "Middleware")

	func beginInterval(named name: String) -> any MiddlewareInterval {
		let state = signposter.beginInterval(Self.intervalName, id: signposter.makeSignpostID(), "\(name, privacy: .public)")
		return SignpostInterval(signposter: signposter, state: state)
	}
}

private struct SignpostInterval: MiddlewareInterval {
	let signposter: OSSignposter
	let state: OSSignpostIntervalState

	func end() {
		signposter.endInterval(SignpostMiddlewareTracing.intervalName, state)
	}
}
