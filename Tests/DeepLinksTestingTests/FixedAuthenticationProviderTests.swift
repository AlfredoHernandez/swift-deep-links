//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

struct FixedAuthenticationProviderTests {
	@Test
	func `returns true when configured as authenticated`() {
		let sut = FixedAuthenticationProvider(isAuthenticated: true)

		#expect(sut.isAuthenticated())
	}

	@Test
	func `returns false when configured as unauthenticated`() {
		let sut = FixedAuthenticationProvider(isAuthenticated: false)

		#expect(!sut.isAuthenticated())
	}
}
