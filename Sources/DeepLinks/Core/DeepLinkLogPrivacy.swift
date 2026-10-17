//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// How framework log messages, analytics events and console output describe
/// URLs and errors.
///
/// Every built-in site defaults to ``redacted``: URLs pass through
/// ``URLRedactor``, framework errors use ``DeepLinkError/redactedDescription``,
/// and other errors are described by their type name only. Plain path
/// segments (`/reset/<token>`) are not redacted; see ``URLRedactor``. Use
/// ``unredacted`` only while debugging, because deep links can carry tokens,
/// codes and e-mail addresses.
public struct DeepLinkLogPrivacy: Sendable {
	/// Redacts with the default ``URLRedactor``.
	public static let redacted = DeepLinkLogPrivacy(redactor: URLRedactor())

	/// Emits full URLs, ``DeepLinkError/unredactedDescription`` for framework
	/// errors and `localizedDescription` for others. For debugging only.
	public static let unredacted = DeepLinkLogPrivacy(redactor: nil)

	let redactor: URLRedactor?

	/// Redacts with a custom redactor.
	///
	/// - Parameter redactor: The redactor applied to URLs and error text.
	/// - Returns: A redacting privacy setting.
	public static func redacted(using redactor: URLRedactor) -> DeepLinkLogPrivacy {
		DeepLinkLogPrivacy(redactor: redactor)
	}

	/// `url` with sensitive values replaced, or unchanged when unredacted.
	public func redact(_ url: URL) -> URL {
		redactor?.redact(url) ?? url
	}

	/// The absolute string of ``redact(_:)``.
	public func describe(_ url: URL) -> String {
		redact(url).absoluteString
	}

	/// A description of `error` safe for logs: ``DeepLinkError/redactedDescription(using:)``
	/// for framework errors and the type name for any other error; when
	/// unredacted, ``DeepLinkError/unredactedDescription`` or `localizedDescription`.
	public func describe(_ error: any Error) -> String {
		guard let redactor else { return DeepLinkError.unredactedDescription(of: error) }
		return DeepLinkError.redactedDescription(of: error, using: redactor)
	}

	/// `text` with every embedded `scheme://` URL redacted, or unchanged when unredacted.
	public func redactingURLs(in text: String) -> String {
		redactor?.redactingURLs(in: text) ?? text
	}
}
