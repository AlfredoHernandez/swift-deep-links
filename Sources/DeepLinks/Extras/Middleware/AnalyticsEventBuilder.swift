//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Builds the shared analytics-parameter envelope used by both
/// ``DeepLinkAnalyticsDelegate`` and ``AnalyticsStrategy``.
///
/// Keeping the scheme / host / timestamp / url / path assembly in one place
/// prevents the two surfaces from drifting on key names and default values
/// (e.g. `"unknown"` vs `""` for a missing host) as new strategies or
/// delegate events are added.
enum AnalyticsEventBuilder {
	/// How much URL detail to include in the generated parameters.
	enum URLDetail {
		/// `scheme` + `host` only. Used by the privacy-oriented `.minimal`
		/// analytics strategy.
		case hostOnly
		/// `url` + `scheme` + `host`. Used by the default `.standard`
		/// strategy.
		case withURL
		/// `url` + `scheme` + `host` + `path`. The `path` key is always
		/// present, even when the URL's path is empty. Used by every
		/// ``DeepLinkAnalyticsDelegate`` lifecycle event.
		case full
		/// Same as ``full`` but omits `path` when the URL has no path
		/// segment. Used by the `.detailed` ``AnalyticsStrategy`` so
		/// privacy-sensitive analytics dashboards never see a `"path": ""`
		/// that could be confused with an intentional empty value.
		case fullOmittingEmptyPath
	}

	/// Assembles the shared parameter envelope for an analytics event.
	///
	/// - Parameters:
	///   - url: The URL the event is about.
	///   - detail: How much URL detail the caller wants to include. See
	///     ``URLDetail`` for the concrete key set emitted per case.
	/// - Returns: A parameter dictionary that callers can extend with
	///   event-specific keys before passing to ``AnalyticsProvider/track(_:parameters:)``.
	static func parameters(for url: URL, detail: URLDetail) -> [String: Any] {
		var parameters: [String: Any] = [
			"scheme": url.scheme ?? "unknown",
			"host": url.host() ?? "unknown",
			"timestamp": Date().timeIntervalSince1970,
		]
		switch detail {
		case .hostOnly:
			break

		case .withURL:
			parameters["url"] = url.absoluteString

		case .full:
			parameters["url"] = url.absoluteString
			parameters["path"] = url.path

		case .fullOmittingEmptyPath:
			parameters["url"] = url.absoluteString
			if !url.path.isEmpty {
				parameters["path"] = url.path
			}
		}
		return parameters
	}
}
