//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation
import os

/// Sample authentication provider for demonstration purposes.
///
/// This provider simulates authentication state for testing deep link functionality.
/// In a real application, this would integrate with your actual authentication system
/// to verify user login status and permissions.
///
/// ## Features:
/// - Simulated authentication state management
/// - Synchronous authentication checking
/// - Thread-safe state mutations via `OSAllocatedUnfairLock`
///
/// ## Usage:
/// ```swift
/// let authProvider = SampleAuthenticationProvider()
/// let isAuthenticated = authProvider.isAuthenticated()
///
/// // For testing
/// authProvider.toggleAuthentication()
/// ```
final class SampleAuthenticationProvider: AuthenticationProvider, Sendable {
	// MARK: - Private Properties

	private let state = OSAllocatedUnfairLock(initialState: true)

	// MARK: - Public Interface

	/// Checks if the user is currently authenticated.
	///
	/// - Returns: `true` if the user is authenticated, `false` otherwise
	func isAuthenticated() -> Bool {
		state.withLock { $0 }
	}

	/// Toggles the authentication state for testing purposes.
	func toggleAuthentication() {
		state.withLock { $0.toggle() }
	}

	/// Sets the authentication state to a specific value.
	///
	/// - Parameter authenticated: The desired authentication state
	func setAuthentication(_ authenticated: Bool) {
		state.withLock { $0 = authenticated }
	}

	/// Gets the current authentication state without async delay.
	///
	/// - Returns: The current authentication state
	func getCurrentState() -> Bool {
		state.withLock { $0 }
	}
}
