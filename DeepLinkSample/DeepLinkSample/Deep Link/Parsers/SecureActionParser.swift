//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// Parses the sensitive links the Secure showcase opens and reports each as an alert.
///
/// - `deeplink://reset?user=<id>` must be signed (``SignedLinkMiddleware``).
/// - `deeplink://pay?amount=<value>` asks the user first (``ConfirmationMiddleware``).
/// - `deeplink://account` requires sign-in and resumes after it (``AuthenticationMiddleware``).
///
/// The parser itself trusts nothing: the middleware chain enforces each rule
/// before a link reaches it.
final class SecureActionParser: DeepLinkParser {
	typealias Route = AppRoute

	static let resetHost = "reset"
	static let paymentHost = "pay"
	static let accountHost = "account"
	static let hosts: Set<String> = [resetHost, paymentHost, accountHost]

	static let accountRoute = AppRoute.alert(.alert(title: "Account", message: "You are signed in and the account link resumed.", type: .success))

	static func resetRoute(userID: String) -> AppRoute {
		.alert(.alert(title: "Password reset", message: "Signed link verified for user \(userID).", type: .success))
	}

	static func paymentRoute(amount: String) -> AppRoute {
		.alert(.alert(title: "Payment", message: "You confirmed a payment of \(amount).", type: .info))
	}

	func parse(from url: URL) throws -> [AppRoute] {
		let deepLinkURL = try DeepLinkURL(url: url)

		switch deepLinkURL.host {
		case Self.resetHost:
			guard let userID = deepLinkURL.queryParameters["user"] else {
				throw DeepLinkError.missingRequiredParameter("user")
			}
			return [Self.resetRoute(userID: userID)]

		case Self.paymentHost:
			return [Self.paymentRoute(amount: deepLinkURL.queryParameters["amount"] ?? "an unknown amount")]

		case Self.accountHost:
			return [Self.accountRoute]

		default:
			throw DeepLinkError.routeNotFound(url)
		}
	}
}
