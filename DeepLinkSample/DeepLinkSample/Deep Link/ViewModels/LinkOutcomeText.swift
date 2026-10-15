//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A one-line, redacted explanation of what happened to a deep link.
enum LinkOutcomeText {
	static func describe(_ result: DeepLinkResult<AppRoute>?) -> String {
		guard let result else { return "Deep links are unavailable." }
		if result.wasSuccessful {
			return "Opened."
		}
		guard let error = result.firstError else {
			return "Stopped quietly: opened again within the replay window, or queued until the app is ready."
		}
		return describe(error)
	}

	private static func describe(_ error: any Error) -> String {
		guard let deepLinkError = error as? DeepLinkError else {
			return "Failed: \(DeepLinkLogPrivacy.redacted.describe(error))"
		}
		if let reason = deepLinkError.securityViolationReason {
			return "Rejected by a security check: \(reason)."
		}
		switch deepLinkError {
		case .unauthorizedAccess:
			return "Rejected: sign in first. The link is saved and resumes after sign-in."

		case .confirmationDenied:
			return "You declined the link."

		case .rateLimitExceeded:
			return "Rejected: too many links in a short time."

		default:
			return "Failed: \(deepLinkError.redactedDescription)"
		}
	}
}
