//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Drops the second delivery of a web link that SwiftUI hands to both
/// `onOpenURL` and `onContinueUserActivity` for one tap.
///
/// A web link delivered by one callback and then by the other within
/// ``defaultWindow`` seconds is suppressed once. Repeats through the same
/// callback (a double tap) are left to ``ReplayProtectionMiddleware``, and
/// custom-scheme links, which only `onOpenURL` receives, always pass.
@MainActor
final class LinkDeliveryDeduplicator {
	enum Channel {
		case openURL
		case userActivity
	}

	static let defaultWindow: TimeInterval = 1

	private let window: TimeInterval
	private let dateProvider: @Sendable () -> Date
	private var recent: [URL: (channel: Channel, at: Date)] = [:]

	init(window: TimeInterval = LinkDeliveryDeduplicator.defaultWindow, dateProvider: @Sendable @escaping () -> Date = Date.init) {
		self.window = window
		self.dateProvider = dateProvider
	}

	func shouldDeliver(_ url: URL, via channel: Channel) -> Bool {
		guard ["http", "https"].contains(url.scheme?.lowercased()) else { return true }
		let now = dateProvider()
		recent = recent.filter { _, delivery in
			let age = now.timeIntervalSince(delivery.at)
			return age >= 0 && age < window
		}
		if let earlier = recent[url], earlier.channel != channel {
			recent[url] = nil
			return false
		}
		recent[url] = (channel, now)
		return true
	}
}
