//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation

/// Drives the Secure screen: a signed link, a confirmation prompt, resume
/// after sign-in and, in debug builds, a configuration check.
@Observable
final class SecureShowcaseViewModel {
	private let service: DeepLinkService
	private let coordinator: DeepLinkCoordinator<AppRoute>?
	private var lastSignedLink: URL?

	/// What happened to the last link this screen opened.
	private(set) var outcome: String?
	private(set) var isSignedIn: Bool

	/// `nil` until the check has run.
	private(set) var diagnosticMessages: [String]?

	var canReopenSignedLink: Bool {
		lastSignedLink != nil
	}

	init(service: DeepLinkService, coordinator: DeepLinkCoordinator<AppRoute>?) {
		self.service = service
		self.coordinator = coordinator
		isSignedIn = service.authenticationProvider.isAuthenticated()
	}

	// MARK: - Signed Links

	func openSignedResetLink() async {
		do {
			let link = try service.signedResetLink(userID: "42")
			lastSignedLink = link
			await open(link)
		} catch {
			outcome = "Could not sign the link: \(DeepLinkLogPrivacy.redacted.describe(error))"
		}
	}

	func reopenSignedLink() async {
		guard let lastSignedLink else { return }
		await open(lastSignedLink)
	}

	func openUnsignedResetLink() async {
		await open("deeplink://reset?user=42")
	}

	// MARK: - Confirmation

	func openPaymentLink() async {
		await open("deeplink://pay?amount=25")
	}

	// MARK: - Resume After Sign-In

	func openAccountLink() async {
		await open("deeplink://account")
	}

	func signIn() async {
		service.authenticationProvider.setAuthentication(true)
		isSignedIn = true
		let resumed = await coordinator?.resumePendingLinks(from: service.pendingLinks) ?? []
		outcome = resumed.last.map(LinkOutcomeText.describe) ?? "Signed in. No link was waiting."
	}

	func signOut() async {
		service.authenticationProvider.setAuthentication(false)
		isSignedIn = false
		await service.pendingLinks.removeAll()
		outcome = "Signed out."
	}

	// MARK: - Diagnostics

	#if DEBUG
	func runDiagnostics() async {
		let warnings = await service.diagnosticWarnings()
		diagnosticMessages = warnings.map(\.description)
	}
	#endif
}

// MARK: - Private Methods

private extension SecureShowcaseViewModel {
	func open(_ string: String) async {
		guard let url = URL(string: string) else { return }
		await open(url)
	}

	func open(_ url: URL) async {
		let result = await coordinator?.handle(url: url, context: .openedURL(url))
		outcome = LinkOutcomeText.describe(result)
	}
}
