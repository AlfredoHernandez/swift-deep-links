//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

@Suite("FixedAuthenticationProvider")
struct FixedAuthenticationProviderTests {
	@Test("returns true when configured as authenticated")
	func isAuthenticated_returnsTrueWhenAuthenticated() {
		let sut = FixedAuthenticationProvider(isAuthenticated: true)

		#expect(sut.isAuthenticated())
	}

	@Test("returns false when configured as unauthenticated")
	func isAuthenticated_returnsFalseWhenUnauthenticated() {
		let sut = FixedAuthenticationProvider(isAuthenticated: false)

		#expect(!sut.isAuthenticated())
	}
}
