//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

// MARK: - Delegate Notifications

extension DeepLinkCoordinator {
	/// Notifies the delegate that processing will begin.
	///
	/// - Parameter url: The URL that will be processed
	func notifyDelegateWillProcess(_ url: URL) async {
		guard let delegate else { return }

		await delegate.coordinator(self, willProcess: url)
	}

	/// Notifies the delegate that processing has completed.
	///
	/// - Parameters:
	///   - url: The URL that was processed
	///   - result: The result of the processing
	func notifyDelegateDidProcess(_ url: URL, result: DeepLinkResult<Route>) async {
		guard let delegate else { return }

		await delegate.coordinator(self, didProcess: url, result: result)
	}

	/// Notifies the delegate that processing has failed.
	///
	/// - Parameters:
	///   - url: The URL that failed to process
	///   - error: The error that caused the failure
	func notifyDelegateDidFailProcessing(_ url: URL, error: Error) async {
		guard let delegate else { return }

		await delegate.coordinator(self, didFailProcessing: url, error: error)
	}
}
