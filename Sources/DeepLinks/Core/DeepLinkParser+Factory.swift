//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

public extension DeepLinkParser {
	/// Creates a lightweight ``DeepLinkParser`` backed by a closure that
	/// returns an array of routes.
	///
	/// Use this overload when a single URL may map to zero, one, or many
	/// routes. The returned parser forwards each URL to the supplied closure
	/// and returns its result as-is.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(.from { url in try parse(url) })
	///     .handler(appHandler)
	///     .build()
	/// ```
	///
	/// - Parameter parse: A `Sendable` closure invoked with each incoming URL.
	///   Errors thrown from the closure propagate to the caller.
	/// - Returns: A ``DeepLinkParser`` whose ``DeepLinkParser/parse(from:)``
	///   implementation calls `parse`.
	static func from<R: DeepLinkRoute>(
		_ parse: @Sendable @escaping (URL) async throws -> [R],
	) -> Self where Self == ClosureDeepLinkParser<R> {
		ClosureDeepLinkParser(parse: parse)
	}

	/// Creates a lightweight ``DeepLinkParser`` backed by a closure that
	/// returns a single optional route.
	///
	/// This convenience overload covers the common case where a URL either
	/// produces exactly one route or no route at all. When the closure
	/// returns a non-`nil` value it is wrapped in a single-element array; a
	/// `nil` result is translated into
	/// ``DeepLinkError/routeNotFound(_:)`` carrying the full URL, so the
	/// sentinel is unambiguous even for schemes that omit the host.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(.from { url in
	///         url.host == "settings" ? .settings : nil
	///     })
	///     .handler(appHandler)
	///     .build()
	/// ```
	///
	/// - Parameter parse: A `Sendable` closure invoked with each incoming
	///   URL. Return `nil` to signal that the URL is not handled; errors
	///   thrown from the closure propagate to the caller.
	/// - Returns: A ``DeepLinkParser`` that wraps the closure's result in a
	///   one-element array, or throws
	///   ``DeepLinkError/routeNotFound(_:)`` if the closure returns `nil`.
	static func from<R: DeepLinkRoute>(
		_ parse: @Sendable @escaping (URL) async throws -> R?,
	) -> Self where Self == SingleRouteClosureDeepLinkParser<R> {
		SingleRouteClosureDeepLinkParser(parse: parse)
	}
}

// MARK: - ClosureDeepLinkParser

/// A closure-backed ``DeepLinkParser`` produced by the multi-route
/// `DeepLinkParser.from` factory.
///
/// You rarely need to reference this type directly; prefer the `.from`
/// factory on ``DeepLinkParser`` and dot-shorthand when passing the parser
/// to APIs such as ``DeepLinkCoordinatorBuilder/parser(_:)``.
public struct ClosureDeepLinkParser<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
	private let parse: @Sendable (URL) async throws -> [Route]

	fileprivate init(parse: @Sendable @escaping (URL) async throws -> [Route]) {
		self.parse = parse
	}

	/// Forwards the URL to the closure supplied at construction time.
	public func parse(from url: URL) async throws -> [Route] {
		try await parse(url)
	}
}

// MARK: - SingleRouteClosureDeepLinkParser

/// A single-route closure-backed ``DeepLinkParser`` produced by the
/// optional-returning `DeepLinkParser.from` factory.
///
/// You rarely need to reference this type directly; prefer the `.from`
/// factory on ``DeepLinkParser`` and dot-shorthand when passing the parser
/// to APIs such as ``DeepLinkCoordinatorBuilder/parser(_:)``.
public struct SingleRouteClosureDeepLinkParser<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
	private let parse: @Sendable (URL) async throws -> Route?

	fileprivate init(parse: @Sendable @escaping (URL) async throws -> Route?) {
		self.parse = parse
	}

	/// Forwards the URL to the closure supplied at construction time,
	/// wrapping a non-`nil` result in a one-element array and throwing
	/// ``DeepLinkError/routeNotFound(_:)`` when the closure returns `nil`.
	public func parse(from url: URL) async throws -> [Route] {
		guard let route = try await parse(url) else {
			throw DeepLinkError.routeNotFound(url)
		}
		return [route]
	}
}
