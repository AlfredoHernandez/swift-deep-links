//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

public extension DeepLinkHandler {
	/// Creates a lightweight ``DeepLinkHandler`` backed by a closure.
	///
	/// Use this factory when you want to wire up route handling without
	/// declaring a dedicated type. The returned handler simply forwards each
	/// incoming route to the supplied closure.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(MyParser())
	///     .handler(.from { route in await navigate(route) })
	///     .build()
	/// ```
	///
	/// - Parameter handle: A `Sendable` closure invoked with each incoming
	///   route. Errors thrown from the closure propagate to the caller.
	/// - Returns: A ``DeepLinkHandler`` whose ``DeepLinkHandler/handle(_:)``
	///   implementation calls `handle`.
	static func from<R: DeepLinkRoute>(
		_ handle: @Sendable @escaping (R) async throws -> Void,
	) -> Self where Self == ClosureDeepLinkHandler<R> {
		ClosureDeepLinkHandler(handle: handle)
	}
}

// MARK: - ClosureDeepLinkHandler

/// A closure-backed ``DeepLinkHandler`` produced by
/// ``DeepLinkHandler/from(_:)``.
///
/// You rarely need to reference this type directly; prefer the
/// ``DeepLinkHandler/from(_:)`` factory and dot-shorthand when passing the
/// handler to APIs such as ``DeepLinkCoordinatorBuilder/handler(_:)``.
public struct ClosureDeepLinkHandler<Route: DeepLinkRoute>: DeepLinkHandler, Sendable {
	private let handle: @Sendable (Route) async throws -> Void

	fileprivate init(handle: @Sendable @escaping (Route) async throws -> Void) {
		self.handle = handle
	}

	/// Forwards the route to the closure supplied at construction time.
	public func handle(_ route: Route) async throws {
		try await handle(route)
	}
}
