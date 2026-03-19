//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

// MARK: - Convenience Type Aliases

/// A convenience type alias for `DeepLinkCoordinator<R.Route>` where `R` is a `DeepLinkRoute`.
///
/// This type alias reduces verbosity when working with coordinators for specific route types.
///
/// ## Usage
///
/// ```swift
/// // Before
/// let coordinator: DeepLinkCoordinator<AppRoute> = ...
///
/// // After
/// let coordinator: CoordinatorOf<AppRoute> = ...
/// ```
public typealias CoordinatorOf<Route: DeepLinkRoute> = DeepLinkCoordinator<Route>

/// A convenience type alias for `DeepLinkResult<Route>`.
///
/// This type alias provides consistency with other `*Of` type aliases in the API.
///
/// ## Usage
///
/// ```swift
/// // Before
/// func handleResult(_ result: DeepLinkResult<AppRoute>) { ... }
///
/// // After
/// func handleResult(_ result: ResultOf<AppRoute>) { ... }
/// ```
public typealias ResultOf<Route: DeepLinkRoute> = DeepLinkResult<Route>
