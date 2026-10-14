//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Reads the deep link URL out of a notification, shortcut or Spotlight
/// payload. Only an absolute URL with a scheme is accepted; nothing else in
/// the payload is read.
enum DeepLinkPayloadURL {
	static func url(from payload: [AnyHashable: Any]?, key: String) -> URL? {
		switch payload?[key] {
		case let url as URL:
			absolute(url)

		case let string as String:
			URL(string: string).flatMap(absolute)

		default:
			nil
		}
	}

	static func shortcutURL(type: String, userInfo: [String: any NSSecureCoding]?, key: String) -> URL? {
		url(from: userInfo, key: key) ?? URL(string: type).flatMap(absolute)
	}

	static func absolute(_ url: URL) -> URL? {
		guard let scheme = url.scheme, !scheme.isEmpty else { return nil }
		return url
	}
}
