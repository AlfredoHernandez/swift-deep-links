//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Identifies one pass of a link through DeepLinkCoordinator, so
/// middleware can match DeepLinkMiddleware/didFinish(_:outcome:) with the
/// `intercept` call it follows even when identical links run concurrently.
enum DeepLinkRun {
	/// What the enclosing coordinator pass knows about its link.
	struct Pass: Sendable {
		var id: UUID?

		/// The link as it entered the chain in this pass, before any middleware
		/// rewrote it (for example stripped its signature).
		var arrival: DeepLinkRequest?

		/// The URL the router and handlers received in this pass, after every
		/// middleware (signature parameters already stripped).
		var routedURL: URL?

		/// Set by DeepLinkCoordinator around each route's handler; built-in
		/// route guards mark it when they decline the route before the wrapped
		/// handler runs, so the coordinator can tell "nothing executed" apart
		/// from a handler that failed after it may have acted.
		var routeDecline: RouteDecline?
	}

	@TaskLocal static var pass: Pass?

	static var id: UUID? {
		pass?.id
	}

	static var arrival: DeepLinkRequest? {
		pass?.arrival
	}

	static var routedURL: URL? {
		pass?.routedURL
	}

	static var routeDecline: RouteDecline? {
		pass?.routeDecline
	}

	/// Records that the current route was declined with `error` before its
	/// handler ran; the guard then throws `error`.
	static func declineRoute(with error: DeepLinkError) -> DeepLinkError {
		routeDecline?.markDeclined(with: error)
		return error
	}

	/// Runs `body` with the enclosing pass changed by `change`, starting
	/// from an empty pass outside one.
	static func updating<Output>(
		_ change: (inout Pass) -> Void,
		isolation _: isolated (any Actor)? = #isolation,
		_ body: () async throws -> Output,
	) async rethrows -> Output {
		var updated = pass ?? Pass()
		change(&updated)
		return try await $pass.withValue(updated) {
			try await body()
		}
	}

	/// Runs `body` as a standalone call, not part of the enclosing
	/// coordinator pass, so middleware called from a handler (for example
	/// DeepLinkMiddlewareCoordinator/process(_:)-(DeepLinkRequest)) cannot
	/// settle or overwrite the outer link's state.
	static func outside<Output>(
		isolation _: isolated (any Actor)? = #isolation,
		_ body: () async throws -> Output,
	) async rethrows -> Output {
		try await $pass.withValue(nil) {
			try await body()
		}
	}
}
