//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct SampleDiagnosticsTests {
	@Test
	func `The sample configuration produces no diagnostic warnings`() async {
		let service = DeepLinkService(
			handler: CollectingHandler<AppRoute>(),
			confirmationProvider: CollectingConfirmation(approves: true),
			rateLimitPersistence: InMemoryRateLimitPersistence(),
			delegates: [],
		)

		let warnings = await service.diagnosticWarnings()

		#expect(warnings.isEmpty, "\(warnings)")
	}

	@Test
	func `Every allowed scheme is declared in Info.plist`() {
		let declared = DeepLinkDiagnostics.declaredURLSchemes(inInfoDictionary: Bundle.main.infoDictionary)

		#expect(DeepLinkService.allowedSchemes.isSubset(of: declared))
	}
}
