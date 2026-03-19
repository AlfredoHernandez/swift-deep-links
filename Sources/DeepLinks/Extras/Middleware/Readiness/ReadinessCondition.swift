//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// A condition that must be satisfied before deep links can be processed.
///
/// Implement this protocol to define readiness gates such as
/// app launch completion, authentication, feature flags, or onboarding.
///
/// ## Built-in Implementations
///
/// - ``DeepLinkReadinessQueue``: A queue-based implementation that stores
///   deep links until readiness is signaled, then returns them for reprocessing.
public protocol ReadinessCondition: Sendable {
	/// Whether the condition is currently satisfied.
	var isReady: Bool { get }
}
