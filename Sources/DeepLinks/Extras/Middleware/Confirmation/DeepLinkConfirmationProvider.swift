//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// What ``ConfirmationMiddleware`` asks the user to confirm.
public struct DeepLinkConfirmationRequest: Sendable, Hashable {
	/// The link with sensitive values redacted, safe to show in the prompt.
	public var url: URL

	/// Where the link came from, for example to warn about links opened by another app.
	public var context: DeepLinkContext

	/// Creates a confirmation request.
	public init(url: URL, context: DeepLinkContext) {
		self.url = url
		self.context = context
	}
}

/// Asks the user whether to continue with a sensitive deep link.
///
/// Implemented by the app, typically by presenting an alert:
///
/// ```swift
/// @MainActor
/// final class AlertConfirmation: DeepLinkConfirmationProvider {
///     private var pending: CheckedContinuation<Bool, Never>?
///
///     func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
///         await withTaskCancellationHandler {
///             await withCheckedContinuation { continuation in
///                 pending = continuation
///                 presentAlert(for: request) { approved in self.finish(approved) }
///             }
///         } onCancel: {
///             Task { @MainActor in self.finish(false) }  // timeout or cancelled link
///         }
///     }
///
///     private func finish(_ approved: Bool) {
///         dismissAlert()
///         pending?.resume(returning: approved)
///         pending = nil
///     }
/// }
/// ```
///
/// When the middleware's timeout fires, or the link's task is cancelled, the
/// link is denied immediately and the task running `confirm` is cancelled:
/// dismiss the prompt and resume with `false`. The middleware does not wait
/// for a provider that ignores cancellation, but its prompt stays on screen
/// and its task keeps running until it answers.
public protocol DeepLinkConfirmationProvider: Sendable {
	/// Returns `true` when the user approves the link.
	///
	/// - Parameter request: The redacted link and its context.
	/// - Returns: The user's decision; `false` stops the link.
	func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool
}
