//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

/// Sample authentication provider for demonstration purposes.
///
/// This provider simulates authentication state for testing deep link functionality.
/// In a real application, this would integrate with your actual authentication system
/// to verify user login status and permissions.
///
/// ## Features:
/// - Simulated authentication state management
/// - Async authentication checking
/// - Testing utilities for toggling auth state
///
/// ## Usage:
/// ```swift
/// let authProvider = SampleAuthenticationProvider()
/// let isAuthenticated = await authProvider.isAuthenticated()
///
/// // For testing
/// authProvider.toggleAuthentication()
/// ```
final class SampleAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    // MARK: - Private Properties

    /// Simulates authentication state - in a real app, this would check actual auth status
    private var isUserAuthenticated = true

    // MARK: - Public Interface

    /// Checks if the user is currently authenticated.
    ///
    /// This method simulates an async authentication check with a small delay
    /// to mimic real-world authentication service calls.
    ///
    /// - Returns: `true` if the user is authenticated, `false` otherwise
    func isAuthenticated() async -> Bool {
        // Simulate async authentication check
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        return isUserAuthenticated
    }

    /// Toggles the authentication state for testing purposes.
    ///
    /// This method is useful for testing protected deep link scenarios
    /// where authentication state affects the processing flow.
    func toggleAuthentication() {
        isUserAuthenticated.toggle()
    }

    /// Sets the authentication state to a specific value.
    ///
    /// - Parameter authenticated: The desired authentication state
    func setAuthentication(_ authenticated: Bool) {
        isUserAuthenticated = authenticated
    }

    /// Gets the current authentication state without async delay.
    ///
    /// This method provides synchronous access to the current state
    /// for testing and debugging purposes.
    ///
    /// - Returns: The current authentication state
    func getCurrentState() -> Bool {
        isUserAuthenticated
    }
}
